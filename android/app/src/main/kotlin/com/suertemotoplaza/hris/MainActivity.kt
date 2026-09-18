package com.suertemotoplaza.hris

import android.app.AlarmManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * IN-APP UPDATE (2026-09-15): the `hris/app_update` channel. The Dart side downloads
 * and verifies the APK; this only asks ANDROID'S OWN INSTALLER to open it. Android
 * always shows its install screen — nothing here can install silently.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hris/app_update").setMethodCallHandler { call, result ->
            when (call.method) {
                // Android 8+ asks the user, once per app, to allow "Install unknown apps".
                "canInstall" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()
                )
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                    }
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    val file = if (path == null) null else File(path)
                    if (file == null || !file.exists()) {
                        result.error("NO_FILE", "The downloaded update is missing.", null)
                    } else {
                        try {
                            val uri = FileProvider.getUriForFile(this, "$packageName.update_provider", file)
                            startActivity(
                                Intent(Intent.ACTION_VIEW)
                                    .setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        // CLOCK REMINDERS (2026-09-18): may this app set EXACT alarms right now?
        // Asked of AlarmManager itself, because a permission plugin reads it off
        // the manifest's SCHEDULE_EXACT_ALARM entry — which this app declares for
        // Android 12 only; 13+ runs on USE_EXACT_ALARM, granted at install, and
        // the plugin reported that as "denied".
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hris/alarms").setMethodCallHandler { call, result ->
            when (call.method) {
                "canScheduleExact" -> result.success(
                    Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                        (getSystemService(ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()
                )
                else -> result.notImplemented()
            }
        }
    }
}
