import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:openvpn_dart/vpn_status.dart';

class OpenVPNDart {
  ///Channel's names of _VPNStatusSnapshot
  static const String _eventChannelVPNStatus = "id.mysteriumvpn.openvpn_flutter/vpnstatus";

  ///Channel's names of _channelControl
  static const String _methodChannelVpnControl = "id.mysteriumvpn.openvpn_flutter/vpncontrol";

  ///Method channel to invoke methods from native side
  static const MethodChannel _channelControl = MethodChannel(_methodChannelVpnControl);

  ///Snapshot of stream that produced by native side
  static Stream<String> _vpnStatusSnapshot() =>
      const EventChannel(_eventChannelVPNStatus).receiveBroadcastStream().cast();

  ///To indicate the engine already initialize
  bool initialized = false;

  ConnectionStatus? _lastStatus;

  /// is a listener to see what status the connection was
  final Function(ConnectionStatus status, String rawStatus)? onVPNStatusChanged;

  /// OpenVPN's Constructions, don't forget to implement the listeners
  /// onVPNStatusChanged is a listener to see what status the connection was
  OpenVPNDart({this.onVPNStatusChanged});

  ///This function should be called before any usage of OpenVPN
  ///All params required for iOS, make sure you read the plugin's documentation
  ///
  ///
  ///providerBundleIdentfier is for your Network Extension identifier
  ///
  ///localizedDescription is for description to show in user's settings
  ///
  ///
  ///Will return latest VPNStatus
  Future<void> initialize({
    String? providerBundleIdentifier,
    String? localizedDescription,
    String? groupIdentifier,
    Function(ConnectionStatus status)? lastStatus,
  }) async {
    if (Platform.isIOS) {
      assert(
        providerBundleIdentifier != null && localizedDescription != null,
        "These values are required for ios.",
      );
    }

    initialized = true;
    _initializeListener();
    try {
      await _channelControl.invokeMethod("initialize", {
        "providerBundleIdentifier": providerBundleIdentifier,
        "localizedDescription": localizedDescription,
      });
    } catch (e) {
      throw Exception("Failed to initialize VPN: $e");
    }
  }

  ///Connect to VPN
  ///
  ///config : Your openvpn configuration script, you can find it inside your .ovpn file
  ///
  ///name : name that will show in user's notification
  ///
  ///certIsRequired : default is false, if your config file has cert, set it to true
  ///
  ///username & password : set your username and password if your config file has auth-user-pass
  ///
  ///bypassPackages : exclude some apps to access/use the VPN Connection,
  /// it was List&lt;String&gt; of applications package's name (Android Only)
  Future<void> connect(String config) async {
    if (!initialized) {
      throw StateError("OpenVPN must be initialized before connecting");
    }

    try {
      final result = await _channelControl.invokeMethod("connect", {"config": config});
      return result;
    } on PlatformException catch (e) {
      throw ArgumentError("Failed to connect VPN: ${e.message}");
    } catch (e) {
      throw Exception("Unexpected error while connecting VPN: $e");
    }
  }

  ///Disconnect from VPN
  void disconnect() {
    _channelControl.invokeMethod("disconnect");
  }

  ///Check if connected to vpn
  Future<bool> isConnected() async =>
      getVPNStatus().then((value) => value == ConnectionStatus.connected);

  ///Get latest connection status
  Future<ConnectionStatus> getVPNStatus() async {
    String? status = await _channelControl.invokeMethod("status");
    return ConnectionStatus.fromString(status ?? "disconnected");
  }

  ///Request android permission (Return true if already granted)
  Future<bool> requestPermissionAndroid() async {
    return _channelControl.invokeMethod("request_permission").then((value) => value ?? false);
  }

  ///Convert String to ConnectionStatus
  static ConnectionStatus _strToStatus(String? status) {
    status = status?.trim().toLowerCase();
    if (status == null || status.isEmpty || status == "idle" || status == "invalid") {
      return ConnectionStatus.disconnected;
    }
    return ConnectionStatus.fromString(status);
  }

  ///Initialize listener, called when you start connection and stoped when you disconnect
  void _initializeListener() {
    _vpnStatusSnapshot().listen((event) {
      var vpnStatus = _strToStatus(event);
      if (vpnStatus != _lastStatus) {
        onVPNStatusChanged?.call(vpnStatus, event);
        _lastStatus = vpnStatus;
      }
    });
  }

  Future<bool> checkTunnelConfiguration() async {
    try {
      final result = await _channelControl.invokeMethod("checkTunnelConfiguration");
      return result == true; // Ensure bool
    } on PlatformException catch (e) {
      throw Exception("checkTunnelConfiguration failed: ${e.message}");
    }
  }

  Future<void> removeTunnelConfiguration() async {
    try {
      await _channelControl.invokeMethod("removeTunnelConfiguration");
    } on PlatformException catch (e) {
      throw Exception("removeTunnelConfiguration failed: ${e.message}");
    }
  }

  Future<void> setupTunnel() async {
    try {
      await _channelControl.invokeMethod("setupTunnel");
    } on PlatformException catch (e) {
      throw Exception("setupTunnel failed: ${e.message}");
    }
  }
}
