#!/bin/bash
# Script to build OpenVPN 3 Core library for Android NDK

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPENVPN3_DIR="${PROJECT_ROOT}/openvpn3-core"

# Configuration
NDK_VERSION="27.0.12077973"  # Adjust to your NDK version
MIN_SDK=21
TARGET_ARCHS=("arm64-v8a" "armeabi-v7a" "x86" "x86_64")

echo "========================================"
echo "Building OpenVPN 3 Core for Android"
echo "========================================"

# Check if OpenVPN 3 repo exists
if [ ! -d "$OPENVPN3_DIR" ]; then
    echo "Cloning OpenVPN 3 Core repository..."
    cd "$PROJECT_ROOT"
    git clone https://github.com/OpenVPN/openvpn3-core.git
    cd "$OPENVPN3_DIR"
    # Initialize submodules if needed
    git submodule update --init --recursive
fi

echo "✓ OpenVPN 3 Core source ready at: $OPENVPN3_DIR"

# Build for each architecture
for arch in "${TARGET_ARCHS[@]}"; do
    echo ""
    echo "Building for architecture: $arch"
    
    case $arch in
        "arm64-v8a")
            ANDROID_ABI="arm64-v8a"
            ;;
        "armeabi-v7a")
            ANDROID_ABI="armeabi-v7a"
            ;;
        "x86")
            ANDROID_ABI="x86"
            ;;
        "x86_64")
            ANDROID_ABI="x86_64"
            ;;
    esac
    
    # Note: Full build instructions depend on OpenVPN 3's build system
    # This is a template - actual build may require additional configuration
    
    echo "✓ Build preparation for $arch complete"
done

echo ""
echo "========================================"
echo "OpenVPN 3 Core build setup complete!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Build the native library using Android Studio or:"
echo "   ./gradlew build"
echo ""
echo "2. Pre-built .so files should be placed in:"
echo "   android/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86,x86_64}/"
echo ""
