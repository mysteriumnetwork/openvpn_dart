package com.mysteriumvpn.openvpn_dart

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.util.Log
import kotlinx.coroutines.*
import java.io.File

class OpenVPNService : VpnService() {
    private val TAG = "OpenVPNService"
    private val scope = CoroutineScope(Job() + Dispatchers.Main)
    private lateinit var notificationHelper: NotificationHelper
    private lateinit var vpnLaunchHelper: VPNLaunchHelper
    private var managementThread: OpenVpnManagementThread? = null
    private var managementThreadRunner: Thread? = null
    private var openvpnProcess: Process? = null
    private var updateJob: Job? = null
    private var vpnInterface: ParcelFileDescriptor? = null

    private var isRunning = false
    private var configFile: String? = null

    // VPN Configuration
    private var localIp: String? = null
    private var netmask: String? = null
    private val dnsServers = mutableListOf<String>()
    private val routes = mutableListOf<RouteInfo>()
    private var bytesIn: Long = 0
    private var bytesOut: Long = 0

    companion object {
        @Volatile
        private var instance: OpenVPNService? = null

        fun getInstance(): OpenVPNService? = instance
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        notificationHelper = NotificationHelper(this)
        vpnLaunchHelper = VPNLaunchHelper(this)
        NotificationHelper.initNotificationChannel(this)
        OpenVPNBackend.instance.serviceCreated(this)
        Log.d(TAG, "Service created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand called with action: ${intent?.action}")
        
        try {
            when (intent?.action) {
                VPNManager.ACTION_CONNECT -> {
                    if (!isRunning) {
                        configFile = intent.getStringExtra(VPNManager.EXTRA_CONFIG)
                        startVPN()
                    }
                }
                VPNManager.ACTION_DISCONNECT -> {
                    stopVPN()
                }
                else -> {
                    // Service restarted by Android - maintain current state
                    Log.d(TAG, "Service restarted by system, current state: isRunning=$isRunning")
                }
            }

            // Show foreground notification
            try {
                val notification = notificationHelper.buildTunnelNotification(
                    ConnectionStatus.connecting,
                    TunnelStatistics(0, 0, 0),
                    "Mysterium VPN"
                )
                startForeground(NotificationHelper.NOTIFICATION_ID, notification)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start foreground: ${e.message}", e)
                // Don't crash - continue without notification
            }

            // Update notification periodically
            updateJob?.cancel()
            updateJob = scope.launch {
                while (isActive) {
                    try {
                        val status = OpenVPNBackend.instance.statusFlow.value
                        val stats = OpenVPNBackend.instance.latestStats
                        notificationHelper.updateStatusNotification(status, stats, "Mysterium VPN")
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to update notification: ${e.message}")
                    }
                    delay(1000)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in onStartCommand: ${e.message}", e)
        }

        return START_STICKY
    }

    private fun startVPN() {
        if (isRunning) {
            Log.w(TAG, "VPN already running")
            return
        }

        try {
            val configPath = configFile ?: throw Exception("No config file")
            Log.i(TAG, "Starting VPN: $configPath")

            // Validate config exists
            if (!File(configPath).exists()) {
                throw Exception("Config file not found: $configPath")
            }

            // Reset configuration
            dnsServers.clear()
            routes.clear()
            localIp = null
            bytesIn = 0
            bytesOut = 0

            // Mark as running
            isRunning = true
            Log.i(TAG, "VPN service initializing")

            // Initialize native OpenVPN3 protocol
            try {
                if (!OpenVpnJni.isLoaded()) {
                    throw Exception("Native OpenVPN library failed to load")
                }
                if (!OpenVpnJni.initOpenVpn()) {
                    throw Exception("Failed to initialize OpenVPN3 native library")
                }
                Log.d(TAG, "OpenVPN3 native library initialized")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load native library: ${e.message}")
                throw e
            }

            // Setup VPN interface first
            setupVpnInterface()
            
            // Get TUN file descriptor
            val tunFd = vpnInterface?.fd ?: throw Exception("TUN interface not established")
            Log.d(TAG, "TUN fd: $tunFd")

            // Start connection using native protocol with callback for status updates
            val statusListener = object : StatusListener {
                override fun onStatus(status: String) {
                    Log.d(TAG, "Native status: $status")
                    when (status) {
                        "connected" -> {
                            scope.launch {
                                OpenVPNBackend.instance.updateStatus(ConnectionStatus.connected)
                                Log.i(TAG, "VPN fully initialized")
                            }
                        }
                        "disconnected" -> {
                            scope.launch {
                                OpenVPNBackend.instance.updateStatus(ConnectionStatus.disconnected)
                            }
                        }
                        "connecting" -> {
                            // Already connecting
                        }
                    }
                }
            }

            val success = OpenVpnJni.startConnection(
                configPath,
                "",  // username
                "",  // password
                tunFd,  // Pass TUN file descriptor to native code
                statusListener
            )

            if (!success) {
                throw Exception("Failed to start native VPN connection")
            }

            Log.i(TAG, "Native OpenVPN connection started")

            // Start monitoring native connection stats
            scope.launch {
                while (isRunning && isActive) {
                    try {
                        bytesIn = OpenVpnJni.getBytesIn()
                        bytesOut = OpenVpnJni.getBytesOut()
                    } catch (e: Exception) {
                        Log.d(TAG, "Error reading stats: ${e.message}")
                    }
                    delay(1000)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Failed to start VPN: ${e.message}", e)
            isRunning = false
            OpenVPNBackend.instance.updateStatus(ConnectionStatus.disconnected)
            stopVPN()
        }
    }

    fun stopVPN() {
        isRunning = false
        try {
            // Stop native connection first
            try {
                OpenVpnJni.stopConnection()
            } catch (e: Exception) {
                Log.d(TAG, "Error stopping native connection: ${e.message}")
            }

            // Close VPN interface
            try {
                vpnInterface?.close()
            } catch (e: Exception) {
                Log.d(TAG, "Error closing VPN interface: ${e.message}")
            }
            vpnInterface = null
            Log.d(TAG, "VPN interface closed")
            
            // Interrupt management thread
            try {
                managementThreadRunner?.interrupt()
            } catch (e: Exception) {
                Log.d(TAG, "Error interrupting management thread: ${e.message}")
            }
            
            // Stop OpenVPN process if any
            try {
                openvpnProcess?.destroy()
                Thread.sleep(500)
                if (openvpnProcess?.isAlive == true) {
                    openvpnProcess?.destroyForcibly()
                }
            } catch (e: Exception) {
                Log.d(TAG, "Error stopping process: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping VPN", e)
        }
        OpenVPNBackend.instance.updateStatus(ConnectionStatus.disconnected)
    }

    // VPN Configuration Methods called by Management Thread

    fun setLocalIP(ip: String, netmask: String) {
        this.localIp = ip
        this.netmask = netmask
        Log.d(TAG, "Local IP set: $ip/$netmask")
    }

    fun addRoute(network: String, netmask: String, gateway: String) {
        routes.add(RouteInfo(network, netmask, gateway))
        Log.d(TAG, "Route added: $network/$netmask via $gateway")
    }

    fun addDnsServer(dns: String) {
        if (dns.isNotEmpty() && !dnsServers.contains(dns)) {
            dnsServers.add(dns)
            Log.d(TAG, "DNS added: $dns")
        }
    }

    fun updateStatistics(bytesIn: Long, bytesOut: Long) {
        this.bytesIn = bytesIn
        this.bytesOut = bytesOut
    }

    fun updateStatus(status: ConnectionStatus) {
        OpenVPNBackend.instance.updateStatus(status)
    }

    fun getStats(): TunnelStatistics {
        return TunnelStatistics(bytesIn, bytesOut, System.currentTimeMillis())
    }

    private fun setupVpnInterface() {
        try {
            // Parse config to extract connection details for basic routing
            val config = File(configFile!!).readText()

            // Set a default local IP if not configured by management interface
            if (localIp == null) {
                localIp = "10.8.0.6"
                netmask = "255.255.255.0"
                Log.d(TAG, "Using default local IP: $localIp/$netmask")
            }

            // Add default DNS if not set
            if (dnsServers.isEmpty()) {
                dnsServers.add("8.8.8.8")
                dnsServers.add("8.8.4.4")
                Log.d(TAG, "Using default DNS servers")
            }

            // Set up basic route for all traffic through VPN
            routes.add(RouteInfo("0.0.0.0", "0.0.0.0", "10.8.0.1"))

            // Open TUN interface
            vpnInterface = openTun()
            if (vpnInterface == null) {
                throw Exception("Failed to establish TUN interface")
            }

            Log.i(TAG, "VPN interface established successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error setting up VPN interface: ${e.message}", e)
            throw e
        }
    }

    fun openTun(): android.os.ParcelFileDescriptor? {
        return try {
            val builder = Builder()

            if (localIp == null) {
                Log.e(TAG, "Local IP not set")
                return null
            }

            // Add local address
            val cidr = calculateCIDR(netmask ?: "255.255.255.0")
            builder.addAddress(localIp!!, cidr)

            // Add DNS servers
            for (dns in dnsServers) {
                try {
                    builder.addDnsServer(dns)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to add DNS: $dns", e)
                }
            }

            // Add routes
            for (route in routes) {
                try {
                    val routeCidr = calculateCIDR(route.netmask)
                    builder.addRoute(route.network, routeCidr)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to add route: ${route.network}", e)
                }
            }

            builder.setSession("Mysterium VPN")
            builder.setMtu(1500)

            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open TUN", e)
            null
        }
    }

    private fun calculateCIDR(netmask: String): Int {
        val parts = netmask.split(".")
        var cidr = 0
        for (part in parts) {
            val num = part.toInt()
            var count = 0
            var bit = 128
            while (bit >= 1) {
                if ((num and bit) != 0) count++
                bit /= 2
            }
            cidr += count
        }
        return cidr
    }

    override fun onDestroy() {
        updateJob?.cancel()
        stopVPN()
        OpenVPNBackend.instance.serviceDestroyed()
        instance = null
        super.onDestroy()
        Log.d(TAG, "Service destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    data class RouteInfo(val network: String, val netmask: String, val gateway: String)
}
