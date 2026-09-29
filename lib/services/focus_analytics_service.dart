import 'package:isar/isar.dart';

import '../models/pomodoro_session.dart';
import '../models/training.dart';
import 'isar_service.dart';

class FocusSlice {
  final String title;
  final int seconds;
  final bool isWorkout;
  const FocusSlice(this.title, this.seconds, {this.isWorkout = false});
}

class FocusDayStats {
  final int focusSeconds;
  final int workoutSeconds;
  final List<FocusSlice> slices;
  const FocusDayStats(this.focusSeconds, this.workoutSeconds, this.slices);
  int get totalSeconds => focusSeconds + workoutSeconds;
  int get focusCount => slices.where((s) => !s.isWorkout).length;
}

class FocusAnalyticsService {
  static Future<FocusDayStats> forDay(DateTime day) async {
    final isar = IsarService.instance.isar;
    final sessions = await isar.pomodoroSessions.where().findAll();
    final workouts = await isar.workoutLogs.where().findAll();
    return fromRecords(day, sessions, workouts);
  }

  /// 使用完成的训练记录。旧记录没有结束时间，不猜测训练时长。
  static FocusDayStats fromRecords(
      DateTime day, List<PomodoroSession> sessions, List<WorkoutLog> workouts) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    int overlap(DateTime a, DateTime b) {
      final left = a.isBefore(start) ? start : a;
      final right = b.isAfter(end) ? end : b;
      return right.isAfter(left) ? right.difference(left).inSeconds : 0;
    }

    final workoutIntervals = <(DateTime, DateTime)>[];
    final values = <(String, bool), int>{};
    var trainingSeconds = 0;
    for (final log in workouts) {
      final ended = log.endedAt;
      if (!log.completed || ended == null || !ended.isAfter(log.startedAt)) {
        continue;
      }
      final seconds = overlap(log.startedAt, ended);
      if (seconds == 0) continue;
      workoutIntervals.add((log.startedAt, ended));
      trainingSeconds += seconds;
      final key = (log.title, true);
      values[key] = (values[key] ?? 0) + seconds;
    }
    var focusSeconds = 0;
    for (final session in sessions) {
      if (!session.completed ||
          session.type != PomodoroPhaseType.focus ||
          session.durationSeconds <= 0) {
        continue;
      }
      // 会话可能暂停过，使用保存的有效时长，而非墙上时钟差。
      final effectiveStart =
          session.endedAt.subtract(Duration(seconds: session.durationSeconds));
      var seconds = overlap(effectiveStart, session.endedAt);
      if (seconds == 0) continue;
      // 同时打开计时与训练时，重叠部分归入训练，避免总时长重复。
      final cuts = <(DateTime, DateTime)>[];
      for (final interval in workoutIntervals) {
        final left =
            interval.$1.isAfter(effectiveStart) ? interval.$1 : effectiveStart;
        final right = interval.$2.isBefore(session.endedAt)
            ? interval.$2
            : session.endedAt;
        if (right.isAfter(left)) cuts.add((left, right));
      }
      cuts.sort((a, b) => a.$1.compareTo(b.$1));
      DateTime? coveredUntil;
      for (final cut in cuts) {
        final left = coveredUntil != null && coveredUntil.isAfter(cut.$1)
            ? coveredUntil
            : cut.$1;
        seconds -= overlap(left, cut.$2);
        if (coveredUntil == null || cut.$2.isAfter(coveredUntil)) {
          coveredUntil = cut.$2;
        }
      }
      if (seconds <= 0) continue;
      focusSeconds += seconds;
      final title = session.taskTitle?.trim().isNotEmpty == true
          ? session.taskTitle!.trim()
          : '自由专注';
      final key = (title, false);
      values[key] = (values[key] ?? 0) + seconds;
    }
    final slices = [
      for (final entry in values.entries)
        FocusSlice(entry.key.$1, entry.value, isWorkout: entry.key.$2),
    ]..sort((a, b) => b.seconds.compareTo(a.seconds));
    return FocusDayStats(focusSeconds, trainingSeconds, slices);
  }
}
