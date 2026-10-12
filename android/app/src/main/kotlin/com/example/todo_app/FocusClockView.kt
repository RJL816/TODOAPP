package com.example.todo_app

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import android.view.View
import kotlin.math.cos
import kotlin.math.sin

/** 小型奶油白计时表盘：刻度、剩余进度环、清晰数字与单行主题。 */
class FocusClockView(context: Context) : View(context) {
    private val scale = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)
    private var seconds = 0
    private var paused = false
    private var title = ""
    private var phase = "专注"
    private var stopwatch = false
    private var total = 1

    init {
        setLayerType(LAYER_TYPE_SOFTWARE, null)
        textPaint.fontFeatureSettings = "tnum"
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
    }

    fun update(seconds: Int, paused: Boolean, title: String, phase: String,
               stopwatch: Boolean, total: Int) {
        if (this.seconds == seconds && this.paused == paused && this.title == title &&
            this.phase == phase && this.stopwatch == stopwatch && this.total == total) return
        this.seconds = seconds; this.paused = paused; this.title = title
        this.phase = phase; this.stopwatch = stopwatch; this.total = total.coerceAtLeast(1)
        contentDescription = "$phase，${formatTime(seconds)}" + if (paused) "，已暂停，点击返回" else "，点击返回"
        invalidate()
    }

    private fun formatTime(value: Int): String = if (value >= 3600)
        "%d:%02d:%02d".format(value / 3600, value % 3600 / 60, value % 60)
        else "%02d:%02d".format(value / 60, value % 60)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.save()
        canvas.scale(scale, scale)
        val cx = 60f; val cy = 58f; val radius = 48f
        val accent = Color.parseColor(if (phase.contains("休息")) "#AD7C3F" else "#306B5D")
        paint.style = Paint.Style.FILL
        paint.color = Color.parseColor("#F5EEE1")
        paint.setShadowLayer(5f, 0f, 3f, Color.parseColor("#440F2C27"))
        canvas.drawCircle(cx, cy, radius, paint)
        paint.clearShadowLayer()
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1f; paint.color = Color.parseColor("#D5C6AD")
        canvas.drawCircle(cx, cy, radius, paint)
        paint.strokeWidth = 2.5f; paint.color = Color.parseColor("#DDE3D9")
        val ring = RectF(cx - 42, cy - 42, cx + 42, cy + 42)
        canvas.drawArc(ring, -90f, 360f, false, paint)
        val fraction = if (stopwatch) (seconds % 3600) / 3600f
            else (seconds.toFloat() / total).coerceIn(0f, 1f)
        paint.color = if (paused) Color.parseColor("#92A69B") else accent
        paint.strokeCap = Paint.Cap.ROUND
        canvas.drawArc(ring, -90f, 360f * fraction, false, paint)
        paint.strokeCap = Paint.Cap.BUTT
        for (i in 0 until 12) {
            val angle = Math.toRadians(i * 30.0 - 90)
            paint.color = Color.parseColor("#A8AC9F"); paint.strokeWidth = if (i % 3 == 0) 1.5f else 1f
            val inner = if (i % 3 == 0) 34f else 36f
            canvas.drawLine(cx + cos(angle).toFloat() * inner, cy + sin(angle).toFloat() * inner,
                cx + cos(angle).toFloat() * 38f, cy + sin(angle).toFloat() * 38f, paint)
        }
        val angle = Math.toRadians(fraction * 360.0 - 90)
        paint.style = Paint.Style.FILL; paint.color = Color.parseColor("#BA935A")
        canvas.drawCircle(cx + cos(angle).toFloat() * 42f, cy + sin(angle).toFloat() * 42f, 3f, paint)
        textPaint.textAlign = Paint.Align.CENTER
        textPaint.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        textPaint.color = accent; textPaint.textSize = 9f
        canvas.drawText(if (stopwatch) "正计时" else phase, cx, cy - 17f, textPaint)
        textPaint.color = Color.parseColor("#263F37")
        textPaint.textSize = if (seconds >= 3600) 15f else 21f
        canvas.drawText(formatTime(seconds), cx, cy + 7f, textPaint)
        textPaint.textSize = 8.5f; textPaint.color = Color.parseColor("#7E8A7E")
        canvas.drawText(if (paused) "已暂停" else if (stopwatch) "专注积累" else "剩余时间", cx, cy + 22f, textPaint)
        paint.style = Paint.Style.FILL; paint.color = Color.parseColor("#E622443B")
        canvas.drawRoundRect(RectF(6f, 113f, 114f, 135f), 11f, 11f, paint)
        textPaint.textSize = 10f; textPaint.color = Color.parseColor("#F5EFE3")
        textPaint.setShadowLayer(2f, 0f, 1f, Color.parseColor("#B01B3029"))
        val caption = TextUtils.ellipsize(title.ifBlank { "点击返回拾序" },
            textPaint, 96f, TextUtils.TruncateAt.END).toString()
        canvas.drawText(caption, cx, 127f, textPaint)
        textPaint.clearShadowLayer()
        canvas.restore()
    }
}
