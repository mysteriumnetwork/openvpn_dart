#!/bin/bash

# Complete OpenVPN Android Setup Script
# This downloads and integrates OpenVPN binary with your Flutter app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${CYAN}→${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

echo ""
echo "════════════════════════════════════════════════════════════"
echo "   OpenVPN Android Integration Setup"
echo "════════════════════════════════════════════════════════════"
echo ""

# Step 1: Create assets directory
print_info "Setting up assets directory..."
ASSETS_DIR="$PROJECT_ROOT/example/assets"
mkdir -p "$ASSETS_DIR"
print_success "Assets directory ready: $ASSETS_DIR"

# Step 2: Information about OpenVPN binary availability
echo ""
print_info "OpenVPN Binary Availability"
echo ""
echo "  Option A: Download from ICS-OpenVPN releases"
echo "    URL: https://github.com/schwabe/ics-openvpn/releases"
echo ""
echo "  Option B: Build from OpenVPN Android project"
echo "    URL: https://github.com/OpenVPN/openvpn-android"
echo ""
echo "  Option C: Use pre-compiled ARM64 binary"
echo "    Most compatible with modern Android devices"
echo ""

# Step 3: Check if binary already exists
if [ -f "$ASSETS_DIR/openvpn" ]; then
    print_success "OpenVPN binary already present"
    SIZE=$(du -h "$ASSETS_DIR/openvpn" | cut -f1)
    echo "  Location: $ASSETS_DIR/openvpn"
    echo "  Size: $SIZE"
else
    print_warning "OpenVPN binary not found"
    echo ""
    echo "Manual Setup Required:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "1. Download OpenVPN binary for Android ARM64:"
    echo ""
    echo "   Download from:"
    echo "   https://github.com/schwabe/ics-openvpn/releases"
    echo ""
    echo "   Or search for 'openvpn-arm64' in releases"
    echo ""
    echo "2. Place the binary here:"
    echo "   $ASSETS_DIR/openvpn"
    echo ""
    echo "3. Make sure it's executable:"
    echo "   chmod +x $ASSETS_DIR/openvpn"
    echo ""
    echo "4. Verify with:"
    echo "   file $ASSETS_DIR/openvpn"
    echo ""
    echo "5. Then rebuild:"
    echo "   flutter clean && flutter build apk --release"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

# Step 4: Verify Flutter setup
echo ""
print_info "Verifying Flutter setup..."

if ! command -v flutter &> /dev/null; then
    print_error "Flutter not found in PATH"
    exit 1
fi

FLUTTER_VERSION=$(flutter --version | head -1)
print_success "Flutter found: $FLUTTER_VERSION"

# Step 5: Check example app structure
if [ ! -f "$PROJECT_ROOT/example/pubspec.yaml" ]; then
    print_error "Example app not found"
    exit 1
fi
print_success "Example app found"

# Step 6: Android setup check
print_info "Checking Android setup..."

ANDROID_MANIFEST="$PROJECT_ROOT/example/android/app/src/main/AndroidManifest.xml"
if grep -q "android.permission.BIND_VPN_SERVICE" "$ANDROID_MANIFEST" 2>/dev/null; then
    print_success "VPN service permissions configured"
else
    print_warning "VPN service permissions may not be configured"
fi

# Step 7: Summary
echo ""
echo "════════════════════════════════════════════════════════════"
echo "Setup Summary"
echo "════════════════════════════════════════════════════════════"
echo ""

if [ -f "$ASSETS_DIR/openvpn" ]; then
    print_success "✓ OpenVPN binary found"
    echo ""
    echo "Next steps:"
    echo "  1. flutter clean"
    echo "  2. flutter build apk --release"
    echo "  3. flutter install"
    echo "  4. Test VPN connection"
else
    print_warning "⚠ OpenVPN binary needed"
    echo ""
    echo "Next steps:"
    echo "  1. Download OpenVPN binary (see instructions above)"
    echo "  2. Place in: $ASSETS_DIR/openvpn"
    echo "  3. chmod +x $ASSETS_DIR/openvpn"
    echo "  4. flutter clean"
    echo "  5. flutter build apk --release"
fi

echo ""
print_info "Kotlin Integration"
echo "  OpenVPNBinaryRunner.kt - Handles binary execution"
echo "  OpenVPN3Manager.kt - Uses binary runner"
echo "  OpenVPNService.kt - VPN interface and lifecycle"
echo ""

print_info "For support, see:"
echo "  ANDROID_VPN_IMPLEMENTATION.md - Technical details"
echo "  VPN_INTERNET_CONNECTION_EXPLAINED.md - Architecture"
echo ""

echo "════════════════════════════════════════════════════════════"
echo ""
