package com.mysteriumvpn.openvpn_dart

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class OpenvpnDartPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler,
    ActivityAware, PluginRegistry.ActivityResultListener {
    
    private val scope = CoroutineScope(Job() + Dispatchers.Main.immediate)

    companion object {
        private const val METHOD_CHANNEL_VPN_CONTROL = "id.mysteriumvpn.openvpn_flutter/vpncontrol"
        private const val EVENT_CHANNEL_VPN_STATUS = "id.mysteriumvpn.openvpn_flutter/vpnstatus"
        private const val VPN_PERMISSION_REQUEST_CODE = 24
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var vpnManager: VPNManager? = null
    private var initialized: Boolean = false
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var pendingResult: MethodChannel.Result? = null
    private var tunnelSetupRequested: Boolean = false
    private lateinit var notificationPermissionManager: NotificationPermissionManager

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        notificationPermissionManager = NotificationPermissionManager()
        
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_VPN_CONTROL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_VPN_STATUS)
        eventChannel.setStreamHandler(this)

        vpnManager = VPNManager(binding.applicationContext)

        // Initialize OpenVPNBackend singleton
        OpenVPNBackend.init(binding.applicationContext, scope)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        vpnManager?.disconnect()
        vpnManager = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                initialized = true
                vpnManager?.setEventSink(eventSink)
                result.success("disconnected")
            }

            "connect" -> {
                if (!initialized) {
                    result.error("-1", "VPN engine must be initialized", null)
                    return
                }

                val config = call.argument<String>("config")
                if (config.isNullOrEmpty()) {
                    result.error("-2", "Config is empty or nil", null)
                    return
                }

                vpnManager?.connect(config) { error ->
                    if (error != null) {
                        result.error("99", "Failed to start VPN: $error", null)
                    } else {
                        result.success(null)
                    }
                }
            }

            "disconnect" -> {
                vpnManager?.disconnect()
                result.success(null)
            }

            "status" -> {
                val status = vpnManager?.getCurrentStatus() ?: "disconnected"
                result.success(status)
            }

            "checkTunnelConfiguration" -> {
                // Check if VPN permission has been granted
                val intent = VpnService.prepare(activity?.applicationContext)
                val hasPermission = intent == null
                result.success(hasPermission)
            }

            "setupTunnel" -> {
                // Request VPN permission from user
                if (!initialized) {
                    result.error("-1", "VPN engine must be initialized", null)
                    return
                }

                val intent = VpnService.prepare(activity?.applicationContext)
                if (intent != null) {
                    // Need to request permission
                    pendingResult = result
                    tunnelSetupRequested = true
                    activity?.startActivityForResult(intent, VPN_PERMISSION_REQUEST_CODE)
                } else {
                    // Permission already granted
                    result.success("disconnected")
                }
            }

            "removeTunnelConfiguration" -> {
                // Disconnect and reset tunnel setup state
                tunnelSetupRequested = false
                if (vpnManager?.getCurrentStatus() != "disconnected") {
                    vpnManager?.disconnect()
                }
                result.success(true)
            }

            "getStatistics" -> {
                val stats = vpnManager?.getStatistics()
                result.success(stats)
            }

            "dispose" -> {
                initialized = false
                vpnManager?.disconnect()
                result.success(null)
            }

            "checkNotificationPermission" -> checkNotificationPermission(result)
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "openAppNotificationSettings" -> openNotificationPermissionSettings(result)

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        vpnManager?.setEventSink(events)
        
        // Subscribe to backend status flow
        scope.launch {
            OpenVPNBackend.instance.statusFlow.collect { status ->
                events?.success(status.name)
            }
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        vpnManager?.setEventSink(null)
    }

    private fun checkNotificationPermission(result: MethodChannel.Result) {
        val status = notificationPermissionManager.checkPermission(checkActivity())
        result.success(status.name)
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        val callback = object : NotificationPermissionCallback {
            override fun onResult(permissionStatus: NotificationPermission) {
                result.success(permissionStatus.name)
            }

            override fun onError(exception: Exception) {
                result.error("ERR_NOTIFICATION_PERMISSION", exception.message, null)
            }
        }
        notificationPermissionManager.requestPermission(checkActivity(), callback)
    }

    private fun openNotificationPermissionSettings(result: MethodChannel.Result) {
        try {
            val callback = object : NotificationPermissionCallback {
                override fun onResult(permissionStatus: NotificationPermission) {
                    result.success(permissionStatus.name)
                }

                override fun onError(exception: Exception) {
                    result.error("ERR_OPEN_NOTIFICATION_SETTINGS", exception.message, null)
                }
            }
            notificationPermissionManager.openAppNotificationSettings(checkActivity(), callback)
        } catch (e: Exception) {
            result.error("ERR_OPEN_NOTIFICATION_SETTINGS", e.message, null)
        }
    }

    private fun checkActivity(): Activity {
        return activity ?: throw ActivityNotAttachedException()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        // Forward activity result to NotificationPermissionManager
        if (::notificationPermissionManager.isInitialized) {
            if (notificationPermissionManager.onActivityResult(requestCode, resultCode, data)) {
                return true
            }
        }

        // Existing VPN permission handling
        if (requestCode == VPN_PERMISSION_REQUEST_CODE) {
            val granted = resultCode == Activity.RESULT_OK
            
            if (tunnelSetupRequested && pendingResult != null) {
                // This is from setupTunnel call
                if (granted) {
                    pendingResult?.success("disconnected")
                } else {
                    pendingResult?.error("-3", "VPN permission denied by user", null)
                }
                pendingResult = null
            }
            
            return true
        }
        return false
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(notificationPermissionManager)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(notificationPermissionManager)
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(notificationPermissionManager)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
