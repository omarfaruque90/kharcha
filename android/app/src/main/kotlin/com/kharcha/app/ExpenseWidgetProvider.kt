package com.kharcha.app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.widget.RemoteViews
import com.dergo.homewidget.HomeWidgetPlugin

/**
 * Home-screen widget for Khorcha: shows today's spending, this month's
 * spending and the monthly balance. Values are written from Dart via
 * HomeWidgetService (home_widget plugin) into 'khorcha_today',
 * 'khorcha_month' and 'khorcha_balance' keys; the provider just renders them.
 */
class ExpenseWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val today = prefs.getString("khorcha_today", "৳0") ?: "৳0"
        val month = prefs.getString("khorcha_month", "৳0") ?: "৳0"
        val balance = prefs.getString("khorcha_balance", "৳0") ?: "৳0"

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.expense_widget)
            views.setTextViewText(R.id.widget_today, "আজকে: $today")
            views.setTextViewText(R.id.widget_month, "এই মাসে: $month")
            views.setTextViewText(R.id.widget_balance, "Balance: $balance")
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }

    override fun onEnabled(context: Context) {
        // No-op: the widget is refreshed from Dart via HomeWidget.updateWidget.
    }

    override fun onDisabled(context: Context) {
        // No-op: nothing to clean up.
    }
}
