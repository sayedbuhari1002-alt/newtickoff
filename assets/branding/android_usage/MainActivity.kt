package dev.tickoffreplacement.tickoff_replacement

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ResolveInfo
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "tazkiyane/usage_stats"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsageAccess" -> result.success(hasUsageAccess())
                "getInstalledApps" -> {
                    try {
                        result.success(getInstalledLauncherApps())
                    } catch (error: Exception) {
                        result.error("APP_LIST_FAILED", error.message, null)
                    }
                }
                "openUsageAccessSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("USAGE_SETTINGS_UNAVAILABLE", error.message, null)
                    }
                }
                "queryUsageEvents" -> {
                    if (!hasUsageAccess()) {
                        result.error("USAGE_ACCESS_REQUIRED", "Enable Usage Access for Tazkiyane in Android Settings.", null)
                    } else {
                        try {
                            val start = call.argument<Number>("startMillis")?.toLong() ?: 0L
                            val end = call.argument<Number>("endMillis")?.toLong() ?: 0L
                            val packages = call.argument<List<String>>("packageNames")?.toSet() ?: emptySet()
                            result.success(readUsageEvents(start, end, packages))
                        } catch (error: Exception) {
                            result.error("USAGE_QUERY_FAILED", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun getInstalledLauncherApps(): List<Map<String, String>> {
        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val activities: List<ResolveInfo> = packageManager.queryIntentActivities(launcherIntent, 0)
        val seenPackages = mutableSetOf<String>()
        return activities.mapNotNull { resolveInfo ->
            val activity = resolveInfo.activityInfo ?: return@mapNotNull null
            val appPackage = activity.packageName
            if (appPackage == packageName || !seenPackages.add(appPackage)) return@mapNotNull null
            val label = resolveInfo.loadLabel(packageManager)?.toString()?.trim().orEmpty()
            if (label.isBlank()) null else mapOf("packageName" to appPackage, "label" to label)
        }.sortedBy { it["label"]?.lowercase() ?: "" }
    }

    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun readUsageEvents(start: Long, end: Long, packages: Set<String>): List<Map<String, Any>> {
        if (end <= start || packages.isEmpty()) return emptyList()
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(start, end) ?: return emptyList()
        val event = UsageEvents.Event()
        val active = mutableMapOf<String, Long>()
        val records = mutableListOf<Map<String, Any>>()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val packageName = event.packageName ?: continue
            if (!packages.contains(packageName)) continue
            val eventType = event.eventType
            val foreground = eventType == UsageEvents.Event.MOVE_TO_FOREGROUND ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && eventType == UsageEvents.Event.ACTIVITY_RESUMED)
            val background = eventType == UsageEvents.Event.MOVE_TO_BACKGROUND ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && (eventType == UsageEvents.Event.ACTIVITY_PAUSED || eventType == UsageEvents.Event.ACTIVITY_STOPPED))
            if (foreground) {
                val previous = active.put(packageName, event.timeStamp)
                if (previous != null && event.timeStamp > previous) {
                    records.add(mapOf("packageName" to packageName, "startMillis" to previous, "endMillis" to event.timeStamp))
                }
            } else if (background) {
                val previous = active.remove(packageName)
                if (previous != null && event.timeStamp > previous) {
                    records.add(mapOf("packageName" to packageName, "startMillis" to previous, "endMillis" to event.timeStamp))
                }
            }
        }
        // An app that is still in the foreground must only be charged up to
        // the current time when the selected day is today, never through the
        // future end-of-day query boundary.
        val cutoff = minOf(end, System.currentTimeMillis())
        for ((packageName, from) in active) {
            if (cutoff > from) records.add(mapOf("packageName" to packageName, "startMillis" to from, "endMillis" to cutoff))
        }
        return records
    }
}
