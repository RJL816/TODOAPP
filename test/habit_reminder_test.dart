import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/todo_item.dart';
import 'package:todo_app/services/reminder_calc.dart';

/// 每日习惯打卡提醒的触发计算
void main() {
  final now = DateTime(2026, 9, 28, 20, 0); // 周一 20:00

  TodoItem habit({int? remindMinutes, bool enabled = true, bool done = false}) {
    final todo = TodoItem.create(
      title: '背单词',
      date: DateTime(2026, 9, 1),
      taskType: TaskType.recurring,
    )
      ..isReminderEnabled = enabled
      ..habitRemindMinutes = remindMinutes
      ..isCompleted = done;
    return todo;
  }

  group('habitOccurrence 每日打卡提醒', () {
    test('未打卡且时刻未到 → 今天触发', () {
      final o = habitOccurrence(habit(remindMinutes: 21 * 60),
          completedToday: false, now: now);
      expect(o, isNotNull);
      expect(o!.fireAt, DateTime(2026, 9, 28, 21, 0));
      expect(o.channel, ReminderChannels.habit);
    });

    test('未打卡且时刻已过 → 明天触发', () {
      final o = habitOccurrence(habit(remindMinutes: 8 * 60),
          completedToday: false, now: now);
      expect(o!.fireAt, DateTime(2026, 9, 29, 8, 0));
    });

    test('今天已打卡 → 跳过今天，排明天（打卡后重排不断档）', () {
      final o = habitOccurrence(habit(remindMinutes: 21 * 60),
          completedToday: true, now: now);
      expect(o!.fireAt, DateTime(2026, 9, 29, 21, 0));
    });

    test('未设置提醒时间 → 不生成', () {
      expect(
          habitOccurrence(habit(), completedToday: false, now: now), isNull);
    });

    test('提醒开关关闭 → 不生成', () {
      expect(
          habitOccurrence(habit(remindMinutes: 21 * 60, enabled: false),
              completedToday: false, now: now),
          isNull);
    });

    test('一次性任务不走打卡提醒', () {
      final todo = TodoItem.create(
        title: '交作业',
        date: DateTime(2026, 9, 28),
      )
        ..taskType = TaskType.oneTime
        ..isReminderEnabled = true
        ..habitRemindMinutes = 21 * 60;
      expect(
          habitOccurrence(todo, completedToday: false, now: now), isNull);
    });

    test('非法分钟数（≥24h）→ 不生成', () {
      expect(
          habitOccurrence(habit(remindMinutes: 24 * 60),
              completedToday: false, now: now),
          isNull);
    });
  });
}

