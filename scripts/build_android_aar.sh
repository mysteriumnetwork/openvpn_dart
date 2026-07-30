#!/usr/bin/env bash
#
# Builds the ics-openvpn native backend AAR consumed by the openvpn_dart Android plugin,
# FROM SOURCE, and stages it into android/localmaven/.
#
# Why this exists: ics-openvpn is published as an application, not a consumable library, and the
# only ready-made prebuilt (nizwar/openvpn_library) ships EOL OpenSSL. We build a current,
# auditable AAR ourselves. See android/localmaven/PROVENANCE.md.
#
# Prerequisites (build host):
#   - Android SDK (ANDROID_HOME or ~/Library/Android/sdk), with NDK ${NDK_VERSION} + cmake
#   - swig            (macOS: `brew install swig`)
#   - JDK 17, git
#
# Usage:
#   scripts/build_android_aar.sh [<aar-version>]
#   e.g. scripts/build_android_aar.sh 0.7.55-myst
#
# After it runs: update the coordinate in android/build.gradle and the SHA-256 in
# android/localmaven/PROVENANCE.md (the script prints both).
set -euo pipefail

# --- Config (keep in sync with PROVENANCE.md) ---------------------------------------------------
ICS_TAG="v0.7.55"
NDK_VERSION="28.2.13676358"
AAR_VERSION="${1:-0.7.55-myst}"
GROUP_PATH="network/mysterium/openvpn/icsopenvpn"
GRADLE_VARIANT="assembleSkeletonOvpn23Release"   # skeleton = core w/o UI, ovpn23 = OpenVPN3+OpenSSL

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH="${REPO_ROOT}/scripts/icsopenvpn-mysterium-${ICS_TAG}.patch"
BUILD_DIR="${BUILD_DIR:-/tmp/icsopenvpn-aar-build}"
SRC="${BUILD_DIR}/src"
OUT_DIR="${REPO_ROOT}/android/localmaven/${GROUP_PATH}/${AAR_VERSION}"

echo "==> openvpn_dart ics-openvpn AAR build"
echo "    tag=${ICS_TAG}  ndk=${NDK_VERSION}  version=${AAR_VERSION}"

# --- Prerequisite checks ------------------------------------------------------------------------
command -v swig >/dev/null || { echo "ERROR: swig not found (brew install swig)"; exit 1; }
command -v git  >/dev/null || { echo "ERROR: git not found"; exit 1; }
[ -f "$PATCH" ] || { echo "ERROR: patch not found: $PATCH"; exit 1; }
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
[ -d "$SDK" ] || { echo "ERROR: Android SDK not found at $SDK (set ANDROID_HOME)"; exit 1; }

# --- Clone pinned source + submodules -----------------------------------------------------------
rm -rf "$SRC"
mkdir -p "$BUILD_DIR"
echo "==> Cloning schwabe/ics-openvpn@${ICS_TAG} + submodules (shallow)…"
git clone --depth 1 --branch "$ICS_TAG" https://github.com/schwabe/ics-openvpn.git "$SRC"
git -C "$SRC" submodule update --init --recursive --depth 1

# --- Apply the Mysterium repackaging patch ------------------------------------------------------
# (application->library, strip imposed branding, drop :openvpn process, key notification icon,
#  WireGuard-style notification text, remove Pause/Resume action.)
echo "==> Applying repackaging patch…"
git -C "$SRC" apply --binary "$PATCH"
echo "sdk.dir=${SDK}" > "$SRC/local.properties"

# --- Build ---------------------------------------------------------------------------------------
echo "==> Building :main:${GRADLE_VARIANT} (NDK build; first run ~10-15 min)…"
( cd "$SRC" && ./gradlew ":main:${GRADLE_VARIANT}" --console=plain )
AAR_SRC="$SRC/main/build/outputs/aar/main-skeleton-ovpn23-release.aar"
[ -f "$AAR_SRC" ] || { echo "ERROR: AAR not produced at $AAR_SRC"; exit 1; }

# --- Verify --------------------------------------------------------------------------------------
echo "==> Verifying AAR…"
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
  # libovpnexec.so is the binary ics actually execs (needs useLegacyPackaging on the consumer);
  # libopenvpn.so is the engine. Verify both per ABI.
  for lib in libopenvpn.so libovpnexec.so; do
    unzip -l "$AAR_SRC" | grep -q "jni/${abi}/${lib}" || { echo "ERROR: missing ${abi}/${lib}"; exit 1; }
  done
done
unzip -l "$AAR_SRC" | grep -q "ic_launcher" && { echo "ERROR: launcher resources leaked into AAR"; exit 1; }
echo "    ABIs present, no launcher leak."

# --- Stage into localmaven -----------------------------------------------------------------------
echo "==> Staging into ${OUT_DIR}"
mkdir -p "$OUT_DIR"
cp "$AAR_SRC" "${OUT_DIR}/icsopenvpn-${AAR_VERSION}.aar"
cat > "${OUT_DIR}/icsopenvpn-${AAR_VERSION}.pom" <<POM
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>network.mysterium.openvpn</groupId>
    <artifactId>icsopenvpn</artifactId>
    <version>${AAR_VERSION}</version>
    <packaging>aar</packaging>
    <description>ics-openvpn backend (built from source, v0.7.55). See PROVENANCE.md.</description>
    <dependencies>
        <dependency>
            <groupId>androidx.annotation</groupId>
            <artifactId>annotation</artifactId>
            <version>1.9.1</version>
            <scope>runtime</scope>
        </dependency>
        <dependency>
            <groupId>androidx.core</groupId>
            <artifactId>core-ktx</artifactId>
            <version>1.13.1</version>
            <scope>runtime</scope>
        </dependency>
    </dependencies>
</project>
POM

SHA="$(shasum -a 256 "${OUT_DIR}/icsopenvpn-${AAR_VERSION}.aar" | awk '{print $1}')"
echo ""
echo "==> DONE."
echo "    AAR:    android/localmaven/${GROUP_PATH}/${AAR_VERSION}/icsopenvpn-${AAR_VERSION}.aar"
echo "    SHA256: ${SHA}"
echo ""
echo "    Next: set the coordinate in android/build.gradle to"
echo "      implementation \"network.mysterium.openvpn:icsopenvpn:${AAR_VERSION}\""
echo "    and update the SHA-256 + version in android/localmaven/PROVENANCE.md."
