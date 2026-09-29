import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/ai_service.dart';
import 'app_theme.dart';
import 'glass_panel.dart';

/// AI 悬浮球：可拖拽、点击展开助手面板；位置记忆。
/// 显示条件由外部控制（已配置 API 且非沉浸模式时才挂载）。
class AiFloatingOrb extends StatefulWidget {
  final AiConfig config;
  final AiService service;

  /// 悬浮球底边到可用区域底部的最小距离；窄屏时应包含导航栏和间隙。
  final double minBottom;

  const AiFloatingOrb({
    super.key,
    required this.config,
    required this.service,
    this.minBottom = 16,
  });

  @override
  State<AiFloatingOrb> createState() => _AiFloatingOrbState();
}

class _AiFloatingOrbState extends State<AiFloatingOrb>
    with SingleTickerProviderStateMixin {
  static const String _positionKey = 'ai_orb_position';
  static const double _orbSize = 46;

  Offset _position = const Offset(18, 120); // 距右/距底
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _loadPosition();
  }

  Future<void> _loadPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dx = prefs.getDouble('${_positionKey}_x');
      final dy = prefs.getDouble('${_positionKey}_y');
      if (mounted && dx != null && dy != null) {
        setState(() => _position = Offset(dx, dy));
      }
    } catch (_) {}
  }

  Future<void> _savePosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('ai_orb_position_x', _position.dx);
      await prefs.setDouble('ai_orb_position_y', _position.dy);
    } catch (_) {}
  }

  void _openPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AiChatPanel(config: widget.config),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    // 越界保护：上下避开标题栏/底部导航，左右留边；拖拽与持久化共用此范围
    final maxX = max(media.width - _orbSize - 8, 8);
    final minDy = max(widget.minBottom, 8.0);
    final maxDy = max(media.height - _orbSize - 8, minDy);
    final clamped = Offset(
      _position.dx.clamp(8.0, maxX).toDouble(),
      _position.dy.clamp(minDy, maxDy).toDouble(),
    );

    return Positioned(
      right: clamped.dx,
      bottom: clamped.dy,
      child: GestureDetector(
        onTap: _openPanel,
        onPanUpdate: (details) {
          final media = MediaQuery.sizeOf(context);
          final minDy = max(widget.minBottom, 8.0);
          final maxDy = max(media.height - _orbSize - 8, minDy);
          final maxX = max(media.width - _orbSize - 8, 8.0);
          setState(() {
            // 每次移动都钳制在安全范围内：底栏/标题栏下方不可进入
            _position = Offset(
              (clamped.dx - details.delta.dx).clamp(8.0, maxX).toDouble(),
              (clamped.dy - details.delta.dy).clamp(minDy, maxDy).toDouble(),
            );
            _dragging = true;
          });
        },
        onPanEnd: (_) {
          if (_dragging) _savePosition();
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) setState(() => _dragging = false);
          });
        },
        child: AnimatedScale(
          scale: _dragging ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          child: GlassPanel(
            level: GlassSurfaceLevel.dark,
            radius: 23,
            opacity: .55,
            shadow: true,
            child: SizedBox(
              key: const Key('ai-floating-orb-target'),
              width: _orbSize,
              height: _orbSize,
              child: Icon(Icons.auto_awesome,
                  color: AppColors.warmAmber, size: _dragging ? 24 : 22),
            ),
          ),
        ),
      ),
    );
  }
}

/// AI 助手聊天面板：底部滑出的毛玻璃卡片。
/// 每次提问独立（不带历史），面板打开期间保留问答记录。
class AiChatPanel extends StatefulWidget {
  final AiConfig config;
  final AiService? service;

  const AiChatPanel({super.key, required this.config, this.service});

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  late final AiService _service = widget.service ?? AiService.instance;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<_ChatEntry> _entries = [];
  bool _loading = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String question) async {
    final text = question.trim();
    if (text.isEmpty || _loading) return;
    _input.clear();
    setState(() {
      _entries.add(_ChatEntry(role: 'user', text: text));
      _loading = true;
    });
    _scrollToBottom();

    String? answer;
    String? error;
    try {
      final context = await _service
          .buildTodayContext(widget.config)
          .timeout(const Duration(seconds: 20));
      answer = await _service.chat(
        config: widget.config,
        system: AiService.systemPrompt,
        user: '$context\n\n\n用户问题：$text',
      );
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _entries.add(_ChatEntry(role: 'ai', text: answer ?? '', error: error));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, media.viewInsets.bottom + 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: media.size.height * .78,
          ),
          child: GlassPanel(
            level: GlassSurfaceLevel.solid,
            radius: 22,
            opacity: .82,
            shadow: true,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _header(context),
                  const SizedBox(height: 10),
                  Flexible(child: _messages()),
                  const SizedBox(height: 10),
                  _quickChips(),
                  const SizedBox(height: 8),
                  _inputRow(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(children: [
      const Icon(Icons.auto_awesome, color: AppColors.warmAmber, size: 20),
      const SizedBox(width: 10),
      Text('AI 助手',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(widget.config.model,
            style: Theme.of(context).textTheme.labelSmall),
      ),
      const Spacer(),
      IconButton(
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close, size: 20),
        tooltip: '关闭',
      ),
    ]);
  }

  Widget _messages() {
    if (_entries.isEmpty && !_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Column(children: [
          Icon(Icons.auto_awesome,
              size: 30,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: .6)),
          const SizedBox(height: 10),
          Text('问我今天的安排、饮食或训练',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      );
    }
    return ListView.builder(
      controller: _scroll,
      shrinkWrap: true,
      itemCount: _entries.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _entries.length) return _loadingBubble();
        final entry = _entries[index];
        return entry.role == 'user'
            ? _userBubble(entry.text)
            : _aiBubble(entry);
      },
    );
  }

  Widget _userBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 60, bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.actionFill.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.actionInk)),
      ),
    );
  }

  Widget _aiBubble(_ChatEntry entry) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 40, bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .7)),
        ),
        child: entry.error != null
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.error!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.amber)),
                OutlinedButton(
                  onPressed: () =>
                      _send(_entries.lastWhere((e) => e.role == 'user').text),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(
                        color: AppColors.amber.withValues(alpha: .8)),
                  ),
                  child: const Text('重试'),
                ),
              ])
            : SelectableText(entry.text,
                style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }

  Widget _loadingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 40, bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SizedBox(
          width: 46,
          height: 16,
          child: LinearProgressIndicator(
              borderRadius: BorderRadius.all(Radius.circular(8))),
        ),
      ),
    );
  }

  Widget _quickChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        for (final prompt in AiService.quickPrompts.keys)
          ActionChip(
            label: Text(prompt, style: Theme.of(context).textTheme.labelSmall),
            onPressed: _loading ? null : () => _send(prompt),
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }

  Widget _inputRow(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _input,
          minLines: 1,
          maxLines: 3,
          textInputAction: TextInputAction.send,
          onSubmitted: _send,
          decoration: InputDecoration(
            hintText: '问问今天的安排…',
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      IconButton.filled(
        onPressed: _loading ? null : () => _send(_input.text),
        icon: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.send_rounded, size: 18),
        tooltip: '发送',
      ),
    ]);
  }
}

class _ChatEntry {
  final String role; // 'user' | 'ai'
  final String text;
  final String? error;
  const _ChatEntry({required this.role, required this.text, this.error});
}
