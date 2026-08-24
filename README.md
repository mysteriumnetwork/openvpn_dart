# OpenVPN Dart

A Flutter plugin for OpenVPN connectivity with built-in Windows support. Connect to OpenVPN servers directly from your Flutter app without requiring users to install OpenVPN separately.

## Features

✅ **Full OpenVPN Protocol Support**
- Connect to any OpenVPN server using standard .ovpn config files
- Support for TCP and UDP protocols
- Certificate-based and username/password authentication

✅ **Bundled Windows Support**
- OpenVPN binaries included with the package
- No separate installation required
- Automatic TAP driver installation
- Works out-of-the-box on Windows 10/11

✅ **Cross-Platform**
- ✅ Windows (fully bundled)
- ✅ iOS (via NetworkExtension)
- ✅ macOS (via NetworkExtension)
- ✅ Android (via ics-openvpn, bundled as a from-source AAR)

✅ **Real-Time Status Updates**
- Stream connection status changes
- Monitor connection progress
- Handle connection errors gracefully

✅ **Easy Integration**
- Simple API
- Minimal configuration
- Comprehensive error handling

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  openvpn_dart: ^1.0.0
```

Then run:
```bash
flutter pub get
```

### Windows Setup

For Windows, you need to bundle OpenVPN with your app:

1. **Run the download script:**
   ```powershell
   cd your_package
   .\scripts\download_openvpn.ps1
   ```

2. **Update your app's manifest** (required for admin rights):
   
   Add to `windows/runner/Runner.manifest`:
   ```xml
   <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
     <security>
       <requestedPrivileges>
         <requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
       </requestedPrivileges>
     </security>
   </trustInfo>
   ```

That's it! OpenVPN is now bundled with your app.

### Android Setup

Android is powered by the **ics-openvpn** engine, bundled as an AAR that is **built from source**
(not a third-party prebuilt) and committed under `android/localmaven/`. See
[`android/localmaven/PROVENANCE.md`](android/localmaven/PROVENANCE.md) for the exact upstream tag,
pinned submodule SHAs, OpenSSL/OpenVPN versions, and SHA-256. The plugin's own manifest contributes
`OpenVPNService` (registered with `BIND_VPN_SERVICE`), the status service, and all required
permissions automatically — but a consuming app must do the following (steps 1–2 are required,
step 3 is needed only to show the notification):

**1. Expose the bundled AAR's Maven repo.** The AAR is delivered as
`network.mysterium.openvpn:icsopenvpn` from a local Maven repo inside the plugin. Add it to your
app's `android/build.gradle.kts` (`allprojects { repositories { … } }`) or
`settings.gradle.kts` (`dependencyResolutionManagement`), pointing at the plugin's `localmaven`
folder. For the bundled example this is a relative path:

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("${rootProject.projectDir}/../../android/localmaven") } // path to openvpn_dart/android/localmaven
    }
}
```

> For production, publish the AAR to a shared Maven (e.g. GitHub Packages under your org) and point
> the repo there instead — this removes the relative-path fragility. See "Rebuilding the AAR" below.

