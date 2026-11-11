package dev.tickoffreplacement.tickoff_replacement

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
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
                        result.success(getInstalledApps())
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
                "queryDailyUsageStats" -> {
                    if (!hasUsageAccess()) {
                        result.error("USAGE_ACCESS_REQUIRED", "Enable Usage Access for Tazkiyane in Android Settings.", null)
                    } else {
                        try {
                            val start = call.argument<Number>("startMillis")?.toLong() ?: 0L
                            val end = call.argument<Number>("endMillis")?.toLong() ?: 0L
                            val packages = call.argument<List<String>>("packageNames")?.toSet() ?: emptySet()
                            result.success(readDailyUsageStats(start, end, packages))
                        } catch (error: Exception) {
                            result.error("USAGE_STATS_QUERY_FAILED", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun getInstalledApps(): List<Map<String, String>> {
        // QUERY_ALL_PACKAGES is declared in the generated Android manifest.
        // Enumerating installed applications is necessary because some OEM and
        // preinstalled apps (including YouTube on certain devices) are not
        // consistently returned by a launcher-intent query.
        val applications: List<ApplicationInfo> =
            packageManager.getInstalledApplications(PackageManager.GET_META_DATA)

        return applications.mapNotNull { application ->
            val appPackage = application.packageName
            if (appPackage == packageName || !application.enabled) return@mapNotNull null

            // Keep regular installed apps and user-visible system apps. Omit
            // non-launchable system services so the picker is not flooded with
            // Android internals that users cannot meaningfully select.
            val isSystemApp = (application.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                (application.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
            val hasLauncherActivity = packageManager.getLaunchIntentForPackage(appPackage) != null
            if (isSystemApp && !hasLauncherActivity) return@mapNotNull null

            val label = application.loadLabel(packageManager)?.toString()?.trim().orEmpty()
            if (label.isBlank()) null else mapOf("packageName" to appPackage, "label" to label)
        }.distinctBy { it["packageName"] }
            .sortedBy { it["label"]?.lowercase() ?: "" }
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

    /**
     * Reconstruct package foreground sessions without treating an individual
     * Activity's onPause/onStop as the end of the whole package session.
     * Android Q+ emits ACTIVITY_RESUMED/PAUSED per Activity. A package remains
     * foreground while at least one of its Activities is resumed. STOPPED is
     * intentionally ignored because it is a later, activity-level callback and
     * can arrive after a different Activity in the same package has resumed.
     */
    private fun readUsageEvents(start: Long, end: Long, packages: Set<String>): List<Map<String, Any>> {
        if (end <= start || packages.isEmpty()) return emptyList()
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(start, end) ?: return emptyList()
        val event = UsageEvents.Event()
        val records = mutableListOf<Map<String, Any>>()
        val packageSessionStarts = mutableMapOf<String, Long>()
        val activeActivityCounts = mutableMapOf<String, MutableMap<String, Int>>()
        val unknownActivityKey = "__unknown_activity__"

        fun closeSession(packageName: String, at: Long) {
            val sessionStart = packageSessionStarts.remove(packageName) ?: return
            if (at > sessionStart) {
                records.add(mapOf(
                    "packageName" to packageName,
                    "startMillis" to sessionStart,
                    "endMillis" to at
                ))
            }
        }

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val eventType = event.eventType
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && eventType == UsageEvents.Event.DEVICE_SHUTDOWN) {
                // Device-level shutdown events use the system package name, not
                // one of the selected app package names. Close every open app.
                for (packageName in packageSessionStarts.keys.toList()) {
                    closeSession(packageName, event.timeStamp)
                }
                activeActivityCounts.clear()
                continue
            }
            val packageName = event.packageName ?: continue
            if (!packages.contains(packageName)) continue

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                when (eventType) {
                    UsageEvents.Event.ACTIVITY_RESUMED -> {
                        val activityName = event.className?.takeIf { it.isNotBlank() } ?: unknownActivityKey
                        val counts = activeActivityCounts.getOrPut(packageName) { mutableMapOf() }
                        val activeBefore = counts.values.sum()
                        counts[activityName] = (counts[activityName] ?: 0) + 1
                        if (activeBefore == 0 && !packageSessionStarts.containsKey(packageName)) {
                            packageSessionStarts[packageName] = event.timeStamp
                        }
                    }
                    UsageEvents.Event.ACTIVITY_PAUSED -> {
                        val counts = activeActivityCounts[packageName] ?: continue
                        val suppliedName = event.className?.takeIf { it.isNotBlank() }
                        val activityName = when {
                            suppliedName != null && (counts[suppliedName] ?: 0) > 0 -> suppliedName
                            suppliedName == null && counts.values.sum() == 1 -> counts.keys.firstOrNull()
                            else -> null
                        } ?: continue
                        val currentCount = counts[activityName] ?: 0
                        if (currentCount <= 1) counts.remove(activityName) else counts[activityName] = currentCount - 1
                        val activeAfter = counts.values.sum()
                        if (activeAfter == 0) {
                            activeActivityCounts.remove(packageName)
                            closeSession(packageName, event.timeStamp)
                        }
                    }
                    // ACTIVITY_STOPPED is not a package-background event.
                }
            } else {
                // Before Android Q the legacy events are package-level.
                when (eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                        if (!packageSessionStarts.containsKey(packageName)) {
                            packageSessionStarts[packageName] = event.timeStamp
                        }
                    }
                    UsageEvents.Event.MOVE_TO_BACKGROUND -> closeSession(packageName, event.timeStamp)
                }
            }
        }

        // If an app is still foreground at query time, stop its interval at now;
        // never extend the current day's usage into the future.
        val cutoff = minOf(end, System.currentTimeMillis())
        for (packageName in packageSessionStarts.keys.toList()) {
            closeSession(packageName, cutoff)
        }
        return records.sortedBy { (it["startMillis"] as Number).toLong() }
    }

    /**
     * Gets Android's daily aggregate for the selected apps. This is independent
     * of the event parser and is the primary source for each app's daily total.
     * An explicit availability flag prevents an unavailable stats query from
     * being mistaken for a genuine zero-minute day.
     */
    private fun readDailyUsageStats(
        start: Long,
        end: Long,
        packages: Set<String>
    ): Map<String, Any> {
        if (end <= start || packages.isEmpty()) {
            return mapOf("available" to true, "items" to emptyList<Map<String, Any>>())
        }
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val queryEnd = minOf(end, System.currentTimeMillis())
        if (queryEnd <= start) {
            return mapOf("available" to true, "items" to packages.map {
                mapOf("packageName" to it, "foregroundMillis" to 0L)
            })
        }

        val stats = manager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, queryEnd)
            ?: return mapOf("available" to false, "items" to emptyList<Map<String, Any>>())
        val totals = packages.associateWith { 0L }.toMutableMap()
        for (usage in stats) {
            val appPackage = usage.packageName ?: continue
            if (totals.containsKey(appPackage)) {
                totals[appPackage] = (totals[appPackage] ?: 0L) + usage.totalTimeInForeground
            }
        }
        val items = totals.map { (appPackage, foregroundMillis) ->
            mapOf("packageName" to appPackage, "foregroundMillis" to foregroundMillis)
        }
        return mapOf("available" to true, "items" to items)
    }

}
