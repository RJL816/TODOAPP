import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';

import 'package:todo_app/models/class_time_config.dart';
import 'package:todo_app/models/course.dart';
import 'package:todo_app/models/daily_completion.dart';
import 'package:todo_app/models/memo.dart';
import 'package:todo_app/models/pomodoro_session.dart';
import 'package:todo_app/models/training.dart';
import 'package:todo_app/models/diet_log.dart';
import 'package:todo_app/models/expense.dart';
import 'package:todo_app/models/todo_item.dart';

/// 测试基建：在 Dart VM 中加载 Isar 原生库并打开独立的临时数据库。
///
/// 优先复用 pub 缓存中 isar_flutter_libs 自带的原生库（离线、确定），
/// 找不到时回退到官方下载。
var _coreInitialized = false;

Future<void> initIsarCoreForTests() async {
  if (_coreInitialized) return;
  final local = _findLocalIsarLibrary();
  if (local != null) {
    await Isar.initializeIsarCore(libraries: {Abi.current(): local});
  } else {
    await Isar.initializeIsarCore(download: true);
  }
  _coreInitialized = true;
}

String? _findLocalIsarLibrary() {
  if (!Platform.isWindows) return null;
  final home = Platform.environment['USERPROFILE'];
  if (home == null) return null;
  final caches = <String>[
    if (Platform.environment['PUB_CACHE'] != null)
      '${Platform.environment['PUB_CACHE']}\\hosted',
    '$home\\AppData\\Local\\Pub\\Cache\\hosted',
    '$home\\.pub-cache\\hosted',
  ];
  for (final cache in caches) {
    final hosted = Directory(cache);
    if (!hosted.existsSync()) continue;
    for (final mirror in hosted.listSync()) {
      if (mirror is! Directory) continue;
      final dll =
          File('${mirror.path}\\isar_flutter_libs-3.1.0+1\\windows\\isar.dll');
      if (dll.existsSync()) return dll.path;
    }
  }
  return null;
}

List<CollectionSchema<dynamic>> get appSchemas => [
      TodoItemSchema,
      DailyCompletionSchema,
      CourseSchema,
      SemesterConfigSchema,
      ExamSchema,
      MemoSchema,
      TagSchema,
      ClassTimeConfigSchema,
      PomodoroSessionSchema,
      TrainingPlanSchema,
      PlanExerciseSchema,
      WorkoutLogSchema,
      WorkoutSetSchema,
      DietLogSchema,
      ExpenseSchema,
    ];

/// 打开一个独立的临时数据库，测试结束自动清理。
Future<Isar> openTestIsar() async {
  await initIsarCoreForTests();
  final dir = await Directory.systemTemp.createTemp('todoapp_isar_test');
  final isar = await Isar.open(appSchemas, directory: dir.path);
  addTearDown(() async {
    if (isar.isOpen) {
      await isar.close(deleteFromDisk: true);
    }
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  });
  return isar;
}
