import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/services/course_import_service.dart';

/// 老版 .xls 课表导入：用仓库根目录的真实教务系统导出样本验证
void main() {
  group('CourseImportService .xls 支持', () {
    test('解析老版 .xls 课表（学生个人课表.xls）', () async {
      final courses =
          await CourseImportService.instance.importFromExcel('学生个人课表.xls');
      expect(courses, isNotEmpty);
      for (final course in courses) {
        expect(course.name, isNotEmpty);
        expect(course.weekday, inInclusiveRange(1, 7));
        expect(course.startPeriod, greaterThan(0));
        expect(course.weekRange, isNotEmpty);
      }
    });

    test('xls 与同名 xlsx 样本解析出相同数量的课程', () async {
      final path = '学生个人课表_220231090714';
      final fromXls =
          await CourseImportService.instance.importFromExcel('$path.xls');
      final fromXlsx =
          await CourseImportService.instance.importFromExcel('$path.xlsx');
      expect(fromXls.length, fromXlsx.length);
      expect(
        fromXls.map((c) => '${c.name}|${c.weekday}|${c.startPeriod}').toSet(),
        fromXlsx.map((c) => '${c.name}|${c.weekday}|${c.startPeriod}').toSet(),
      );
    });
  });
}
