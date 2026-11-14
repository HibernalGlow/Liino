package app.liino.liino_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Phase 3 foreground host for the Android capture/transport lifecycle.
 *
 * Audio capture itself lives in Rust (`liino-audio-core` / `liino-engine`);
 * this service only keeps the process alive while a link is active and owns
 * the user-visible notification required by Android's microphone policy.
 */
class AudioForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val role = intent?.getStringExtra(EXTRA_ROLE) ?: "auto"
        createNotificationChannel()
        val notification = buildNotification(role)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.audio_service_channel),
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.audio_service_channel_description)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(role: String): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(getString(R.string.audio_service_title))
            .setContentText(getString(R.string.audio_service_text, role))
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }

    companion object {
        const val EXTRA_ROLE = "role_mode"
        private const val CHANNEL_ID = "liino_audio"
        private const val NOTIFICATION_ID = 7102
    }
}
