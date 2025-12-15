package com.mysteriumvpn.openvpn_dart

interface StatusListener {
    fun onStatus(status: String)
}

object OpenVpnJni {
    private var libraryLoaded = false

    init {
        try {
            System.loadLibrary("openvpn3_jni")
            libraryLoaded = true
        } catch (e: UnsatisfiedLinkError) {
            libraryLoaded = false
            android.util.Log.e("OpenVpnJni", "Failed to load native library: ${e.message}")
        }
    }

    fun isLoaded(): Boolean = libraryLoaded

    external fun getVersion(): String
    external fun initOpenVpn(): Boolean
    external fun startConnection(
        configPath: String,
        username: String,
        password: String,
        tunFd: Int,
        statusListener: StatusListener
    ): Boolean
    external fun stopConnection(): Boolean
    external fun getBytesIn(): Long
    external fun getBytesOut(): Long
    external fun getStatus(): String
}
