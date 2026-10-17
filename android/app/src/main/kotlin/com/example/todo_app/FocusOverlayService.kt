package com.example.todo_app

import android.app.Service
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Build
import android.provider.Settings
import android.view.ViewConfiguration
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import kotlin.math.abs

/** 专注计时悬浮窗：暖白钟盘，可拖动，点击回到应用。 */
open class FocusOverlayService : Service() {
    protected open val training = false
    private val notificationId get() = if (training) 4000012 else NOTIFICATION_ID
    private val channelId get() = if (training) "workout_running" else CHANNEL
    private fun launchIntent(): Intent? = packageManager.getLaunchIntentForPackage(packageName)?.apply {
        if (training) { action = "com.todo.app.OPEN_WORKOUT"; putExtra("openWorkout", true) }
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var clockView: FocusClockView? = null
    private var plannedSeconds = 1
    private val handler = Handler(Looper.getMainLooper())
    private var phase = "focus"

    private var stopwatch = true
    private var startEpochMs = 0L
    private var targetEpochMs = 0L
    private var paused = false
    private var frozenSeconds = 0
    private var title = ""

    private val tick = object : Runnable {
        override fun run() {
            if (!paused && !stopwatch && currentSeconds() == 0) {
                stopSelf()
                return
            }
            updateText()
            // 系统通知自身驱动秒数；仅悬浮窗需要每秒刷新，避免后台空转。
            if (overlayView != null && !paused) handler.postDelayed(this, 1000)
            else if (!paused && !stopwatch) {
                handler.postDelayed(this,
                    (targetEpochMs - System.currentTimeMillis()).coerceAtLeast(1L))
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        stopwatch = intent.getBooleanExtra(EXTRA_STOPWATCH, false)
        startEpochMs = intent.getLongExtra(EXTRA_START, System.currentTimeMillis())
        targetEpochMs = intent.getLongExtra(EXTRA_TARGET, 0L)
        paused = intent.getBooleanExtra(EXTRA_PAUSED, false)
        frozenSeconds = intent.getIntExtra(EXTRA_FROZEN, 0)
        title = intent.getStringExtra(EXTRA_TITLE) ?: ""
        phase = intent.getStringExtra("phase") ?: "focus"
        plannedSeconds = intent.getIntExtra("planned", 1)
        startForeground(notificationId, timerNotification())
        if (!training) FocusTimerEndReceiver.schedule(this, if (paused || stopwatch) 0L else targetEpochMs)
        if (intent.getBooleanExtra("overlay", false) && Settings.canDrawOverlays(this)) {
            try { showOverlay() } catch (_: RuntimeException) { removeOverlay() }
        } else removeOverlay()
        updateText()
        handler.removeCallbacks(tick)
        handler.post(tick)
        return START_NOT_STICKY
    }

    private fun phaseTitle() = if (training) "训练计时" else when (phase) {
        "shortBreak" -> "短休息"
        "longBreak" -> "长休息"
        else -> "番茄专注"
    }

    private fun timerNotification(): Notification {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(
                channelId, if (training) "正在进行的训练" else "正在进行的番茄钟", NotificationManager.IMPORTANCE_LOW).apply {
                description = "通知栏与锁屏计时，不播放声音"
                setSound(null, null)
                enableVibration(false)
            })
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId)
            else Notification.Builder(this)
        val launch = launchIntent()!!
        val open = PendingIntent.getActivity(this, notificationId, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        builder.setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(phaseTitle() + if (paused) " · 已暂停" else "")
            .setContentText(if (title.isBlank()) "点击返回应用" else title)
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        if (paused) {
            builder.setSubText(format(frozenSeconds)).setShowWhen(false)
        } else {
            builder.setWhen(if (stopwatch) startEpochMs else targetEpochMs)
                .setUsesChronometer(true).setChronometerCountDown(!stopwatch)
        }
        if (Build.VERSION.SDK_INT >= 31) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    private fun currentSeconds(): Int {
        if (paused) return frozenSeconds
        val millis = if (stopwatch) System.currentTimeMillis() - startEpochMs
            else targetEpochMs - System.currentTimeMillis()
        return (if (stopwatch) millis / 1000 else kotlin.math.ceil(millis / 1000.0).toLong())
            .coerceIn(0L, Int.MAX_VALUE.toLong()).toInt()
    }

    private fun format(seconds: Int): String {
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
    }

    private fun updateText() {
        clockView?.update(currentSeconds(), paused, title, phaseTitle(), stopwatch, plannedSeconds)
    }

    private fun showOverlay() {
        if (overlayView != null) return
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val density = resources.displayMetrics.density
        clockView = FocusClockView(this)
        overlayView = clockView

        val params = WindowManager.LayoutParams(
            (120 * density).toInt(),
            (140 * density).toInt(),
            if (Build.VERSION.SDK_INT >= 26) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = if (training) (resources.displayMetrics.widthPixels - 140 * density).toInt().coerceAtLeast(0) else 40
        params.y = if (training) (240 * density).toInt() else 200

        // 拖动 + 点击回应用
        var downRawX = 0f
        var downRawY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        val slop = ViewConfiguration.get(this).scaledTouchSlop
        overlayView!!.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX; downRawY = event.rawY
                    startX = params.x; startY = params.y; moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (moved || abs(dx) > slop || abs(dy) > slop) {
                        moved = true
                        val metrics = resources.displayMetrics
                        params.x = (startX + dx.toInt()).coerceIn(0,
                            (metrics.widthPixels - (overlayView?.width ?: 0)).coerceAtLeast(0))
                        params.y = (startY + dy.toInt()).coerceIn(0,
                            (metrics.heightPixels - (overlayView?.height ?: 0)).coerceAtLeast(0))
                        try { windowManager?.updateViewLayout(overlayView, params) }
                        catch (_: RuntimeException) { removeOverlay() }
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        val launch = launchIntent()
                        if (launch != null) startActivity(launch)
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> true
                else -> false
            }
        }

        windowManager?.addView(overlayView, params)

    }

    private fun removeOverlay() {
        overlayView?.let { try { windowManager?.removeView(it) } catch (_: RuntimeException) {} }
        overlayView = null
        clockView = null
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        removeOverlay()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    companion object {
        const val NOTIFICATION_ID = 4000002
        const val CHANNEL = "pomodoro_running"
        const val EXTRA_STOPWATCH = "stopwatch"
        const val EXTRA_START = "start"
        const val EXTRA_TARGET = "target"
        const val EXTRA_PAUSED = "paused"
        const val EXTRA_FROZEN = "frozen"
        const val EXTRA_TITLE = "title"
    }
}
