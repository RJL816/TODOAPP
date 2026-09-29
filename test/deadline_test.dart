import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/models/todo_item.dart';

/// DDL 截止时间：过期判定与快速添加工厂参数
void main() {
  final now = DateTime(2026, 9, 28, 12, 0);

  TodoItem make({
    DateTime? deadline,
    TaskType type = TaskType.oneTime,
    bool completed = false,
  }) {
    final todo = TodoItem.create(
      title: '任务',
      date: DateTime(2026, 9, 28),
      taskType: type,
    )
      ..deadline = deadline
      ..isCompleted = completed;
    return todo;
  }

  group('TodoItem.isExpired', () {
    test('截止时刻已过 → 过期（精确到时刻，不是按天）', () {
      final todo = make(deadline: DateTime(2026, 9, 28, 11, 59));
      expect(todo.isExpired(now: now), isTrue);
    });

    test('截止时刻未到 → 不过期', () {
      final todo = make(deadline: DateTime(2026, 9, 28, 12, 1));
      expect(todo.isExpired(now: now), isFalse);
    });

    test('截止恰好是当前时刻 → 不算过期（isBefore 语义）', () {
      final todo = make(deadline: now);
      expect(todo.isExpired(now: now), isFalse);
    });

    test('无截止时间 → 永不过期', () {
      expect(make().isExpired(now: now), isFalse);
    });

    test('每日习惯不判过期', () {
      final todo = make(
        deadline: DateTime(2026, 9, 1),
        type: TaskType.recurring,
      );
      expect(todo.isExpired(now: now), isFalse);
    });

    test('已完成 + 已过期：判定仍为过期（是否展示由列表逻辑决定）', () {
      final todo = make(deadline: DateTime(2026, 9, 20), completed: true);
      expect(todo.isExpired(now: now), isTrue);
    });
  });

  group('TodoItem.create 的 DDL 参数', () {
    test('携带截止时间并开启到点提醒（提前量 0）', () {
      final deadline = DateTime(2026, 9, 30, 18, 0);
      final todo = TodoItem.create(
        title: '交作业',
        date: DateTime(2026, 9, 28),
        deadline: deadline,
        enableReminder: true,
        remindBeforeMinutes: 0,
      );
      expect(todo.deadline, deadline);
      expect(todo.isReminderEnabled, isTrue);
      expect(todo.remindBeforeMinutes, 0);
    });

    test('不设截止时保持旧行为：无提醒、默认提前量', () {
      final todo = TodoItem.create(title: '随手记', date: DateTime(2026, 9, 28));
      expect(todo.deadline, isNull);
      expect(todo.isReminderEnabled, isFalse);
      expect(todo.remindBeforeMinutes, 15);
    });
  });
}
