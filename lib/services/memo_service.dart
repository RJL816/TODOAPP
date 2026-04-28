import 'package:isar/isar.dart';
import '../models/memo.dart';

/// 备忘录服务类
class MemoService {
  static MemoService? _instance;
  static Isar? _isar;

  MemoService._();

  static MemoService get instance {
    _instance ??= MemoService._();
    return _instance!;
  }

  /// 初始化服务
  void init(Isar isar) {
    _isar = isar;
  }

  Isar get isar {
    if (_isar == null) {
      throw Exception('Isar database not initialized. Call init() first.');
    }
    return _isar!;
  }

  // ==================== 基本 CRUD 操作 ====================

  /// 添加新备忘录
  Future<int> addMemo(Memo memo) async {
    return await isar.writeTxn(() async {
      final id = await isar.memos.put(memo);
      return id;
    });
  }

  /// 更新备忘录
  Future<void> updateMemo(Memo memo) async {
    memo.updatedAt = DateTime.now();
    await isar.writeTxn(() async {
      await isar.memos.put(memo);
    });
  }

  /// 删除备忘录（软删除）
  Future<void> deleteMemo(int id) async {
    await isar.writeTxn(() async {
      final memo = await isar.memos.get(id);
      if (memo != null) {
        memo.isDeleted = true;
        memo.deletedAt = DateTime.now();
        memo.isPinned = false; // 取消置顶
        await isar.memos.put(memo);
      }
    });
  }

  /// 永久删除备忘录（真删除）
  Future<bool> permanentDeleteMemo(int id) async {
    return await isar.writeTxn(() async {
      return await isar.memos.delete(id);
    });
  }

  /// 恢复备忘录（从回收站）
  Future<void> restoreMemo(int id) async {
    await isar.writeTxn(() async {
      final memo = await isar.memos.get(id);
      if (memo != null) {
        memo.isDeleted = false;
        memo.deletedAt = null;
        await isar.memos.put(memo);
      }
    });
  }

  /// 切换置顶状态
  Future<void> togglePin(int id) async {
    await isar.writeTxn(() async {
      final memo = await isar.memos.get(id);
      if (memo != null) {
        memo.isPinned = !memo.isPinned;
        memo.updatedAt = DateTime.now();
        await isar.memos.put(memo);
      }
    });
  }

  // ==================== 查询操作 ====================

  /// 获取所有未删除的备忘录（按置顶和修改时间排序）
  Future<List<Memo>> getAllMemos() async {
    final memos = await isar.memos
        .filter()
        .isDeletedEqualTo(false)
        .findAll();

    // 手动排序：先按置顶，再按修改时间
    memos.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return b.isPinned ? 1 : -1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return memos;
  }

  /// 获取置顶的备忘录
  Future<List<Memo>> getPinnedMemos() async {
    return await isar.memos
        .filter()
        .isDeletedEqualTo(false)
        .isPinnedEqualTo(true)
        .sortByUpdatedAtDesc()
        .findAll();
  }

  /// 获取回收站的备忘录
  Future<List<Memo>> getDeletedMemos() async {
    return await isar.memos
        .filter()
        .isDeletedEqualTo(true)
        .sortByDeletedAtDesc()
        .findAll();
  }

  /// 根据 ID 获取备忘录
  Future<Memo?> getMemoById(int id) async {
    return await isar.memos.get(id);
  }

  /// 搜索备忘录（标题和内容全文搜索）
  Future<List<Memo>> searchMemos(String keyword) async {
    if (keyword.trim().isEmpty) {
      return await getAllMemos();
    }

    final lowerKeyword = keyword.toLowerCase();

    final memos = await isar.memos
        .filter()
        .isDeletedEqualTo(false)
        .and()
        .group((q) => q
            .titleContains(lowerKeyword, caseSensitive: false)
            .or()
            .contentContains(lowerKeyword, caseSensitive: false))
        .findAll();

    // 手动排序：先按置顶，再按修改时间
    memos.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return b.isPinned ? 1 : -1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return memos;
  }

  /// 根据标签筛选备忘录
  Future<List<Memo>> getMemosByTag(int tagId) async {
    final tag = await isar.tags.get(tagId);
    if (tag == null) return [];

    // 使用反向链接查询
    final memos = await isar.memos
        .filter()
        .tags((q) => q.idEqualTo(tagId))
        .and()
        .isDeletedEqualTo(false)
        .findAll();

    // 手动排序：先按置顶，再按修改时间
    memos.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return b.isPinned ? 1 : -1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return memos;
  }

