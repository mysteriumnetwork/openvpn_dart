package com.mysteriumvpn.openvpn_dart

import android.content.Context
import android.net.LocalServerSocket
import android.net.LocalSocket
import android.net.LocalSocketAddress
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.io.PrintWriter

class OpenVpnManagementThread(
    private val context: Context,
    private val service: OpenVPNService?
) : Runnable {
    
    private val TAG = "OpenVpnMgmt"
    private var serverSocket: LocalServerSocket? = null
    private var socket: LocalSocket? = null
    private var managementReader: BufferedReader? = null
    private var managementWriter: PrintWriter? = null
    private var isRunning = false
    private val handler = Handler(Looper.getMainLooper())
    private var bytesIn: Long = 0
    private var bytesOut: Long = 0
    private var isConnected = false
    
    fun openManagementInterface(): Boolean {
        return try {
            val socketName = "${context.cacheDir.absolutePath}/mgmt_socket"
            val localSocket = LocalSocket()
            
            var attempts = 0
            while (attempts < 10) {
                try {
                    localSocket.bind(LocalSocketAddress(socketName, LocalSocketAddress.Namespace.FILESYSTEM))
                    break
                } catch (e: IOException) {
                    attempts++
                    Thread.sleep(300)
                }
            }
            
            serverSocket = LocalServerSocket(localSocket.fileDescriptor)
            Log.i(TAG, "Management interface opened at $socketName")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open management interface", e)
            false
        }
    }

    override fun run() {
        isRunning = true
        try {
            socket = serverSocket?.accept()
            if (socket != null) {
                managementReader = BufferedReader(InputStreamReader(socket!!.inputStream))
                managementWriter = PrintWriter(socket!!.outputStream, true)
                
                Log.i(TAG, "Management client connected")
                processManagementCommands()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Management thread error", e)
        } finally {
            cleanup()
        }
    }

    private fun processManagementCommands() {
        try {
            var line: String? = null
            while (isRunning && managementReader?.readLine().also { line = it } != null) {
                line?.let { processCommand(it) }
            }
        } catch (e: IOException) {
            if (isRunning) {
                Log.e(TAG, "Error reading management command", e)
            }
        }
    }

    private fun processCommand(command: String) {
        Log.d(TAG, "Management command: $command")
        
        when {
            command.startsWith(">PASSWORD:") -> {
                sendCommand("password All \"dummy\"\n")
            }
            command.startsWith(">NEED-OK") -> {
                val parts = command.split(" ")
                if (parts.size >= 2) {
                    val needType = parts[1]
                    when (needType) {
                        "OPENTUN" -> handleOpenTun()
                        "IFCONFIG" -> handleIfconfig(command)
                        "ROUTE" -> handleRoute(command)
                        "DNS" -> handleDns(command)
                        else -> sendCommand("needok '$needType' ok\n")
                    }
                }
            }
            command.startsWith(">INFO") || command.startsWith("SUCCESS") || command.startsWith("HOLD") -> {
                Log.d(TAG, "INFO: $command")
            }
            command.startsWith(">STATE:") -> {
                parseStateChange(command)
            }
            command.startsWith(">BYTECOUNT") -> {
                parseBytecount(command)
            }
        }
    }

    private fun handleOpenTun() {
        try {
            val tunFd = service?.openTun()
            if (tunFd != null) {
                sendCommandWithFd("tun-fd", tunFd)
                Log.i(TAG, "TUN FD sent to OpenVPN")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open TUN", e)
            sendCommand("needok 'OPENTUN' cancel\n")
        }
    }

    private fun handleIfconfig(command: String) {
        try {
            val parts = command.split(" ")
            if (parts.size >= 4) {
                val localIp = parts[2]
                val netmask = parts[3]
                service?.setLocalIP(localIp, netmask)
                Log.i(TAG, "IP configured: $localIp/$netmask")
            }
            sendCommand("needok 'IFCONFIG' ok\n")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to handle IFCONFIG", e)
            sendCommand("needok 'IFCONFIG' cancel\n")
        }
    }

    private fun handleRoute(command: String) {
        try {
            val parts = command.split(" ")
            if (parts.size >= 4) {
                val network = parts[2]
                val netmask = parts[3]
                val gateway = if (parts.size > 4) parts[4] else "0.0.0.0"
                service?.addRoute(network, netmask, gateway)
                Log.d(TAG, "Route added: $network/$netmask via $gateway")
            }
            sendCommand("needok 'ROUTE' ok\n")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to handle ROUTE", e)
            sendCommand("needok 'ROUTE' cancel\n")
        }
    }

    private fun handleDns(command: String) {
        try {
            val parts = command.split(" ")
            if (parts.size >= 3) {
                val dns = parts[2]
                service?.addDnsServer(dns)
                Log.d(TAG, "DNS added: $dns")
            }
            sendCommand("needok 'DNS' ok\n")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to handle DNS", e)
            sendCommand("needok 'DNS' cancel\n")
        }
    }

    private fun parseStateChange(command: String) {
        try {
            val parts = command.split(",")
            if (parts.isNotEmpty()) {
                val state = parts.lastOrNull()?.trim() ?: return
                when {
                    state.contains("CONNECTED") -> {
                        isConnected = true
                        service?.updateStatus(ConnectionStatus.connected)
                        Log.i(TAG, "VPN Connected")
                    }
                    state.contains("CONNECTING") -> {
                        service?.updateStatus(ConnectionStatus.connecting)
                        Log.i(TAG, "VPN Connecting")
                    }
                    state.contains("DISCONNECTED") -> {
                        isConnected = false
                        service?.updateStatus(ConnectionStatus.disconnected)
                        Log.i(TAG, "VPN Disconnected")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to parse state change", e)
        }
    }

    private fun parseBytecount(command: String) {
        try {
            val parts = command.split(",")
            if (parts.size >= 2) {
                bytesIn = parts[0].replaceFirst(">BYTECOUNT ", "").toLongOrNull() ?: 0
                bytesOut = parts[1].toLongOrNull() ?: 0
                service?.updateStatistics(bytesIn, bytesOut)
            }
        } catch (e: Exception) {
            Log.d(TAG, "Failed to parse bytecount", e)
        }
    }

    private fun sendCommand(cmd: String) {
        try {
            managementWriter?.print(cmd)
            managementWriter?.flush()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send command: $cmd", e)
        }
    }

    private fun sendCommandWithFd(cmd: String, fd: android.os.ParcelFileDescriptor) {
        try {
            val writer = PrintWriter(socket!!.outputStream, true)
            writer.println("$cmd ${fd.fd}")
            writer.flush()
            Log.d(TAG, "Sent FD for: $cmd")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send FD command", e)
        }
    }

    fun stop() {
        isRunning = false
        try {
            sendCommand("signal SIGTERM\n")
        } catch (e: Exception) {
            Log.d(TAG, "Error sending SIGTERM", e)
        }
        cleanup()
    }

    fun isConnected(): Boolean = isConnected

    fun getBytesIn(): Long = bytesIn

    fun getBytesOut(): Long = bytesOut

    private fun cleanup() {
        try {
            managementReader?.close()
            managementWriter?.close()
            socket?.close()
            serverSocket?.close()
        } catch (e: Exception) {
            Log.d(TAG, "Error during cleanup", e)
        }
        serverSocket = null
        socket = null
    }
}
