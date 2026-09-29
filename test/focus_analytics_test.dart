import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/pomodoro_session.dart';
import 'package:todo_app/models/training.dart';
import 'package:todo_app/services/focus_analytics_service.dart';

void main() {
  test('循环、训练结束和专注事项在备份 JSON 中保留', () {
    final start = DateTime(2026, 9, 25);
    final plan = TrainingPlan.create(weekday: 5, name: '推')
      ..cycleGroupId = 12
      ..cycleStartDate = start
      ..cycleLength = 3
      ..cycleDay = 1
      ..cycleName = '推拉休';
    final restoredPlan = TrainingPlan.fromJson(plan.toJson());
    expect(restoredPlan.cycleLength, 3);
    expect(restoredPlan.cycleName, '推拉休');

    final workout = WorkoutLog.create(
        date: start,
        title: '推',
        startedAt: DateTime(2026, 9, 25, 10),
        endedAt: DateTime(2026, 9, 25, 11));
    expect(WorkoutLog.fromJson(workout.toJson()).endedAt, workout.endedAt);

    final session = PomodoroSession.create(
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 25)),
        durationSeconds: 1500,
        type: PomodoroPhaseType.focus,
        taskTitle: '读论文');
    expect(PomodoroSession.fromJson(session.toJson()).taskTitle, '读论文');
  });

  test('专注和训练汇总，重叠时间只计一次，旧训练不推算时长', () {
    final day = DateTime(2026, 9, 25);
    final sessions = [
      PomodoroSession.create(
        startedAt: DateTime(2026, 9, 25, 10),
        endedAt: DateTime(2026, 9, 25, 10, 30),
        durationSeconds: 30 * 60,
        type: PomodoroPhaseType.focus,
        taskTitle: '阅读',
      ),
      PomodoroSession.create(
        startedAt: DateTime(2026, 9, 25, 11),
        endedAt: DateTime(2026, 9, 25, 11, 10),
        durationSeconds: 10 * 60,
        type: PomodoroPhaseType.focus,
        completed: false,
      ),
    ];
    final workouts = [
      WorkoutLog.create(
          date: day,
          title: '推',
          startedAt: DateTime(2026, 9, 25, 10, 20),
          endedAt: DateTime(2026, 9, 25, 11)),
      WorkoutLog.create(
          date: day, title: '旧记录', startedAt: DateTime(2026, 9, 25, 13)),
    ];
    final stats = FocusAnalyticsService.fromRecords(day, sessions, workouts);
    expect(stats.focusSeconds, 20 * 60);
    expect(stats.workoutSeconds, 40 * 60);
    expect(stats.totalSeconds, 60 * 60);
    expect(stats.slices.map((s) => s.title), containsAll(['阅读', '推']));
  });
}
