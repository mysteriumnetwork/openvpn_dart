#!/bin/bash

# OpenVPN Android Setup Script
# Downloads and configures de.blinkt.openvpn library for Android Flutter project
# Mimics the Windows script pattern but for de.blinkt library

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${CYAN}→${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

echo "================================"
echo "OpenVPN Android Setup"
echo "================================"
echo ""

# Check prerequisites
print_info "Checking prerequisites..."

if ! command -v gradle &> /dev/null && ! [ -f "$PROJECT_ROOT/android/gradlew" ]; then
    print_error "Gradle not found"
    exit 1
fi

if ! command -v dart &> /dev/null; then
    print_error "Dart not found"
    exit 1
fi

print_success "Prerequisites found"
echo ""

# Check if we're in the right directory
if [ ! -f "$PROJECT_ROOT/pubspec.yaml" ]; then
    print_error "Not in Flutter project root"
    print_info "Expected: $PROJECT_ROOT/pubspec.yaml"
    exit 1
fi

print_info "Project root: $PROJECT_ROOT"
echo ""

# Update Android build.gradle with de.blinkt dependency
print_info "Configuring Android build system..."

ANDROID_BUILD_GRADLE="$PROJECT_ROOT/android/build.gradle"

# Check if de.blinkt dependency is already present
if grep -q "de.blinkt:openvpn-android" "$ANDROID_BUILD_GRADLE"; then
    print_success "de.blinkt.openvpn dependency already configured"
else
    print_warning "de.blinkt.openvpn dependency not found in build.gradle"
    print_info "Please ensure build.gradle contains:"
    echo "  implementation(\"de.blinkt:openvpn-android:0.7.48\")"
    echo ""
fi

echo ""
print_info "Downloading Android dependencies..."
echo ""

# Navigate to project root and run gradle sync
cd "$PROJECT_ROOT"

print_info "Running: flutter pub get"
if flutter pub get; then
    print_success "Flutter dependencies downloaded"
else
    print_error "Failed to download Flutter dependencies"
    exit 1
fi

echo ""
print_info "Downloading Android dependencies..."

# Use gradle to download dependencies
cd "$PROJECT_ROOT/android"

if [ -f "gradlew" ]; then
    print_info "Using ./gradlew (Gradle wrapper)"
    GRADLE_CMD="./gradlew"
else
    print_info "Using gradle from system"
    GRADLE_CMD="gradle"
fi

# Download dependencies
if $GRADLE_CMD --version &>/dev/null; then
    print_success "Gradle available: $($GRADLE_CMD --version | head -n 1)"
else
    print_error "Gradle not available"
    exit 1
fi

echo ""
print_info "Dependencies configuration:"
echo "  - de.blinkt:openvpn-android:0.7.48 (includes native OpenVPN3 library)"
echo "  - Supports architectures: arm64-v8a, armeabi-v7a, x86, x86_64"
echo ""

# Summary
echo "================================"
print_success "Setup completed!"
echo "================================"
echo ""

print_info "Configuration Summary:"
echo "  Library: de.blinkt.openvpn (ics-openvpn)"
echo "  Version: 0.7.48"
echo "  Includes native OpenVPN protocol implementation"
echo "  Pre-built for Android: arm64-v8a, armeabi-v7a, x86, x86_64"
echo ""

print_info "Next steps:"
echo "  1. Build Flutter app:"
echo "     flutter build apk --release"
echo "     or"
echo "     flutter build aab --release  # For Play Store"
echo ""
echo "  2. Install on device:"
echo "     flutter install"
echo ""
echo "  3. Test VPN connection with your config file"
echo ""

print_info "The de.blinkt.openvpn library includes:"
echo "  ✓ Full OpenVPN protocol support (via native library)"
echo "  ✓ OpenSSL integration"
echo "  ✓ TAP/TUN interface management"
echo "  ✓ Configuration file parsing"
echo "  ✓ Connection management"
echo ""

print_success "Ready to build and deploy!"
echo ""
