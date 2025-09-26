/// Connection lifecycle states we care about
enum ConnectionStatus {
  connecting,
  connected,
  disconnecting,
  disconnected,
  unknown;

  static ConnectionStatus fromString(String status) {
    switch (status) {
      case "connecting":
        return ConnectionStatus.connecting;
      case "connected":
        return ConnectionStatus.connected;
      case "disconnecting":
        return ConnectionStatus.disconnecting;
      case "disconnected":
        return ConnectionStatus.disconnected;
      default:
        return ConnectionStatus.unknown;
    }
  }
}
