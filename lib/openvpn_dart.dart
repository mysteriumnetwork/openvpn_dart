import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:openvpn_dart/vpn_status.dart';
import 'package:openvpn_dart/vpn_statistics.dart';

/// Entry point for controlling an OpenVPN connection.
///
/// Call [initialize] once before any other method, then [connect] / [disconnect]
/// and observe progress via [statusStream] (or poll [getVPNStatus]). Live traffic
/// counters are available from [tunnelStatistics].
///
/// Supported platforms: Android (ics-openvpn), iOS & macOS (NetworkExtension),
/// Windows (bundled OpenVPN binaries). Methods that don't apply to a platform are
/// no-ops or return gracefully there.
class OpenVPNDart {
  ///Channel's names of _VPNStatusSnapshot
  static const String _eventChannelVPNStatus =
      "id.mysteriumvpn.openvpn_flutter/vpnstatus";

  ///Channel's names of _channelControl
  static const String _methodChannelVpnControl =
      "id.mysteriumvpn.openvpn_flutter/vpncontrol";

  ///Method channel to invoke methods from native side
  static const MethodChannel _channelControl =
      MethodChannel(_methodChannelVpnControl);

  ///Snapshot of stream that produced by native side
  static Stream<String> _vpnStatusSnapshot() =>
      const EventChannel(_eventChannelVPNStatus)
          .receiveBroadcastStream()
          .cast();

  ///To indicate the engine already initialize
  bool initialized = false;

  /// OpenVPN's Constructions, don't forget to implement the listeners
  /// onVPNStatusChanged is a listener to see what status the connection was
  OpenVPNDart();

  ///Ensures TAP driver is installed (Windows only)
  ///Call this during app initialization to check/install the driver
  ///Returns true if driver is installed or successfully installed
  ///Throws exception if installation fails
  Future<bool> ensureTapDriver() async {
    if (!Platform.isWindows) {
      return true; // Not needed on other platforms
    }

    try {
      await _channelControl.invokeMethod("ensureTapDriver");
      return true;
    } on PlatformException catch (e) {
      throw Exception("Failed to ensure TAP driver: ${e.message}");
    } catch (e) {
      throw Exception("Unexpected error ensuring TAP driver: $e");
    }
  }

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
    try {
      await _channelControl.invokeMethod("initialize", {
        "providerBundleIdentifier": providerBundleIdentifier,
        "localizedDescription": localizedDescription,
      });
    } catch (e) {
      throw Exception("Failed to initialize VPN: $e");
    }
  }

  /// Connect to the VPN.
  ///
  /// [config] : the full OpenVPN configuration (the contents of your `.ovpn` file).
  /// Credentials are taken from an inline `<auth-user-pass>` block in [config];
  /// there are no separate username/password parameters.
  ///
  /// This resolves once the tunnel has been *requested to start*, NOT once it is
  /// connected. Connection progress and failures (including auth failure) are
  /// reported via [statusStream] / [getVPNStatus], not via this Future.
  Future<void> connect(String config) async {
    if (!initialized) {
      throw StateError("OpenVPN must be initialized before connecting");
    }

    try {
      final result =
          await _channelControl.invokeMethod("connect", {"config": config});
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

  /// Cumulative traffic statistics (bytes up/down) for the current session.
  ///
  /// Returns null if unavailable or not supported on the current platform.
  /// (Implemented on Android via ics-openvpn's byte counters.)
  Future<VPNStatistics?> tunnelStatistics() async {
    try {
      final result = await _channelControl.invokeMethod("tunnelStatistics");
      if (result is! String) return null;
      return VPNStatistics.fromJson(jsonDecode(result) as Map<String, dynamic>);
    } on PlatformException {
      return null; // method not implemented on this platform
    } catch (_) {
      return null;
    }
  }

  ///Request android permission (Return true if already granted)
  Future<bool> requestPermissionAndroid() async {
    return _channelControl
        .invokeMethod("request_permission")
        .then((value) => value ?? false);
  }

  ///Convert String to ConnectionStatus
  static ConnectionStatus _strToStatus(String? status) {
    status = status?.trim().toLowerCase();
    if (status == null ||
        status.isEmpty ||
        status == "idle" ||
        status == "invalid") {
      return ConnectionStatus.disconnected;
    }
    return ConnectionStatus.fromString(status);
  }

  ///Initialize listener, called when you start connection and stoped when you disconnect
  /// is a listener to see what status the connection was
  Stream<ConnectionStatus> statusStream() {
    return _vpnStatusSnapshot().asBroadcastStream().distinct().map((event) {
      final status = _strToStatus(event);
      return status;
    });
  }

  /// Whether the VPN tunnel is already configured / permitted.
  ///
  /// iOS/macOS: whether a NetworkExtension tunnel configuration exists.
  /// Android: whether the user has already granted VPN consent
  /// (`VpnService.prepare` returns no prompt).
  Future<bool> checkTunnelConfiguration() async {
    try {
      final result =
          await _channelControl.invokeMethod("checkTunnelConfiguration");
      return result == true; // Ensure bool
    } on PlatformException catch (e) {
      throw Exception("checkTunnelConfiguration failed: ${e.message}");
    }
  }

  /// Remove the saved tunnel configuration.
  ///
  /// iOS/macOS: removes the NetworkExtension configuration. Android has no
  /// persistent configuration, so this simply ensures any running tunnel is
  /// stopped.
  Future<void> removeTunnelConfiguration() async {
    try {
      await _channelControl.invokeMethod("removeTunnelConfiguration");
    } on PlatformException catch (e) {
      throw Exception("removeTunnelConfiguration failed: ${e.message}");
    }
  }

  /// Prepare the tunnel before connecting.
  ///
  /// iOS/macOS: creates the NetworkExtension tunnel configuration.
  /// Android: requests VPN consent (shows the system prompt if not yet granted).
  Future<void> setupTunnel() async {
    try {
      await _channelControl.invokeMethod("setupTunnel");
    } on PlatformException catch (e) {
      throw Exception("setupTunnel failed: ${e.message}");
    }
  }
}
