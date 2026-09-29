import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:todo_app/models/course.dart';
import 'package:todo_app/models/daily_completion.dart';
import 'package:todo_app/models/memo.dart';
import 'package:todo_app/models/todo_item.dart';
import 'package:todo_app/models/expense.dart';
import 'package:todo_app/services/backup_service.dart';

import 'isar_test_base.dart';

/// 备份/导出/覆盖恢复的单元测试。
/// 流程对应 docs/UPGRADE_PLAN.md 1A.2：
/// 打开前备份（可校验）→ 打开/迁移 → 条数验证 → 全量导出 → 覆盖恢复。
void main() {
  setUpAll(() async {
    await initIsarCoreForTests();
  });

  test('完整链路：打开前备份 → 验证 → 导出 → 覆盖恢复', () async {
    // ---- 准备：在"文档目录"里建库并写入覆盖全部集合的数据 ----
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final docsDir =
        await Directory.systemTemp.createTemp('todoapp_backup_docs');
    addTearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });

    var isar = await Isar.open(appSchemas, directory: docsDir.path);

    final habit = TodoItem.create(
      title: '习惯',
      date: DateTime.now(),
      taskType: TaskType.recurring,
    );
    final habitId = await isar.writeTxn(() async {
      final id = await isar.todoItems.put(habit);
      await isar.dailyCompletions.put(DailyCompletion.create(
        todoId: id,
        completionDate: DateTime.now(),
      ));
      await isar.courses.put(Course.create(
        name: '高等数学',
        weekday: 1,
        startPeriod: 1,
        endPeriod: 2,
        weekRange: '1-16',
        semester: '2025-2026-1',
      ));
      await isar.semesterConfigs.put(SemesterConfig.create(
        name: '2025-2026-1',
        startDate: DateTime(2026, 3, 2),
        totalWeeks: 18,
      ));
      await isar.exams.put(Exam.create(
        name: '期末考试',
        examDateTime: DateTime(2026, 7, 1, 9, 0),
        semester: '2025-2026-1',
      ));
      await isar.expenses.put(Expense.create(
        date: DateTime(2026, 9, 24),
        amountCents: 12345,
        category: '餐饮',
        paymentMethod: '微信',
      ));
      final memo = Memo.create(title: '笔记', content: '# 内容');
      final memoId = await isar.memos.put(memo);
      final tagId = await isar.tags.put(Tag.create(name: '学习'));
      final savedMemo = await isar.memos.get(memoId);
      final savedTag = await isar.tags.get(tagId);
      savedMemo!.tags.add(savedTag!);
      await savedMemo.tags.save();
      return id;
    });

    // 模拟生产时序：先关库，备份发生在 Isar.open（自动迁移）之前
    await isar.close();

    // ---- 打开前自动备份 ----
    final svc = BackupService.forTest(docsDir, prefs);
    final backup = await svc.ensureBackupBeforeOpen();

    expect(backup, isNotNull);
    expect(backup!.success, isTrue, reason: backup.failedReason ?? '');
    expect(backup.counts['todoItems'], 1);
    expect(backup.counts['dailyCompletions'], 1);
    expect(backup.counts['courses'], 1);
    expect(backup.counts['semesterConfigs'], 1);
    expect(backup.counts['exams'], 1);
    expect(backup.counts['memos'], 1);
    expect(backup.counts['tags'], 1);
    expect(backup.counts['expenses'], 1);
    // 备份文件真实存在
    final backupDir = Directory(backup.path!);
    expect(
      await File('${backupDir.path}/default.isar').exists(),
      isTrue,
    );
    // 版本号推进
    expect(prefs.getInt('app_data_version'), BackupService.kAppDataVersion);

    // 再次运行不再重复备份
    expect(await svc.ensureBackupBeforeOpen(), isNull);

    // ---- 重新打开（相当于 Isar 自动迁移后）并验证条数一致 ----
    isar = await Isar.open(appSchemas, directory: docsDir.path);
    addTearDown(() async => await isar.close(deleteFromDisk: true));
    expect(await svc.verifyAfterOpen(isar, backup), isTrue);

    // ---- 全量导出 ----
    final json = await svc.exportAllToJson(isar);
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    expect(decoded['format'], BackupService.exportFormat);
    final cols = decoded['collections'] as Map<String, dynamic>;
    expect((cols['todoItems'] as List).length, 1);
    expect((cols['expenses'] as List).length, 1);
    final links = decoded['memoTagLinks'] as List;
    expect(links.length, 1);
    expect((links.first as Map<String, dynamic>)['tagIds'], isNotEmpty);

    // ---- 覆盖恢复到一个已存在脏数据的全新库 ----
    final otherDir =
        await Directory.systemTemp.createTemp('todoapp_restore_target');
    addTearDown(() async {
      if (await otherDir.exists()) await otherDir.delete(recursive: true);
    });
    // 用不同实例名打开（Isar 注册表按名称去重，同一进程不能有两个 default）
    final target = await Isar.open(appSchemas,
        directory: otherDir.path, name: 'restore_target');
    addTearDown(() async => await target.close(deleteFromDisk: true));
    // 预置脏数据：恢复后应被清掉
    await target.writeTxn(() async {
      await target.todoItems
          .put(TodoItem.create(title: '脏数据', date: DateTime.now()));
    });

    final summary = await svc.restoreFromJson(json, target);

    expect(summary.verified, isTrue, reason: summary.warnings.join('; '));
    expect(summary.restoredCounts['todoItems'], 1);
    expect(summary.restoredCounts['tags'], 1);
    expect(summary.restoredCounts['expenses'], 1);
    expect((await target.expenses.where().findFirst())!.amountCents, 12345);
    // 脏数据被清除（todoItems 仍为源数据的 1 条）
    expect(await target.todoItems.count(), 1);

    // 关键引用保留：完成记录指向的习惯仍存在
    final restoredCompletion =
        await target.dailyCompletions.where().findFirst();
    expect(restoredCompletion, isNotNull);
    expect(await target.todoItems.get(restoredCompletion!.todoId), isNotNull);
    expect(restoredCompletion.todoId, habitId);

    // 标签关联恢复
    final restoredMemo = await target.memos.where().findFirst();
    await restoredMemo!.tags.load();
    expect(restoredMemo.tags.length, 1);
    expect(restoredMemo.tags.first.name, '学习');
  });

  test('损坏的 JSON 与错误格式标识被拒绝', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final docsDir = await Directory.systemTemp.createTemp('todoapp_backup_bad');
    addTearDown(() async {
      if (await docsDir.exists()) await docsDir.delete(recursive: true);
    });
    final isar = await Isar.open(appSchemas, directory: docsDir.path);
    addTearDown(() async => await isar.close(deleteFromDisk: true));

    final svc = BackupService.forTest(docsDir, prefs);

    expect(
      () => svc.restoreFromJson('这不是json', isar),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => svc.restoreFromJson('{"format": "other.app", "version": 2}', isar),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => svc.restoreFromJson(
          '{"format": "${BackupService.exportFormat}", "version": 999}', isar),
      throwsA(isA<FormatException>()),
    );
  });
}
