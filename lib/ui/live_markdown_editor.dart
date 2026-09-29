import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// A source-preserving Markdown editor. Only the selected block shows syntax;
/// all other blocks stay rendered. The full document controller remains the
/// single source of truth, so existing save and export flows need no changes.
class LiveMarkdownEditor extends StatefulWidget {
  const LiveMarkdownEditor({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.styleSheet,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final MarkdownStyleSheet styleSheet;

  @override
  State<LiveMarkdownEditor> createState() => _LiveMarkdownEditorState();
}

class _LiveMarkdownEditorState extends State<LiveMarkdownEditor> {
  final TextEditingController _blockController = TextEditingController();
  final FocusNode _blockFocus = FocusNode();
  List<_MarkdownBlock>? _editingBlocks;
  String? _editingSource;
  int? _activeIndex;
  String _prefix = '';
  String _suffix = '';

  @override
  void initState() {
    super.initState();
    _blockFocus.addListener(_onFocusChanged);
    if (widget.controller.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _activeIndex == null) _activate(0);
      });
    }
  }

  @override
  void didUpdateWidget(covariant LiveMarkdownEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) _finishEditing();
  }

  @override
  void dispose() {
    _blockFocus.removeListener(_onFocusChanged);
    _blockFocus.dispose();
    _blockController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_blockFocus.hasFocus && _activeIndex != null) _finishEditing();
  }

  void _finishEditing() {
    if (_activeIndex == null) return;
    setState(() {
      _activeIndex = null;
      _editingBlocks = null;
      _editingSource = null;
    });
  }

  void _activate(int index) {
    final blocks = _splitMarkdown(widget.controller.text);
    if (index >= blocks.length) return;
    final block = blocks[index];
    final source = widget.controller.text;
    _prefix = source.substring(0, block.start);
    _suffix = source.substring(block.end);
    _blockController.value = TextEditingValue(
      text: source.substring(block.start, block.end),
      selection: TextSelection.collapsed(offset: block.end - block.start),
    );
    setState(() {
      _editingBlocks = blocks;
      _editingSource = source;
      _activeIndex = index;
    });
    _blockFocus.requestFocus();
  }

  void _updateSource(String text) {
    widget.controller.text = '$_prefix$text$_suffix';
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.colorScheme.brightness == Brightness.dark;
    final blocks = _editingBlocks ?? _splitMarkdown(widget.controller.text);
    final previewSource = _editingSource ?? widget.controller.text;
    return ListView.builder(
      key: const Key('markdown-live-editor'),
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
      itemCount: blocks.length,
      itemBuilder: (context, index) {
        if (_activeIndex == index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: (dark ? Colors.black : Colors.white)
                    .withValues(alpha: dark ? .22 : .12),
                border: Border.all(
                  color: theme.colorScheme.onSurface.withValues(alpha: .34),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: TextField(
                  key: const Key('markdown-active-block'),
                  controller: _blockController,
                  focusNode: _blockFocus,
                  autofocus: true,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textAlignVertical: TextAlignVertical.top,
                  cursorColor: dark
                      ? const Color(0xFFF5F1E8)
                      : theme.colorScheme.primary,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    height: 1.65,
                  ),
                  decoration: InputDecoration(
                    hintText: '在这里开始写...',
                    hintStyle: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onTapOutside: (_) => _blockFocus.unfocus(),
                  onChanged: _updateSource,
                ),
              ),
            ),
          );
        }

        final block = blocks[index];
        if (block.start == block.end) {
          return GestureDetector(
            key: Key('markdown-preview-block-$index'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _activate(index),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '在这里开始写...',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        return GestureDetector(
          key: Key('markdown-preview-block-$index'),
          behavior: HitTestBehavior.opaque,
          onTap: () => _activate(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: AbsorbPointer(
              child: MarkdownBody(
                data: previewSource.substring(block.start, block.end),
                selectable: false,
                styleSheet: widget.styleSheet,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MarkdownBlock {
  const _MarkdownBlock(this.start, this.end);
  final int start;
  final int end;
}

class _SourceLine {
  const _SourceLine(this.start, this.end, this.content);
  final int start;
  final int end;
  final String content;
}

List<_MarkdownBlock> _splitMarkdown(String source) {
  final lines = <_SourceLine>[];
  var offset = 0;
  while (offset < source.length) {
    final newline = source.indexOf('\n', offset);
    final end = newline < 0 ? source.length : newline;
    final contentEnd = end > offset && source[end - 1] == '\r' ? end - 1 : end;
    lines.add(
        _SourceLine(offset, contentEnd, source.substring(offset, contentEnd)));
    offset = newline < 0 ? source.length : newline + 1;
  }
  if (lines.isEmpty || lines.every((line) => line.content.trim().isEmpty)) {
    return [_MarkdownBlock(0, source.length)];
  }

  final blocks = <_MarkdownBlock>[];
  var i = 0;
  while (i < lines.length) {
    if (lines[i].content.trim().isEmpty) {
      i++;
      continue;
    }
    final start = i;
    final first = lines[i].content;
    final fence = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(first);
    if (fence != null) {
      final marker = fence.group(1)!;
      i++;
      while (i < lines.length) {
        final close = lines[i].content.trimLeft();
        i++;
        if (close.startsWith(marker)) break;
      }
    } else {
      final kind = _lineKind(first);
      i++;
      while (kind != 'heading' &&
          kind != 'rule' &&
          i < lines.length &&
          lines[i].content.trim().isNotEmpty) {
        final next = _lineKind(lines[i].content);
        if (next == 'heading' || next == 'fence' || next == 'rule') break;
        if (kind == 'paragraph' && next != 'paragraph') break;
        if (kind == 'list' &&
            next != 'list' &&
            !lines[i].content.startsWith('  ')) {
          break;
        }
        if (kind == 'quote' && next != 'quote') break;
        i++;
      }
    }
    blocks.add(_MarkdownBlock(lines[start].start, lines[i - 1].end));
  }
  return blocks;
}

String _lineKind(String line) {
  if (RegExp(r'^\s{0,3}(`{3,}|~{3,})').hasMatch(line)) return 'fence';
  if (RegExp(r'^\s{0,3}#{1,6}\s').hasMatch(line)) return 'heading';
  if (RegExp(r'^\s{0,3}(?:---+|\*\*\*+|___+)\s*$').hasMatch(line)) {
    return 'rule';
  }
  if (RegExp(r'^\s{0,3}(?:[-*+]|\d+[.)])\s').hasMatch(line)) {
    return 'list';
  }
  if (RegExp(r'^\s{0,3}>').hasMatch(line)) return 'quote';
  return 'paragraph';
}
