package com.mysteriumvpn.openvpn_dart

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.util.Log
import de.blinkt.openvpn.VpnProfile
import de.blinkt.openvpn.core.ConfigParser
import de.blinkt.openvpn.core.ConnectionStatus as IcsStatus
import de.blinkt.openvpn.core.IOpenVPNServiceInternal
import de.blinkt.openvpn.core.OpenVPNService
import de.blinkt.openvpn.core.ProfileManager
import de.blinkt.openvpn.core.VPNLaunchHelper
import de.blinkt.openvpn.core.VpnStatus
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.StringReader

/**
 * Single source of truth + orchestrator for the OpenVPN tunnel: owns the status [StateFlow],
 * drives connect/disconnect, and translates ics-openvpn's [VpnStatus] callbacks into our
 * Dart-facing [ConnectionStatus]. Independent of Flutter classes so it stays testable.
 */
object OpenVPNBackend : VpnStatus.StateListener, VpnStatus.ByteCountListener {

    private const val TAG = "OpenVPNBackend"
    private const val PROFILE_NAME = "Mysterium VPN"

    private lateinit var appContext: Context
    private var initialized = false

    private val _statusFlow = MutableStateFlow(ConnectionStatus.disconnected)
    val statusFlow: StateFlow<ConnectionStatus> = _statusFlow

    // Cumulative byte counts for the current session (download = received, upload = sent),
    // fed by ics-openvpn's ByteCountListener. Reset on each connect.
    @Volatile private var totalDownload: Long = 0
    @Volatile private var totalUpload: Long = 0

    /** Idempotent. Creates notification channels and registers the status listener once. */
    fun init(context: Context) {
        if (initialized) return
        appContext = context.applicationContext
        // ICSOpenVPNApplication normally creates these channels, but the host app keeps its own
        // Application class, so we do it here — otherwise OpenVPNService.startForeground() throws
        // CannotPostForegroundServiceNotificationException. (OpenVPNService runs in the app process
        // per our manifest, so status reaches this listener directly — no cross-process bridge.)
        createNotificationChannels(appContext)
        VpnStatus.addStateListener(this)
        VpnStatus.addByteCountListener(this)
        initialized = true
        Log.d(TAG, "Backend initialized")
    }

    // --- VpnStatus.ByteCountListener ---
    override fun updateByteCount(inBytes: Long, outBytes: Long, diffIn: Long, diffOut: Long) {
        totalDownload = inBytes
        totalUpload = outBytes
    }

    /** Latest cumulative byte counts for the current session: download (rx) and upload (tx). */
    fun statistics(): Pair<Long, Long> = Pair(totalDownload, totalUpload)

    /** Mirrors ICSOpenVPNApplication.createNotificationChannels using ics-openvpn's channel IDs. */
    private fun createNotificationChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(
                OpenVPNService.NOTIFICATION_CHANNEL_BG_ID, "VPN connection",
                NotificationManager.IMPORTANCE_MIN,
            )
        )
        nm.createNotificationChannel(
            NotificationChannel(
                OpenVPNService.NOTIFICATION_CHANNEL_NEWSTATUS_ID, "VPN status",
                NotificationManager.IMPORTANCE_LOW,
            )
        )
        nm.createNotificationChannel(
            NotificationChannel(
                OpenVPNService.NOTIFICATION_CHANNEL_USERREQ_ID, "VPN requests",
                NotificationManager.IMPORTANCE_HIGH,
            )
        )
    }

    // --- VpnStatus.StateListener ---
    override fun updateState(
        state: String?,
        logmessage: String?,
        localizedResId: Int,
        level: IcsStatus?,
        intent: Intent?,
    ) {
        val mapped = level?.let { ConnectionStatus.fromIcs(it) } ?: ConnectionStatus.unknown
        _statusFlow.value = mapped
        Log.d(TAG, "ics state '$state' level=$level -> $mapped")
    }

    override fun setConnectedVPN(uuid: String?) {
        // No-op: we track a single active tunnel; status comes via updateState.
    }

    /**
     * Parses [config] (a full .ovpn, credentials inline via `<auth-user-pass>`), registers the
     * profile, and starts the OpenVPN service. VPN consent MUST already be granted by the caller.
     * Returns after the service is asked to start; progress arrives via [statusFlow].
     */
    fun connect(config: String) {
        val profile: VpnProfile = ConfigParser().run {
            parseConfig(StringReader(config))
            convertProfile()
        }
        profile.mName = PROFILE_NAME
        // Kill switch (in-tunnel leak prevention). Forced on regardless of what the config says:
        // - persist-tun keeps the tun interface up across reconnects/network changes, so while the
        //   tunnel is down packets hit a tun with no working route and are DROPPED instead of
        //   leaking to the underlying network.
        // - blocking unused address families closes the IPv6 leak path on an IPv4-only tunnel
        //   (and vice-versa): traffic for a family the tunnel doesn't route is null-routed, not
        //   sent in the clear.
        // This does NOT cover the app being killed/crashed before traffic is blocked — that
        // requires Android's system "Always-on VPN + Block connections without VPN", which apps
        // cannot enable programmatically.
        profile.mPersistTun = true
        profile.mBlockUnusedAddressFamilies = true
        ProfileManager.setTemporaryProfile(appContext, profile)
        totalDownload = 0
        totalUpload = 0
        _statusFlow.value = ConnectionStatus.connecting
        VPNLaunchHelper.startOpenVpn(profile, appContext, "openvpn_dart", false)
        Log.d(TAG, "startOpenVpn requested for '$PROFILE_NAME'")
    }

    /** Binds the running [OpenVPNService] and asks it to stop the tunnel. */
    fun disconnect() {
        // Nothing to do if already down — avoids getting stuck on `disconnecting`.
        if (_statusFlow.value == ConnectionStatus.disconnected) return
        _statusFlow.value = ConnectionStatus.disconnecting
        // Clear counters so tunnelStatistics() doesn't report the ended session's totals.
        totalDownload = 0
        totalUpload = 0

        val intent = Intent(appContext, OpenVPNService::class.java).apply {
            action = OpenVPNService.START_SERVICE
        }
        val conn = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
                val service = IOpenVPNServiceInternal.Stub.asInterface(binder)
                try {
                    service?.stopVPN(false)
                    Log.d(TAG, "stopVPN sent")
                } catch (e: Exception) {
                    Log.e(TAG, "stopVPN failed", e)
                    _statusFlow.value = ConnectionStatus.disconnected
                } finally {
                    try {
                        appContext.unbindService(this)
                    } catch (_: Exception) {
                    }
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) {}
        }
        // Bind WITHOUT auto-create: if the service isn't running there's nothing to stop, and we
        // must not spin up a foreground service just to tell it to stop.
        val bound = try {
            appContext.bindService(intent, conn, 0)
        } catch (e: Exception) {
            Log.e(TAG, "bindService failed", e)
            false
        }
        if (!bound) {
            try {
                appContext.unbindService(conn)
            } catch (_: Exception) {
            }
            Log.d(TAG, "No running OpenVPNService to stop; marking disconnected")
            _statusFlow.value = ConnectionStatus.disconnected
        }
    }

    /** True when VPN consent has already been granted (no system prompt needed). */
    fun isPermissionGranted(context: Context): Boolean = VpnService.prepare(context) == null
}
