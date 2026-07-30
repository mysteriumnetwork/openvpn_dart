# Provenance — `icsopenvpn-0.7.55-myst.aar`

This AAR is the OpenVPN (ics-openvpn) native backend consumed by the `openvpn_dart`
Android plugin. It was **built from source** from auditable upstream code — it is NOT
an opaque third-party prebuilt. This file is the audit trail.

## Artifact
- **File:** `android/localmaven/network/mysterium/openvpn/icsopenvpn/0.7.55-myst/icsopenvpn-0.7.55-myst.aar`
- **Coordinate:** `network.mysterium.openvpn:icsopenvpn:0.7.55-myst`
- **Size:** ~33 MB
- **SHA-256:** `1da7a6068d0bda22fef4b8ec7a887c07ab456e65c1246ea9a7533c4676891454`
- **Gradle variant built:** `:main:assembleSkeletonOvpn23Release`
  - `skeleton` flavor = VPN core engine **without** the ics-openvpn UI.
  - `ovpn23` flavor = OpenVPN3 C++ engine + OpenSSL.

## Modifications vs upstream v0.7.55
Library + resource changes so the AAR behaves as a well-mannered library and matches the app's
WireGuard notification (no functional/crypto change to the engine):
- dropped `FLAG_ACTIVITY_REORDER_TO_FRONT` from the notification tap intent — after the
  app is swiped from recents the task is gone, and reordering a dead task showed a black screen.
  Now uses `CLEAR_TOP | SINGLE_TOP` (matching wireguard_dart) so it cold-starts cleanly.
- notification byte-count shows **cumulative totals** (↑ total uploaded, ↓ total
  downloaded) to match wireguard_dart, instead of instantaneous speed (`statusline_bytecount` now
  uses the total args `%3$s`/`%1$s`).
