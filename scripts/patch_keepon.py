# -*- coding: utf-8 -*-
"""番茄钟专注运行时：锁屏/息屏保持计时可见（Android channel 联动）。"""
path = 'lib/services/pomodoro_service.dart'
src = open(path, encoding='utf-8').read()
edits = []

edits.append(("""import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';""",
"""import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';"""))

edits.append(("""import '../models/pomodoro_session.dart';
import 'gamification_service.dart';""",
"""import '../models/pomodoro_session.dart';
import 'gamification_service.dart';
import 'dart:io' show Platform;"""))

edits.append(("""  Timer? _ticker;
  bool _loaded = false;""",
"""  Timer? _ticker;
  bool _loaded = false;

  static const MethodChannel _screenChannel =
      MethodChannel('com.todo.app/screen');

  /// 专注运行/暂停期间：锁屏与息屏界面保持计时可见、屏幕常亮；
  /// 离开专注后恢复系统默认。仅 Android 有效。
  void _updateScreenKeepOn() {
    if (!Platform.isAndroid) return;
    final keep = runningPhase == PomodoroRunPhase.focus;
    _screenChannel
        .invokeMethod('setFocusKeepOn', {'keep': keep})
        .catchError((_) {});
  }"""))

applied = 0
for old, new in edits:
    if old not in src:
        print('MISS:', old.splitlines()[0][:60])
        continue
    src = src.replace(old, new, 1)
    applied += 1

# 在状态转换的 notifyListeners 前插入 keep-on 更新（逐个锚点）
notify_anchors = [
    # startPhase
    ("    if (targetEndTime != null) _scheduleEndNotification();\n    _startTicker();\n    notifyListeners();\n  }",
     "    if (targetEndTime != null) _scheduleEndNotification();\n    _startTicker();\n    _updateScreenKeepOn();\n    notifyListeners();\n  }"),
    # pause
    ("    _cancelEndNotification();\n    _stopTicker();\n    await _persistState();\n    notifyListeners();\n  }\n\n  /// 继续：",
     "    _cancelEndNotification();\n    _stopTicker();\n    await _persistState();\n    _updateScreenKeepOn();\n    notifyListeners();\n  }\n\n  /// 继续："),
    # resume
    ("    await _persistState();\n    _startTicker();\n    notifyListeners();\n  }\n\n  /// 放弃当前阶段",
     "    await _persistState();\n    _startTicker();\n    _updateScreenKeepOn();\n    notifyListeners();\n  }\n\n  /// 放弃当前阶段"),
    # abort
    ("    await _resetState();\n    _cancelEndNotification();\n    _stopTicker();\n    notifyListeners();\n  }",
     "    await _resetState();\n    _cancelEndNotification();\n    _stopTicker();\n    _updateScreenKeepOn();\n    notifyListeners();\n  }"),
    # finishCurrentFocus
    ("    suggestedNext = PomodoroRunPhase.shortBreak;\n    completionChoicePending = associatedTaskTitle?.isNotEmpty == true;\n    await _resetState();\n    _cancelEndNotification();\n    _stopTicker();\n    notifyListeners();\n  }",
     "    suggestedNext = PomodoroRunPhase.shortBreak;\n    completionChoicePending = associatedTaskTitle?.isNotEmpty == true;\n    await _resetState();\n    _cancelEndNotification();\n    _stopTicker();\n    _updateScreenKeepOn();\n    notifyListeners();\n  }"),
]
for old, new in notify_anchors:
    if old not in src:
        print('MISS anchor:', old.splitlines()[0][:60])
        continue
    src = src.replace(old, new, 1)
    applied += 1

open(path, 'w', encoding='utf-8').write(src)
print(f'applied {applied}/{len(edits) + len(notify_anchors)}')
