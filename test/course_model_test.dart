import 'package:flutter_test/flutter_test.dart';

import 'package:todo_app/models/course.dart';

/// 课程周次范围解析与工具方法的单元测试。
void main() {
  group('Course.parseWeekRange', () {
    test('单个范围 "1-12"', () {
      final weeks = Course.parseWeekRange('1-12');
      expect(weeks, List<int>.generate(12, (i) => i + 1));
    });

    test('混合范围 "11-13,15,17-18"', () {
      expect(Course.parseWeekRange('11-13,15,17-18'),
          [11, 12, 13, 15, 17, 18]);
    });

    test('去重并排序 "3,1-2"', () {
      expect(Course.parseWeekRange('3,1-2'), [1, 2, 3]);
    });

    test('带"周"标记的格式', () {
      expect(Course.parseWeekRange('1-16周'), List.generate(16, (i) => i + 1));
      expect(Course.parseWeekRange('1-2[周]'), [1, 2]);
      expect(Course.parseWeekRange('1-2 [周]'), [1, 2]);
    });

    test('空串与非法输入返回空列表', () {
      expect(Course.parseWeekRange(''), isEmpty);
      expect(Course.parseWeekRange('abc'), isEmpty);
      expect(Course.parseWeekRange('a-b'), isEmpty);
    });

    test('半解析输入只保留合法部分', () {
      // "x" 无法解析被跳过，"5" 正常
      expect(Course.parseWeekRange('x,5'), [5]);
    });
  });

  group('Course.hasClassInWeek', () {
    test('范围内返回 true，范围外返回 false', () {
      final course = Course.create(
        name: '测试',
        weekday: 2,
        startPeriod: 3,
        endPeriod: 4,
        weekRange: '1-8,10',
        semester: '2025-2026-1',
      );
      expect(course.hasClassInWeek(1), isTrue);
      expect(course.hasClassInWeek(8), isTrue);
      expect(course.hasClassInWeek(9), isFalse);
      expect(course.hasClassInWeek(10), isTrue);
      expect(course.hasClassInWeek(11), isFalse);
    });
  });

  group('Course.getColorForName', () {
    test('同名课程颜色稳定且在色板内', () {
      final a = Course.getColorForName('高等数学');
      final b = Course.getColorForName('高等数学');
      expect(a, b);
      expect(Course.courseColors, contains(a));
      // 空名回退到首个颜色且不抛异常
      expect(Course.getColorForName(''), Course.courseColors.first);
    });
  });

  group('SemesterConfig 周次计算', () {
    test('开学第 1 天是第 1 周', () {
      final config = SemesterConfig.create(
        name: '2025-2026-1',
        startDate: DateTime(2026, 3, 2), // 周一
        totalWeeks: 20,
      );
      expect(config.getWeekOf(DateTime(2026, 3, 2)), 1);
      expect(config.getWeekOf(DateTime(2026, 3, 8)), 1); // 周日
      expect(config.getWeekOf(DateTime(2026, 3, 9)), 2); // 第二周周一
    });

    test('超出学期范围收敛到边界周次', () {
      final config = SemesterConfig.create(
        name: 't',
        startDate: DateTime(2026, 3, 2),
        totalWeeks: 20,
      );
      expect(config.getWeekOf(DateTime(2025, 1, 1)), 1);
      expect(config.getWeekOf(DateTime(2027, 1, 1)), 20);
    });
  });
}
