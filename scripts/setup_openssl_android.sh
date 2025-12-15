#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$SCRIPT_DIR/../android"
OPENSSL_DIR="$ANDROID_DIR/src/main/cpp/openssl"

echo "Setting up OpenSSL for Android..."

# Create OpenSSL directory
mkdir -p "$OPENSSL_DIR"
cd "$OPENSSL_DIR"

# Download prebuilt OpenSSL for Android
# Using prebuilt binaries from openssl-android
OPENSSL_ANDROID_REPO="https://github.com/KDAB/android_openssl"

echo "Cloning OpenSSL Android repository..."
if [ ! -d "android_openssl" ]; then
    git clone --depth 1 "$OPENSSL_ANDROID_REPO" android_openssl
fi

cd android_openssl

echo "OpenSSL setup complete!"
echo "OpenSSL libraries are in: $OPENSSL_DIR/android_openssl"