  /// 根据多个标签筛选备忘录（包含任一标签）
  Future<List<Memo>> getMemosByTags(List<int> tagIds) async {
    if (tagIds.isEmpty) {
      return await getAllMemos();
    }

    final memos = <Memo>[];
    for (final tagId in tagIds) {
      final tagMemos = await getMemosByTag(tagId);
      memos.addAll(tagMemos);
    }

    // 去重并排序
    final uniqueMemos = {for (var memo in memos) memo.id: memo}.values.toList();
    uniqueMemos.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return b.isPinned ? 1 : -1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });

    return uniqueMemos;
  }

  // ==================== 标签操作 ====================

  /// 添加标签
  Future<int> addTag(Tag tag) async {
    return await isar.writeTxn(() async {
      return await isar.tags.put(tag);
    });
  }

  /// 获取所有标签
  Future<List<Tag>> getAllTags() async {
    return await isar.tags.where().findAll();
  }

  /// 根据名称获取标签
  Future<Tag?> getTagByName(String name) async {
    return await isar.tags
        .filter()
        .nameEqualTo(name)
        .findFirst();
  }

  /// 创建或获取标签（如果不存在则创建）
  Future<Tag> getOrCreateTag(String name, {int? colorArgb}) async {
    final existingTag = await getTagByName(name);
    if (existingTag != null) {
      return existingTag;
    }

    final newTag = Tag.create(
      name: name,
      colorArgb: colorArgb,
    );

    final id = await addTag(newTag);
    newTag.id = id;
    return newTag;
  }

  /// 为备忘录添加标签
  Future<void> addTagToMemo(int memoId, int tagId) async {
    await isar.writeTxn(() async {
      final memo = await isar.memos.get(memoId);
      final tag = await isar.tags.get(tagId);

      if (memo != null && tag != null) {
        // 使用 IsarLinks 的 add 方法
        memo.tags.add(tag);
        memo.updatedAt = DateTime.now();
        await isar.memos.put(memo);
      }
    });
  }

  /// 从备忘录移除标签
  Future<void> removeTagFromMemo(int memoId, int tagId) async {
    await isar.writeTxn(() async {
      final memo = await isar.memos.get(memoId);
      final tag = await isar.tags.get(tagId);

      if (memo != null && tag != null) {
        // 使用 IsarLinks 的 remove 方法
        memo.tags.remove(tag);
        memo.updatedAt = DateTime.now();
        await isar.memos.put(memo);
      }
    });
  }

  /// 更新备忘录的标签列表
  Future<void> updateMemoTags(int memoId, List<int> tagIds) async {
    await isar.writeTxn(() async {
      final memo = await isar.memos.get(memoId);
      if (memo == null) return;

      // 清除现有标签
      memo.tags.clear();

      // 添加新标签
      for (final tagId in tagIds) {
        final tag = await isar.tags.get(tagId);
        if (tag != null) {
          memo.tags.add(tag);
        }
      }

      memo.updatedAt = DateTime.now();
      await isar.memos.put(memo);
    });
  }

  /// 删除标签
  Future<bool> deleteTag(int id) async {
    return await isar.writeTxn(() async {
      return await isar.tags.delete(id);
    });
  }

  /// 获取备忘录的标签
  Future<List<Tag>> getMemoTags(int memoId) async {
    // 直接查询所有标签，然后在内存中过滤
    final allTags = await isar.tags.where().findAll();
    final linkedTags = <Tag>[];

    for (final tag in allTags) {
      // 检查这个标签是否链接到指定的备忘录
      final memos = await isar.memos
          .filter()
          .tags((q) => q.idEqualTo(tag.id))
          .and()
          .idEqualTo(memoId)
          .findAll();

      if (memos.isNotEmpty) {
        linkedTags.add(tag);
      }
    }

    return linkedTags;
  }

  // ==================== 回收站清理 ====================

  /// 清理超过30天的已删除备忘录
  Future<int> cleanupOldDeletedMemos() async {
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));

    return await isar.writeTxn(() async {
      final oldMemos = await isar.memos
          .filter()
          .isDeletedEqualTo(true)
          .and()
          .deletedAtLessThan(thirtyDaysAgo)
          .findAll();

      int count = 0;
      for (final memo in oldMemos) {
        // 清除标签关联
        memo.tags.clear();
        // 删除备忘录
        final deleted = await isar.memos.delete(memo.id);
        if (deleted) {
          count++;
        }
      }

      return count;
    });
  }

  /// 清空所有已删除的备忘录（永久删除）
  Future<int> emptyTrash() async {
    return await isar.writeTxn(() async {
      final deletedMemos = await isar.memos
          .filter()
          .isDeletedEqualTo(true)
          .findAll();

      int count = 0;
      for (final memo in deletedMemos) {
        // 清除标签关联
        memo.tags.clear();
        // 删除备忘录
        final deleted = await isar.memos.delete(memo.id);
        if (deleted) {
          count++;
        }
      }

      return count;
    });
  }

  // ==================== 导出功能 ====================

  /// 导出备忘录为 Markdown 格式
  Future<String> exportMemoToMarkdown(int id) async {
    final memo = await getMemoById(id);
    if (memo == null) {
      throw Exception('备忘录不存在');
    }

    final tags = await getMemoTags(id);
    final tagNames = tags.map((t) => t.name).join(', ');

    final sb = StringBuffer();
    sb.writeln('# ${memo.title}');
    sb.writeln();
    if (tagNames.isNotEmpty) {
      sb.writeln('**标签:** $tagNames');
      sb.writeln();
    }
    sb.writeln('**创建时间:** ${memo.formattedCreatedAt}');
    sb.writeln('**修改时间:** ${memo.formattedUpdatedAt}');
    sb.writeln();
    sb.writeln('---');
    sb.writeln();
    sb.writeln(memo.content);

    return sb.toString();
  }

  /// 导出所有备忘录为 JSON
  Future<String> exportAllToJson() async {
    final memos = await getAllMemos();
    final jsonList = <Map<String, dynamic>>[];

    for (final memo in memos) {
      final tags = await getMemoTags(memo.id);
      final memoData = memo.toJson();
      memoData['tags'] = tags.map((t) => t.toJson()).toList();
      jsonList.add(memoData);
    }

    return jsonList.toString();
  }

  // ==================== 统计操作 ====================

  /// 获取备忘录总数（不包括已删除）
  Future<int> getMemoCount() async {
    return await isar.memos
        .filter()
        .isDeletedEqualTo(false)
        .count();
  }

  /// 获取置顶备忘录数量
  Future<int> getPinnedCount() async {
    return await isar.memos
        .filter()
        .isDeletedEqualTo(false)
        .isPinnedEqualTo(true)
        .count();
  }

  /// 获取回收站备忘录数量
  Future<int> getDeletedCount() async {
    return await isar.memos
        .filter()
        .isDeletedEqualTo(true)
        .count();
  }

  /// 获取标签数量
  Future<int> getTagCount() async {
    return await isar.tags.count();
  }
}
