
# openvpn_dart

`openvpn_dart` is a Flutter plugin that provides OpenVPN client functionality for Android, iOS, macOS, and Windows. It allows you to control and monitor VPN connections directly from your Flutter app using platform-specific implementations.

## Features

- Start, stop, and monitor OpenVPN connections
- Listen to VPN status updates
- Cross-platform support: Android, iOS, macOS, Windows

## Installation

Add this to your `pubspec.yaml`:

```yaml
dependencies:
	openvpn_dart: ^0.0.1
```

Then run:

```sh
flutter pub get
```

## Usage

Import the package:

```dart
import 'package:openvpn_dart/openvpn_dart.dart';
```

Create an instance and listen to VPN status:

```dart
final openVPN = OpenVPNDart(
	onVPNStatusChanged: (status, rawStatus) {
		print('VPN Status: $status');
	},
);
```

Refer to the API documentation and example project for more details.

## Platform Support

- **Android**: Uses native OpenVPN implementation
- **iOS/macOS**: Uses Network Extension
- **Windows**: Uses C API

## Documentation

- [Repository](https://github.com/mysteriumnetwork/openvpn_dart)

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
