package com.example.budgeting_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import java.util.Calendar
import java.util.Locale

/**
 * Home-screen widget showing what can still be spent today and in this pay period.
 *
 * The app saves what is left in the current period and when that period starts
 * and ends (see home_widget_sync.dart). The per-day figure is worked out here
 * from today's date, so it stays correct as days pass even if the app isn't opened.
 */
class BudgetWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        val currency = prefs.getString("currency", "$") ?: "$"
        val left = prefs.getString("left_period", null)?.toDoubleOrNull()
        val start = prefs.getString("period_start", null)?.toLongOrNull()
        val end = prefs.getString("period_end", null)?.toLongOrNull()

        val today = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val dayMs = 24L * 60 * 60 * 1000
        // Rounded so a daylight-saving change inside the period can't shift the count.
        val daysLeft = if (end != null) Math.round((end - today).toDouble() / dayMs).toInt() else 0
        val current = left != null && start != null && end != null && today >= start && today < end

        val launch = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.budget_widget)
            if (current && left != null && daysLeft > 0) {
                val perDay = if (left > 0) left / daysLeft else 0.0
                views.setTextViewText(R.id.widget_title, "Left today")
                views.setTextViewText(R.id.widget_value, money(currency, perDay))
                views.setTextViewText(
                    R.id.widget_sub,
                    "${money(currency, left)} left · $daysLeft ${if (daysLeft == 1) "day" else "days"} to go",
                )
            } else {
                // The saved period has ended (or the app hasn't run yet).
                views.setTextViewText(R.id.widget_title, "Ledgerly")
                views.setTextViewText(R.id.widget_value, "Open app")
                views.setTextViewText(R.id.widget_sub, "Tap to refresh your numbers")
            }
            views.setOnClickPendingIntent(R.id.widget_root, launch)
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    private fun money(currency: String, v: Double): String {
        val neg = v < -0.004
        return (if (neg) "-" else "") + currency + String.format(Locale.US, "%,.2f", Math.abs(v))
    }
}
