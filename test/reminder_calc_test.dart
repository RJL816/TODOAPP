import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:todo_app/models/class_time_config.dart';
import 'package:todo_app/models/course.dart';
import 'package:todo_app/models/todo_item.dart';
import 'package:todo_app/services/course_service.dart';
import 'package:todo_app/services/reminder_calc.dart';

/// 提醒触发时刻计算与 ID 派生的单元测试（对应 UPGRADE_PLAN 2.4/2.6 验收）。
void main() {
  final now = DateTime(2026, 9, 24, 12, 0); // 周四

  TodoItem todo({
    required int id,
    bool enabled = true,
    bool completed = false,
    DateTime? start,
    DateTime? deadline,
    int lead = 15,
  }) {
    final t = TodoItem.create(title: '测试任务', date: now);
    t.id = id;
    t.isCompleted = completed;
    t.startTime = start;
    t.deadline = deadline;
    t.remindBeforeMinutes = lead;
    t.isReminderEnabled = enabled;
    return t;
  }

  group('todoOccurrence 待办提醒', () {
    test('按截止时间减提前量触发', () {
      final o = todoOccurrence(
        todo(id: 1, deadline: DateTime(2026, 9, 25, 18, 0), lead: 30),
        now: now,
      );
      expect(o, isNotNull);
      expect(o!.fireAt, DateTime(2026, 9, 25, 17, 30));
      expect(o.id, todoReminderId(1));
      expect(jsonDecode(o.payload)['type'], 'todo');
    });

    test('无截止时间时用开始时间', () {
      final o = todoOccurrence(
        todo(id: 2, start: DateTime(2026, 9, 26, 8, 0), lead: 15),
        now: now,
      );
      expect(o!.fireAt, DateTime(2026, 9, 26, 7, 45));
    });

    test('截止时间优先于开始时间', () {
      final o = todoOccurrence(
        todo(
          id: 3,
          start: DateTime(2026, 9, 26, 8, 0),
          deadline: DateTime(2026, 9, 27, 20, 0),
        ),
        now: now,
      );
      expect(o!.fireAt, DateTime(2026, 9, 27, 19, 45));
    });

    test('未开启/已完成/无时间/已过期 均不生成', () {
      expect(
          todoOccurrence(
              todo(id: 4, enabled: false,
                  deadline: DateTime(2026, 9, 25, 18, 0)),
              now: now),
          isNull);
      expect(
          todoOccurrence(
              todo(id: 5, completed: true,
                  deadline: DateTime(2026, 9, 25, 18, 0)),
              now: now),
          isNull);
      expect(todoOccurrence(todo(id: 6), now: now), isNull);
      expect(
          todoOccurrence(
              todo(id: 7, deadline: DateTime(2026, 9, 24, 12, 10), lead: 15),
              now: now), // 触发时刻 11:55 已过
          isNull);
    });
  });

  group('courseOccurrences 整学期排程', () {
    final semester = SemesterConfig.create(
      name: '2026-1',
      startDate: DateTime(2026, 9, 7), // 周一
      totalWeeks: 20,
    );

    Course course(int id, String name,
        {int weekday = 1, int start = 1, String weeks = '1-20'}) {
      final c = Course()
        ..name = name
        ..semester = '2026-1'
        ..weekday = weekday
        ..startPeriod = start
        ..endPeriod = start + 1
        ..weekRange = weeks
        ..teacher = ''
        ..location = 'A101'
        ..colorArgb = 0xFF42A5F5;
      c.id = id;
      return c;
    }

    test('按学期起始日期+周次+星期+节次配置计算上课时刻', () {
      // 第 4 周 周一（2026-09-28）第 1 节 08:00，提前 15 分钟
      //（now 为第 3 周周三，第 3 周周一的提醒时刻已过、应被排除）
      final list = courseOccurrences(
        semester: semester,
        courses: [course(1, '高数', weekday: 1, start: 1)],
        timeConfigs: CourseService.defaultTimeConfigs(),
        now: now,
        leadMinutes: 15,
      );
      final week4 = list
          .firstWhere((o) => o.id == courseReminderId(1, 4));
      expect(week4.fireAt, DateTime(2026, 9, 28, 7, 45));
      // 第 3 周周一（已过）不应存在
      expect(
        list.any((o) => o.id == courseReminderId(1, 3)),
        isFalse,
      );

      // 第 4 节（第二大节 10:00 开始）
      final list2 = courseOccurrences(
        semester: semester,
        courses: [course(2, '大物', weekday: 3, start: 3)],
        timeConfigs: CourseService.defaultTimeConfigs(),
        now: now,
      );
      final week4Wed = list2
          .firstWhere((o) => o.id == courseReminderId(2, 4));
      // 第 4 周周三 = 2026-09-30，第二大节 10:00
      // 默认提前 30 分钟
      expect(week4Wed.fireAt, DateTime(2026, 9, 30, 9, 30));
    });

    test('窗口覆盖整学期：学期最后一周的课也在排程内（"8 天不开 App"场景）', () {
      final list = courseOccurrences(
        semester: semester,
        courses: [course(1, '高数', weekday: 1)],
        timeConfigs: CourseService.defaultTimeConfigs(),
        now: now,
      );
      // now 为第 3 周周三：第 3 周周一已过 → 第 4..20 周共 17 个
      expect(list.length, 17);
      // 最远一条是第 20 周周一（2026-09-07 + 19 周 = 2027-01-18）08:00 − 30 分钟
      final last = list.last;
      expect(last.id, courseReminderId(1, 20));
      expect(last.fireAt, DateTime(2027, 1, 18, 7, 30));
    });

    test('超出上限按最近优先截断', () {
      final many = List.generate(
          30, (i) => course(100 + i, '课$i', weekday: (i % 7) + 1));
      final list = courseOccurrences(
        semester: semester,
        courses: many,
        timeConfigs: CourseService.defaultTimeConfigs(),
        now: now,
        maxCount: 50,
      );
      expect(list.length, 50);
      // 升序排列（同一时刻可能并列）
      for (int i = 1; i < list.length; i++) {
        expect(list[i].fireAt.isBefore(list[i - 1].fireAt), isFalse);
      }
    });

    test('ID 派生：同一课程不同周次互不冲突，不同类型分段不冲突', () {
      expect(courseReminderId(1, 3), isNot(courseReminderId(1, 4)));
      expect(todoReminderId(1), lessThan(2000000));
      expect(courseReminderId(1, 1), lessThan(examReminderId(1)));
      expect(examReminderId(1), greaterThan(courseReminderId(999, 20)));
    });
  });

  group('examOccurrence 考试提醒', () {
    test('默认提前 30 分钟', () {
      final exam = Exam.create(
        name: '期末考试',
        examDateTime: DateTime(2026, 12, 30, 9, 0),
        semester: '2026-1',
      );
      final o = examOccurrence(exam, now: now);
      expect(o!.fireAt, DateTime(2026, 12, 30, 8, 30));
    });

    test('已开始的考试不生成', () {
      final exam = Exam.create(
        name: '旧考试',
        examDateTime: DateTime(2026, 9, 20, 9, 0),
        semester: '2026-1',
      );
      expect(examOccurrence(exam, now: now), isNull);
    });
  });
}
