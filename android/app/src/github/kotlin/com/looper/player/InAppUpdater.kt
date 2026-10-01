package com.looper.player

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * github flavor: installs an update APK that Dart downloaded from the
 * project's GitHub releases (see lib/core/services/update). In-App Updates is
 * a Google Play feature, so this build neither includes the Play library nor
 * uses it; Dart sees "unsupported" from [checkAndStart] and runs the GitHub
 * flow instead. The play flavor's src/play counterpart has the Play
 * implementation and none of this.
 *
 * The install goes through a PackageInstaller session, so no FileProvider is
 * needed and the system's own confirmation dialog also walks the user through
 * allowing "install unknown apps" for Looper the first time.
 */
@Suppress("UNUSED_PARAMETER")
class InAppUpdater(private val activity: Activity, onDownloaded: () -> Unit) {
    private companion object {
        const val TAG = "LooperApkInstall"
        const val ACTION_INSTALL_STATUS = "com.looper.player.APK_INSTALL_STATUS"
    }

    // The in-flight installApk() call, answered once the session ends.
    private var pendingInstall: MethodChannel.Result? = null
    @Volatile
    private var sessionId = -1
    private var receiverRegistered = false

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val id = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
            if (id != sessionId) return // a session an earlier call abandoned
            val status = intent.getIntExtra(
                PackageInstaller.EXTRA_STATUS,
                PackageInstaller.STATUS_FAILURE
            )
            val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
            when (status) {
                PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                    val confirm = if (Build.VERSION.SDK_INT >= 33) {
                        intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(Intent.EXTRA_INTENT)
                    }
                    try {
                        activity.startActivity(confirm)
                    } catch (e: Exception) {
                        Log.e(TAG, "Could not open the install confirmation", e)
                        abandonSession()
                        finish("failed", e.message)
                    }
                }
                PackageInstaller.STATUS_SUCCESS -> finish("success", null)
                PackageInstaller.STATUS_FAILURE_ABORTED -> finish("aborted", message)
                PackageInstaller.STATUS_FAILURE_STORAGE -> finish("storage", message)
                else -> finish("failed", message)
            }
        }
    }

    fun checkAndStart(result: MethodChannel.Result) {
        result.success(mapOf("status" to "unsupported", "versionCode" to 0))
    }

    fun completeUpdate() {}

    /** The update-channel methods only this flavor has. */
    fun onMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "getSupportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())
            "installApk" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("bad_args", "path is required", null)
                } else {
                    install(File(path), result)
                }
            }
            else -> return false
        }
        return true
    }

    /**
     * Stages [apk] in a PackageInstaller session and commits it. Completes
     * [result] with {"status": ..., "message": ...} where status is:
     *  - "success" installed (rarely seen - the update replaces this process)
     *  - "aborted" the user dismissed the system dialog
     *  - "storage" not enough free space
     *  - "failed"  anything else; message carries the system's reason
     */
    private fun install(apk: File, result: MethodChannel.Result) {
        // A dialog the user left without answering never reports back, so a
        // new request simply supersedes the old one.
        finish("aborted", null)
        abandonSession()
        pendingInstall = result
        registerReceiver()

        val installer = activity.packageManager.packageInstaller
        Thread {
            var id = -1
            try {
                // Sessions left behind by a killed process keep their staged
                // copy of the APK until abandoned.
                installer.mySessions.forEach { stale ->
                    try {
                        installer.abandonSession(stale.sessionId)
                    } catch (_: Exception) {
                    }
                }

                val length = apk.length()
                val params = PackageInstaller.SessionParams(
                    PackageInstaller.SessionParams.MODE_FULL_INSTALL
                ).apply {
                    setAppPackageName(activity.packageName)
                    setSize(length)
                }
                id = installer.createSession(params)
                sessionId = id
                installer.openSession(id).use { session ->
                    session.openWrite("update.apk", 0, length).use { out ->
                        apk.inputStream().use { it.copyTo(out, 1 shl 16) }
                        session.fsync(out)
                    }
                    // The system fills in the status extras, so the intent
                    // has to be mutable; naming the package keeps it explicit.
                    val intent = Intent(ACTION_INSTALL_STATUS).setPackage(activity.packageName)
                    var flags = PendingIntent.FLAG_UPDATE_CURRENT
                    if (Build.VERSION.SDK_INT >= 31) flags = flags or PendingIntent.FLAG_MUTABLE
                    val callback = PendingIntent.getBroadcast(activity, id, intent, flags)
                    session.commit(callback.intentSender)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Could not stage the update", e)
                val failed = id
                activity.runOnUiThread {
                    if (failed != -1 && failed == sessionId) abandonSession()
                    if (pendingInstall === result) finish("failed", e.message)
                }
            }
        }.start()
    }

    private fun finish(status: String, message: String?) {
        val result = pendingInstall ?: return
        pendingInstall = null
        result.success(mapOf("status" to status, "message" to message))
    }

    private fun abandonSession() {
        val id = sessionId
        sessionId = -1
        if (id == -1) return
        try {
            activity.packageManager.packageInstaller.abandonSession(id)
        } catch (_: Exception) {
            // already finished or gone
        }
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        ContextCompat.registerReceiver(
            activity,
            statusReceiver,
            IntentFilter(ACTION_INSTALL_STATUS),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        receiverRegistered = true
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean = false

    /**
     * Back from the system dialog: if the session is gone and nothing was
     * reported, the user backed out without the abort broadcast reaching us.
     */
    fun onResume() {
        val id = sessionId
        if (pendingInstall == null || id == -1) return
        val info = try {
            activity.packageManager.packageInstaller.getSessionInfo(id)
        } catch (_: Exception) {
            null
        }
        if (info == null) {
            sessionId = -1
            finish("aborted", null)
        }
    }

    fun onDestroy() {
        if (receiverRegistered) {
            try {
                activity.unregisterReceiver(statusReceiver)
            } catch (_: Exception) {
            }
            receiverRegistered = false
        }
        // The channel may already be gone with the engine; drop the call.
        pendingInstall = null
    }
}
