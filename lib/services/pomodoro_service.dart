import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pomodoro_session.dart';
import 'gamification_service.dart';
import 'isar_service.dart';
import 'reminder_calc.dart';
import 'reminder_service.dart';

/// 运行中的阶段
enum PomodoroRunPhase { focus, shortBreak, longBreak }

/// 番茄钟服务
///
/// 防漂移核心：持久化的是**目标结束时刻**（targetEndTime）而非剩余时长。
/// 切页、回前台、甚至杀掉应用重开，剩余时间都按 `targetEndTime - now` 重算，
/// 秒级 tick 只驱动 UI 刷新，不参与计时。
///
/// 会话结束提醒：开始阶段时即通过 ReminderService 在结束时刻排一条系统通知，
/// 应用被杀也能响；暂停/放弃时取消。
class PomodoroService extends ChangeNotifier {
  static PomodoroService? _instance;
  static PomodoroService get instance => _instance ??= PomodoroService._();
  PomodoroService._() : _clock = null;

  @visibleForTesting
  PomodoroService.forTest(this._clock);

  /// 可注入时钟（测试用）
  final DateTime Function()? _clock;
  DateTime now() => _clock?.call() ?? DateTime.now();

  /// 阶段结束提示音；界面会保存用户的选择。
  static bool playSounds = true;

  // ==================== 可配置时长（SharedPreferences 持久化） ====================
  static const String _kFocusMinutes = 'pomodoro_focus_minutes';
  static const String _kShortBreak = 'pomodoro_short_break_minutes';
  static const String _kLongBreak = 'pomodoro_long_break_minutes';
  static const String _kLongBreakInterval = 'pomodoro_long_break_interval';
  static const String _kStateKey = 'pomodoro_state';

  int focusMinutes = 25;
  int shortBreakMinutes = 5;
  int longBreakMinutes = 15;
  int longBreakInterval = 4; // 每完成 N 个专注进入长休息

  // ==================== 运行状态（持久化到 _kStateKey） ====================
  PomodoroRunPhase? runningPhase; // null = 空闲
  DateTime? targetEndTime; // 运行中的目标结束时刻
  int? pausedRemainingSeconds; // 暂停时的剩余秒数
  DateTime? sessionStartTime; // 本阶段开始时刻
  int? associatedTodoId; // 关联的待办
  String? associatedTaskTitle; // 自建主题或待办标题快照
  bool completionChoicePending = false;
  int focusStreak = 0; // 自上次长休息以来完成的专注数
  PomodoroRunPhase? suggestedNext; // 上一阶段自然结束后建议的下一阶段

  Timer? _ticker;
  bool _loaded = false;

  bool get isRunning => runningPhase != null && targetEndTime != null;
  bool get isPaused => runningPhase != null && pausedRemainingSeconds != null;

  /// 剩余秒数（按目标时刻实时计算；暂停时读暂停值）
  int remainingSeconds() {
    if (runningPhase == null) return 0;
    if (pausedRemainingSeconds != null) return pausedRemainingSeconds!;
    final remain = targetEndTime!.difference(now()).inSeconds;
    return remain < 0 ? 0 : remain;
  }

  /// 本阶段总时长（秒）
  int plannedSeconds(PomodoroRunPhase phase) {
    switch (phase) {
      case PomodoroRunPhase.focus:
        return focusMinutes * 60;
      case PomodoroRunPhase.shortBreak:
        return shortBreakMinutes * 60;
      case PomodoroRunPhase.longBreak:
        return longBreakMinutes * 60;
    }
  }

  int currentPlannedSeconds() =>
      runningPhase == null ? 0 : plannedSeconds(runningPhase!);

