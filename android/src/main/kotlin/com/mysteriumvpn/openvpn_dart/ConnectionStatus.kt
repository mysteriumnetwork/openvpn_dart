package com.mysteriumvpn.openvpn_dart

import de.blinkt.openvpn.core.ConnectionStatus as IcsStatus

/**
 * Dart-facing connection states. Names MUST match `lib/vpn_status.dart` exactly
 * (they are sent over the event channel as `status.name`).
 */
enum class ConnectionStatus {
    connecting,
    connected,
    disconnecting,
    disconnected,
    unknown;

    companion object {
        /**
         * Maps an ics-openvpn [IcsStatus] level to our Dart-facing status.
         * `disconnecting` has no ics equivalent — it is set locally when we initiate a stop.
         */
        fun fromIcs(level: IcsStatus): ConnectionStatus = when (level) {
            IcsStatus.LEVEL_CONNECTED -> connected
            IcsStatus.LEVEL_START,
            IcsStatus.LEVEL_CONNECTING_SERVER_REPLIED,
            IcsStatus.LEVEL_CONNECTING_NO_SERVER_REPLY_YET,
            IcsStatus.LEVEL_WAITING_FOR_USER_INPUT,
            IcsStatus.LEVEL_NONETWORK -> connecting
            IcsStatus.LEVEL_NOTCONNECTED,
            IcsStatus.LEVEL_AUTH_FAILED -> disconnected
            else -> unknown // LEVEL_VPNPAUSED, UNKNOWN_LEVEL
        }
    }
}
