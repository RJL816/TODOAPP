# -*- coding: utf-8 -*-
"""番茄钟服务层：加入正计时模式（stopwatch mode）。"""
path = 'lib/services/pomodoro_service.dart'
src = open(path, encoding='utf-8').read()
edits = []

edits.append(("""  static const String _kLongBreakInterval = 'pomodoro_long_break_interval';
  static const String _kStateKey = 'pomodoro_state';""",
"""  static const String _kLongBreakInterval = 'pomodoro_long_break_interval';
  static const String _kStopwatchMode = 'pomodoro_stopwatch_mode';
  static const String _kStateKey = 'pomodoro_state';"""))

edits.append(("""  int longBreakInterval = 4; // 每完成 N 个专注进入长休息""",
"""  int longBreakInterval = 4; // 每完成 N 个专注进入长休息

  /// 正计时模式：专注不限时长，从 0 开始计，随时"完成"记录实际时长
  bool stopwatchMode = false;"""))

edits.append(("""  int? pausedRemainingSeconds; // 暂停时的剩余秒数""",
"""  int? pausedRemainingSeconds; // 暂停时的剩余秒数（倒计时）
  int? pausedElapsedSeconds; // 暂停时的已计秒数（正计时）"""))

edits.append(("""  bool get isRunning => runningPhase != null && targetEndTime != null;
  bool get isPaused => runningPhase != null && pausedRemainingSeconds != null;

  /// 剩余秒数（按目标时刻实时计算；暂停时读暂停值）
  int remainingSeconds() {
    if (runningPhase == null) return 0;
    if (pausedRemainingSeconds != null) return pausedRemainingSeconds!;
    final remain = targetEndTime!.difference(now()).inSeconds;
    return remain < 0 ? 0 : remain;
  }""",
"""  /// 正计时专注运行中（无目标结束时刻，按开始时刻累计）
  bool get _isStopwatchRunning =>
      stopwatchMode &&
      runningPhase == PomodoroRunPhase.focus &&
      sessionStartTime != null &&
      pausedElapsedSeconds == null;

  bool get isRunning =>
      runningPhase != null &&
      (targetEndTime != null || _isStopwatchRunning);
  bool get isPaused => runningPhase != null &&
      (pausedRemainingSeconds != null || pausedElapsedSeconds != null);

  /// 正计时专注是否处于活动/暂停状态
  bool get isStopwatchFocus =>
      stopwatchMode && runningPhase == PomodoroRunPhase.focus;

  /// 正计时已计秒数（暂停时读冻结值）
  int elapsedSeconds() {
    if (runningPhase != PomodoroRunPhase.focus || sessionStartTime == null) {
      return 0;
    }
    if (pausedElapsedSeconds != null) return pausedElapsedSeconds!;
    final elapsed = now().difference(sessionStartTime!).inSeconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  /// 剩余秒数（按目标时刻实时计算；暂停时读暂停值；正计时时无剩余概念返回 0）
  int remainingSeconds() {
    if (runningPhase == null) return 0;
    if (pausedRemainingSeconds != null) return pausedRemainingSeconds!;
    if (targetEndTime == null) return 0;
    final remain = targetEndTime!.difference(now()).inSeconds;
    return remain < 0 ? 0 : remain;
  }"""))

edits.append(("""      longBreakInterval = prefs.getInt(_kLongBreakInterval) ?? 4;
      await _loadState();""",
"""      longBreakInterval = prefs.getInt(_kLongBreakInterval) ?? 4;
      stopwatchMode = prefs.getBool(_kStopwatchMode) ?? false;
      await _loadState();"""))

edits.append(("""      if (runningPhase != null && targetEndTime != null) {
        if (!targetEndTime!.isAfter(now())) {""",
"""      if (runningPhase != null && _isStopwatchRunning) {
        // 正计时恢复：无结束时刻，继续按开始时刻累计
        _startTicker();
        notifyListeners();
      } else if (runningPhase != null && targetEndTime != null) {
        if (!targetEndTime!.isAfter(now())) {"""))

edits.append(("""            'pausedRemaining': pausedRemainingSeconds,""",
"""            'pausedRemaining': pausedRemainingSeconds,
            'pausedElapsed': pausedElapsedSeconds,"""))

