import 'package:isar/isar.dart';

part 'memo.g.dart';

/// 备忘录
@Collection()
class Memo {
  Id id = Isar.autoIncrement;

  /// 标题
  @Index()
  late String title;

  /// 内容（Markdown 格式）
  late String content;

  /// 创建时间
  @Index()
  late DateTime createdAt;

  /// 最后修改时间
  @Index()
  late DateTime updatedAt;

  /// 是否置顶
  late bool isPinned;

  /// 是否已删除（软删除标记）
  @Index()
  late bool isDeleted;

  /// 删除时间（用于30天后自动清除）
  DateTime? deletedAt;

  /// 标签关联（多对多关系）
  final tags = IsarLinks<Tag>();

  Memo() {
    isPinned = false;
    isDeleted = false;
  }

  /// 创建新备忘录
  Memo.create({
    required this.title,
    required this.content,
    this.isPinned = false,
    List<int>? tagIds, // 标签ID列表（用于初始化关联）
  })  : createdAt = DateTime.now(),
        updatedAt = DateTime.now(),
        isDeleted = false,
        deletedAt = null;

  /// 获取摘要（前50个字符）
  String get summary {
    final text = content.replaceAll('\n', ' ').trim();
    if (text.length <= 50) return text;
    return '${text.substring(0, 50)}...';
  }

  /// 获取格式化的创建时间
  String get formattedCreatedAt {
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} '
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  /// 获取格式化的修改时间
  String get formattedUpdatedAt {
    final now = DateTime.now();
    final diff = now.difference(updatedAt);

    if (diff.inMinutes < 1) {
      return '刚刚';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}分钟前';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}小时前';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${updatedAt.year}-${updatedAt.month.toString().padLeft(2, '0')}-${updatedAt.day.toString().padLeft(2, '0')}';
    }
  }

  /// 转换为 JSON（用于备份导出）
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isPinned': isPinned,
        'isDeleted': isDeleted,
        'deletedAt': deletedAt?.toIso8601String(),
      };

  /// 从 JSON 创建（用于备份恢复）
  factory Memo.fromJson(Map<String, dynamic> json) => Memo()
    ..id = (json['id'] as int?) ?? Isar.autoIncrement
    ..title = (json['title'] as String?) ?? '无标题'
    ..content = (json['content'] as String?) ?? ''
    ..createdAt = DateTime.parse(json['createdAt'] as String)
    ..updatedAt = DateTime.parse(json['updatedAt'] as String)
    ..isPinned = (json['isPinned'] as bool?) ?? false
    ..isDeleted = (json['isDeleted'] as bool?) ?? false
    ..deletedAt = json['deletedAt'] != null
        ? DateTime.parse(json['deletedAt'] as String)
        : null;
}

/// 标签
@Collection()
class Tag {
  Id id = Isar.autoIncrement;

  /// 标签名称
  @Index(unique: true)
  late String name;

  /// 颜色（ARGB 格式）
  late int colorArgb;

  /// 创建时间
  late DateTime createdAt;

  Tag() {
    colorArgb = _generateRandomColor();
    createdAt = DateTime.now();
  }

  /// 创建新标签
  Tag.create({
    required this.name,
    int? colorArgb,
  })  : colorArgb = colorArgb ?? _generateRandomColor(),
        createdAt = DateTime.now();

  /// 预设颜色方案（柔和配色）
  static const List<int> tagColors = [
    0xFF5C6BC0, // 靛蓝
    0xFF7E57C2, // 深紫
    0xFFAB47BC, // 紫色
    0xFFEC407A, // 粉红
    0xFFEF5350, // 红色
    0xFFFF7043, // 深橙
    0xFFFFA726, // 橙色
    0xFFFFCA28, // 琥珀
    0xFF66BB6A, // 绿色
    0xFF26A69A, // 蓝绿
    0xFF29B6F6, // 浅蓝
    0xFF42A5F5, // 蓝色
  ];

  /// 生成随机颜色
  static int _generateRandomColor() {
    final now = DateTime.now();
    final seed = now.millisecondsSinceEpoch % tagColors.length;
    return tagColors[seed >= 0 ? seed : 0];
  }

  /// 根据标签名生成固定颜色（相同标签名颜色相同）
  static int getColorForName(String name) {
    if (name.isEmpty) return tagColors[0];
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = name.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return tagColors[(hash.abs()) % tagColors.length];
  }

  /// 转换为 JSON（用于备份导出）
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorArgb': colorArgb,
        'createdAt': createdAt.toIso8601String(),
      };

  /// 从 JSON 创建（用于备份恢复）
  factory Tag.fromJson(Map<String, dynamic> json) => Tag()
    ..id = (json['id'] as int?) ?? Isar.autoIncrement
    ..name = json['name'] as String
    ..colorArgb = (json['colorArgb'] as int?) ?? 0xFF5C6BC0
    ..createdAt = json['createdAt'] != null
        ? DateTime.parse(json['createdAt'] as String)
        : DateTime.now();
}
