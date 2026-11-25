package com.suertemotoplaza.hris

import android.app.ActivityManager
import android.app.AlarmManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.print.PrintAttributes
import android.print.PrintManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi
import java.io.File

/**
 * IN-APP UPDATE (2026-09-15): the `hris/app_update` channel. The Dart side downloads
 * and verifies the APK; this only asks ANDROID'S OWN INSTALLER to open it. Android
 * always shows its install screen — nothing here can install silently.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // PRINT PAYSLIP (2026-10-23): hand the payslip web page shown in the app's
        // WebView to ANDROID'S OWN print screen (print, or Save as PDF). The Dart
        // side passes the webview_flutter WebView's identifier; A4 landscape is
        // the payslip's page.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hris/print").setMethodCallHandler { call, result ->
            if (call.method != "printWebView") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val id = call.argument<Number>("id")?.toLong()
            val name = call.argument<String>("name") ?: "Payslip"
            val webView = if (id == null) null else WebViewFlutterAndroidExternalApi.getWebView(flutterEngine, id)
            if (webView == null) {
                result.error("NO_WEBVIEW", "The payslip page is not ready.", null)
                return@setMethodCallHandler
            }
            try {
                val printManager = getSystemService(Context.PRINT_SERVICE) as PrintManager
                val attributes = PrintAttributes.Builder()
                    .setMediaSize(PrintAttributes.MediaSize.ISO_A4.asLandscape())
                    .build()
                printManager.print(name, webView.createPrintDocumentAdapter(name), attributes)
                result.success(true)
            } catch (e: Exception) {
                result.error("PRINT_FAILED", e.message, null)
            }
        }
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
        // PHONE SETTINGS THAT CAN STOP RECORDING (2026-11-19): read them, and open
        // the exact page that changes each. Every read is guarded: a phone that
        // refuses one answers null ("could not tell"), never an error.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "hris/phone_state").setMethodCallHandler { call, result ->
            when (call.method) {
                "read" -> {
                    val m = HashMap<String, Any?>()
                    val power = getSystemService(Context.POWER_SERVICE) as PowerManager
                    m["powerSaveOn"] = guard { power.isPowerSaveMode }
                    m["locationPowerSaveMode"] =
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) guard { power.locationPowerSaveMode } else null
                    m["backgroundRestricted"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        guard { (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).isBackgroundRestricted }
                    } else null
                    m["dataSaverOn"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        guard {
                            (getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).restrictBackgroundStatus ==
                                ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
                        }
                    } else null
                    m["model"] = Build.MODEL
                    m["osVersion"] = Build.VERSION.RELEASE
                    result.success(m)
                }
                // OFFLINE CLOCK-IN (2026-11-24): a clock the user cannot set — the time
                // since the phone started — and which start this is. The app keeps the
                // last server time beside it, so a punch made with no signal can say
                // when it happened even if the phone's own clock was changed.
                "clock" -> {
                    val m = HashMap<String, Any?>()
                    m["elapsedMs"] = SystemClock.elapsedRealtime()
                    m["bootCount"] = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        guard { Settings.Global.getInt(contentResolver, Settings.Global.BOOT_COUNT) }
                    } else null
                    result.success(m)
                }
                "openBatterySaver" -> result.success(
                    tryStart(Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)) || tryStart(appDetails())
                )
                "openDataSaver" -> result.success(
                    (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
                        tryStart(Intent(Settings.ACTION_IGNORE_BACKGROUND_DATA_RESTRICTIONS_SETTINGS, Uri.parse("package:$packageName")))) ||
                        tryStart(appDetails())
                )
                "openAutostart" -> result.success(AUTOSTART_PAGES.any { (pkg, cls) ->
                    tryStart(Intent().setComponent(ComponentName(pkg, cls)))
                })
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

    private fun <T> guard(read: () -> T): T? = try { read() } catch (e: Exception) { null }

    private fun appDetails() = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))

    /** Start a settings page; false when this phone has no such page or refuses it. */
    private fun tryStart(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    companion object {
        /** The makers' own Autostart / app-launch pages, tried in order. Names
         *  move between skin versions, so several per maker; the first that
         *  opens wins. No API reports these switches. */
        private val AUTOSTART_PAGES = listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oplus.safecenter" to "com.oplus.safecenter.permission.startup.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.hihonor.systemmanager" to "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.transsion.phonemaster" to "com.cyin.himgr.autostart.AutoStartActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
        )
    }
}
