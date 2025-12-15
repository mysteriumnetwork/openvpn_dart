package com.mysteriumvpn.openvpn_dart

import android.content.Context
import android.content.Intent
import io.flutter.plugin.common.EventChannel
import java.io.File

class VPNManager(private val context: Context) {
    private var eventSink: EventChannel.EventSink? = null

    companion object {
        const val ACTION_CONNECT = "com.mysteriumvpn.openvpn_dart.CONNECT"
        const val ACTION_DISCONNECT = "com.mysteriumvpn.openvpn_dart.DISCONNECT"
        const val EXTRA_CONFIG = "config"
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    fun connect(config: String, callback: (String?) -> Unit) {
        try {
            OpenVPNBackend.instance.connect(config, context)
            callback(null)
        } catch (e: Exception) {
            callback(e.message)
        }
    }

    fun disconnect() {
        OpenVPNBackend.instance.disconnect(context)
    }

    fun getCurrentStatus(): String {
        return OpenVPNBackend.instance.statusFlow.value.name
    }

    fun getStatistics(): Map<String, Long>? {
        return OpenVPNBackend.instance.latestStats?.let { stats ->
            mapOf(
                "bytesIn" to stats.totalRx,
                "bytesOut" to stats.totalTx,
                "connectedSince" to stats.connectedSince
            )
        }
    }
}