- the foreground-notification tap intent (and the VpnService configure intent) opens
  the host app's launcher activity instead of ics's stripped `.activities.MainActivity` (which
  doesn't exist in the consumer app), so tapping the notification brings the app to the front /
  relaunches it.
- `keepVPNAlive` schedules a **non-persisted** JobScheduler job
  (`setPersisted(false)`). The persisted variant requires `RECEIVE_BOOT_COMPLETED` (removed above
  for hardening), and its absence crashed `startOpenVPN` on connect. Non-persisted is consistent
  with the removed boot auto-start; in-session keepalive is unaffected.
- **Security hardening:** removed permissions and exported components that the headless
  connect flow never uses and that are unsafe for a consumer VPN app:
  - permissions: `QUERY_ALL_PACKAGES` (Play-restricted), `READ_EXTERNAL_STORAGE`,
    `RECEIVE_BOOT_COMPLETED`.
  - components: `ExternalOpenVPNService` (exported AIDL remote-control API), the
    `ConnectVPN`/`DisconnectVPN`/`PauseVPN`/`ResumeVPN` activity-aliases + `RemoteAction`,
    `GrantPermissionsActivity`, `ConfirmDialog`, `OnBootReceiver`. `LaunchVPN` and the skeleton
    flavor's no-op stub activities (`NotImplemented`, `LogWindow`, `Req`) made non-exported.
  Kept: `OpenVPNService` (BIND_VPN_SERVICE), `OpenVPNStatusService`, `DisconnectVPN` (notification
  action), `keepVPNAlive` (BIND_JOB_SERVICE-protected). The only `exported` components are these
  two, both system-permission-protected.
- removed the Pause/Resume notification action (`addVpnActionsToNotification`). The app
  has no pause concept; a paused tunnel (`LEVEL_VPNPAUSED`) would surface as an unhandled state.
  The Disconnect action is kept.
- foreground notification text aligned to the WireGuard pattern — title is just the
  profile name (`notifcation_title` `"OpenVPN - %s"` → `"%s"`) and the byte-count line
  (`statusline_bytecount`) is `Connected ↑ {upSpeed} ↓ {downSpeed}`.
- the foreground-notification small icon (`ic_stat_vpn` and the
  `ic_stat_vpn_offline`/`_outline`/`_empty_halo` drawables) now use the same VPN-key vector as
  wireguard_dart, for a consistent status-bar/notification icon across both protocols.
- Removed application-level branding from the library manifest: `android:name`
  (ICSOpenVPNApplication), `icon`, `roundIcon`, `label`, `theme`, `allowBackup`, `appCategory`,
  `supportsRtl`. The library no longer imposes ics-openvpn's icon/label/theme/Application on the
  host app (consumers need no `tools:replace`).
- Deleted the bundled launcher resources (`mipmap*/ic_launcher*`, `drawable/ic_launcher3_foreground`)
  so they cannot leak into a consumer app's launcher icon via resource merge.
- Removed `android:process=":openvpn"` from all services → they run in the app's main process.
  Required for correctness: `VpnStatus`/`ProfileManager` are per-process statics (status + the
  temporary profile must be visible to the service in-process), and it avoids the ANR-prone
  cross-process StatusListener bridge.

## Source
- **Upstream:** `schwabe/ics-openvpn`
- **Tag:** `v0.7.55`  (HEAD commit `f9e66b2845b03e5f67b81b8c0613e829a5484383`)
- **Submodules (pinned):**
  | Submodule | Commit |
  |---|---|
  | `main/src/main/cpp/openssl` (schwabe/platform_external_openssl) | `bd116192e16f53f3f91b0d0efc20dfd36e1cfac7` |
  | `main/src/main/cpp/openvpn` (schwabe/openvpn) | `e2e36469b41e59187297eaf3dd96cf0b71a70de0` |
  | `main/src/main/cpp/openvpn3` (schwabe/openvpn3) | `3e3cd518eadf0b8d9de441f095b841f93dd09fcc` |
  | `main/src/main/cpp/mbedtls` (ARMmbed/mbedtls) | `b1c8e41ae3b36a9a88e0cbee10ed38a577b54726` |
  | `main/src/main/cpp/lz4` (lz4/lz4) | `5ff839680134437dbf4678f3d0c7b371d84f4964` |
  | `main/src/main/cpp/asio` (chriskohlhoff/asio) | `03ae834edbace31a96157b89bf50e5ee464e5ef9` |

## Crypto versions shipped (verified in the submodule sources)
- **OpenSSL 3.4.1** (11 Feb 2025) — current, supported. (Contrast: the rejected
  `nizwar/openvpn_library` shipped EOL OpenSSL 1.1.1l.)
- **OpenVPN 2.7_git** (schwabe fork).

## Repackaging diff vs upstream v0.7.55
Upstream `main` is a `com.android.application`; an application module cannot be published
as a consumable AAR. The only changes made (no crypto/source/native changes):
- plugin `com.android.application` → `com.android.library`
- `android.applicationVariants.all { … }` → `android.libraryVariants.all { … }`
  (the SWIG OpenVPN3 binding-generation hook; `ApplicationVariant` → `LibraryVariant`)
- removed app-only blocks: `signingConfigs`, release signing wiring, `splits { abi }`,
  `bundle { codeTransparency }`, `versionCode`/`versionName`, `versionNameSuffix`
- `ndkVersion` pinned to the build host's installed NDK `28.2.13676358`
  (upstream pinned `28.0.12916984-rc2`)

## Build environment
- **Host:** macOS (Apple Silicon)
- **NDK:** `28.2.13676358`
- **SWIG:** 4.4.1
- **JDK:** 17, **Gradle:** 8.10.2, **AGP:** 8.8.0
- **CMake:** Android SDK / externalNativeBuild

## Verified at build time
- Native `.so` present for all 4 ABIs: `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64`.
- `classes.jar` contains `de.blinkt.openvpn.core.{ConfigParser, OpenVPNService, VpnStatus,
  VPNLaunchHelper, ProfileManager, IOpenVPNServiceInternal}` and `de.blinkt.openvpn.VpnProfile`.
- 16 KB page-size aligned (`LOAD` segment `Align 0x4000`) — Google Play compliant.

## How to reproduce
```
git clone --depth 1 --branch v0.7.55 https://github.com/schwabe/ics-openvpn.git
cd ics-openvpn && git submodule update --init --recursive --depth 1
# apply the repackaging diff to main/build.gradle.kts (application -> library; see above)
./gradlew :main:assembleSkeletonOvpn23Release
# output: main/build/outputs/aar/main-skeleton-ovpn23-release.aar
```
