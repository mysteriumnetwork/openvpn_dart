package com.mysteriumvpn.openvpn_dart

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.File

class OpenVPNBackend private constructor(
    private val appContext: Context,
    private val mainScope: CoroutineScope
) {
    private val serviceTag = "OpenVPNBackend"

    private var serviceRef: OpenVPNService? = null
    private var monitoringJob: Job? = null

    private val _statusFlow = MutableStateFlow(ConnectionStatus.disconnected)
    val statusFlow: StateFlow<ConnectionStatus> = _statusFlow

    private var _latestStats: TunnelStatistics? = null
    val latestStats: TunnelStatistics? get() = _latestStats

    private var currentConfigFile: String? = null

    companion object {
        @Volatile
        lateinit var instance: OpenVPNBackend
            private set

        fun init(context: Context, mainScope: CoroutineScope) {
            if (!::instance.isInitialized) {
                instance = OpenVPNBackend(context.applicationContext, mainScope)
                Log.d("OpenVPNBackend", "Backend singleton initialized")
            }
        }
    }

    fun serviceCreated(service: OpenVPNService) {
        serviceRef = service
        Log.d(serviceTag, "Service reference set in backend")
    }

    fun serviceDestroyed() {
        serviceRef = null
        Log.d(serviceTag, "Service reference cleared")
    }

    fun updateStatus(status: ConnectionStatus) {
        _statusFlow.value = status
    }

    fun connect(configString: String, context: Context) {
        Log.d(serviceTag, "connect: Saving config and starting service")
        
        // Save config to file
        val configFile = File(context.filesDir, "openvpn_config.ovpn")
        configFile.writeText(configString)
        currentConfigFile = configFile.absolutePath

        updateStatus(ConnectionStatus.connecting)
        startServiceIfNeeded(context)
        startMonitoringJob()
    }

    fun disconnect(context: Context) {
        Log.d(serviceTag, "disconnect: Stopping VPN")
        updateStatus(ConnectionStatus.disconnecting)
        monitoringJob?.cancel()
        monitoringJob = null
        _latestStats = null
        
        serviceRef?.stopVPN()
        stopService(context)
    }

    fun getConfigFile(): String? = currentConfigFile

    private fun startServiceIfNeeded(context: Context) {
        val intent = Intent(context, OpenVPNService::class.java).apply {
            action = VPNManager.ACTION_CONNECT
            putExtra(VPNManager.EXTRA_CONFIG, currentConfigFile)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.d(serviceTag, "OpenVPNService started")
        } catch (e: Exception) {
            Log.e(serviceTag, "Failed to start OpenVPNService", e)
        }
    }

    private fun stopService(context: Context) {
        serviceRef?.let {
            try {
                val intent = Intent(context, OpenVPNService::class.java)
                context.stopService(intent)
                Log.d(serviceTag, "OpenVPNService stopped")
            } catch (e: Exception) {
                Log.e(serviceTag, "Failed to stop OpenVPNService", e)
            }
            serviceRef = null
        } ?: Log.d(serviceTag, "No service reference to stop")
    }

    private fun startMonitoringJob() {
        monitoringJob?.cancel()

        monitoringJob = mainScope.launch(Dispatchers.IO) {
            Log.d(serviceTag, "Monitoring job started")
            while (isActive) {
                // Update latest stats only if connected
                _latestStats = if (_statusFlow.value == ConnectionStatus.connected) {
                    serviceRef?.getStats()?.let { stats ->
                        TunnelStatistics(
                            stats.totalRx,
                            stats.totalTx,
                            System.currentTimeMillis()
                        )
                    }
                } else {
                    null
                }

                delay(1000) // Update every 1 second
            }
        }
    }
}

enum class ConnectionStatus {
    disconnected,
    connecting,
    connected,
    disconnecting,
    unknown;

    companion object {
        fun fromString(value: String): ConnectionStatus {
            return values().find { it.name == value } ?: unknown
        }
    }
}

data class TunnelStatistics(
    val totalRx: Long,
    val totalTx: Long,
    val connectedSince: Long
)