edits.append(("""  Future<void> _resetState() async {
    runningPhase = null;
    targetEndTime = null;
    pausedRemainingSeconds = null;
    sessionStartTime = null;
    await _persistState();
  }""",
"""  Future<void> _resetState() async {
    runningPhase = null;
    targetEndTime = null;
    pausedRemainingSeconds = null;
    pausedElapsedSeconds = null;
    sessionStartTime = null;
    await _persistState();
  }"""))

edits.append(("""  // ==================== 时长配置 ====================""",
"""  /// 切换专注计时模式（空闲时才可切换）
  Future<void> setStopwatchMode(bool enable) async {
    stopwatchMode = enable;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kStopwatchMode, enable);
    } catch (_) {}
    notifyListeners();
  }

  // ==================== 时长配置 ===================="""))

edits.append(("""    sessionStartTime = now();
    targetEndTime = now().add(Duration(seconds: plannedSeconds(phase)));
    pausedRemainingSeconds = null;
    suggestedNext = null;
    await _persistState();
    _scheduleEndNotification();
    _startTicker();
    notifyListeners();
  }""",
"""    sessionStartTime = now();
    if (stopwatchMode && phase == PomodoroRunPhase.focus) {
      // 正计时：不限时长，由用户主动完成
      targetEndTime = null;
    } else {
      targetEndTime = now().add(Duration(seconds: plannedSeconds(phase)));
    }
    pausedRemainingSeconds = null;
    pausedElapsedSeconds = null;
    suggestedNext = null;
    await _persistState();
    if (targetEndTime != null) _scheduleEndNotification();
    _startTicker();
    notifyListeners();
  }"""))

edits.append(("""  /// 暂停：记录剩余秒数、清空目标时刻、取消结束通知
  Future<void> pause() async {
    if (!isRunning) return;
    pausedRemainingSeconds = remainingSeconds();
    targetEndTime = null;""",
"""  /// 暂停：记录剩余（正计时记录已计）秒数、清空目标时刻、取消结束通知
  Future<void> pause() async {
    if (!isRunning) return;
    if (_isStopwatchRunning) {
      pausedElapsedSeconds = elapsedSeconds();
    } else {
      pausedRemainingSeconds = remainingSeconds();
    }
    targetEndTime = null;"""))

edits.append(("""  /// 继续：以当前时刻 + 剩余秒数重建目标结束时刻
  Future<void> resume() async {
    if (runningPhase == null || pausedRemainingSeconds == null) return;
    targetEndTime = now().add(Duration(seconds: pausedRemainingSeconds!));
    pausedRemainingSeconds = null;
    await _persistState();
    _scheduleEndNotification();
    _startTicker();
    notifyListeners();
  }""",
"""  /// 继续：倒计时以当前时刻 + 剩余秒数重建目标时刻；正计时平移开始时刻补偿暂停
  Future<void> resume() async {
    if (runningPhase == null) return;
    if (pausedElapsedSeconds != null) {
      final frozen = pausedElapsedSeconds!;
      pausedElapsedSeconds = null;
      sessionStartTime =
          now().subtract(Duration(seconds: frozen < 0 ? 0 : frozen));
    } else if (pausedRemainingSeconds != null) {
      targetEndTime = now().add(Duration(seconds: pausedRemainingSeconds!));
      pausedRemainingSeconds = null;
      _scheduleEndNotification();
    }
    await _persistState();
    _startTicker();
    notifyListeners();
  }"""))

edits.append(("""    if (runningPhase != PomodoroRunPhase.focus) return;
    final elapsed = plannedSeconds(PomodoroRunPhase.focus) - remainingSeconds();""",
"""    if (runningPhase != PomodoroRunPhase.focus) return;
    final elapsed = stopwatchMode
        ? elapsedSeconds()
        : plannedSeconds(PomodoroRunPhase.focus) - remainingSeconds();"""))

applied = 0
for old, new in edits:
    if old not in src:
        print('MISS:', old.splitlines()[0][:60])
        continue
    src = src.replace(old, new, 1)
    applied += 1
open(path, 'w', encoding='utf-8').write(src)
print(f'applied {applied}/{len(edits)} edits')
