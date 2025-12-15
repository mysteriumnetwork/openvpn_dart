#include <jni.h>
#include <android/log.h>
#include <cstring>
#include "openvpn_client.h"

#define LOG_TAG "OpenVPNJNI"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

// Global JNI state
static JavaVM* g_jvm = nullptr;
static jobject g_status_listener = nullptr;

// Status callback from native code to Java
void nativeStatusCallback(const char* status) {
    if (!g_jvm || !g_status_listener) {
        LOGD("No status listener registered");
        return;
    }

    JNIEnv* env = nullptr;
    bool attached = false;

    // Check if current thread is already attached
    if (g_jvm->GetEnv((void**)&env, JNI_VERSION_1_6) == JNI_EDETACHED) {
        // Thread is not attached, attach it
        if (g_jvm->AttachCurrentThread(&env, nullptr) != JNI_OK || !env) {
            LOGE("Failed to attach JNI thread");
            return;
        }
        attached = true;
    }

    try {
        jclass listenerClass = env->GetObjectClass(g_status_listener);
        jmethodID onStatusMethod = env->GetMethodID(listenerClass, "onStatus", "(Ljava/lang/String;)V");

        if (onStatusMethod) {
            jstring statusStr = env->NewStringUTF(status);
            env->CallVoidMethod(g_status_listener, onStatusMethod, statusStr);
            env->DeleteLocalRef(statusStr);
        }

        env->DeleteLocalRef(listenerClass);
    } catch (...) {
        LOGE("Exception in status callback");
    }

    // Only detach if we attached it
    if (attached) {
        g_jvm->DetachCurrentThread();
    }
}

extern "C" {

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void* reserved) {
    g_jvm = vm;
    LOGI("JNI_OnLoad: OpenVPN3 JNI bridge initialized");
    return JNI_VERSION_1_6;
}

void JNI_OnUnload(JavaVM* vm, void* reserved) {
    LOGI("JNI_OnUnload");
    g_jvm = nullptr;
}

JNIEXPORT jstring JNICALL Java_com_mysteriumvpn_openvpn_1dart_OpenVpnJni_getVersion(
        JNIEnv* env, jobject /* this */) {
    OpenVPNClient* client = OpenVPNClient::getInstance();
    const char* version = client->getVersion();
    LOGD("getVersion: %s", version);
    return env->NewStringUTF(version);
}

JNIEXPORT jboolean JNICALL Java_com_mysteriumvpn_openvpn_1dart_OpenVpnJni_initOpenVpn(
        JNIEnv* env, jobject /* this */) {
    LOGI("initOpenVpn");
    OpenVPNClient* client = OpenVPNClient::getInstance();
    bool result = client->initialize();
    return result ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_com_mysteriumvpn_openvpn_1dart_OpenVpnJni_startConnection(
        JNIEnv* env, jobject /* this */,
        jstring config_path, jstring username, jstring password,
        jint tun_fd,
        jobject status_listener) {
    LOGI("startConnection with TUN fd: %d", tun_fd);

    // Store status listener
    if (g_status_listener) {
        env->DeleteGlobalRef(g_status_listener);
    }
    g_status_listener = env->NewGlobalRef(status_listener);

    // Set callback and TUN fd
    OpenVPNClient* client = OpenVPNClient::getInstance();
    client->setStatusCallback(nativeStatusCallback);
    client->setTunFd(tun_fd);

    // Get strings
    const char* config = env->GetStringUTFChars(config_path, nullptr);
    const char* user = env->GetStringUTFChars(username, nullptr);
    const char* pass = env->GetStringUTFChars(password, nullptr);

    LOGD("Config: %s", config);

    bool result = client->connect(config, user, pass);

    env->ReleaseStringUTFChars(config_path, config);
    env->ReleaseStringUTFChars(username, user);
    env->ReleaseStringUTFChars(password, pass);

    return result ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_com_mysteriumvpn_openvpn_1dart_OpenVpnJni_stopConnection(
        JNIEnv* env, jobject /* this */) {
    LOGI("stopConnection");
    OpenVPNClient* client = OpenVPNClient::getInstance();
    bool result = client->disconnect();
    return result ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL Java_com_mysteriumvpn_openvpn_1dart_OpenVpnJni_getBytesIn(
        JNIEnv* env, jobject /* this */) {
    OpenVPNClient* client = OpenVPNClient::getInstance();
    return (jlong)client->getBytesIn();
}

JNIEXPORT jlong JNICALL Java_com_mysteriumvpn_openvpn_1dart_OpenVpnJni_getBytesOut(
        JNIEnv* env, jobject /* this */) {
    OpenVPNClient* client = OpenVPNClient::getInstance();
    return (jlong)client->getBytesOut();
}

JNIEXPORT jstring JNICALL Java_com_mysteriumvpn_openvpn_1dart_OpenVpnJni_getStatus(
        JNIEnv* env, jobject /* this */) {
    OpenVPNClient* client = OpenVPNClient::getInstance();
    const char* status = client->getStatus();
    LOGD("getStatus: %s", status);
    return env->NewStringUTF(status);
}

}
