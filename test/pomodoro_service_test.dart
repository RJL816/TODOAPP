import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:todo_app/models/pomodoro_session.dart';
import 'package:todo_app/services/isar_service.dart';
import 'package:todo_app/services/pomodoro_service.dart';

import 'isar_test_base.dart';

/// 番茄钟状态机与防漂移核心的单元测试。
void main() {
  setUpAll(() async {
    await initIsarCoreForTests();
    PomodoroService.playSounds = false; // 测试不触音频通道
  });

  late _Clock clock;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    clock = _Clock(DateTime(2026, 9, 24, 10, 0));
    final isar = await openTestIsar();
    IsarService.instance.initForTest(isar);
  });

  Future<PomodoroService> newService() async {
    final svc = PomodoroService.forTest(() => clock.now);
    addTearDown(svc.dispose);
    await svc.init();
    return svc;
  }

  group('基础状态机', () {
    test('自建事项可主动结束并保存有效时间', () async {
      final svc = await newService();
      await svc.setCustomTask('读论文');
      await svc.startPhase(PomodoroRunPhase.focus);
      clock.advance(const Duration(minutes: 8));
      await svc.pause();
      clock.advance(const Duration(minutes: 20));
      await svc.finishCurrentFocus();
      final sessions =
          await IsarService.instance.isar.pomodoroSessions.where().findAll();
      expect(sessions.single.taskTitle, '读论文');
      expect(sessions.single.durationSeconds, 8 * 60);
      expect(sessions.single.completed, isTrue);
    });
    test('开始专注：目标结束时刻 = 现在 + 专注时长', () async {
      final svc = await newService();
      await svc.startPhase(PomodoroRunPhase.focus);
      expect(svc.isRunning, isTrue);
      expect(svc.remainingSeconds(), 25 * 60);
      expect(
        svc.targetEndTime,
        DateTime(2026, 9, 24, 10, 25),
      );
    });

    test('暂停记录剩余、继续按当前时刻重建目标（暂停期间时钟走动不影响剩余）', () async {
      final svc = await newService();
      await svc.startPhase(PomodoroRunPhase.focus);

      // 走 10 分钟后暂停
      clock.advance(const Duration(minutes: 10));
      await svc.pause();
      expect(svc.isPaused, isTrue);
      expect(svc.remainingSeconds(), 15 * 60);

      // 暂停中时间流逝 2 小时，剩余不应变化（防漂移关键）
      clock.advance(const Duration(hours: 2));
      expect(svc.remainingSeconds(), 15 * 60);

      // 继续：目标结束时刻 = 现在 + 15 分钟
      await svc.resume();
      expect(svc.isRunning, isTrue);
      expect(svc.remainingSeconds(), 15 * 60);
      expect(svc.targetEndTime, DateTime(2026, 9, 24, 12, 25));
    });

    test('放弃专注：记录未完成会话，不计入统计', () async {
      final svc = await newService();
      await svc.startPhase(PomodoroRunPhase.focus);
      clock.advance(const Duration(minutes: 8));
      await svc.abort();

      expect(svc.isRunning, isFalse);
      final isar = IsarService.instance.isar;
      final sessions = await isar.pomodoroSessions.where().findAll();
      expect(sessions.length, 1);
      expect(sessions.first.completed, isFalse);
      expect(sessions.first.durationSeconds, 8 * 60);

      final stats = await svc.focusStatsForDay(clock.now);
      expect(stats.count, 0);
      expect(stats.minutes, 0);
    });
  });

  group('自然完成与节奏', () {
    test('自然结束后待确认事项在重启后仍可处理', () async {
      final svc = await newService();
      await svc.setCustomTask('整理课程笔记');
      await svc.startPhase(PomodoroRunPhase.focus);
      clock.advance(const Duration(minutes: 25));
      await svc.tick();
      expect(svc.completionChoicePending, isTrue);
      final reopened = await newService();
      expect(reopened.associatedTaskTitle, '整理课程笔记');
      expect(reopened.completionChoicePending, isTrue);
      await reopened.resolveTaskCompletion();
      expect(reopened.completionChoicePending, isFalse);
    });

    test('到点自然完成：记录 completed 会话并建议短休息', () async {
      final svc = await newService();
      await svc.startPhase(PomodoroRunPhase.focus);
      clock.advance(const Duration(minutes: 25));
      await svc.tick();

      expect(svc.isRunning, isFalse);
      expect(svc.focusStreak, 1);
      expect(svc.suggestedNext, PomodoroRunPhase.shortBreak);

      final stats = await svc.focusStatsForDay(clock.now);
      expect(stats.count, 1);
      expect(stats.minutes, 25);

      // 休息自然结束 → 建议清空（回到可专注）
      await svc.startPhase(PomodoroRunPhase.shortBreak);
      clock.advance(const Duration(minutes: 5));
      await svc.tick();
      expect(svc.isRunning, isFalse);
      expect(svc.suggestedNext, isNull);
      // 休息不计入专注统计
      final stats2 = await svc.focusStatsForDay(clock.now);
      expect(stats2.count, 1);
    });

    test('长休节奏：每 4 个专注建议长休息', () async {
      final svc = await newService();
      for (int i = 1; i <= 4; i++) {
        await svc.startPhase(PomodoroRunPhase.focus);
        clock.advance(const Duration(minutes: 25));
        await svc.tick();
        expect(svc.focusStreak, i);
        if (i < 4) {
          expect(svc.suggestedNext, PomodoroRunPhase.shortBreak);
          // 跳过休息直接下一轮
          await svc.startPhase(PomodoroRunPhase.focus);
          await svc.abort(); // 清理，重新开始
        }
      }
      expect(svc.suggestedNext, PomodoroRunPhase.longBreak);
    });

    test('休息会话也留档但不进专注统计', () async {
      final svc = await newService();
      await svc.startPhase(PomodoroRunPhase.longBreak);
      clock.advance(const Duration(minutes: 15));
      await svc.tick();
      final isar = IsarService.instance.isar;
      final sessions = await isar.pomodoroSessions.where().findAll();
      expect(sessions.single.type, PomodoroPhaseType.longBreak);
      expect(sessions.single.completed, isTrue);
      final stats = await svc.focusStatsForDay(clock.now);
      expect(stats.count, 0);
    });
  });

  group('跨启动恢复（防漂移）', () {
    test('应用重启后从持久化的目标结束时刻重算剩余，而非重置', () async {
      final svc1 = await newService();
      await svc1.startPhase(PomodoroRunPhase.focus);
      clock.advance(const Duration(minutes: 10)); // 走了 10 分钟

      // 模拟杀掉应用后重开：新服务实例从同一份持久化状态恢复
      final svc2 = await newService();
      expect(svc2.isRunning, isTrue);
      expect(svc2.remainingSeconds(), 15 * 60,
          reason: '剩余应按 targetEndTime-now 重算');
      expect(svc2.runningPhase, PomodoroRunPhase.focus);
    });

    test('不在期间已到点：恢复时按跑完记录', () async {
      final svc1 = await newService();
      await svc1.startPhase(PomodoroRunPhase.focus);
      clock.advance(const Duration(minutes: 25, seconds: 30));

      final svc2 = await newService();
      expect(svc2.isRunning, isFalse);
      expect(svc2.focusStreak, 1);
      expect(svc2.suggestedNext, PomodoroRunPhase.shortBreak);
      final stats = await svc2.focusStatsForDay(clock.now);
      expect(stats.count, 1);
      expect(stats.minutes, 25);
    });
  });

  group('统计口径', () {
    test('focusStatsForDay 只统计指定日期的已完成专注', () async {
      final svc = await newService();
      final isar = IsarService.instance.isar;

      Future<void> putSession(DateTime start, int minutes,
          {bool completed = true}) async {
        await isar.writeTxn(() async {
          await isar.pomodoroSessions.put(PomodoroSession.create(
            startedAt: start,
            endedAt: start.add(Duration(minutes: minutes)),
            durationSeconds: minutes * 60,
            type: PomodoroPhaseType.focus,
            completed: completed,
          ));
        });
      }

      final day = clock.now; // 2026-09-24
      await putSession(DateTime(2026, 9, 24, 9, 0), 25); // 今天，计入
      await putSession(DateTime(2026, 9, 24, 11, 0), 25,
          completed: false); // 今天但放弃，不计
      await putSession(DateTime(2026, 9, 23, 9, 0), 25); // 昨天，不计

      final stats = await svc.focusStatsForDay(day);
      expect(stats.count, 1);
      expect(stats.minutes, 25);
    });
  });
}

/// 可推进的测试时钟
class _Clock {
  DateTime now;
  _Clock(this.now);
  void advance(Duration d) => now = now.add(d);
}
