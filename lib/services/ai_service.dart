import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/course.dart';
import 'course_service.dart';
import 'diet_service.dart';
import 'fat_loss_service.dart';
import 'focus_analytics_service.dart';
import 'isar_service.dart';
import 'training_service.dart';

/// AI 助手配置与调用（OpenAI 兼容协议，默认智谱 GLM）。
/// API Key 只存本地 SharedPreferences；发送内容范围由用户按模块勾选。
class AiConfig {
  final bool enabled;
  final String baseUrl;
  final String apiKey;
  final String model;

  /// 数据上传范围（隐私开关）：任务 / 课程 / 专注 / 训练 / 饮食 / 减脂目标
  final bool scopeTodos;
  final bool scopeCourses;
  final bool scopeFocus;
  final bool scopeTraining;
  final bool scopeDiet;
  final bool scopeFatLoss;

  const AiConfig({
    this.enabled = false,
    this.baseUrl = defaultBaseUrl,
    this.apiKey = '',
    this.model = defaultModel,
    this.scopeTodos = true,
    this.scopeCourses = true,
    this.scopeFocus = true,
    this.scopeTraining = true,
    this.scopeDiet = true,
    this.scopeFatLoss = true,
  });

  static const String defaultBaseUrl =
      'https://open.bigmodel.cn/api/paas/v4';
  static const String defaultModel = 'glm-4-flash';

  /// 常用模型预设：(提供商分组, 模型名, 对应端点)
  /// 选择预设时自动联动 API 地址；也可手动输入任意模型名。
  static const List<(String, String, String)> modelPresets = [
    ('智谱 GLM', 'glm-4-flash', defaultBaseUrl),
    ('智谱 GLM', 'glm-4-plus', defaultBaseUrl),
    ('智谱 GLM', 'glm-4.5', defaultBaseUrl),
    ('智谱 GLM', 'glm-5.3', defaultBaseUrl),
    ('DeepSeek', 'deepseek-chat', 'https://api.deepseek.com/v1'),
    ('DeepSeek', 'deepseek-reasoner', 'https://api.deepseek.com/v1'),
    ('Kimi', 'kimi-k2-0711-preview', 'https://api.moonshot.cn/v1'),
    ('Kimi', 'moonshot-v1-8k', 'https://api.moonshot.cn/v1'),
    ('通义 Qwen', 'qwen-plus',
        'https://dashscope.aliyuncs.com/compatible-mode/v1'),
    ('通义 Qwen', 'qwen-max',
        'https://dashscope.aliyuncs.com/compatible-mode/v1'),
    ('通义 Qwen', 'qwen-turbo',
        'https://dashscope.aliyuncs.com/compatible-mode/v1'),
  ];

  bool get isConfigured => enabled && apiKey.trim().isNotEmpty;

  AiConfig copyWith({
    bool? enabled,
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? scopeTodos,
    bool? scopeCourses,
    bool? scopeFocus,
    bool? scopeTraining,
    bool? scopeDiet,
    bool? scopeFatLoss,
  }) {
    return AiConfig(
      enabled: enabled ?? this.enabled,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      scopeTodos: scopeTodos ?? this.scopeTodos,
      scopeCourses: scopeCourses ?? this.scopeCourses,
      scopeFocus: scopeFocus ?? this.scopeFocus,
      scopeTraining: scopeTraining ?? this.scopeTraining,
      scopeDiet: scopeDiet ?? this.scopeDiet,
      scopeFatLoss: scopeFatLoss ?? this.scopeFatLoss,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'scopeTodos': scopeTodos,
        'scopeCourses': scopeCourses,
        'scopeFocus': scopeFocus,
        'scopeTraining': scopeTraining,
        'scopeDiet': scopeDiet,
        'scopeFatLoss': scopeFatLoss,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) => AiConfig(
        enabled: json['enabled'] as bool? ?? false,
        baseUrl: json['baseUrl'] as String? ?? defaultBaseUrl,
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? defaultModel,
        scopeTodos: json['scopeTodos'] as bool? ?? true,
        scopeCourses: json['scopeCourses'] as bool? ?? true,
        scopeFocus: json['scopeFocus'] as bool? ?? true,
        scopeTraining: json['scopeTraining'] as bool? ?? true,
        scopeDiet: json['scopeDiet'] as bool? ?? true,
        scopeFatLoss: json['scopeFatLoss'] as bool? ?? true,
      );
}

class AiService {
  static AiService? _instance;
  static AiService get instance {
    _instance ??= AiService._();
    return _instance!;
  }

  AiService._();

  static const String _configKey = 'ai_assistant_config';

