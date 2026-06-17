package com.privacyog.pfsense_manager

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class PfSenseWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_pfsense_status)

            val profileName = widgetData.getString("profile_name", "pfSense Manager") ?: "pfSense Manager"
            val cpuTemp = widgetData.getString("cpu_temp", "--") ?: "--"
            val gatewayName = widgetData.getString("gateway_name", "--") ?: "--"
            val gatewayLatency = widgetData.getString("gateway_latency", "--") ?: "--"
            val trafficIn = widgetData.getString("traffic_in", "--") ?: "--"
            val trafficOut = widgetData.getString("traffic_out", "--") ?: "--"
            val lastUpdated = widgetData.getString("last_updated", "--") ?: "--"

            views.setTextViewText(R.id.widget_profile_name, profileName)
            views.setTextViewText(R.id.widget_cpu_temp, cpuTemp)
            views.setTextViewText(R.id.widget_gateway_name, "🌐 $gatewayName")
            views.setTextViewText(R.id.widget_gateway_latency, gatewayLatency)
            views.setTextViewText(R.id.widget_traffic_in, trafficIn)
            views.setTextViewText(R.id.widget_traffic_out, trafficOut)
            views.setTextViewText(R.id.widget_last_updated, lastUpdated)

            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = android.app.PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.widget_profile_name, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
