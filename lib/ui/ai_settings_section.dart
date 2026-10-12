import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ai_service.dart';
import 'app_theme.dart';

/// Keeps editable credentials alive across rebuilds and saves current drafts.
class AiSettingsSection extends StatefulWidget {
  const AiSettingsSection(
      {super.key, required this.onConfigChanged, this.service});

  final VoidCallback onConfigChanged;
  final AiService? service;

  @override
  State<AiSettingsSection> createState() => _AiSettingsSectionState();
}

class _AiSettingsSectionState extends State<AiSettingsSection> {
  late final AiService _service = widget.service ?? AiService.instance;
  final _addressController = TextEditingController();
  final _keyController = TextEditingController();
  final _modelController = TextEditingController();
  AiConfig _aiConfig = const AiConfig();
  Future<void> _saveQueue = Future.value();
  Timer? _saveTimer;
  bool _loading = true;
  bool _testing = false;
  String? _result;
  bool _resultIsError = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final config = await _service.loadConfig();
    if (!mounted) return;
    setState(() {
      _aiConfig = config;
      _syncFields(config);
      _loading = false;
    });
  }

  void _syncFields(AiConfig config) {
    for (final (controller, text) in [
      (_addressController, config.baseUrl),
      (_keyController, config.apiKey),
      (_modelController, config.model),
    ]) {
      if (controller.text != text) controller.text = text;
    }
  }

  AiConfig _draft() => _aiConfig.copyWith(
      baseUrl: _addressController.text.trim(),
      apiKey: _keyController.text.trim(),
      model: _modelController.text.trim());

  void _updateAiConfig(AiConfig config) {
    setState(() {
      _aiConfig = config;
      _syncFields(config);
      _result = null;
    });
    _saveTimer?.cancel();
    _saveTimer =
        Timer(const Duration(milliseconds: 350), () => _queueSave(_draft()));
  }

  // Serial writes prevent an older keystroke from overwriting a newer draft.
  Future<void> _queueSave(AiConfig config) {
    final save = _saveQueue.then((_) async {
      await _service.saveConfig(config);
      widget.onConfigChanged();
    });
    _saveQueue = save.catchError((Object error) {
      if (mounted) {
        setState(() {
          _result = '配置保存失败，请重试';
          _resultIsError = true;
        });
      }
    });
    return save;
  }

  Future<void> _saveNow() async {
    _saveTimer?.cancel();
    try {
      await _queueSave(_draft());
    } catch (_) {
      // The queued save already displays the failure.
    }
  }

  Future<void> _testConnection() async {
    FocusScope.of(context).unfocus();
    _saveTimer?.cancel();
    final config = _draft();
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      await _queueSave(config);
      final reply = await _service.testConnection(config);
      if (mounted) {
        setState(() {
          _result = '连接成功：$reply';
          _resultIsError = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _result = '连接失败：${error.toString().replaceFirst('Exception: ', '')}';
          _resultIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  void dispose() {
    if (!_loading) {
      _saveTimer?.cancel();
      unawaited(_queueSave(_draft()).catchError((Object _) {}));
    }
    _addressController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  /// AI 助手配置：端点 / Key / 模型 / 数据上传范围 / 测试连接
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = _aiConfig;
    if (_loading) return const LinearProgressIndicator();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text('AI 助手', style: theme.textTheme.titleSmall),
        const Spacer(),
        Switch(
          value: config.enabled,
          onChanged: _testing
              ? null
              : (v) => _updateAiConfig(_draft().copyWith(enabled: v)),
        ),
      ]),
      if (config.enabled) ...[
        TextField(
          controller: _addressController,
          enabled: !_testing,
          onChanged: (v) =>
              _updateAiConfig(_draft().copyWith(baseUrl: v.trim())),
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'API 地址（OpenAI 兼容）',
            hintText: AiConfig.defaultBaseUrl,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _keyController,
          enabled: !_testing,
          obscureText: true,
          onChanged: (v) =>
              _updateAiConfig(_draft().copyWith(apiKey: v.trim())),
          decoration: InputDecoration(
            isDense: true,
            labelText: 'API Key（仅保存在本机）',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.check, size: 18),
              tooltip: '保存',
              onPressed: _testing ? null : _saveNow,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _modelController,
              enabled: !_testing,
              onChanged: (v) =>
                  _updateAiConfig(_draft().copyWith(model: v.trim())),
              decoration: const InputDecoration(
                isDense: true,
                labelText: '模型（可选预设或手动输入）',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: '常用模型预设',
            enabled: !_testing,
            onSelected: (value) {
              // 选择预设时联动对应的 API 地址
              final match = AiConfig.modelPresets
                  .firstWhere((p) => p.$2 == value, orElse: () => ('', '', ''));
              final draft = _draft();
              var knownEndpoint = false;
              try {
                final current = AiService.chatEndpoint(draft.baseUrl);
                knownEndpoint = AiConfig.modelPresets.any(
                    (preset) => AiService.chatEndpoint(preset.$3) == current);
              } catch (_) {
                // Preserve incomplete edits until the user finishes the URL.
              }
              _updateAiConfig(draft.copyWith(
                  model: value,
                  baseUrl: knownEndpoint && match.$3.isNotEmpty
                      ? match.$3
                      : draft.baseUrl));
            },
            itemBuilder: (context) => [
              for (final group
                  in AiConfig.modelPresets.map((p) => p.$1).toSet()) ...[
                PopupMenuItem<String>(
                    enabled: false,
                    child: Text(group,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.primary))),
                for (final (_, model, _)
                    in AiConfig.modelPresets.where((p) => p.$1 == group))
                  PopupMenuItem<String>(
                      value: model,
                      child: Text(model, style: theme.textTheme.bodyMedium)),
              ],
            ],
            color: AppColors.paper,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.list, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text('预设',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text('允许 AI 读取的数据（用于生成建议）', style: theme.textTheme.bodySmall),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          for (final (key, label) in const [
            ('scopeTodos', '任务'),
            ('scopeCourses', '课程'),
            ('scopeFocus', '专注'),
            ('scopeTraining', '训练'),
            ('scopeDiet', '饮食'),
            ('scopeFatLoss', '减脂目标'),
          ])
            FilterChip(
              label: Text(label),
              selected: switch (key) {
                'scopeTodos' => config.scopeTodos,
                'scopeCourses' => config.scopeCourses,
                'scopeFocus' => config.scopeFocus,
                'scopeTraining' => config.scopeTraining,
                'scopeDiet' => config.scopeDiet,
                _ => config.scopeFatLoss,
              },
              onSelected: _testing
                  ? null
                  : (v) => _updateAiConfig(switch (key) {
                        'scopeTodos' => _draft().copyWith(scopeTodos: v),
                        'scopeCourses' => _draft().copyWith(scopeCourses: v),
                        'scopeFocus' => _draft().copyWith(scopeFocus: v),
                        'scopeTraining' => _draft().copyWith(scopeTraining: v),
                        'scopeDiet' => _draft().copyWith(scopeDiet: v),
                        _ => _draft().copyWith(scopeFatLoss: v),
                      }),
              visualDensity: VisualDensity.compact,
            ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _testing ? null : _testConnection,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering, size: 16),
            label: Text(_testing ? '正在等待模型…' : '测试连接'),
          ),
        ]),
        if (_result != null) ...[
          const SizedBox(height: 8),
          SelectableText(_result!,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: _resultIsError ? theme.colorScheme.error : null)),
        ],
        const SizedBox(height: 8),
        Text('API 地址、Key 与模型需属于同一平台；第三方平台请使用其提供的地址和模型名。',
            style: theme.textTheme.bodySmall),
        Text(
            '发送内容为按上面勾选范围构建的今日数据摘要；'
            'Key 仅保存在本机。悬浮球会在配置完成后出现。',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
      ],
      const Divider(),
    ]);
  }
}
