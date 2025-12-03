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
  @override
  void initState() {
    openVPNPlugin = OpenVPNDart();

    openVPNPlugin.initialize(
      providerBundleIdentifier:
          Platform.isIOS
              ? "com.mysteriumvpn.openvpnDartExample.VPNExtension"
              : "com.mysteriumvpn.openvpnDartExample.VPNMExtension",
      localizedDescription: "MYST Example OVPN",
      lastStatus: (status) {
        setState(() {
          this.status = status.name;
        });
      },
    );
    _statusStream = openVPNPlugin.statusStream();
    super.initState();
  }

  Future<void> initPlatformState() async {
    try {
      await openVPNPlugin.connect(newConfig);
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
              Text(status?.toString() ?? ConnectionStatus.disconnected.toString()),
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
                    bool exists = await openVPNPlugin.checkTunnelConfiguration();
                    _messangerKey.currentState?.showSnackBar(
                      SnackBar(content: Text("Tunnel exists: $exists")),
                    );
                  } catch (e) {
                    _messangerKey.currentState?.showSnackBar(SnackBar(content: Text("Error: $e")));
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
                      SnackBar(content: Text("Tunnel status retrieved: $status")),
                    );
                  } catch (e) {
                    _messangerKey.currentState?.showSnackBar(
                      SnackBar(content: Text("Remove failed: $e")),
                    );
                  }
                },
              ),

              StreamBuilder<ConnectionStatus>(
                initialData: ConnectionStatus.unknown,
                stream: _statusStream,
                builder: (BuildContext context, AsyncSnapshot<ConnectionStatus> snapshot) {
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
remote 167.235.144.168 1194
nobind
persist-key
persist-tun
remote-cert-tls server

auth-user-pass inline
cipher AES-256-CBC
auth SHA256
data-ciphers AES-256-CBC
verb 6
client-cert-not-required

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
f059a4c3-761e-461f-b9fe-55bd7e10775b
jWeLs7XqlDNUtlmKWom9pJkHz4NZAmju9alajf7XkIg
</auth-user-pass>


''';

final String newConfig = '''
client
dev tun
proto tcp
remote 23.88.100.197 1194
nobind
persist-key
persist-tun
remote-cert-tls server

client-cert-not-required
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
