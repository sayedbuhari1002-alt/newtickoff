package dev.tickoffreplacement.tickoff_replacement

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class TazkiyaneTasksWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        val today = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
        val dateLabel = SimpleDateFormat("EEE, d MMM", Locale.getDefault()).format(Date())
        val raw = widgetData.getString("tazkiyane_tasks_snapshot", null)
        val snapshot = try {
            if (raw.isNullOrBlank()) JSONObject() else JSONObject(raw)
        } catch (_: Exception) {
            JSONObject()
        }
        val recommendations = snapshot.optJSONArray("recommendations")
        val suggestedTasks = (0 until (recommendations?.length() ?: 0)).take(2).mapNotNull { index ->
            recommendations?.optJSONObject(index)?.optString("title", "")?.trim()?.takeIf { it.isNotBlank() }
        }
        val allTasks = snapshot.optJSONArray("tasks")
        data class WidgetTask(val title: String, val overdue: Boolean, val dueDate: String, val completed: Boolean)
        val dueTasks = mutableListOf<WidgetTask>()
        if (allTasks != null) {
            for (i in 0 until allTasks.length()) {
                val task = allTasks.optJSONObject(i) ?: continue
                val completed = task.optBoolean("isCompleted", false)
                val paused = task.optBoolean("isPaused", false)
                val dueDate = task.optString("dueDate", "")
                val scheduledDate = task.optString("scheduledDate", "")
                val reminderDate = task.optString("reminderDate", "")
                val startDate = if (reminderDate.isNotBlank()) reminderDate else dueDate
                val completedDate = task.optString("completedDate", "")
                val overdue = !completed && !paused && dueDate.isNotBlank() && dueDate < today
                val scheduledToday = !paused && (
                    scheduledDate == today ||
                    (startDate.isNotBlank() && startDate <= today &&
                        (dueDate.isBlank() || dueDate >= today))
                )
                val completedToday = completed && completedDate == today
                if (!scheduledToday && !overdue && !completedToday) continue
                val title = task.optString("title", "Untitled task").trim().ifBlank { "Untitled task" }
                dueTasks.add(WidgetTask(title, overdue, dueDate, completed))
            }
        }
        dueTasks.sortWith(
            compareBy<WidgetTask> { when { it.overdue -> 0; !it.completed -> 1; else -> 2 } }
                .thenBy { if (it.dueDate.isBlank()) "9999-99-99" else it.dueDate }
                .thenBy { it.title.lowercase(Locale.getDefault()) }
        )
        val lines = dueTasks.take(6).map {
            (if (it.completed) "✓ " else if (it.overdue) "! " else "• ") + it.title
        }
        val visibleText = if (lines.isEmpty()) "✓ No tasks for today" else lines.joinToString("\n")
        val totalOpen = dueTasks.count { !it.completed }
        val totalCompleted = dueTasks.count { it.completed }

        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.tazkiyane_tasks_widget).apply {
                setTextViewText(R.id.widget_date, dateLabel)
                setTextViewText(
                    R.id.widget_summary,
                    if (dueTasks.isEmpty()) "You're all clear"
                    else "$totalOpen open · $totalCompleted done"
                )
                setTextViewText(R.id.widget_tasks, visibleText)
                setTextViewText(
                    R.id.widget_recommendation,
                    when (suggestedTasks.size) {
                        0 -> "No extra task suggestion right now"
                        1 -> "Suggested next: ${suggestedTasks[0]}"
                        else -> "Suggested next: ${suggestedTasks[0]}\nThen: ${suggestedTasks[1]}"
                    }
                )
                val launchIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
                setOnClickPendingIntent(R.id.widget_root, launchIntent)
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
