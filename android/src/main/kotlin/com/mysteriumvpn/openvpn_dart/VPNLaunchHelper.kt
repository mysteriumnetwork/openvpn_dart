package com.mysteriumvpn.openvpn_dart

import android.content.Context
import android.os.Build
import android.util.Log
import java.io.File
import java.io.FileOutputStream

/**
 * Utility to extract and manage OpenVPN binary from assets
 */
class VPNLaunchHelper(private val context: Context) {
    companion object {
        private const val TAG = "VPNLaunchHelper"
        private const val BINARY_NAME = "pie_openvpn"
    }

    fun getOpenvpnBinary(): File? {
        return try {
            val binDir = File(context.filesDir, "bin")
            val binary = File(binDir, "openvpn")

            // Return if already exists and executable
            if (binary.exists() && binary.canExecute()) {
                Log.d(TAG, "Using cached OpenVPN binary")
                return binary
            }

            // Try to extract from assets
            binDir.mkdirs()
            extractBinaryFromAssets(binary)
                ?: trySystemBinary()
        } catch (e: Exception) {
            Log.e(TAG, "Error getting OpenVPN binary", e)
            null
        }
    }

    private fun extractBinaryFromAssets(outputFile: File): File? {
        return try {
            val abi = Build.SUPPORTED_ABIS[0]
            val assetName = "$BINARY_NAME.$abi"
            
            Log.d(TAG, "Attempting to extract $assetName from assets")
            
            val input = context.assets.open(assetName)
            val output = FileOutputStream(outputFile)

            input.use { inputStream ->
                output.use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
            }

            outputFile.setExecutable(true)
            Log.i(TAG, "Successfully extracted OpenVPN binary")
            outputFile
        } catch (e: Exception) {
            Log.w(TAG, "Failed to extract binary from assets: ${e.message}")
            null
        }
    }

    private fun trySystemBinary(): File? {
        val systemBinary = File("/system/bin/openvpn")
        return if (systemBinary.exists()) {
            Log.i(TAG, "Using system OpenVPN binary")
            systemBinary
        } else {
            Log.e(TAG, "No OpenVPN binary found in system or assets")
            null
        }
    }

    fun buildOpenvpnArguments(configPath: String, managementSocket: String): Array<String> {
        return arrayOf(
            getOpenvpnBinary()?.absolutePath ?: throw Exception("OpenVPN binary not found"),
            "--config", configPath,
            "--management", "127.0.0.1", "11194",
            "--management-query-passwords",
            "--management-signal",
            "--verb", "3"
        )
    }
}
