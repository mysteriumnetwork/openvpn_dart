cmake_minimum_required(VERSION 3.22.1)

project(openvpn_dart_native)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# OpenVPN3 Core library path
set(OPENVPN3_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/openvpn3_core")

# OpenSSL paths
set(OPENSSL_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp/openssl/android_openssl/ssl_3")
set(OPENSSL_INCLUDE_DIR "${OPENSSL_ROOT_DIR}/include")
set(OPENSSL_LIB_DIR "${OPENSSL_ROOT_DIR}/${ANDROID_ABI}")

# Source files for JNI bridge with OpenVPN3 Core integration
set(OPENVPN_SOURCES
    src/main/cpp/openvpn_jni.cpp
    src/main/cpp/openvpn_client.cpp
    src/main/cpp/openvpn3_integration.cpp
    src/main/cpp/openvpn_protocol.cpp
    src/main/cpp/openvpn_tls.cpp
)

# Include OpenVPN3 and OpenSSL headers
include_directories(
    "${OPENVPN3_CORE_DIR}"
    "${OPENSSL_INCLUDE_DIR}"
)

# Create shared library
add_library(openvpn3_jni SHARED
    ${OPENVPN_SOURCES}
)

# Import prebuilt OpenSSL libraries
add_library(ssl SHARED IMPORTED)
set_target_properties(ssl PROPERTIES
    IMPORTED_LOCATION "${OPENSSL_LIB_DIR}/libssl_3.so"
)

add_library(crypto SHARED IMPORTED)
set_target_properties(crypto PROPERTIES
    IMPORTED_LOCATION "${OPENSSL_LIB_DIR}/libcrypto_3.so"
)

# Link Android libraries and OpenSSL
target_link_libraries(openvpn3_jni
    log
    android
    ssl
    crypto
)

# Define that we have OpenSSL
target_compile_definitions(openvpn3_jni PRIVATE HAVE_OPENSSL)

# Compiler flags
target_compile_options(openvpn3_jni PRIVATE
    -Wall
    -Wextra
    -Wpedantic
    -fPIC
    -fvisibility=hidden
    -DOPENVPN_ANDROID
)

# Architecture-specific optimizations
if(ANDROID_ABI STREQUAL "arm64-v8a")
    target_compile_options(openvpn3_jni PRIVATE -O3 -march=armv8-a)
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    target_compile_options(openvpn3_jni PRIVATE -O3 -march=armv7-a -mfpu=neon)
elseif(ANDROID_ABI STREQUAL "x86_64")
    target_compile_options(openvpn3_jni PRIVATE -O3 -march=x86-64)
elseif(ANDROID_ABI STREQUAL "x86")
    target_compile_options(openvpn3_jni PRIVATE -O3 -march=i686)
endif()
