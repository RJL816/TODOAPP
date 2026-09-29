import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:todo_app/models/class_time_config.dart';
import 'package:todo_app/models/course.dart';
import 'package:todo_app/services/course_service.dart';

import 'isar_test_base.dart';

/// 节次时间配置与学期过滤的单元测试。
void main() {
  late Isar isar;
  late CourseService svc;

  setUpAll(() async {
    await initIsarCoreForTests();
  });

  setUp(() async {
    isar = await openTestIsar();
    svc = CourseService.instance;
    svc.init(isar);
  });

  Course makeCourse(String name, String semester,
      {int weekday = 1, int start = 1, int end = 2, String weeks = '1-16'}) {
    return Course()
      ..name = name
      ..semester = semester
      ..weekday = weekday
      ..startPeriod = start
      ..endPeriod = end
      ..weekRange = weeks
      ..teacher = ''
      ..location = ''
      ..colorArgb = 0xFF42A5F5;
  }

  SemesterConfig makeSemester(String name, {bool active = false}) {
    return SemesterConfig()
      ..name = name
      ..startDate = DateTime(2026, 3, 2)
      ..totalWeeks = 20
      ..isActive = active;
  }

  group('节次时间配置', () {
    test('首次读取自动写入默认 5 个节段且与旧版硬编码一致', () async {
      final configs = await svc.getTimeConfigs();
      expect(configs.length, 5);
      expect(configs.first.id, 1);
      expect(configs.first.firstPeriod, 1);
      expect(configs.first.startLabel, '08:00');
      expect(configs.first.endLabel, '09:40');
      expect(configs.last.firstPeriod, 9);
      expect(configs.last.startLabel, '19:30');
      expect(configs.last.endLabel, '21:10');
    });

    test('保存后整体覆盖并可读回', () async {
      await svc.getTimeConfigs(); // 触发默认写入
      final custom = [
        ClassTimeConfig.create(
            id: 1, firstPeriod: 1, lastPeriod: 2, startMinutes: 9 * 60, endMinutes: 10 * 60 + 40),
        ClassTimeConfig.create(
            id: 2, firstPeriod: 3, lastPeriod: 4, startMinutes: 14 * 60, endMinutes: 15 * 60 + 40),
      ];
      await svc.saveTimeConfigs(custom);

      final reloaded = await svc.getTimeConfigs();
      expect(reloaded.length, 2);
      expect(reloaded.first.startLabel, '09:00');
      expect(reloaded.last.endLabel, '15:40');
    });

    test('currentSection 纯函数：边界与区间外', () {
      final configs = CourseService.defaultTimeConfigs();
      expect(CourseService.currentSection(configs, 8 * 60)?.firstPeriod, 1);
      expect(CourseService.currentSection(configs, 9 * 60 + 40)?.firstPeriod, 1); // 含端点
      expect(CourseService.currentSection(configs, 9 * 60 + 41), isNull);
      expect(CourseService.currentSection(configs, 15 * 60)?.firstPeriod, 5);
      expect(CourseService.currentSection(configs, 23 * 60 + 59), isNull);
    });

    test('currentPeriodOf：按配置返回所在节段的起始节次', () {
      final configs = CourseService.defaultTimeConfigs();
      expect(CourseService.currentPeriodOf(configs, DateTime(2026, 1, 1, 8, 30)), 1);
      expect(CourseService.currentPeriodOf(configs, DateTime(2026, 1, 1, 10, 20)), 3);
      expect(CourseService.currentPeriodOf(configs, DateTime(2026, 1, 1, 20, 0)), 9);
      // 午休时间不在任何节段
      expect(CourseService.currentPeriodOf(configs, DateTime(2026, 1, 1, 12, 0)), 0);
      // 修改配置后按新配置判断
      final custom = [
        ClassTimeConfig.create(
            id: 1, firstPeriod: 1, lastPeriod: 2, startMinutes: 9 * 60, endMinutes: 10 * 60 + 40),
      ];
      expect(CourseService.currentPeriodOf(custom, DateTime(2026, 1, 1, 8, 30)), 0);
      expect(CourseService.currentPeriodOf(custom, DateTime(2026, 1, 1, 9, 30)), 1);
    });
  });

  group('活跃学期与课程过滤', () {
    test('旧数据无 isActive 标记时自动激活第一个学期', () async {
      await isar.writeTxn(() async {
        await isar.semesterConfigs.put(makeSemester('2025-2026-1'));
        await isar.semesterConfigs.put(makeSemester('2026-2027-1'));
      });

      final active = await svc.ensureActiveSemester();
      expect(active.name, '2025-2026-1');
      expect(active.isActive, isTrue);

      // 全库只有一个活跃
      final all = await isar.semesterConfigs.where().findAll();
      expect(all.where((c) => c.isActive).length, 1);
    });

    test('getWeeklySchedule 只返回活跃学期的课程', () async {
      await isar.writeTxn(() async {
        await isar.semesterConfigs.put(makeSemester('2025-A', active: true));
        await isar.semesterConfigs.put(makeSemester('2025-B', active: false));
        await isar.courses.put(makeCourse('高数', '2025-A'));
        await isar.courses.put(makeCourse('大物', '2025-B'));
      });

      final schedule = await svc.getWeeklySchedule(1);
      final names = schedule.values.expand((list) => list.map((c) => c.name)).toSet();
      expect(names, {'高数'});
    });

    test('切换学期后过滤随之变化', () async {
      final semA = makeSemester('2025-A', active: true);
      final semB = makeSemester('2025-B');
      await isar.writeTxn(() async {
        await isar.semesterConfigs.put(semA);
        await isar.semesterConfigs.put(semB);
        await isar.courses.put(makeCourse('高数', '2025-A'));
        await isar.courses.put(makeCourse('大物', '2025-B'));
      });

      await svc.setActiveSemester(semB);
      final schedule = await svc.getWeeklySchedule(1);
      final names = schedule.values.expand((list) => list.map((c) => c.name)).toSet();
      expect(names, {'大物'});

      // 活跃标记互斥
      final all = await isar.semesterConfigs.where().findAll();
      expect(all.where((c) => c.isActive).map((c) => c.name), ['2025-B']);
    });

    test('新建学期自动设为活跃', () async {
      await isar.writeTxn(() async {
        await isar.semesterConfigs.put(makeSemester('2025-A', active: true));
      });
      await svc.createSemester(makeSemester('2026-B'));

      final active = await svc.ensureActiveSemester();
      expect(active.name, '2026-B');
    });
  });

  group('isDuplicateCourse 重复判定', () {
    test('同名同星期且节次重叠判为重复', () {
      final a = makeCourse('高数', 's', weekday: 2, start: 1, end: 2);
      final b = makeCourse('高数', 's', weekday: 2, start: 2, end: 4); // 节次2重叠
      expect(CourseService.isDuplicateCourse(a, b), isTrue);
    });

    test('不同名或不同星期不判为重复', () {
      final a = makeCourse('高数', 's', weekday: 2, start: 1, end: 2);
      expect(
          CourseService.isDuplicateCourse(
              a, makeCourse('大物', 's', weekday: 2, start: 1, end: 2)),
          isFalse);
      expect(
          CourseService.isDuplicateCourse(
              a, makeCourse('高数', 's', weekday: 3, start: 1, end: 2)),
          isFalse);
    });

    test('节次不重叠不判为重复（同名不同时段）', () {
      final a = makeCourse('高数', 's', weekday: 2, start: 1, end: 2);
      final b = makeCourse('高数', 's', weekday: 2, start: 3, end: 4);
      expect(CourseService.isDuplicateCourse(a, b), isFalse);
    });
  });
}
