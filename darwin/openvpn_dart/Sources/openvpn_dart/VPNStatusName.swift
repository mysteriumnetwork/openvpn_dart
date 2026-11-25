import NetworkExtension

/// The status name sent to Dart for a system VPN status. The names must match
/// `ConnectionStatus` in `lib/vpn_status.dart`.
///
/// Every case is named so that the compiler points out a status this does not
/// handle. Two of them used to fall through to `unknown`, which host apps tend
/// to show as disconnected.
func statusName(for status: NEVPNStatus) -> String {
    switch status {
    case .connected: return "connected"
    // Reasserting is a tunnel that is still up and re-establishing its link:
    // what the packet tunnel provider reports when OpenVPN reconnects after
    // the network went away. It has not ended and comes back by itself, so it
    // is `connecting`, as it is on Android while there is no network.
    case .connecting, .reasserting: return "connecting"
    case .disconnecting: return "disconnecting"
    // Invalid is a VPN configuration that is missing or was removed.
    case .disconnected, .invalid: return "disconnected"
    @unknown default: return "unknown"
    }
}
