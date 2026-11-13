package com.suertemotoplaza.hris

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * PHONE TURNED OFF (migration 119, 2026-11-13). On every boot, write WHEN the
 * phone started (now minus the time since boot) into the app's Flutter
 * SharedPreferences. The tracking service compares it with its own last
 * "alive" minute: a boot after that minute means the phone was off in between,
 * and the gap on the website then reads "The phone was turned off".
 *
 * The boot time, not "now": the plugin's own boot receiver may start the
 * service before this one runs, so the value must not depend on which ran first.
 */
class BootMarkReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED && action != "android.intent.action.QUICKBOOT_POWERON") return
        val bootedAtMs = System.currentTimeMillis() - SystemClock.elapsedRealtime()
        val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }.format(Date(bootedAtMs))
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("flutter.tracking.booted_at", iso)
            .apply()
    }
}
