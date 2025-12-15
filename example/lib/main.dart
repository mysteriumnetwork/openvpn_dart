import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openvpn_dart/openvpn_dart.dart';

final _messangerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late OpenVPNDart openVPNPlugin;
  late Stream<ConnectionStatus> _statusStream;

  String? status;
  String? initError;

  @override
  void initState() {
    super.initState();
    openVPNPlugin = OpenVPNDart();
    _statusStream = openVPNPlugin.statusStream();
    _initializeVPN();
  }

  Future<void> _ensureTapDriver() async {
    try {
      setState(() {
        status = "Installing TAP driver...";
      });
      await openVPNPlugin.ensureTapDriver();
      _showSnackBar("TAP driver is ready");
      setState(() {
        status = "TAP driver ready";
      });
    } catch (e, stackTrace) {
      final errorMsg = e.toString();
      debugPrint("TAP Driver Error: $errorMsg\nStack trace: $stackTrace");
      _showSnackBar("TAP driver error: $errorMsg", isError: true);
      setState(() {
        status = "TAP driver error";
      });
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    _messangerKey.currentState?.clearSnackBars();
    _messangerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : null,
        duration: Duration(seconds: isError ? 5 : 3),
      ),
    );
  }

  Future<void> _initializeVPN() async {
    try {
      await openVPNPlugin.initialize(
        providerBundleIdentifier: Platform.isIOS
            ? "com.mysteriumvpn.openvpnDartExample.VPNExtension"
            : "com.mysteriumvpn.openvpnDartExample.VPNMExtension",
        localizedDescription: "MYST Example OVPN",
        lastStatus: (status) {
          setState(() {
            this.status = status.name;
          });
        },
      );
      setState(() {
        initError = null;
      });
    } catch (e, stackTrace) {
      final errorMsg = e.toString();
      setState(() {
        initError = errorMsg;
      });
      debugPrint("Initialization Error: $errorMsg\nStack trace: $stackTrace");
      _showSnackBar("Initialization failed: $errorMsg", isError: true);
    }
  }

  Future<void> initPlatformState() async {
    try {
      await openVPNPlugin.connect(config);
      _showSnackBar("VPN connection started");
    } catch (e, stackTrace) {
      final errorMsg = e.toString();
      debugPrint("Connection Error: $errorMsg\nStack trace: $stackTrace");
      _showSnackBar("Failed to connect: $errorMsg", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messangerKey,
      home: Scaffold(
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (initError != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(
                    'Init Error: $initError',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              Text(status?.toString() ??
                  ConnectionStatus.disconnected.toString()),
              TextButton(
                child: const Text("Install TAP Driver"),
                onPressed: () {
                  _ensureTapDriver();
                },
              ),
              TextButton(
                child: const Text("Start"),
                onPressed: () {
                  initPlatformState();
                },
              ),
              TextButton(
                child: const Text("STOP"),
                onPressed: () {
                  try {
                    openVPNPlugin.disconnect();
                    _showSnackBar("VPN disconnection requested");
                  } catch (e, stackTrace) {
                    debugPrint(
                        "Disconnect Error: $e\nStack trace: $stackTrace");
                    _showSnackBar("Failed to disconnect: $e", isError: true);
                  }
                },
              ),
              TextButton(
                child: const Text("Check Tunnel"),
                onPressed: () async {
                  try {
                    final exists =
                        await openVPNPlugin.checkTunnelConfiguration();
                    _showSnackBar("Tunnel exists: $exists");
                  } catch (e, stackTrace) {
                    debugPrint(
                        "Check Tunnel Error: $e\nStack trace: $stackTrace");
                    _showSnackBar("Failed to check tunnel: $e", isError: true);
                  }
                },
              ),
              TextButton(
                child: const Text("Setup Tunnel"),
                onPressed: () async {
                  try {
                    await openVPNPlugin.setupTunnel();
                    _showSnackBar("Tunnel setup succeeded");
                  } catch (e, stackTrace) {
                    debugPrint(
                        "Setup Tunnel Error: $e\nStack trace: $stackTrace");
                    _showSnackBar("Setup failed: $e", isError: true);
                  }
                },
              ),
              TextButton(
                child: const Text("Remove Tunnel"),
                onPressed: () async {
                  try {
                    await openVPNPlugin.removeTunnelConfiguration();
                    _showSnackBar("Tunnel removed successfully");
                  } catch (e, stackTrace) {
                    debugPrint(
                        "Remove Tunnel Error: $e\nStack trace: $stackTrace");
                    _showSnackBar("Remove failed: $e", isError: true);
                  }
                },
              ),
              TextButton(
                child: const Text("Tunnel Status"),
                onPressed: () async {
                  try {
                    final status = await openVPNPlugin.getVPNStatus();
                    _showSnackBar("Current status: ${status.name}");
                  } catch (e, stackTrace) {
                    debugPrint(
                        "Get Status Error: $e\nStack trace: $stackTrace");
                    _showSnackBar("Failed to get status: $e", isError: true);
                  }
                },
              ),
              const Divider(),
              const Text('Notification Permissions (Android 13+)',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              TextButton(
                child: const Text("Check Notification Permission"),
                onPressed: () async {
                  try {
                    final permission = await openVPNPlugin.checkNotificationPermission();
                    _showSnackBar("Notification permission: ${permission.name}");
                  } catch (e, stackTrace) {
                    debugPrint("Check Notification Permission Error: $e\nStack trace: $stackTrace");
                    _showSnackBar("Failed to check permission: $e", isError: true);
                  }
                },
              ),
              TextButton(
                child: const Text("Request Notification Permission"),
                onPressed: () async {
                  try {
                    final permission = await openVPNPlugin.requestNotificationPermission();
                    _showSnackBar("Notification permission result: ${permission.name}");
                  } catch (e, stackTrace) {
                    debugPrint(
                        "Request Notification Permission Error: $e\nStack trace: $stackTrace");
                    _showSnackBar("Failed to request permission: $e", isError: true);
                  }
                },
              ),
              TextButton(
                child: const Text("Open Notification Settings"),
                onPressed: () async {
                  try {
                    final permission = await openVPNPlugin.openAppNotificationSettings();
                    _showSnackBar("Returned with permission: ${permission.name}");
                  } catch (e, stackTrace) {
                    debugPrint("Open Notification Settings Error: $e\nStack trace: $stackTrace");
                    _showSnackBar("Failed to open settings: $e", isError: true);
                  }
                },
              ),
              const Divider(),
              TextButton(
                child: const Text("Show Logs"),
                onPressed: () async {
                  try {
                    if (!Platform.isWindows) {
                      _showSnackBar("Logs only available on Windows",
                          isError: true);
                      return;
                    }

                    final localAppData = Platform.environment['LOCALAPPDATA'];
                    if (localAppData == null || localAppData.isEmpty) {
                      _showSnackBar(
                          "LOCALAPPDATA environment variable not found",
                          isError: true);
                      return;
                    }

                    final baseDir = Directory('$localAppData\\OpenVPNDart');
                    final configDir =
                        Directory('$localAppData\\OpenVPNDart\\config');
                    final logPath =
                        '$localAppData\\OpenVPNDart\\config\\openvpn.log';
                    final logFile = File(logPath);

                    // Debug info
                    debugPrint("LOCALAPPDATA: $localAppData");
                    debugPrint("Base dir exists: ${await baseDir.exists()}");
                    debugPrint(
                        "Config dir exists: ${await configDir.exists()}");
                    debugPrint("Log file exists: ${await logFile.exists()}");

                    if (await baseDir.exists()) {
                      final files = await baseDir.list().toList();
                      debugPrint(
                          "Files in OpenVPNDart: ${files.map((f) => f.path).join(', ')}");
                    }

                    if (await logFile.exists()) {
                      final logs = await logFile.readAsString();
                      debugPrint(
                          "===== OpenVPN Logs =====\n$logs\n===== End Logs =====");

                      // Show last 300 characters in snackbar
                      final preview = logs.length > 300
                          ? '...${logs.substring(logs.length - 300)}'
                          : logs;
                      _messangerKey.currentState?.clearSnackBars();
                      _messangerKey.currentState?.showSnackBar(
                        SnackBar(
                          content: Text("Log preview:\n$preview"),
                          duration: const Duration(seconds: 8),
                        ),
                      );
                    } else {
                      final msg = "Log file not found. "
                          "Base dir exists: ${await baseDir.exists()}, "
                          "Config dir exists: ${await configDir.exists()}. "
                          "Path: $logPath";
                      _showSnackBar(msg, isError: true);
                      debugPrint(msg);
                    }
                  } catch (e, stackTrace) {
                    debugPrint("Show Logs Error: $e\nStack trace: $stackTrace");
                    _showSnackBar("Error reading logs: $e", isError: true);
                  }
                },
              ),
              StreamBuilder<ConnectionStatus>(
                initialData: ConnectionStatus.unknown,
                stream: _statusStream,
                builder: (BuildContext context,
                    AsyncSnapshot<ConnectionStatus> snapshot) {
                  // Check if the snapshot has data and is a map containing the 'status' key
                  if (snapshot.hasData) {
                    return Text("Tunnel stream status: ${snapshot.data!.name}");
                  }
                  return const CircularProgressIndicator();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String get config {
  // Use platform-specific config option for client certificate verification
  // Windows OpenVPN 2.6+ requires 'verify-client-cert none'
  // iOS/macOS OpenVPNAdapter requires 'client-cert-not-required'
  final certOption = Platform.isWindows ? '' : 'client-cert-not-required';

  return '''
client
dev tun
proto tcp
remote 23.88.100.197 1194
nobind
persist-key
persist-tun
remote-cert-tls server

$certOption
auth-user-pass inline
cipher AES-256-CBC
auth SHA256
data-ciphers AES-256-CBC
verb 3

<ca>
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIUeWpW3vmG6W8g/jtfRrzhZI9uwrgwDQYJKoZIhvcNAQEL
BQAwHDEaMBgGA1UEAwwRc3VwZXJ2cG4tdGVzdG5ldDAwHhcNMjUwODA1MDMxNTI4
WhcNMzUwODAzMDMxNTI4WjAcMRowGAYDVQQDDBFzdXBlcnZwbi10ZXN0bmV0MDCC
ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKr0nAwWsVC8g7ByUhzYvY8r
QpR1tFRQdyCoPRMsIA79J6kkrBGGYlmkA56I6lzhvEv3Od0dRzvrtnT03yzAyAmU
EFojVUQjxH9yj0VWPJ+pDIfukSSQAQ83BAFvEhR/27M+6N26HEd8TgRMJtUN8l4M
uH14CpI+cYeoqd2B/C3tatsG8xneUT3T/E8NNYeTXqETtmMXl9S7tqkGz2+2x5Ie
dOJK+FTUxrqgHvsSR/nb23FnARvU6kB2jt18tPdnvWyMZ2zyY/dV2EzdYcATSWdr
5zqSXY2xy+sh5tpeVak4QcNPJ8B6gjD/rQqAWAyT7IpCW48Qk1Mw98nFdXcPwVMC
AwEAAaOBljCBkzAdBgNVHQ4EFgQUTgZYUZissmpM0Pt0A5uxKYmNbOIwVwYDVR0j
BFAwToAUTgZYUZissmpM0Pt0A5uxKYmNbOKhIKQeMBwxGjAYBgNVBAMMEXN1cGVy
dnBuLXRlc3RuZXQwghR5albe+YbpbyD+O19GvOFkj27CuDAMBgNVHRMEBTADAQH/
MAsGA1UdDwQEAwIBBjANBgkqhkiG9w0BAQsFAAOCAQEAmNmvzg0pJl55QTTle+/f
HiCArWs6atuXNPw7UGPPgZIg6El8wIUccXIv9TKKO0FWfg5MfvrBJW5MqKY5KAwj
e39z8fJ6LjVUVW689jsgsQBC9ag1lKzQ2Hm0T4q/NTiiOTmrQzf5LskwxDqBViNb
NhHx3EGsegMMSFu1vY5PLGhWuRUX9n6JhgoyBBW7fGdK6auE+JWbKKn6jIvFqvsu
Og7Xucsfjn7W6POtN1k/Bi3jR+ui6Bd+Jy5L+wmOAS9J2MUOEBuVVJlu1OB4/sgY
MLUM00xZpx1x2FBrIGLhanF7qAYi5W+FKWII6d3Wn7XFR/R8sx5p15c40F7Rr/xs
vg==
-----END CERTIFICATE-----
</ca>

<auth-user-pass>
b1c9af339f776072bbbfb4a1b526408808b0
LjfEMsbBFFZfT5UkjO6czeIr64eJjpyGRCeqE3G97cg
</auth-user-pass>

''';
}
