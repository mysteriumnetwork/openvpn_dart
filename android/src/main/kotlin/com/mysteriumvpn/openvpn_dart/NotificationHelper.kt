package com.mysteriumvpn.openvpn_dart

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import java.util.Locale

class NotificationHelper(private val context: Context) {

    companion object {
        const val CHANNEL_ID = "network_openvpn_channel"
        const val NOTIFICATION_ID = 424242

        fun initNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "VPN Status",
                    NotificationManager.IMPORTANCE_LOW
                )
                channel.description = "VPN connection"
                val mgr = context.getSystemService(NotificationManager::class.java)
                mgr?.createNotificationChannel(channel)
            }
        }
    }

    private fun getMainActivityIntent(): PendingIntent {
        val intent = Intent(context, getLauncherActivity()).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
        
        return PendingIntent.getActivity(context, 0, intent, flags)
    }

    private fun getLauncherActivity(): Class<*> {
        return try {
            // Try to get the main launcher activity from the app package
            val packageName = context.packageName
            val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
            val componentName = launchIntent?.component
            if (componentName != null) {
                Class.forName(componentName.className)
            } else {
                // Fallback to MainActivity
                Class.forName("$packageName.MainActivity")
            }
        } catch (e: Exception) {
            // If all else fails, try the standard MainActivity path
            try {
                Class.forName("${context.packageName}.MainActivity")
            } catch (e2: Exception) {
                // Last resort - return a dummy class (shouldn't happen)
                this.javaClass
            }
        }
    }

    fun buildTunnelNotification(
        status: ConnectionStatus,
        stats: TunnelStatistics?,
        notificationTitle: String,
    ): Notification {

        val baseText = when (status) {
            ConnectionStatus.connecting -> "Connecting..."
            ConnectionStatus.connected -> {
                if (stats != null) {
                    val rx = formatBytes(stats.totalRx)
                    val tx = formatBytes(stats.totalTx)
                    "↓ $rx  ↑ $tx"
                } else {
                    "Connected"
                }
            }
            ConnectionStatus.disconnecting -> "Disconnecting..."
            ConnectionStatus.disconnected -> "Disconnected"
            else -> "Unknown"
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

        return builder
            .setContentTitle(notificationTitle)
            .setContentText(baseText)
            .setSmallIcon(R.drawable.baseline_vpn_key_24)
            .setContentIntent(getMainActivityIntent())
            .setOngoing(status == ConnectionStatus.connected || status == ConnectionStatus.connecting)
            .setAutoCancel(false)
            .build()
    }

    fun updateStatusNotification(
        status: ConnectionStatus,
        stats: TunnelStatistics?,
        notificationTitle: String
    ) {
        val notification = buildTunnelNotification(status, stats, notificationTitle)
        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    private fun formatBytes(bytes: Long): String {
        return when {
            bytes < 1024 -> "$bytes B"
            bytes < 1024 * 1024 -> String.format(Locale.US, "%.1f KB", bytes / 1024.0)
            bytes < 1024 * 1024 * 1024 -> String.format(Locale.US, "%.1f MB", bytes / (1024.0 * 1024.0))
            else -> String.format(Locale.US, "%.1f GB", bytes / (1024.0 * 1024.0 * 1024.0))
        }
    }
}