  Future<AiConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_configKey);
      if (raw == null || raw.isEmpty) return const AiConfig();
      return AiConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AiConfig();
    }
  }

  Future<void> saveConfig(AiConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(config.toJson()));
  }

  /// OpenAI 兼容对话补全。失败抛出带可读信息的异常。
  Future<String> chat({
    required AiConfig config,
    required String system,
    required String user,
  }) async {
    final base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final url = Uri.parse('$base/chat/completions');
    try {
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${config.apiKey.trim()}',
            },
            body: jsonEncode({
              'model': config.model,
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
              'temperature': 0.7,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('API Key 无效或无权限（${response.statusCode}）');
      }
      if (response.statusCode == 429) {
        throw Exception('调用过于频繁或额度不足（429）');
      }
      if (response.statusCode != 200) {
        // 透传服务商返回的原始原因（如"模型不存在""余额不足"），便于定位
        var detail = '';
        try {
          final errBody =
              jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          final err = errBody['error'];
          if (err is Map) {
            detail = err['message']?.toString() ?? '';
          } else if (err != null) {
            detail = err.toString();
          }
        } catch (_) {}
        throw Exception(
            '请求失败（${response.statusCode}）${detail.isNotEmpty ? '：$detail' : ''}');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw Exception('AI 返回内容为空');
      }
      final message = choices.first['message'] as Map<String, dynamic>?;
      final content = message?['content'] as String?;
      if (content == null || content.trim().isEmpty) {
        throw Exception('AI 返回内容为空');
      }
      return content.trim();
    } on TimeoutException {
      throw Exception('请求超时，请检查网络后重试');
    } catch (e) {
      if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('SocketException')) {
        throw Exception('网络不可达，请检查网络或 API 地址');
      }
      rethrow;
    }
  }

  /// 快捷测试连接
  Future<String> testConnection(AiConfig config) async {
    return chat(
      config: config,
      system: '你是连通性测试助手。',
      user: '请回复"连接成功"四个字。',
    );
  }

  // ==================== 今日数据上下文 ====================

  static const String systemPrompt =
      '你是"学习桌"应用内置的 AI 学习生活助手。'
      '用户消息末尾附带了今天的真实数据摘要（仅包含用户允许上传的模块）。'
      '请基于这些数据给简短、友好、可执行的中文建议；'
      '数据中没有的方面不要臆测；避免空泛套话；不要重复罗列原始数据。';

  /// 快捷提问模板
  static const quickPrompts = <String, String>{
    '今日建议': '根据我今天的任务和课程安排，给我接下来的时间规划建议。',
    '饮食点评': '根据我今天的饮食记录和减脂目标，点评当前摄入并给出下一步饮食建议。',
    '训练规划': '根据我的训练记录和本周训练情况，给出今天的训练建议。',
  };

  /// 按用户勾选的范围收集今日数据并构建上下文文本。
  /// 只包含数字与条目标题等摘要信息，不含备注长文本。
  Future<String> buildTodayContext(AiConfig config, {DateTime? date}) async {
    final d = date ?? DateTime.now();
    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final parts = <String>[
      '日期：${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${weekdays[d.weekday - 1]}',
    ];

    if (config.scopeTodos) {
      try {
        final todos = await IsarService.instance.getTodosForDate(d);
        final active = todos.where((t) => !t.isCompleted).toList();
        final done = todos.where((t) => t.isCompleted).toList();
        final buffer = StringBuffer(
            '任务（待办 ${active.length} 项 / 已完成 ${done.length} 项）：');
        for (final t in active) {
          final ddl = t.deadline != null
              ? '，截止 ${t.deadline!.month}/${t.deadline!.day} ${t.deadline!.hour.toString().padLeft(2, '0')}:${t.deadline!.minute.toString().padLeft(2, '0')}'
              : '';
          buffer.write(
              '\n- [待办] ${t.title}（${t.category.displayName}${t.taskType.isRecurring ? '·每日习惯' : ''}$ddl）');
        }
        for (final t in done) {
          buffer.write('\n- [已完成] ${t.title}');
        }
        parts.add(buffer.toString());
      } catch (_) {}
    }

    if (config.scopeCourses) {
      try {
        final courseSvc = CourseService.instance;
        final semester = await courseSvc.ensureActiveSemester();
        final week = semester.getCurrentWeek();
        final schedule = await courseSvc.getWeeklySchedule(week);
        final todayCourses =
            (schedule[d.weekday] ?? <Course>[])
              ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
        final buffer = StringBuffer('今日课程（第 $week 周，共 ${todayCourses.length} 节课）：');
        for (final c in todayCourses) {
          buffer.write('\n- ${c.name}（第${c.startPeriod}-${c.endPeriod}节'
              '${c.location.isNotEmpty ? ' · ${c.location}' : ''}）');
        }
        parts.add(buffer.toString());
      } catch (_) {}
    }

    if (config.scopeFocus) {
      try {
        final stats = await FocusAnalyticsService.forDay(d);
        if (stats.totalSeconds > 0) {
          parts.add('今日投入：专注/训练共 ${stats.totalSeconds ~/ 60} 分钟'
              '（专注 ${stats.focusSeconds ~/ 60} 分钟）');
        }
      } catch (_) {}
    }

    if (config.scopeTraining) {
      try {
        final training = TrainingService.instance;
        final weekCount = await training.workoutCountThisWeek(d);
        parts.add('本周训练 $weekCount 次');
      } catch (_) {}
    }

    if (config.scopeDiet) {
      try {
        final summary = await DietService.instance.getSummaryForDate(d);
        if (summary.count > 0) {
          final buffer = StringBuffer(
              '今日饮食 ${summary.count} 条：共 ${summary.calories} 千卡');
          if (summary.proteinGrams > 0) buffer.write('，蛋白 ${summary.proteinGrams}g');
          if (summary.carbsGrams > 0) buffer.write('，碳水 ${summary.carbsGrams}g');
          if (summary.fatGrams > 0) buffer.write('，脂肪 ${summary.fatGrams}g');
          parts.add(buffer.toString());
        } else {
          parts.add('今日饮食：尚未记录');
        }
      } catch (_) {}
    }

    if (config.scopeFatLoss) {
      try {
        final profile = await FatLossService.instance.loadProfile();
        if (profile != null) {
          final t = FatLossService.computeTargets(profile);
          parts.add('减脂计划：每日目标 ${t.targetKcal} 千卡'
              '（蛋白 ≥${t.proteinG}g / 脂肪 ≤${t.fatG}g / 碳水 ≤${t.carbG}g）');
        }
      } catch (_) {}
    }

    return parts.join('\n\n');
  }
}
