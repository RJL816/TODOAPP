package com.example.todo_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var openWorkoutPending = false
    private var workoutChannel: MethodChannel? = null
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("openWorkout", false)) {
            openWorkoutPending = true
            workoutChannel?.invokeMethod("open", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        workoutChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.todo.app/workout")
        workoutChannel!!.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "consumeOpen" -> {
                            val pending = openWorkoutPending || intent.getBooleanExtra("openWorkout", false)
                            openWorkoutPending = false
                            intent.removeExtra("openWorkout")
                            result.success(pending)
                        }
                        "sync" -> {
                            val timer = Intent(this, WorkoutOverlayService::class.java).apply {
                                putExtra("stopwatch", true)
                                putExtra("start", call.argument<Number>("startEpochMs")?.toLong() ?: System.currentTimeMillis())
                                putExtra("title", call.argument<String>("title") ?: "训练")
                                putExtra("phase", "workout")
                                putExtra("overlay", call.argument<Boolean>("overlay") ?: false)
                            }
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(timer) else startService(timer)
                            result.success(true)
                        }
                        "stop" -> {
                            stopService(Intent(this, WorkoutOverlayService::class.java))
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("workout_timer_unavailable", e.message, null) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.todo.app/screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "setFocusKeepOn") {
                    val keep = call.argument<Boolean>("keep") ?: false
                    // 只在应用前台常亮，不主动唤醒手机或覆盖锁屏。
                    if (keep) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    result.success(true)
                } else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.todo.app/focus_overlay")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))
                        "syncFocusTimer" -> {
                            val intent = Intent(this, FocusOverlayService::class.java).apply {
                                putExtra("stopwatch", call.argument<Boolean>("stopwatch") ?: false)
                                putExtra("start", call.argument<Number>("startEpochMs")?.toLong() ?: 0L)
                                putExtra("target", call.argument<Number>("targetEpochMs")?.toLong() ?: 0L)
                                putExtra("paused", call.argument<Boolean>("paused") ?: false)
                                putExtra("frozen", call.argument<Int>("frozen") ?: 0)
                                putExtra("title", call.argument<String>("title") ?: "")
                                putExtra("phase", call.argument<String>("phase") ?: "focus")
                                putExtra("overlay", call.argument<Boolean>("overlay") ?: false)
                                putExtra("planned", call.argument<Int>("plannedSeconds") ?: 1)
                            }
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent)
                            else startService(intent)
                            result.success(true)
                        }
                        "stopFocusTimer" -> {
                            FocusTimerEndReceiver.cancel(this)
                            stopService(Intent(this, FocusOverlayService::class.java))
                            result.success(true)
                        }
                        "openOverlayPermissionSettings" -> {
                            startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")))
                            result.success(true)
                        }
                        "openFocusNotificationSettings" -> {
                            val intent = if (Build.VERSION.SDK_INT >= 26) {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            } else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName"))
                            startActivity(intent)
                            result.success(true)
                        }
                        "openFocusBackgroundSettings" -> {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.parse("package:$packageName")))
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("focus_timer_unavailable", e.message, null)
                }
            }
    }
}
