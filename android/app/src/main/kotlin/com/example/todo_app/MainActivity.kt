package com.example.todo_app

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.todo.app/screen")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showFocusOverlay" -> {
                        if (!Settings.canDrawOverlays(this)) {
                            result.success(false)
                        } else {
                            val intent = Intent(this, FocusOverlayService::class.java).apply {
                                putExtra("stopwatch", call.argument<Boolean>("stopwatch") ?: true)
                                putExtra("start", call.argument<Long>("startEpochMs") ?: 0L)
                                putExtra("target", call.argument<Long>("targetEpochMs") ?: 0L)
                                putExtra("paused", call.argument<Boolean>("paused") ?: false)
                                putExtra("frozen", call.argument<Int>("frozen") ?: 0)
                                putExtra("title", call.argument<String>("title") ?: "")
                            }
                            startService(intent)
                            result.success(true)
                        }
                    }
                    "hideFocusOverlay" -> {
                        startService(Intent(this, FocusOverlayService::class.java).setAction(FocusOverlayService.ACTION_HIDE))
                        result.success(true)
                    }
                    "openOverlayPermissionSettings" -> {
                        val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }
                    // 专注运行时：锁屏/息屏界面继续显示计时，屏幕保持常亮
                    "setFocusKeepOn" -> {
                        val keep = call.argument<Boolean>("keep") ?: false
                        runOnUiThread {
                            if (keep) {
                                setShowWhenLocked(true)
                                setTurnScreenOn(true)
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                setShowWhenLocked(false)
                                setTurnScreenOn(false)
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // 专注悬浮窗（需要用户授予"显示在其他应用上层"权限）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.todo.app/focus_overlay")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canDrawOverlays" -> result.success(Settings.canDrawOverlays(this))
                    "showFocusOverlay" -> {
                        if (!Settings.canDrawOverlays(this)) {
                            result.success(false)
                        } else {
                            val intent = Intent(this, FocusOverlayService::class.java).apply {
                                putExtra("stopwatch", call.argument<Boolean>("stopwatch") ?: true)
                                putExtra("start", call.argument<Long>("startEpochMs") ?: 0L)
                                putExtra("target", call.argument<Long>("targetEpochMs") ?: 0L)
                                putExtra("paused", call.argument<Boolean>("paused") ?: false)
                                putExtra("frozen", call.argument<Int>("frozen") ?: 0)
                                putExtra("title", call.argument<String>("title") ?: "")
                            }
                            startService(intent)
                            result.success(true)
                        }
                    }
                    "hideFocusOverlay" -> {
                        startService(
                            Intent(this, FocusOverlayService::class.java)
                                .setAction(FocusOverlayService.ACTION_HIDE))
                        result.success(true)
                    }
                    "openOverlayPermissionSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"))
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
