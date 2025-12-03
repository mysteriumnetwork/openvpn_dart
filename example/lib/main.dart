import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openvpn_dart/openvpn_dart.dart';
import 'package:openvpn_dart/vpn_status.dart';

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
    } catch (e) {
      setState(() {
        initError = e.toString();
      });
      debugPrint("Initialization Error: $e");
    }
  }

  Future<void> initPlatformState() async {
    try {
      await openVPNPlugin.connect(config);
    } on Exception catch (e) {
      debugPrint("Error: $e");
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
                child: const Text("Start"),
                onPressed: () {
                  initPlatformState();
                },
              ),
              TextButton(
                child: const Text("STOP"),
                onPressed: () {
                  openVPNPlugin.disconnect();
                },
              ),
              TextButton(
                child: const Text("Check Tunnel"),
                onPressed: () async {
                  try {
                    bool exists =
                        await openVPNPlugin.checkTunnelConfiguration();
                    _messangerKey.currentState?.showSnackBar(
                      SnackBar(content: Text("Tunnel exists: $exists")),
                    );
                  } catch (e) {
                    _messangerKey.currentState
                        ?.showSnackBar(SnackBar(content: Text("Error: $e")));
                  }
                },
              ),
              TextButton(
                child: const Text("Setup Tunnel"),
                onPressed: () async {
                  try {
                    await openVPNPlugin.setupTunnel();
                    _messangerKey.currentState?.showSnackBar(
                      const SnackBar(content: Text("Tunnel setup succeeded")),
                    );
                  } catch (e) {
                    _messangerKey.currentState?.showSnackBar(
                      SnackBar(content: Text("Setup failed: $e")),
                    );
                  }
                },
              ),
              TextButton(
                child: const Text("Remove Tunnel"),
                onPressed: () async {
                  try {
                    await openVPNPlugin.removeTunnelConfiguration();
                    _messangerKey.currentState?.showSnackBar(
                      const SnackBar(content: Text("Tunnel removed")),
                    );
                  } catch (e) {
                    _messangerKey.currentState?.showSnackBar(
                      SnackBar(content: Text("Remove failed: $e")),
                    );
                  }
                },
              ),
              TextButton(
                child: const Text("Tunnel Status"),
                onPressed: () async {
                  try {
                    final status = await openVPNPlugin.getVPNStatus();
                    _messangerKey.currentState?.showSnackBar(
                      SnackBar(
                          content: Text("Tunnel status retrieved: $status")),
                    );
                  } catch (e) {
                    _messangerKey.currentState?.showSnackBar(
                      SnackBar(content: Text("Remove failed: $e")),
                    );
                  }
                },
              ),
              TextButton(
                child: const Text("Show Logs"),
                onPressed: () async {
                  try {
                    // Log path on Windows
                    final logPath =
                        '${Platform.environment['LOCALAPPDATA']}\\OpenVPNDart\\config\\openvpn.log';
                    final logFile = File(logPath);
                    if (await logFile.exists()) {
                      final logs = await logFile.readAsString();
                      debugPrint(
                          "===== OpenVPN Logs =====\n$logs\n===== End Logs =====");
                      // Show last 300 characters in snackbar
                      final preview = logs.length > 300
                          ? '...${logs.substring(logs.length - 300)}'
                          : logs;
                      _messangerKey.currentState?.showSnackBar(
                        SnackBar(
                          content: Text("Log preview:\n$preview"),
                          duration: const Duration(seconds: 8),
                        ),
                      );
                    } else {
                      _messangerKey.currentState?.showSnackBar(
                        SnackBar(
                            content: Text("Log file not found at: $logPath")),
                      );
                    }
                  } catch (e) {
                    _messangerKey.currentState?.showSnackBar(
                      SnackBar(content: Text("Error reading logs: $e")),
                    );
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

String get config => '''
client
dev tun
proto tcp
remote 88.99.85.196 1194
nobind
persist-key
persist-tun
remote-cert-tls server

auth-user-pass inline
data-ciphers AES-256-GCM:AES-128-GCM:AES-256-CBC:AES-128-CBC
auth SHA256
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
