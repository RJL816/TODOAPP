import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

/// 回复正文保留选择复制，并呈现标题、列表、表格、引用和代码。
class AiMarkdownMessage extends StatelessWidget {
  const AiMarkdownMessage({super.key, required this.text});
  final String text;

  Future<void> _openLink(BuildContext context, String? href) async {
    final uri = href == null ? null : Uri.tryParse(href);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) return;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        code: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        blockquoteDecoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
          border: Border(
              left: BorderSide(color: theme.colorScheme.primary, width: 3)),
        ),
      ),
      onTapLink: (_, href, __) => _openLink(context, href),
      // 不自动加载模型输出的任意远程图片；点击可在浏览器查看。
      imageBuilder: (uri, title, alt) => TextButton.icon(
        onPressed: () => _openLink(context, uri.toString()),
        icon: const Icon(Icons.image_outlined, size: 18),
        label: Text(alt?.isNotEmpty == true ? alt! : '查看图片'),
      ),
    );
  }
}
