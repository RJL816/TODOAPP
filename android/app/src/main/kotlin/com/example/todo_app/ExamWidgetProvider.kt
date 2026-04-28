package com.example.todo_app

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import android.view.View
import android.app.PendingIntent
import android.content.Intent
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.*
import org.json.JSONArray
import org.json.JSONObject

class ExamWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    override fun onEnabled(context: Context) {
        // Widget 首次添加时调用
    }

    override fun onDisabled(context: Context) {
        // 最后一个 Widget 被移除时调用
    }

    companion object {
        fun updateAppWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            appWidgetId: Int
        ) {
            val views = RemoteViews(context.packageName, R.layout.exam_widget)
            
            // 获取 SharedPreferences 数据（home_widget 包使用的文件名）
            val prefs = context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
            val examsJson = prefs.getString("exams_data", null)
            
            // 点击打开 App
            val intent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(
                context, 
                0, 
                intent, 
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_title, pendingIntent)
            
            // 隐藏所有考试条目
            views.setViewVisibility(R.id.exam_item_1, View.GONE)
            views.setViewVisibility(R.id.exam_item_2, View.GONE)
            views.setViewVisibility(R.id.exam_item_3, View.GONE)
            views.setViewVisibility(R.id.no_exam_text, View.VISIBLE)
            
            if (examsJson != null && examsJson.isNotEmpty()) {
                try {
                    val exams = JSONArray(examsJson)
                    val now = System.currentTimeMillis()
                    val upcomingExams = mutableListOf<JSONObject>()
                    
                    // 筛选未来的考试
                    for (i in 0 until exams.length()) {
                        val exam = exams.getJSONObject(i)
                        val examTime = exam.getLong("examTime")
                        if (examTime > now) {
                            upcomingExams.add(exam)
                        }
                    }
                    
                    // 按时间排序
                    upcomingExams.sortBy { it.getLong("examTime") }
                    
                    // 显示最多3个考试
                    if (upcomingExams.isNotEmpty()) {
                        views.setViewVisibility(R.id.no_exam_text, View.GONE)
                        
                        val itemIds = listOf(
                            Triple(R.id.exam_item_1, R.id.exam_name_1, R.id.exam_countdown_1),
                            Triple(R.id.exam_item_2, R.id.exam_name_2, R.id.exam_countdown_2),
                            Triple(R.id.exam_item_3, R.id.exam_name_3, R.id.exam_countdown_3)
                        )
                        
                        for ((index, exam) in upcomingExams.take(3).withIndex()) {
                            val (itemId, nameId, countdownId) = itemIds[index]
                            val name = exam.getString("name")
                            val examTime = exam.getLong("examTime")
                            val countdown = getCountdownText(examTime, now)
                            
                            views.setViewVisibility(itemId, View.VISIBLE)
                            views.setTextViewText(nameId, name)
                            views.setTextViewText(countdownId, countdown)
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
        
        private fun getCountdownText(examTime: Long, now: Long): String {
            val diff = examTime - now
            val days = diff / (1000 * 60 * 60 * 24)
            val hours = (diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60)
            
            return when {
                days > 0 -> "⏰ ${days}天${hours}时"
                hours > 0 -> "⏰ ${hours}小时"
                else -> "⏰ 即将开始"
            }
        }
    }
}
