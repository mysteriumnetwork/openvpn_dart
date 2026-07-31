package com.mysteriumvpn.openvpn_dart

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler

/**
 * Bridges [OpenVPNBackend] status changes to the Dart `statusStream()` event channel,
 * emitting [ConnectionStatus.name] on the main thread (required by the event sink).
 */
class ConnectionStatusBroadcaster : StreamHandler {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventSink? = null

    override fun onListen(arguments: Any?, events: EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun send(status: ConnectionStatus) {
        mainHandler.post { eventSink?.success(status.name) }
    }
}
