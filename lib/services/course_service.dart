import 'package:isar/isar.dart';
import '../models/course.dart';
import '../models/class_time_config.dart';
import 'widget_service.dart';

/// 课程数据库服务
class CourseService {
  static CourseService? _instance;
  static Isar? _isar;

  static CourseService get instance {
    _instance ??= CourseService._();
    return _instance!;
  }

  CourseService._();

  /// 初始化服务
  Future<void> init(Isar isar) async {
    _isar = isar;
  }

  Isar get isar {
    if (_isar == null) {
      throw Exception('Isar database not initialized. Call init() first.');
    }
    return _isar!;
  }

  // ==================== 节次时间配置 ====================

  /// 默认节次时间（与旧版硬编码保持一致，首次使用时写入）
  static List<ClassTimeConfig> defaultTimeConfigs() => [
        ClassTimeConfig.create(id: 1, firstPeriod: 1, lastPeriod: 2, startMinutes: 8 * 60, endMinutes: 9 * 60 + 40),
        ClassTimeConfig.create(id: 2, firstPeriod: 3, lastPeriod: 4, startMinutes: 10 * 60, endMinutes: 11 * 60 + 40),
        ClassTimeConfig.create(id: 3, firstPeriod: 5, lastPeriod: 6, startMinutes: 14 * 60 + 30, endMinutes: 16 * 60 + 10),
        ClassTimeConfig.create(id: 4, firstPeriod: 7, lastPeriod: 8, startMinutes: 16 * 60 + 30, endMinutes: 18 * 60 + 10),
        ClassTimeConfig.create(id: 5, firstPeriod: 9, lastPeriod: 10, startMinutes: 19 * 60 + 30, endMinutes: 21 * 60 + 10),
      ];

  /// 获取节次时间配置（首次使用时写入默认值），按节次序号排序
  Future<List<ClassTimeConfig>> getTimeConfigs() async {
    var configs = await isar.classTimeConfigs.where().findAll();
    if (configs.isEmpty) {
      configs = defaultTimeConfigs();
      await isar.writeTxn(() async {
        await isar.classTimeConfigs.putAll(configs);
      });
    }
    configs.sort((a, b) => a.id.compareTo(b.id));
    return configs;
  }

  /// 整体保存节次时间配置（id 会被重排为 1..n）
  Future<void> saveTimeConfigs(List<ClassTimeConfig> configs) async {
    for (int i = 0; i < configs.length; i++) {
      configs[i].id = i + 1;
    }
    await isar.writeTxn(() async {
      await isar.classTimeConfigs.clear();
      await isar.classTimeConfigs.putAll(configs);
    });
  }

  /// 判断某时刻处于哪个大节（纯函数，供测试与提醒计算复用）
  static ClassTimeConfig? currentSection(
      List<ClassTimeConfig> configs, int nowMinutes) {
    for (final c in configs) {
      if (nowMinutes >= c.startMinutes && nowMinutes <= c.endMinutes) {
        return c;
      }
    }
    return null;
  }

  /// 根据 [time]（默认现在）计算其所处大节的起始节次；不在上课时间返回 0
  static int currentPeriodOf(List<ClassTimeConfig> configs, DateTime time) {
    final nowMinutes = time.hour * 60 + time.minute;
    return currentSection(configs, nowMinutes)?.firstPeriod ?? 0;
  }

  // ==================== 学期配置管理 ====================

  /// 确保恰好有一个活跃学期并返回它。
  /// 兼容旧数据：没有任何 isActive 标记时，激活第一个（没有则创建默认）。
  Future<SemesterConfig> ensureActiveSemester() async {
    final configs = await isar.semesterConfigs.where().findAll();

    if (configs.isEmpty) {
      final now = DateTime.now();
      final config = SemesterConfig.create(
        name: _generateDefaultSemesterName(now),
        startDate: _findMonday(now),
        totalWeeks: 20,
        isActive: true,
      );
      await isar.writeTxn(() async {
        await isar.semesterConfigs.put(config);
      });
      return config;
    }

    final active =
        configs.where((c) => c.isActive).toList()..sort((a, b) => a.id.compareTo(b.id));

    if (active.isNotEmpty) {
      // 多个活跃时只保留第一个（防御性处理）
      if (active.length > 1) {
        await isar.writeTxn(() async {
          for (int i = 1; i < active.length; i++) {
            active[i].isActive = false;
            await isar.semesterConfigs.put(active[i]);
          }
        });
      }
      return active.first;
    }

    // 旧数据迁移：没有任何标记 → 激活第一个
    final first = configs.first;
    first.isActive = true;
    await isar.writeTxn(() async {
      await isar.semesterConfigs.put(first);
    });
    return first;
  }

