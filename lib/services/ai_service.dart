import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  static const String defaultBaseUrl = 'https://open.bigmodel.cn/api/paas/v4';
  static const String defaultModel = 'glm-4-flash';

  /// 常用模型预设：(提供商分组, 模型名, 对应端点)
  /// 2026-10-12 按官方文档核验；证据见 docs/AI_COMPATIBILITY.md。
  /// 既有配置和手动输入不受预设清单变化影响。
  static const List<(String, String, String)> modelPresets = [
    ('智谱 GLM', 'glm-5.3-flash', defaultBaseUrl),
    ('智谱 GLM', 'glm-5.3-flashx', defaultBaseUrl),
    ('智谱 GLM', 'glm-5.3', defaultBaseUrl),
    ('DeepSeek', 'deepseek-flash', 'https://api.deepseek.com/v1'),
    ('DeepSeek', 'deepseek-v4-pro', 'https://api.deepseek.com/v1'),
    ('Kimi', 'kimi-k3', 'https://api.moonshot.cn/v1'),
    ('Kimi', 'kimi-k2.7-code', 'https://api.moonshot.cn/v1'),
    ('Kimi', 'kimi-k2.6', 'https://api.moonshot.cn/v1'),
    (
      '通义 Qwen',
      'qwen3.8-flash',
      'https://dashscope.aliyuncs.com/compatible-mode/v1'
    ),
    (
      '通义 Qwen',
      'qwen3.7-plus',
      'https://dashscope.aliyuncs.com/compatible-mode/v1'
    ),
    (
      '通义 Qwen',
      'qwen3.8-max',
      'https://dashscope.aliyuncs.com/compatible-mode/v1'
    ),
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

  AiService._()
      : _client = http.Client(),
        _requestTimeout = const Duration(minutes: 3);

  @visibleForTesting
  AiService.forTest(this._client,
      {Duration requestTimeout = const Duration(minutes: 3)})
      : _requestTimeout = requestTimeout;

  final http.Client _client;
  final Duration _requestTimeout;

  /// Accept either an API base or the complete Chat Completions URL.
  static Uri chatEndpoint(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw Exception('API 地址无效，请填写完整的 http:// 或 https:// 地址');
    }
    final path = uri.path.replaceAll(RegExp(r'/+$'), '');
    if (path.endsWith('/responses') || path.endsWith('/messages')) {
      throw Exception('请使用 Chat Completions 兼容地址，当前地址属于另一种接口');
    }
    return uri.replace(
        path: path.endsWith('/chat/completions')
            ? path
            : '$path/chat/completions');
  }

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
    final url = chatEndpoint(config.baseUrl);
    final key = config.apiKey.trim();
    final model = config.model.trim();
    if (key.isEmpty) throw Exception('请先填写 API Key');
    if (model.isEmpty) throw Exception('请先填写模型名称');
    final body = <String, dynamic>{
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
      'stream': false,
    };
    // Leave optional sampling parameters to each model's defaults. Official
    // reasoning models use light reasoning for this short-advice assistant.
    if ((['open.bigmodel.cn', 'api.z.ai'].contains(url.host) &&
            ['glm-5.3', 'glm-5.3-flash', 'glm-5.3-flashx'].contains(model)) ||
        (url.host == 'api.deepseek.com' &&
            ['deepseek-flash', 'deepseek-v4-pro'].contains(model)) ||
        (['api.moonshot.cn', 'api.moonshot.ai'].contains(url.host) &&
            model == 'kimi-k3') ||
        ((['dashscope.aliyuncs.com', 'dashscope-intl.aliyuncs.com']
                    .contains(url.host) ||
                url.host.endsWith('.maas.aliyuncs.com')) &&
            ['qwen3.8-max', 'qwen3.8-flash'].contains(model))) {
      body['reasoning_effort'] = 'low';
    }
    try {
      final response = await _client
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $key',
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);

      final text = utf8.decode(response.bodyBytes, allowMalformed: true);
      dynamic data;
      try {
        data = jsonDecode(text);
      } on FormatException {
        if (response.statusCode == 200) {
          throw Exception('服务端返回的不是有效 JSON，请检查 API 地址是否为 Chat Completions 接口');
        }
      }
      if (response.statusCode != 200) {
        final hint = switch (response.statusCode) {
          401 => '认证失败，请确认 Key 与 API 地址属于同一平台',
          403 => '无调用权限，请确认账户已开通该模型',
          404 => '接口或模型不存在，请核对 API 地址和模型名称',
          429 => '调用受限，可能是频率、并发或额度限制',
          _ => '请求失败',
        };
        final detail = _errorDetail(data).replaceAll(key, '[已隐藏]');
        throw Exception('$hint（HTTP ${response.statusCode}）'
            '${detail.isEmpty ? '' : '：$detail'}');
      }
      if (data is! Map) throw Exception('AI 返回格式不兼容：缺少对话结果');
      if (data['error'] != null) {
        throw Exception(
            '服务端返回错误：${_errorDetail(data).replaceAll(key, '[已隐藏]')}');
      }
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        throw Exception('AI 返回格式不兼容：缺少 choices 对话结果');
      }
      final choice = choices.first as Map;
      final message = choice['message'];
      final content = message is Map ? _contentText(message['content']) : '';
      if (content.isEmpty) {
        if (choice['finish_reason'] == 'length') {
          throw Exception('模型达到输出长度限制，未生成最终回答；请调整平台的输出预算');
        }
        if (choice['finish_reason'] == 'content_filter') {
          throw Exception('请求被服务端内容审核拦截，请调整问题后重试');
        }
        throw Exception('AI 返回内容为空');
      }
      return content;
    } on TimeoutException {
      throw Exception('等待模型回复超时（${_requestTimeout.inSeconds} 秒），'
          '思考模型可能需要更长时间；请稍后重试或选择更快的模型');
    } catch (e) {
      if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('SocketException')) {
        throw Exception('网络不可达，请检查网络或 API 地址');
      }
      rethrow;
    }
  }

  static String _errorDetail(dynamic data) {
    if (data is! Map) return '';
    final error = data['error'];
    if (error is String) return error;
    final fields = error is Map ? error : data;
    final code = fields['code']?.toString() ?? fields['type']?.toString() ?? '';
    final message =
        fields['message']?.toString() ?? fields['msg']?.toString() ?? '';
    return [code, message].where((part) => part.isNotEmpty).join('：');
  }

  static String _contentText(dynamic content) {
    if (content is String) return content.trim();
    if (content is List) {
      return content
          .whereType<Map>()
          .where((block) => ['text', 'output_text'].contains(block['type']))
          .map((block) => block['text'])
          .whereType<String>()
          .join('\n')
          .trim();
    }
    return '';
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

  static const String systemPrompt = '你是"拾序 · Dayloom"应用内置的 AI 学习生活助手。'
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
        final buffer =
            StringBuffer('任务（待办 ${active.length} 项 / 已完成 ${done.length} 项）：');
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
        final todayCourses = (schedule[d.weekday] ?? <Course>[])
          ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
        final buffer =
            StringBuffer('今日课程（第 $week 周，共 ${todayCourses.length} 节课）：');
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
          final buffer =
              StringBuffer('今日饮食 ${summary.count} 条：共 ${summary.calories} 千卡');
          if (summary.proteinGrams > 0) {
            buffer.write('，蛋白 ${summary.proteinGrams}g');
          }
          if (summary.carbsGrams > 0) {
            buffer.write('，碳水 ${summary.carbsGrams}g');
          }
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
