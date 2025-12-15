#!/bin/bash
# Setup OpenVPN binary from ics-openvpn for the Flutter app

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ASSETS_DIR="$SCRIPT_DIR/example/assets"
TEMP_DIR=$(mktemp -d)

echo "🔧 Setting up OpenVPN binary from ics-openvpn..."

# Create assets directory
mkdir -p "$ASSETS_DIR"

# Clone ics-openvpn repository
echo "📦 Cloning ics-openvpn repository..."
cd "$TEMP_DIR"
git clone --depth 1 https://github.com/schwabe/ics-openvpn.git

# Find and copy the ARM64 binary (most common on modern Android)
echo "🔍 Looking for ARM64 OpenVPN binary..."
BINARY_PATH=$(find "$TEMP_DIR/ics-openvpn" -name "openvpn" -type f 2>/dev/null | grep -E "(arm64|aarch64)" | head -1)

if [ -z "$BINARY_PATH" ]; then
    echo "⚠️  ARM64 binary not found, trying any ARM binary..."
    BINARY_PATH=$(find "$TEMP_DIR/ics-openvpn" -name "openvpn" -type f 2>/dev/null | grep "arm" | head -1)
fi

if [ -z "$BINARY_PATH" ]; then
    echo "❌ OpenVPN binary not found in ics-openvpn repository"
    echo "Available binaries:"
    find "$TEMP_DIR/ics-openvpn" -name "openvpn" -type f 2>/dev/null | head -10 || echo "None found"
    rm -rf "$TEMP_DIR"
    exit 1
fi

echo "✅ Found binary at: $BINARY_PATH"

# Copy and make executable
echo "📋 Copying binary to app assets..."
cp "$BINARY_PATH" "$ASSETS_DIR/openvpn"
chmod +x "$ASSETS_DIR/openvpn"

# Verify the binary was copied
if [ -f "$ASSETS_DIR/openvpn" ]; then
    SIZE=$(stat -f%z "$ASSETS_DIR/openvpn" 2>/dev/null || stat -c%s "$ASSETS_DIR/openvpn" 2>/dev/null || echo "unknown")
    echo "✅ Binary copied successfully ($SIZE bytes)"
else
    echo "❌ Failed to copy binary"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Check if pubspec.yaml already has the asset
if ! grep -q "assets/openvpn" "$SCRIPT_DIR/example/pubspec.yaml"; then
    echo "📝 Adding asset to example/pubspec.yaml..."
    # This is a simplified check - might need manual verification
    echo "⚠️  Please verify that example/pubspec.yaml has this under flutter:"
    echo "   assets:"
    echo "     - assets/openvpn"
else
    echo "✅ Asset already declared in pubspec.yaml"
fi

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Verify 'assets/openvpn' is in example/pubspec.yaml under 'flutter:' section"
echo "2. Run: cd $SCRIPT_DIR/example && flutter clean"
echo "3. Run: flutter pub get && flutter build apk --debug"
echo "4. Test the app with your .ovpn configuration"
