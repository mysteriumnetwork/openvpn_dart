#!/bin/bash

# Build de.blinkt OpenVPN Android Library Locally
# This clones ics-openvpn and builds the AAR locally

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LIBS_DIR="$PROJECT_ROOT/android/libs"

echo "========================================"
echo "Building de.blinkt OpenVPN AAR"
echo "========================================"
echo ""

# Create libs directory
mkdir -p "$LIBS_DIR"

# Clone ics-openvpn if not exists
ICS_OPENVPN_DIR="/tmp/ics-openvpn-build"

if [ ! -d "$ICS_OPENVPN_DIR" ]; then
    echo "Cloning ics-openvpn repository..."
    git clone https://github.com/schwabe/ics-openvpn.git "$ICS_OPENVPN_DIR"
else
    echo "Using existing ics-openvpn clone at $ICS_OPENVPN_DIR"
fi

echo ""
echo "Building OpenVPN AAR..."
cd "$ICS_OPENVPN_DIR/main"

if [ -f "../../gradlew" ]; then
    ../../gradlew assembleRelease
else
    gradle assembleRelease
fi

echo ""
echo "Copying built AAR to project..."
AAR_FILE="$ICS_OPENVPN_DIR/main/build/outputs/aar/main-release.aar"

if [ -f "$AAR_FILE" ]; then
    cp "$AAR_FILE" "$LIBS_DIR/openvpn-android.aar"
    echo "✓ OpenVPN AAR built successfully: $LIBS_DIR/openvpn-android.aar"
    echo ""
    echo "Update your build.gradle to use local AAR:"
    echo "  dependencies {"
    echo "    implementation files('libs/openvpn-android.aar')"
    echo "  }"
else
    echo "✗ Failed to find built AAR at: $AAR_FILE"
    exit 1
fi

echo ""
echo "Done!"