**2. Extract native libraries.** ics-openvpn launches the OpenVPN binary as a process, which
requires native libs on disk. Modern AGP defaults to `extractNativeLibs=false`, which breaks this
(the process can't spawn). In your app's `android/app/build.gradle.kts`:

```kotlin
android {
    packaging {
        jniLibs { useLegacyPackaging = true }
    }
}
```

**3. (Android 13+) Request the notification permission.** The VPN runs as a foreground service.
To show its notification, request `POST_NOTIFICATIONS` at runtime (e.g. via the
[`permission_handler`](https://pub.dev/packages/permission_handler) package, as the example app
does). The VPN still connects without it; only the notification is suppressed.

**Notes**
- `connect(String config)` takes a full inline `.ovpn`; credentials come from an inline
  `<auth-user-pass>` block in that config.
- The service runs in the app's main process (consistent with `wireguard_dart`), so only one VPN
  tunnel is active at a time — disconnect one protocol before connecting the other.
- The notification (key icon, title, `Connected ↑/↓`) is styled to match a WireGuard notification;
  there is no "pause" action.

#### Rebuilding / updating the AAR

The committed AAR can be regenerated from upstream source with one script (requires Android NDK,
`swig`, JDK 17):

```bash
brew install swig                       # one-time (macOS)
scripts/build_android_aar.sh 0.7.55-myst
```

It clones the pinned `schwabe/ics-openvpn` tag, applies
`scripts/icsopenvpn-mysterium-*.patch` (application→library repackaging, branding strip,
single-process, notification styling), builds the native libs for all 4 ABIs, verifies the output,
and stages it into `android/localmaven/`. Then bump the coordinate in `android/build.gradle` and the
SHA-256 in `PROVENANCE.md` (the script prints both).

> **Maintainers:** see [doc/android_architecture.md](doc/android_architecture.md) for how the
> Android plugin works internally (channels, single-process design, the AAR, and gotchas), and
> [android/localmaven/PROVENANCE.md](android/localmaven/PROVENANCE.md) for the AAR's build provenance.

## Usage

### Basic Example

```dart
import 'package:openvpn_dart/openvpn_dart.dart';
import 'package:openvpn_dart/vpn_status.dart';

class VPNService {
  final OpenVPNDart _vpn = OpenVPNDart();

  Future<void> initialize() async {
    // Initialize the VPN client
    await _vpn.initialize();

    // Listen to connection status
    _vpn.statusStream().listen((status) {
      switch (status) {
        case ConnectionStatus.connected:
          print('✓ Connected to VPN');
          break;
        case ConnectionStatus.disconnected:
          print('○ Disconnected from VPN');
          break;
        case ConnectionStatus.connecting:
          print('⟳ Connecting...');
          break;
        case ConnectionStatus.error:
          print('✗ Connection error');
          break;
      }
    });
  }

  Future<void> connect(String ovpnConfig) async {
    try {
      await _vpn.connect(ovpnConfig);
    } catch (e) {
      print('Connection failed: $e');
    }
  }

  Future<void> disconnect() async {
    await _vpn.disconnect();
  }

  Future<bool> isConnected() async {
    return await _vpn.isConnected();
  }
}
```

### Complete UI Example

```dart
import 'package:flutter/material.dart';
import 'package:openvpn_dart/openvpn_dart.dart';
import 'package:openvpn_dart/vpn_status.dart';

class VPNPage extends StatefulWidget {
  @override
  _VPNPageState createState() => _VPNPageState();
}

class _VPNPageState extends State<VPNPage> {
  final OpenVPNDart _vpn = OpenVPNDart();
  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeVPN();
  }

  Future<void> _initializeVPN() async {
    try {
      await _vpn.initialize();
      
      _vpn.statusStream().listen((status) {
        setState(() {
          _status = status;
        });
      });

      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      _showError('Initialization failed: $e');
    }
  }

  Future<void> _connect() async {
    // Load your .ovpn config
    String config = await _loadConfig();
    
    try {
      await _vpn.connect(config);
    } catch (e) {
      _showError('Connection failed: $e');
    }
  }

  Future<void> _disconnect() async {
    await _vpn.disconnect();
  }

  Future<String> _loadConfig() async {
    // Load from assets or API
    return '''
client
dev tun
proto udp
remote your-server.com 1194
# ... rest of your OpenVPN config
    ''';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('VPN Connection')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildStatusIndicator(),
            SizedBox(height: 40),
            _buildConnectionButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    IconData icon;
    Color color;
    String text;

    switch (_status) {
      case ConnectionStatus.connected:
        icon = Icons.check_circle;
        color = Colors.green;
        text = 'Connected';
        break;
      case ConnectionStatus.connecting:
        icon = Icons.sync;
        color = Colors.orange;
        text = 'Connecting...';
        break;
      case ConnectionStatus.error:
        icon = Icons.error;
        color = Colors.red;
        text = 'Error';
        break;
      default:
        icon = Icons.circle_outlined;
        color = Colors.grey;
        text = 'Disconnected';
    }

    return Column(
      children: [
        Icon(icon, size: 80, color: color),
        SizedBox(height: 16),
        Text(text, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildConnectionButton() {
    if (!_isInitialized) {
      return CircularProgressIndicator();
    }

    bool isConnected = _status == ConnectionStatus.connected;
    bool isConnecting = _status == ConnectionStatus.connecting;

    return ElevatedButton(
      onPressed: isConnecting ? null : (isConnected ? _disconnect : _connect),
      style: ElevatedButton.styleFrom(
        backgroundColor: isConnected ? Colors.red : Colors.green,
        padding: EdgeInsets.symmetric(horizontal: 48, vertical: 16),
      ),
      child: Text(
        isConnected ? 'Disconnect' : 'Connect',
        style: TextStyle(fontSize: 18),
      ),
    );
  }
}
```

## OpenVPN Configuration

### Config File Format

Your OpenVPN config should follow the standard .ovpn format:

```
client
dev tun
proto udp
remote vpn.example.com 1194
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-256-CBC
auth SHA256
verb 3

# Inline certificates (recommended)
<ca>
-----BEGIN CERTIFICATE-----
YOUR_CA_CERTIFICATE
-----END CERTIFICATE-----
</ca>

<cert>
-----BEGIN CERTIFICATE-----
YOUR_CLIENT_CERTIFICATE
-----END CERTIFICATE-----
</cert>

<key>
-----BEGIN PRIVATE KEY-----
YOUR_PRIVATE_KEY
-----END PRIVATE KEY-----
</key>

<tls-auth>
-----BEGIN OpenVPN Static key V1-----
YOUR_TLS_AUTH_KEY
-----END OpenVPN Static key V1-----
</tls-auth>
```

### Loading Config Files

#### From Assets

```dart
import 'package:flutter/services.dart';

Future<String> loadConfigFromAssets() async {
  return await rootBundle.loadString('assets/config.ovpn');
}
```

#### From File

```dart
import 'dart:io';

Future<String> loadConfigFromFile(String path) async {
  final file = File(path);
  return await file.readAsString();
}
```

#### From API

```dart
import 'package:http/http.dart' as http;

Future<String> loadConfigFromAPI() async {
  final response = await http.get(
    Uri.parse('https://api.example.com/vpn/config'),
    headers: {'Authorization': 'Bearer YOUR_TOKEN'},
  );
  
  if (response.statusCode == 200) {
    return response.body;
  } else {
    throw Exception('Failed to load config');
  }
}
```

## API Reference

### OpenVPNDart

#### Methods

**`initialize({String? providerBundleIdentifier, String? localizedDescription})`**
- Initializes the VPN client
- Required before any other operations
- iOS/macOS parameters are optional on Windows

**`connect(String config)`**
- Connects to VPN using the provided OpenVPN config
- Throws exception if connection fails
- Returns immediately; use `statusStream()` to monitor progress

**`disconnect()`**
- Disconnects from VPN
- Safe to call even if not connected

**`isConnected()`**
- Returns `Future<bool>` indicating connection status

**`getVPNStatus()`**
- Returns current `ConnectionStatus`

**`statusStream()`**
- Returns `Stream<ConnectionStatus>` for real-time updates

**`tunnelStatistics()`**
- Returns `Future<VPNStatistics?>` — cumulative session traffic (`totalDownload`, `totalUpload`,
  `latestHandshake`). `null` if unavailable / unsupported on the platform. Implemented on Android,
  iOS, macOS and Windows; `latestHandshake` is always 0, as OpenVPN has no handshake.
- On iOS/macOS the packet-tunnel extension must answer an `OPENVPN_STATS` app message with
  `{"totalDownload":N,"totalUpload":N,"latestHandshake":0}` — see the example extensions.

**`setupTunnel()` / `checkTunnelConfiguration()` / `removeTunnelConfiguration()`**
- Prepare / query / remove the tunnel configuration. On iOS/macOS these manage the
  NetworkExtension config; on Android `setupTunnel`/`checkTunnelConfiguration` map to VPN consent
  and `removeTunnelConfiguration` just ensures the tunnel is stopped.

**`requestPermissionAndroid()`**
- Android only — requests VPN consent, returns `Future<bool>` (true if granted).

### ConnectionStatus

Enum values (see [lib/vpn_status.dart](lib/vpn_status.dart)):
- `ConnectionStatus.connecting` - Connection in progress
- `ConnectionStatus.connected` - Successfully connected
- `ConnectionStatus.disconnecting` - Disconnection in progress
- `ConnectionStatus.disconnected` - Not connected
- `ConnectionStatus.unknown` - Indeterminate / unrecognized state

## Platform-Specific Notes

### Windows

**Requirements:**
- Windows 10 or later
- Administrator privileges (automatically requested via manifest)
- TAP-Windows or Wintun driver (auto-installed)

**Bundle Size:**
- Approximately 8-12 MB for OpenVPN binaries
- Included in your app distribution

**Firewall:**
- Users may see Windows Firewall prompt on first connection
- Should be allowed for VPN to function

### iOS/macOS

**Requirements:**
- Network Extension capability
- VPN entitlements in your app
- Keychain access for storing credentials

### Android

**Requirements:**
- `minSdk` 21+
- `useLegacyPackaging = true` for jniLibs (see Android Setup) — the OpenVPN binary is executed at runtime
- The bundled `network.mysterium.openvpn:icsopenvpn` AAR resolved via Maven (see Android Setup)
- `POST_NOTIFICATIONS` requested at runtime on Android 13+ for the foreground-service notification

**Engine:** ics-openvpn (OpenVPN 2.7 / OpenSSL 3.4.1), built from source — see
[`android/localmaven/PROVENANCE.md`](android/localmaven/PROVENANCE.md).

**Bundle size:** ~33 MB AAR (native libs for arm64-v8a, armeabi-v7a, x86, x86_64; per-ABI app
bundles deliver only the device's slice).

## Troubleshooting

### Windows: "TAP driver not installed"

**Solution:**
1. Run your app as Administrator
2. The plugin will automatically install the TAP driver
3. Restart your app

### Windows: "Access Denied"

**Solution:**
Ensure your app manifest requests administrator privileges:
```xml
<requestedExecutionLevel level="requireAdministrator" uiAccess="false"/>
```

### Connection stuck on "Connecting"

**Check:**
1. OpenVPN config is valid
2. Server is reachable
3. Firewall allows OpenVPN traffic
4. Check logs at `%LOCALAPPDATA%\OpenVPNDart\config\openvpn.log`

### iOS: Network Extension not working

**Solution:**
1. Verify Network Extension entitlement is enabled
2. Check provisioning profile includes VPN capability
3. Ensure bundle identifier matches Network Extension

## Advanced Usage

### Auto-Reconnect

```dart
_vpn.statusStream().listen((status) async {
  if (status == ConnectionStatus.error || 
      status == ConnectionStatus.disconnected) {
    // Wait and retry
    await Future.delayed(Duration(seconds: 5));
    await _vpn.connect(config);
  }
});
```

## Building for Release

### Windows

1. **Build release:**
   ```bash
   flutter build windows --release
   ```

2. **Create installer (recommended):**
   
   Use Inno Setup or WiX to create an installer that:
   - Requests admin privileges
   - Installs to Program Files
   - Creates shortcuts
   - Handles uninstallation

3. **Code signing:**
   Sign your executable to avoid Windows Defender warnings:
   ```bash
   signtool sign /f certificate.pfx /p password /t http://timestamp.digicert.com your_app.exe
   ```

## License

Project license: [MIT](LICENSE).

**Third-party engines / Android note:** the Android backend bundles **ics-openvpn**, which is
**GPLv2** (with additional terms). Shipping it inside an app has copyleft implications — confirm
your app's licensing accordingly. (iOS/macOS use OpenVPNAdapter→OpenVPN3 and Windows uses the
official OpenVPN binaries, which carry their own licenses.) See
[`android/localmaven/PROVENANCE.md`](android/localmaven/PROVENANCE.md) for the exact ics-openvpn
source, versions, and build provenance.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on Windows, iOS, and macOS
5. Submit a pull request

## Support

- 📖 [Documentation](https://github.com/yourname/openvpn_dart/wiki)
- 🐛 [Issue Tracker](https://github.com/yourname/openvpn_dart/issues)
- 💬 [Discussions](https://github.com/yourname/openvpn_dart/discussions)

## Acknowledgments

- OpenVPN Community for the excellent VPN software
- Flutter team for the plugin architecture
- All contributors to this project

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for release history.

---

Made with ❤️ for the Flutter community
