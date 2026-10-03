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
 *
 * Layout style comes from the 'widget_style' key ('compact' | 'detailed' |
 * 'minimal' | 'debts_goals', set from Settings via HomeWidgetService.setStyle).
 * NOTE: the original detailed layout keeps its file name (expense_widget.xml)
 * so that expense_widget_info.xml's initialLayout and the manifest need no
 * changes; 'detailed' maps to R.layout.expense_widget. Setting text on a view
 * id that a layout does not contain is a silent no-op in RemoteViews, so all
 * ids can be set unconditionally below.
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
        val debts = prefs.getString("khorcha_debts", "—") ?: "—"
        val goal = prefs.getString("khorcha_goal", "—") ?: "—"
        val style = prefs.getString("widget_style", "detailed") ?: "detailed"

        val layoutRes = when (style) {
            "compact" -> R.layout.expense_widget_compact
            "minimal" -> R.layout.expense_widget_minimal
            "debts_goals" -> R.layout.expense_widget_debts_goals
            else -> R.layout.expense_widget // "detailed"
        }

        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, layoutRes)
            views.setTextViewText(R.id.widget_today, "আজকে: $today")
            views.setTextViewText(R.id.widget_month, "এই মাসে: $month")
            views.setTextViewText(R.id.widget_balance, "Balance: $balance")
            views.setTextViewText(R.id.widget_debts, "ধার: $debts")
            views.setTextViewText(R.id.widget_goal, "লক্ষ্য: $goal")
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
