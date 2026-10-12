package com.example.todo_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/** 结束闹钟仅清理常驻通知/悬浮窗；完成提醒由 Flutter 通知插件独立发出。 */
class FocusTimerEndReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val expected = context.getSharedPreferences("focus_native", Context.MODE_PRIVATE)
            .getLong("deadline", 0L)
        if (expected == 0L || intent.getLongExtra("deadline", -1L) != expected) return
        context.stopService(Intent(context, FocusOverlayService::class.java))
    }

    companion object {
        private fun pending(context: Context, deadline: Long) = PendingIntent.getBroadcast(
            context, 4000001,
            Intent(context, FocusTimerEndReceiver::class.java).putExtra("deadline", deadline),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        fun cancel(context: Context) {
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(pending(context, 0))
            context.getSharedPreferences("focus_native", Context.MODE_PRIVATE)
                .edit().remove("deadline").apply()
        }

        fun schedule(context: Context, deadline: Long) {
            cancel(context)
            if (deadline <= 0) return
            context.getSharedPreferences("focus_native", Context.MODE_PRIVATE)
                .edit().putLong("deadline", deadline).apply()
            val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val alarm = pending(context, deadline)
            try {
                if (Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms()) {
                    alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, alarm)
                } else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, alarm)
            } catch (_: SecurityException) {
                alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, deadline, alarm)
            }
        }
    }
}