  /// 获取所有学期（按名称排序）
  Future<List<SemesterConfig>> getAllSemesters() async {
    final configs = await isar.semesterConfigs.where().findAll();
    configs.sort((a, b) => a.name.compareTo(b.name));
    return configs;
  }

  /// 切换活跃学期
  Future<SemesterConfig> setActiveSemester(SemesterConfig target) async {
    final configs = await isar.semesterConfigs.where().findAll();
    await isar.writeTxn(() async {
      for (final c in configs) {
        final shouldActive = c.id == target.id;
        if (c.isActive != shouldActive) {
          c.isActive = shouldActive;
          await isar.semesterConfigs.put(c);
        }
      }
    });
    return target;
  }

  /// 新建学期并设为活跃
  Future<SemesterConfig> createSemester(SemesterConfig config) async {
    config.isActive = true;
    await isar.writeTxn(() async {
      // 取消其他学期的活跃标记
      final others = await isar.semesterConfigs.where().findAll();
      for (final c in others) {
        if (c.isActive && c.id != config.id) {
          c.isActive = false;
          await isar.semesterConfigs.put(c);
        }
      }
      await isar.semesterConfigs.put(config);
    });
    return config;
  }

  /// 更新学期配置
  Future<void> updateSemesterConfig(SemesterConfig config) async {
    await isar.writeTxn(() async {
      await isar.semesterConfigs.put(config);
    });
  }

  /// 判断两门课程是否重复（同名 + 同星期 + 节次区间重叠）。
  /// 纯函数，供导入预览与测试使用。
  static bool isDuplicateCourse(Course a, Course b) {
    return a.name == b.name &&
        a.weekday == b.weekday &&
        a.startPeriod <= b.endPeriod &&
        b.startPeriod <= a.endPeriod;
  }