  // ==================== 初始化 ====================

  Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      focusMinutes = prefs.getInt(_kFocusMinutes) ?? 25;
      shortBreakMinutes = prefs.getInt(_kShortBreak) ?? 5;
      longBreakMinutes = prefs.getInt(_kLongBreak) ?? 15;
      longBreakInterval = prefs.getInt(_kLongBreakInterval) ?? 4;
      await _loadState();
    } catch (e) {
      debugPrint('番茄钟初始化失败: $e');
    }
    // 向提醒服务注册"额外排程提供者"：全量重排时保留进行中的番茄钟结束通知
    try {
      ReminderService.instance
          .addExtraOccurrencesProvider(() async => _buildOccurrence());
    } catch (_) {}
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStateKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      runningPhase = _phaseFromName(map['phase'] as String?);
      targetEndTime = map['targetEnd'] != null
          ? DateTime.parse(map['targetEnd'] as String)
          : null;
      pausedRemainingSeconds = map['pausedRemaining'] as int?;
      sessionStartTime = map['sessionStart'] != null
          ? DateTime.parse(map['sessionStart'] as String)
          : null;
      associatedTodoId = map['todoId'] as int?;
      associatedTaskTitle = map['taskTitle'] as String?;
      completionChoicePending = map['completionPending'] as bool? ?? false;
      focusStreak = (map['focusStreak'] as int?) ?? 0;
      suggestedNext = _phaseFromName(map['suggestedNext'] as String?);

      if (runningPhase != null && targetEndTime != null) {
        if (!targetEndTime!.isAfter(now())) {
          // 应用不在期间自然结束：按跑完处理（结束通知已由系统在结束时刻发出）
          await _completeNaturally(missedWhileAway: true);
        } else {
          // 恢复进行中的计时；结束通知重新排定
          //（Android 端系统排程未受影响，重排是幂等的；Windows 端进程内定时器已丢失）
          _scheduleEndNotification();
          _startTicker();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('番茄钟状态恢复失败: $e');
      await _resetState();
    }
  }

  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kStateKey,
          jsonEncode({
            'phase': runningPhase?.name,
            'targetEnd': targetEndTime?.toIso8601String(),
            'pausedRemaining': pausedRemainingSeconds,
            'sessionStart': sessionStartTime?.toIso8601String(),
            'todoId': associatedTodoId,
            'taskTitle': associatedTaskTitle,
            'completionPending': completionChoicePending,
            'focusStreak': focusStreak,
            'suggestedNext': suggestedNext?.name,
          }));
    } catch (_) {}
  }

  Future<void> _resetState() async {
    runningPhase = null;
    targetEndTime = null;
    pausedRemainingSeconds = null;
    sessionStartTime = null;
    await _persistState();
  }

  // ==================== 时长配置 ====================

  Future<void> saveDurations({
    required int focus,
    required int shortBreak,
    required int longBreak,
    required int interval,
  }) async {
    focusMinutes = focus.clamp(1, 180);
    shortBreakMinutes = shortBreak.clamp(1, 60);
    longBreakMinutes = longBreak.clamp(1, 90);
    longBreakInterval = interval.clamp(2, 8);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kFocusMinutes, focusMinutes);
      await prefs.setInt(_kShortBreak, shortBreakMinutes);
      await prefs.setInt(_kLongBreak, longBreakMinutes);
      await prefs.setInt(_kLongBreakInterval, longBreakInterval);
    } catch (_) {}
    notifyListeners();
  }

  // ==================== 状态机 ====================

  /// 开始一个阶段
  Future<void> startPhase(PomodoroRunPhase phase, {int? todoId}) async {
    if (isRunning) return;
    runningPhase = phase;
    if (phase == PomodoroRunPhase.focus) {
      associatedTodoId = todoId ?? associatedTodoId;
      completionChoicePending = false;
    }
    sessionStartTime = now();
    targetEndTime = now().add(Duration(seconds: plannedSeconds(phase)));
    pausedRemainingSeconds = null;
    suggestedNext = null;
    await _persistState();
    _scheduleEndNotification();
    _startTicker();
    notifyListeners();
  }

  /// 暂停：记录剩余秒数、清空目标时刻、取消结束通知
  Future<void> pause() async {
    if (!isRunning) return;
    pausedRemainingSeconds = remainingSeconds();
    targetEndTime = null;
    _cancelEndNotification();
    _stopTicker();
    await _persistState();
    notifyListeners();
  }

  /// 继续：以当前时刻 + 剩余秒数重建目标结束时刻
  Future<void> resume() async {
    if (runningPhase == null || pausedRemainingSeconds == null) return;
    targetEndTime = now().add(Duration(seconds: pausedRemainingSeconds!));
    pausedRemainingSeconds = null;
    await _persistState();
    _scheduleEndNotification();
    _startTicker();
    notifyListeners();
  }

  /// 放弃当前阶段（专注被放弃会记录未完成会话，不计入统计）
  Future<void> abort() async {
    if (runningPhase == null) return;
    if (sessionStartTime != null) {
      final elapsed = now().difference(sessionStartTime!).inSeconds;
      await _recordSession(
        type: runningPhase!,
        startedAt: sessionStartTime!,
        endedAt: now(),
        durationSeconds: elapsed < 0 ? 0 : elapsed,
        completed: false,
      );
    }
    if (runningPhase == PomodoroRunPhase.focus) {
      associatedTodoId = null;
      associatedTaskTitle = null;
      completionChoicePending = false;
    }
    await _resetState();
    _cancelEndNotification();
    _stopTicker();
    notifyListeners();
  }

  /// 跳过建议的休息（直接准备下一次专注）
  Future<void> skipSuggestion() async {
    suggestedNext = null;
    await _persistState();
    notifyListeners();
  }

  /// 设置/取消关联待办（空闲时）
  Future<void> setAssociatedTodo(int? todoId, {String? title}) async {
    associatedTodoId = todoId;
    associatedTaskTitle = title;
    completionChoicePending = false;
    await _persistState();
    notifyListeners();
  }

  Future<void> setCustomTask(String? title) async {
    associatedTodoId = null;
    associatedTaskTitle = title?.trim().isEmpty == true ? null : title?.trim();
    completionChoicePending = false;
    await _persistState();
    notifyListeners();
  }

  /// 用户主动结束，按实际有效计时保存。暂停时间不计入。
  Future<void> finishCurrentFocus() async {
    if (runningPhase != PomodoroRunPhase.focus) return;
    final elapsed = plannedSeconds(PomodoroRunPhase.focus) - remainingSeconds();
    final end = now();
    if (elapsed > 0) {
      await _recordSession(
        type: PomodoroRunPhase.focus,
        startedAt: sessionStartTime ?? end.subtract(Duration(seconds: elapsed)),
        endedAt: end,
        durationSeconds: elapsed,
        completed: true,
      );
    }
    suggestedNext = PomodoroRunPhase.shortBreak;
    completionChoicePending = associatedTaskTitle?.isNotEmpty == true;
    await _resetState();
    _cancelEndNotification();
    _stopTicker();
    notifyListeners();
  }

  Future<void> resolveTaskCompletion() async {
    completionChoicePending = false;
    await _persistState();
    notifyListeners();
  }

  void _startTicker() {
    _stopTicker();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// 秒级 tick：只驱动 UI 刷新；到点则自然结束
  @visibleForTesting
  Future<void> tick() async {
    if (!isRunning) return;
    if (remainingSeconds() <= 0) {
      await _completeNaturally();
    } else {
      notifyListeners();
    }
  }

  /// 阶段自然结束：记录完成会话、推进节奏、建议下一阶段
  Future<void> _completeNaturally({bool missedWhileAway = false}) async {
    final phase = runningPhase!;
    final end = targetEndTime ?? now();
    final start = sessionStartTime ??
        end.subtract(Duration(seconds: plannedSeconds(phase)));

    await _recordSession(
      type: phase,
      startedAt: start,
      endedAt: end,
      durationSeconds: plannedSeconds(phase),
      completed: true,
    );

    PomodoroRunPhase? next;
    if (phase == PomodoroRunPhase.focus) {
      focusStreak += 1;
      completionChoicePending = associatedTaskTitle?.isNotEmpty == true;
      next = focusStreak % longBreakInterval == 0
          ? PomodoroRunPhase.longBreak
          : PomodoroRunPhase.shortBreak;
      // 前台时播放完成音效（后台由系统通知提醒）
      if (playSounds) {
        try {
          GamificationService.instance.playAllCompleteSound();
        } catch (_) {}
      }
    } else {
      // 休息结束，回到可专注状态
      next = null;
      if (playSounds) {
        try {
          GamificationService.instance.playCheckSound();
        } catch (_) {}
      }
    }
    suggestedNext = next;

    await _resetState();
    _cancelEndNotification();
    _stopTicker();
    notifyListeners();
  }

  Future<void> _recordSession({
    required PomodoroRunPhase type,
    required DateTime startedAt,
    required DateTime endedAt,
    required int durationSeconds,
    required bool completed,
  }) async {
    try {
      final isar = IsarService.instance.isar;
      final session = PomodoroSession.create(
        startedAt: startedAt,
        endedAt: endedAt,
        durationSeconds: durationSeconds,
        type: _modelType(type),
        completed: completed,
        todoId: associatedTodoId,
        taskTitle: associatedTaskTitle,
      );
      await isar.writeTxn(() async {
        await isar.pomodoroSessions.put(session);
      });
    } catch (e) {
      debugPrint('番茄钟会话记录失败: $e');
    }
  }

  // ==================== 结束通知（复用阶段 2 调度） ====================

  void _scheduleEndNotification() {
    if (targetEndTime == null) return;
    final phase = runningPhase!;
    ReminderService.instance.scheduleOneShot(
      id: ReminderService.pomodoroNotificationId,
      fireAt: targetEndTime!,
      title: phase == PomodoroRunPhase.focus ? '番茄专注完成 🍅' : '休息结束',
      body: phase == PomodoroRunPhase.focus
          ? '专注 $focusMinutes 分钟完成，休息一下吧'
          : '休息结束，开始新的专注吧',
      payload: '{"type":"pomodoro"}',
    );
  }

  void _cancelEndNotification() {
    try {
      ReminderService.instance
          .cancelOneShot(ReminderService.pomodoroNotificationId);
    } catch (_) {}
  }

  /// 供 ReminderService 全量重排时保留进行中的番茄钟通知
  List<ReminderOccurrence> _buildOccurrence() {
    if (!isRunning || targetEndTime == null) return const [];
    final phase = runningPhase!;
    return [
      ReminderOccurrence(
        id: ReminderService.pomodoroNotificationId,
        fireAt: targetEndTime!,
        title: phase == PomodoroRunPhase.focus ? '番茄专注完成 🍅' : '休息结束',
        body: phase == PomodoroRunPhase.focus
            ? '专注 $focusMinutes 分钟完成，休息一下吧'
            : '休息结束，开始新的专注吧',
        payload: '{"type":"pomodoro"}',
        target: ReminderTarget.todo, // 仅作展示分组用，跳转逻辑按 payload
        channel: ReminderChannels.pomodoro,
      ),
    ];
  }

  // ==================== 统计（只计完成的专注） ====================

  /// 某天的专注统计：总分钟数与番茄数（仅 completed 且 focus）
  Future<({int minutes, int count})> focusStatsForDay(DateTime day) async {
    final isar = IsarService.instance.isar;
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final sessions = await isar.pomodoroSessions
        .filter()
        .startedAtBetween(start, end)
        .and()
        .completedEqualTo(true)
        .and()
        .typeEqualTo(PomodoroPhaseType.focus)
        .findAll();
    final seconds = sessions.fold<int>(0, (sum, s) => sum + s.durationSeconds);
    return (minutes: seconds ~/ 60, count: sessions.length);
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }

  // ==================== 工具 ====================

  static PomodoroPhaseType _modelType(PomodoroRunPhase phase) {
    switch (phase) {
      case PomodoroRunPhase.focus:
        return PomodoroPhaseType.focus;
      case PomodoroRunPhase.shortBreak:
        return PomodoroPhaseType.shortBreak;
      case PomodoroRunPhase.longBreak:
        return PomodoroPhaseType.longBreak;
    }
  }

  static PomodoroRunPhase? _phaseFromName(String? name) {
    switch (name) {
      case 'focus':
        return PomodoroRunPhase.focus;
      case 'shortBreak':
        return PomodoroRunPhase.shortBreak;
      case 'longBreak':
        return PomodoroRunPhase.longBreak;
      default:
        return null;
    }
  }
}
