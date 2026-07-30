package com.mysteriumvpn.openvpn_dart

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Android implementation of openvpn_dart, backed by ics-openvpn. */
class OpenvpnDartPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    PluginRegistry.ActivityResultListener {

    companion object {
        private const val TAG = "OpenvpnDartPlugin"
        private const val VPN_REQUEST_CODE = 24601

        // Must match lib/openvpn_dart.dart and the iOS/macOS implementation.
        private const val METHOD_CHANNEL = "id.mysteriumvpn.openvpn_flutter/vpncontrol"
        private const val EVENT_CHANNEL = "id.mysteriumvpn.openvpn_flutter/vpnstatus"
    }

    private lateinit var channel: MethodChannel
    private lateinit var statusChannel: EventChannel
    private val broadcaster = ConnectionStatusBroadcaster()
    private val scope = CoroutineScope(Job() + Dispatchers.Main.immediate)

    private lateinit var context: Context
    private var activityBinding: ActivityPluginBinding? = null
    private val activity: Activity? get() = activityBinding?.activity

    /** Resolves the in-flight VPN-consent request started in [ensurePermission]. */
    private var pendingPermissionCb: ((granted: Boolean) -> Unit)? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        statusChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        statusChannel.setStreamHandler(broadcaster)

        OpenVPNBackend.init(context)
        scope.launch {
            OpenVPNBackend.statusFlow.collect { broadcaster.send(it) }
        }

        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        statusChannel.setStreamHandler(null)
        scope.cancel() // stop the status collector; avoids a leak + duplicate collectors on re-attach
    }

    // --- ActivityAware ---
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        binding.addActivityResultListener(this)
        activityBinding = binding
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding = null
        // If a consent dialog was in flight, the Activity is gone and onActivityResult will never
        // fire — resolve the pending callback as "denied" so the Dart Future doesn't hang forever.
        pendingPermissionCb?.invoke(false)
        pendingPermissionCb = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != VPN_REQUEST_CODE) return false
        val granted = resultCode == Activity.RESULT_OK
        pendingPermissionCb?.invoke(granted)
        pendingPermissionCb = null
        return true
    }

    // --- Method dispatch (see spec §6) ---
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            // initialize takes iOS-only args (ignored on Android) and just reports current status.
            "initialize", "status" -> result.success(OpenVPNBackend.statusFlow.value.name)

            "tunnelStatistics" -> {
                val (down, up) = OpenVPNBackend.statistics()
                // JSON shape mirrors wireguard_dart's TunnelStatistics (no handshake for OpenVPN).
                result.success("""{"totalDownload":$down,"totalUpload":$up,"latestHandshake":0}""")
            }

            "connect" -> {
                val config = call.argument<String>("config")
                if (config.isNullOrEmpty()) {
                    result.error("-2", "Config is empty or nil", null)
                    return
                }
                ensurePermission { granted ->
                    if (!granted) {
                        result.error("err_permission", "VPN permission was not granted", null)
                        return@ensurePermission
                    }
                    scope.launch {
                        try {
                            withContext(Dispatchers.IO) { OpenVPNBackend.connect(config) }
                            result.success(null)
                        } catch (e: Exception) {
                            Log.e(TAG, "connect failed", e)
                            result.error("err_connect", e.message, null)
                        }
                    }
                }
            }

            // Android has no persistent NetworkExtension-style config, so removeTunnelConfiguration
            // is just a stop — same as disconnect.
            "disconnect", "removeTunnelConfiguration" -> {
                OpenVPNBackend.disconnect()
                result.success(null)
            }

            "request_permission" -> ensurePermission { granted -> result.success(granted) }

            "checkTunnelConfiguration" ->
                result.success(OpenVPNBackend.isPermissionGranted(activity ?: context))

            "setupTunnel" -> ensurePermission { granted ->
                if (granted) result.success(null)
                else result.error("err_setup_tunnel", "VPN permission was not granted", null)
            }

            else -> result.notImplemented()
        }
    }

    /** Ensures VPN consent, prompting via the activity if needed; [cb] runs with the outcome. */
    private fun ensurePermission(cb: (granted: Boolean) -> Unit) {
        val act = activity
        if (act == null) {
            cb(false)
            return
        }
        val prepare = VpnService.prepare(act)
        if (prepare == null) {
            cb(true)
        } else if (pendingPermissionCb != null) {
            // A consent dialog is already in flight; don't orphan the first request.
            cb(false)
        } else {
            pendingPermissionCb = cb
            act.startActivityForResult(prepare, VPN_REQUEST_CODE)
        }
    }
}
