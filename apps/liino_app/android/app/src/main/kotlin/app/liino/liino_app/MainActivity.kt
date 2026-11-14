package app.liino.liino_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Phase 3 Android adapter contract used by
 * `lib/platform/android_audio_bridge.dart`.
 */
class MainActivity : FlutterActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ensureAudioPermissions" -> ensureAudioPermissions(result)
                    "startForegroundAudioService" -> {
                        startAudioService(call.argument<String>("roleMode") ?: "auto")
                        result.success(null)
                    }
                    "stopForegroundAudioService" -> {
                        stopService(Intent(this, AudioForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requiredPermissions(): List<String> {
        val permissions = mutableListOf(Manifest.permission.RECORD_AUDIO)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions += Manifest.permission.BLUETOOTH_CONNECT
            permissions += Manifest.permission.BLUETOOTH_SCAN
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions += Manifest.permission.POST_NOTIFICATIONS
        }
        return permissions
    }

    private fun ensureAudioPermissions(result: MethodChannel.Result) {
        val missing = requiredPermissions().filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("permission_request_in_flight", "Another permission request is pending", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PERMISSION_REQUEST) return
        val result = pendingPermissionResult ?: return
        pendingPermissionResult = null
        val denied = grantResults.indices.any {
            grantResults[it] != PackageManager.PERMISSION_GRANTED
        }
        result.success(!denied)
    }

    private fun startAudioService(roleMode: String) {
        val intent = Intent(this, AudioForegroundService::class.java)
            .putExtra(AudioForegroundService.EXTRA_ROLE, roleMode)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private companion object {
        const val CHANNEL = "dev.liino.app/android_audio"
        const val PERMISSION_REQUEST = 7101
    }
}
