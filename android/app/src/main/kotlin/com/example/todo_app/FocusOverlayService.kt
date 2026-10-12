package com.example.todo_app

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.TextView
import kotlin.math.abs

/** 专注计时悬浮窗：简约深色胶囊，可拖动，点击回到应用。 */
class FocusOverlayService : Service() {
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var titleView: TextView? = null
    private var timeView: TextView? = null
    private var handler: Handler? = null

    private var stopwatch = true
    private var startEpochMs = 0L
    private var targetEpochMs = 0L
    private var paused = false
    private var frozenSeconds = 0
    private var title = ""

    private val tick = object : Runnable {
        override fun run() {
            updateText()
            handler?.postDelayed(this, 1000)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_HIDE -> {
                removeOverlay()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_PAUSE -> {
                paused = true
                frozenSeconds = currentSeconds()
                updateText()
            }
            ACTION_RESUME -> {
                paused = false
                startEpochMs = System.currentTimeMillis() - frozenSeconds * 1000L
                updateText()
            }
            else -> {
                stopwatch = intent?.getBooleanExtra(EXTRA_STOPWATCH, true) ?: true
                startEpochMs = intent?.getLongExtra(EXTRA_START, System.currentTimeMillis())
                    ?: System.currentTimeMillis()
                targetEpochMs = intent?.getLongExtra(EXTRA_TARGET, 0L) ?: 0L
                paused = intent?.getBooleanExtra(EXTRA_PAUSED, false) ?: false
                frozenSeconds = intent?.getIntExtra(EXTRA_FROZEN, 0) ?: 0
                title = intent?.getStringExtra(EXTRA_TITLE) ?: ""
                showOverlay()
                updateText()
            }
        }
        handler?.removeCallbacks(tick)
        handler?.postDelayed(tick, 1000)
        return START_NOT_STICKY
    }

    private fun currentSeconds(): Int {
        if (paused) return frozenSeconds
        val elapsed = ((System.currentTimeMillis() - startEpochMs) / 1000).toInt()
        return if (elapsed < 0) 0 else elapsed
    }

    private fun format(seconds: Int): String {
        val h = seconds / 3600
        val m = (seconds % 3600) / 60
        val s = seconds % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, s) else "%02d:%02d".format(m, s)
    }

    private fun updateText() {
        timeView?.text = if (paused) "${format(currentSeconds())} · 已暂停" else format(currentSeconds())
        titleView?.text = if (title.isEmpty()) "专注中" else title
        titleView?.visibility = if (title.isEmpty()) View.GONE else View.VISIBLE
    }

    private fun showOverlay() {
        if (overlayView != null) return
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val padH = (14 * resources.displayMetrics.density).toInt()
        val padV = (10 * resources.displayMetrics.density).toInt()
        val bg = GradientDrawable().apply {
            setColor(Color.parseColor("#E6162228"))
            cornerRadius = 20 * resources.displayMetrics.density
            setStroke(1, Color.parseColor("#33FFFFFF"))
        }

        titleView = TextView(this).apply {
            setTextColor(Color.parseColor("#F2EFE8"))
            textSize = 12f
            maxLines = 1
        }
        timeView = TextView(this).apply {
            setTextColor(Color.parseColor("#92BBC2"))
            textSize = 17f
        }
        val column = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(padH, padV, padH, padV)
            addView(titleView)
            addView(timeView)
        }
        overlayView = android.widget.FrameLayout(this).apply {
            background = bg
            addView(column)
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = 40
        params.y = 200

        // 拖动 + 点击回应用
        var downRawX = 0f
        var downRawY = 0f
        var startX = 0
        var startY = 0
        var moved = false
        overlayView!!.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = event.rawX; downRawY = event.rawY
                    startX = params.x; startY = params.y; moved = false
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (abs(dx) > 8 || abs(dy) > 8) {
                        moved = true
                        params.x = startX + dx.toInt()
                        params.y = startY + dy.toInt()
                        windowManager?.updateViewLayout(overlayView, params)
                    }
                    moved
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        val launch = packageManager.getLaunchIntentForPackage(packageName)
                        launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(launch)
                    }
                    !moved
                }
                else -> false
            }
        }

        windowManager?.addView(overlayView, params)

        handler = Handler(Looper.getMainLooper())
    }

    private fun removeOverlay() {
        handler?.removeCallbacks(tick)
        overlayView?.let { windowManager?.removeView(it) }
        overlayView = null
    }

    override fun onDestroy() {
        removeOverlay()
        super.onDestroy()
    }

    companion object {
        const val ACTION_HIDE = "hide"
        const val ACTION_PAUSE = "pause"
        const val ACTION_RESUME = "resume"
        const val EXTRA_STOPWATCH = "stopwatch"
        const val EXTRA_START = "start"
        const val EXTRA_TARGET = "target"
        const val EXTRA_PAUSED = "paused"
        const val EXTRA_FROZEN = "frozen"
        const val EXTRA_TITLE = "title"
    }
}