  /// 找到指定日期所在周的周一
  DateTime _findMonday(DateTime date) {
    final weekday = date.weekday; // 1=周一, 7=周日
    final monday = date.subtract(Duration(days: weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  /// 根据日期生成默认学期名称
  String _generateDefaultSemesterName(DateTime date) {
    final year = date.year;
    final month = date.month;

    // 2-8月为第一学期，9-1月为第二学期
    if (month >= 2 && month <= 8) {
      return '$year-${year + 1}-1'; // 如 2025-2026-1
    } else {
      if (month == 1) {
        return '${year - 1}-$year-2'; // 如 2024-2025-2
      } else {
        return '$year-${year + 1}-1'; // 如 2025-2026-1
      }
    }
  }

  // ==================== 课程CRUD操作 ====================

  /// 导入课程到指定学期（清除该学期旧数据）
  Future<void> importCourses(List<Course> courses, String semester) async {
    await isar.writeTxn(() async {
      // 删除该学期的旧课程
      await isar.courses.filter().semesterEqualTo(semester).deleteAll();

      // 添加新课程
      for (var course in courses) {
        course.semester = semester;
        await isar.courses.put(course);
      }
    });
  }

  /// 添加课程
  Future<int> addCourse(Course course) async {
    return await isar.writeTxn(() async {
      return await isar.courses.put(course);
    });
  }

  /// 更新课程
  Future<void> updateCourse(Course course) async {
    await isar.writeTxn(() async {
      await isar.courses.put(course);
    });
  }

  /// 删除课程
  Future<bool> deleteCourse(int id) async {
    return await isar.writeTxn(() async {
      return await isar.courses.delete(id);
    });
  }

  /// 清空所有课程
  Future<void> clearAllCourses() async {
    await isar.writeTxn(() async {
      await isar.courses.clear();
    });
  }

  /// 获取活跃学期的所有课程
  Future<List<Course>> getAllCourses({String? semester}) async {
    final name = semester ?? (await ensureActiveSemester()).name;
    return await isar.courses.filter().semesterEqualTo(name).findAll();
  }

  // ==================== 课程查询（全部按活跃学期过滤） ====================

  /// 获取指定周的课程表
  /// @param weekNum 周次数（1-20）
  /// @return Map<星期几, 课程列表>，key为1-7
  Future<Map<int, List<Course>>> getWeeklySchedule(int weekNum,
      {String? semester}) async {
    final name = semester ?? (await ensureActiveSemester()).name;
    final allCourses =
        await isar.courses.filter().semesterEqualTo(name).findAll();

    // 筛选指定周有课的课程（过滤掉已结课的课程）
    final weekCourses = allCourses.where((course) {
      return course.hasClassInWeek(weekNum);
    }).toList();

    // 按星期分组
    final result = <int, List<Course>>{};
    for (var i = 1; i <= 7; i++) {
      result[i] = [];
    }

    for (var course in weekCourses) {
      result[course.weekday]!.add(course);
    }

    // 每天的课程按节次排序
    for (var list in result.values) {
      list.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
    }

    return result;
  }

  /// 获取指定周的课程列表
  /// @param weekNum 周次数
  /// @return 该周的所有课程，已按星期和节次排序
  Future<List<Course>> getCoursesForWeek(int weekNum, {String? semester}) async {
    final name = semester ?? (await ensureActiveSemester()).name;
    final allCourses =
        await isar.courses.filter().semesterEqualTo(name).findAll();

    return allCourses.where((course) {
      return course.hasClassInWeek(weekNum);
    }).toList()
      ..sort((a, b) {
        // 先按星期排序，再按节次排序
        if (a.weekday != b.weekday) {
          return a.weekday.compareTo(b.weekday);
        }
        return a.startPeriod.compareTo(b.startPeriod);
      });
  }

  /// 获取指定日期的课程
  /// @param weekday 星期几（1-7）
  /// @param weekNum 周次数
  /// @return 该天的课程列表，按节次排序
  Future<List<Course>> getCoursesForDay(int weekday, int weekNum,
      {String? semester}) async {
    final name = semester ?? (await ensureActiveSemester()).name;
    final allCourses =
        await isar.courses.filter().semesterEqualTo(name).findAll();

    return allCourses.where((course) {
      return course.weekday == weekday && course.hasClassInWeek(weekNum);
    }).toList()
      ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  }

  /// 获取当前时间的课程
  /// @return 当前正在进行的课程，如果没有返回null
  Future<Course?> getCurrentCourse() async {
    final now = DateTime.now();
    final weekday = now.weekday; // 1=周一, 7=周日

    final configs = await getTimeConfigs();
    final currentPeriod = currentPeriodOf(configs, now);
    if (currentPeriod == 0) return null;

    final semester = await ensureActiveSemester();
    final currentWeek = semester.getCurrentWeek();

    final todayCourses = await getCoursesForDay(weekday, currentWeek);

    for (var course in todayCourses) {
      if (currentPeriod >= course.startPeriod &&
          currentPeriod <= course.endPeriod) {
        return course;
      }
    }

    return null;
  }

  /// 获取下一节课程
  Future<Course?> getNextCourse() async {
    final now = DateTime.now();
    final weekday = now.weekday;

    final configs = await getTimeConfigs();
    final currentPeriod = currentPeriodOf(configs, now);
    final semester = await ensureActiveSemester();
    final currentWeek = semester.getCurrentWeek();

    // 先看今天还有没有课
    final todayCourses = await getCoursesForDay(weekday, currentWeek);
    for (var course in todayCourses) {
      if (course.startPeriod > currentPeriod) {
        return course;
      }
    }

    // 今天没课了，看明天的第一节课
    final tomorrow = weekday < 7 ? weekday + 1 : 1;
    final tomorrowWeek = weekday < 7 ? currentWeek : currentWeek + 1;
    final tomorrowCourses = await getCoursesForDay(tomorrow, tomorrowWeek);

    if (tomorrowCourses.isNotEmpty) {
      return tomorrowCourses.first;
    }

    return null;
  }

  // ==================== 统计功能 ====================

  /// 获取课程数量统计
  /// @param weekNum 周次数
  /// @return Map<'total'|'completed', 数量>
  Future<Map<String, int>> getCourseCountStatistics(int weekNum) async {
    final courses = await getCoursesForWeek(weekNum);
    final total = courses.length;

    // 统计已结课的课程数量
    int completed = 0;
    for (var course in courses) {
      if (!course.hasClassInWeek(weekNum)) {
        completed++;
      }
    }

    return {
      'total': total,
      'active': courses.where((c) => c.hasClassInWeek(weekNum)).length,
      'completed': completed,
    };
  }

  /// 调试：打印所有课程信息
  Future<Map<String, dynamic>> debugGetAllCoursesInfo() async {
    final courses = await isar.courses.where().findAll();

    return {
      'total': courses.length,
      'courses': courses.map((c) => {
        'name': c.name,
        'weekday': c.weekday,
        'period': '${c.startPeriod}-${c.endPeriod}',
        'weekRange': c.weekRange,
        'teacher': c.teacher,
        'location': c.location,
      }).toList(),
    };
  }

  // ==================== 考试管理 ====================

  /// 添加考试
  Future<int> addExam(Exam exam) async {
    final id = await isar.writeTxn(() async {
      return await isar.exams.put(exam);
    });
    // 同步到桌面小部件
    _syncExamsToWidget();
    return id;
  }

  /// 更新考试
  Future<void> updateExam(Exam exam) async {
    await isar.writeTxn(() async {
      await isar.exams.put(exam);
    });
    // 同步到桌面小部件
    _syncExamsToWidget();
  }

  /// 删除考试
  Future<void> deleteExam(int id) async {
    await isar.writeTxn(() async {
      await isar.exams.delete(id);
    });
    // 同步到桌面小部件
    _syncExamsToWidget();
  }

  /// 同步考试数据到桌面小部件
  Future<void> _syncExamsToWidget() async {
    try {
      final exams = await getAllExams();
      await WidgetService.instance.syncExams(exams);
    } catch (e) {
      // 忽略同步错误
    }
  }

  /// 获取所有考试
  Future<List<Exam>> getAllExams() async {
    return await isar.exams.where().sortByExamDateTime().findAll();
  }

  /// 获取即将到来的考试（未来的考试）
  Future<List<Exam>> getUpcomingExams() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final exams = await isar.exams
        .filter()
        .examDateTimeGreaterThan(today.subtract(const Duration(days: 1)))
        .sortByExamDateTime()
        .findAll();
    
    return exams;
  }

  /// 获取指定学期的考试
  Future<List<Exam>> getExamsForSemester(String semester) async {
    return await isar.exams
        .filter()
        .semesterEqualTo(semester)
        .sortByExamDateTime()
        .findAll();
  }

  /// 获取指定日期范围内的考试
  Future<List<Exam>> getExamsInDateRange(DateTime start, DateTime end) async {
    return await isar.exams
        .filter()
        .examDateTimeBetween(start, end)
        .sortByExamDateTime()
        .findAll();
  }

  /// 获取本周的考试
  Future<List<Exam>> getExamsForCurrentWeek() async {
    final now = DateTime.now();
    final weekday = now.weekday;
    final monday = now.subtract(Duration(days: weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    
    final startOfWeek = DateTime(monday.year, monday.month, monday.day);
    final endOfWeek = DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59);
    
    return await getExamsInDateRange(startOfWeek, endOfWeek);
  }

  /// 清空所有考试
  Future<void> clearAllExams() async {
    await isar.writeTxn(() async {
      await isar.exams.clear();
    });
  }
}
