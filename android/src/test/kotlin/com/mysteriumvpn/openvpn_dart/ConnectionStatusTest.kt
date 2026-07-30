package com.mysteriumvpn.openvpn_dart

import de.blinkt.openvpn.core.ConnectionStatus as IcsStatus
import kotlin.test.Test
import kotlin.test.assertEquals

internal class ConnectionStatusTest {
    @Test
    fun maps_connected() {
        assertEquals(ConnectionStatus.connected, ConnectionStatus.fromIcs(IcsStatus.LEVEL_CONNECTED))
    }

    @Test
    fun maps_connecting_variants() {
        listOf(
            IcsStatus.LEVEL_START,
            IcsStatus.LEVEL_CONNECTING_SERVER_REPLIED,
            IcsStatus.LEVEL_CONNECTING_NO_SERVER_REPLY_YET,
            IcsStatus.LEVEL_WAITING_FOR_USER_INPUT,
            IcsStatus.LEVEL_NONETWORK,
        ).forEach { assertEquals(ConnectionStatus.connecting, ConnectionStatus.fromIcs(it)) }
    }

    @Test
    fun maps_disconnected() {
        assertEquals(ConnectionStatus.disconnected, ConnectionStatus.fromIcs(IcsStatus.LEVEL_NOTCONNECTED))
        assertEquals(ConnectionStatus.disconnected, ConnectionStatus.fromIcs(IcsStatus.LEVEL_AUTH_FAILED))
    }

    @Test
    fun maps_unknown() {
        assertEquals(ConnectionStatus.unknown, ConnectionStatus.fromIcs(IcsStatus.LEVEL_VPNPAUSED))
        assertEquals(ConnectionStatus.unknown, ConnectionStatus.fromIcs(IcsStatus.UNKNOWN_LEVEL))
    }
}
