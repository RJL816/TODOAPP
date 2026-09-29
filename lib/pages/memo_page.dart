import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/memo_service.dart';
import '../models/memo.dart';
import '../ui/app_theme.dart';
import '../ui/glass_panel.dart';
import '../ui/live_markdown_editor.dart';

/// 备忘录页面
class MemoPage extends StatefulWidget {
  const MemoPage({super.key});

  @override
  State<MemoPage> createState() => _MemoPageState();
}

class _MemoPageState extends State<MemoPage> {
  final MemoService _memoService = MemoService.instance;
  List<Memo> _memos = [];
  List<Tag> _allTags = [];
  List<Memo> _filteredMemos = [];
  Tag? _selectedTag;
  bool _isLoading = true;
  bool _isTrashMode = false;
  bool _isSourceMode = false; // 整篇源码模式；默认逐段实时预览

  // 搜索控制器
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

  // 当前选中的备忘录
  Memo? _selectedMemo;

  // 窄屏（手机）单栏模式：true 时显示编辑器，false 显示列表
  bool _showEditorPane = false;

  // 宽屏分栏：侧栏宽度可拖拽调整并记忆；可整体收起让编辑器占满全宽
  static const String _kSidebarWidthKey = 'memo_sidebar_width';
  static const String _kSidebarCollapsedKey = 'memo_sidebar_collapsed';
  double _sidebarWidth = 320;
  bool _sidebarCollapsed = false;

  // 编辑控制器
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _contentFocus = FocusNode();
  bool _editorFocused = false;

  // 保存状态反馈与防抖
  Timer? _saveDebounce;
  String? _saveStatus;

  // 搜索防抖
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
    _loadSidebarPrefs();
    _contentFocus.addListener(() {
      if (mounted) setState(() => _editorFocused = _contentFocus.hasFocus);
    });
    // 回收站超过 30 天的清理，每次会话执行一次
    MemoService.instance.cleanupTrashOnce();
  }

  Future<void> _loadSidebarPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final w = prefs.getDouble(_kSidebarWidthKey);
      final collapsed = prefs.getBool(_kSidebarCollapsedKey) ?? false;
      if (mounted) {
        setState(() {
          if (w != null && w >= 260 && w <= 480) _sidebarWidth = w;
          _sidebarCollapsed = collapsed;
        });
      }
    } catch (_) {
      // 读取失败使用默认值
    }
  }

  Future<void> _saveSidebarWidth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kSidebarWidthKey, _sidebarWidth);
      await prefs.setBool(_kSidebarCollapsedKey, _sidebarCollapsed);
    } catch (_) {
      // 保存失败不影响使用
    }
  }

  @override
  void dispose() {
    if (_saveDebounce?.isActive == true && _selectedMemo != null) {
      final memo = _selectedMemo!;
      memo.title = _titleController.text.trim().isEmpty
          ? '无标题'
          : _titleController.text.trim();
      memo.content = _contentController.text;
      unawaited(_memoService.updateMemo(memo));
    }
    _saveDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final memos = _isTrashMode
        ? await _memoService.getDeletedMemos()
        : await _memoService.getAllMemos();

    final tags = await _memoService.getAllTags();

    if (!mounted) return;
    setState(() {
      _memos = memos;
      _allTags = tags;
      _filteredMemos = memos;
      _isLoading = false;
    });

    await _filterMemos();
    if (mounted &&
        !_isTrashMode &&
        _selectedMemo == null &&
        memos.isNotEmpty &&
        MediaQuery.sizeOf(context).width >= 780) {
      _selectMemo(memos.first);
    }
  }

  void _onSearchChanged() {
    // 立即刷新输入框装饰（清空按钮），防抖后再执行过滤
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchKeyword = _searchController.text;
      _filterMemos();
    });
  }

  Future<void> _filterMemos() async {
    List<Memo> result;

    if (_isTrashMode) {
      result = _memos;
    } else if (_searchKeyword.isNotEmpty) {
      result = await _memoService.searchMemos(_searchKeyword);
    } else if (_selectedTag != null) {
      result = await _memoService.getMemosByTag(_selectedTag!.id);
    } else {
      result = await _memoService.getAllMemos();
    }

    setState(() => _filteredMemos = result);
  }

  Future<void> _createNewMemo() async {
    await _flushPendingSave();
    final newMemo = Memo.create(
      title: '',
      content: '',
    );

    final id = await _memoService.addMemo(newMemo);
    newMemo.id = id;

    setState(() {
      _selectedMemo = newMemo;
      _titleController.text = newMemo.title;
      _contentController.text = newMemo.content;
      _isSourceMode = false;
      _showEditorPane = true; // 窄屏单栏模式直接进入编辑页
      _saveStatus = null;
    });

    await _loadData();
  }

  Future<void> _saveMemo() async {
    if (_selectedMemo == null) return;

    _selectedMemo!.title = _titleController.text.trim().isEmpty
        ? '无标题'
        : _titleController.text.trim();
    _selectedMemo!.content = _contentController.text;

    await _memoService.updateMemo(_selectedMemo!);
    await _loadData();
  }

  Future<void> _flushPendingSave() async {
    _saveDebounce?.cancel();
    final memo = _selectedMemo;
    if (memo == null) return;
    final title = _titleController.text.trim().isEmpty
        ? '无标题'
        : _titleController.text.trim();
    if (memo.title == title && memo.content == _contentController.text) return;
    await _saveMemo();
  }

  Future<void> _deleteMemo(int id) async {
    if (_selectedMemo?.id == id) _saveDebounce?.cancel();
    if (_isTrashMode) {
      // 永久删除
      await _memoService.permanentDeleteMemo(id);
    } else {
      // 软删除
      await _memoService.deleteMemo(id);
    }

    if (_selectedMemo?.id == id) {
      setState(() {
        _selectedMemo = null;
        _titleController.clear();
        _contentController.clear();
        _isSourceMode = false;
        _showEditorPane = false; // 删除的是正在编辑的备忘录，回到列表
      });
    }

    await _loadData();
  }

  Future<void> _restoreMemo(int id) async {
    await _memoService.restoreMemo(id);
    await _loadData();
  }

  Future<void> _togglePin(int id) async {
    await _memoService.togglePin(id);
    await _loadData();
  }

  Future<void> _exportMemo(int id) async {
    try {
      final markdown = await _memoService.exportMemoToMarkdown(id);

      if (!mounted) return;

      // 显示导出成功对话框
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出成功'),
          content: SingleChildScrollView(
            child: SelectableText(markdown),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  Future<void> _toggleTrashMode() async {
    await _flushPendingSave();
    if (!mounted) return;
    setState(() {
      _isTrashMode = !_isTrashMode;
      _selectedTag = null;
      _selectedMemo = null;
      _titleController.clear();
      _contentController.clear();
      _isSourceMode = false;
      _showEditorPane = false; // 回收站始终从列表看起
    });
    _loadData();
  }

  Future<void> _emptyTrash() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空回收站'),
        content: const Text('确定要永久删除所有备忘录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final count = await _memoService.emptyTrash();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 $count 个备忘录')),
        );
      }
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 窄屏（手机）：单栏 master-detail，列表页与编辑页切换；
    // 宽屏（桌面/横屏）：左右分栏，分隔条可拖拽调整宽度。
    return LayoutBuilder(builder: (context, bounds) {
      final availableWidth = bounds.maxWidth;
      final isWide = availableWidth >= 780;
      final maxSidebarWidth = (availableWidth - 420).clamp(260.0, 480.0);

      if (!isWide) {
        final showEditor = _selectedMemo != null && _showEditorPane;
        return showEditor
            ? _buildEditor(theme, isNarrow: true)
            : _buildSidebar(theme, isNarrow: true);
      }

      // 满宽工作区：左侧贴导航、右侧直达窗口边界，只留上下少量呼吸空间
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 12),
        child: GlassPanel(
          key: const Key('memo-workspace'),
          level: GlassSurfaceLevel.solid,
          radius: 0,
          opacity: .78,
          blur: 22,
          shadow: false,
          child: Row(
            children: [
              // 左侧列表（宽度可拖拽调整，可整体收起）
              if (!_sidebarCollapsed) ...[
                SizedBox(
                  width: _sidebarWidth.clamp(260.0, maxSidebarWidth),
                  child: _buildSidebar(theme, isNarrow: false),
                ),
                _buildDragHandle(theme, maxSidebarWidth),
              ],

              // 右侧编辑器/预览
              Expanded(
                child: _selectedMemo == null
                    ? _buildEmptyState(theme)
                    : _buildEditor(theme, isNarrow: false),
              ),
            ],
          ),
        ),
      );
    });
  }

  /// 宽屏分栏拖拽条：调整列表宽度并记忆
  Widget _buildDragHandle(ThemeData theme, double maxSidebarWidth) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _sidebarWidth =
              (_sidebarWidth + details.delta.dx).clamp(260.0, maxSidebarWidth);
        });
      },
      onHorizontalDragEnd: (_) => _saveSidebarWidth(),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: 9,
          color: Colors.transparent,
          child: Center(
              child: Container(
            width: 1,
            color: theme.colorScheme.onSurface.withValues(alpha: .12),
          )),
        ),
      ),
    );
  }

  Widget _buildSidebar(ThemeData theme, {required bool isNarrow}) {
    final content = Column(
      children: [
        // 顶部工具栏
        _buildSidebarHeader(theme),

        // 搜索框
        if (!_isTrashMode)
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索备忘录...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: '清空搜索',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchKeyword = '');
                          _filterMemos();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

        // 标签筛选
        if (!_isTrashMode) _buildTagFilter(theme),

        // 备忘录列表
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredMemos.isEmpty
                  ? _buildEmptyListState(theme)
                  : ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _filteredMemos.length,
                      itemBuilder: (context, index) {
                        final memo = _filteredMemos[index];
                        final isSelected = _selectedMemo?.id == memo.id;

                        return _MemoListItem(
                          memo: memo,
                          isSelected: isSelected,
                          isTrashMode: _isTrashMode,
                          onTap: () => _selectMemo(memo),
                          onDelete: () => _deleteMemo(memo.id),
                          onRestore: () => _restoreMemo(memo.id),
                          onTogglePin: () => _togglePin(memo.id),
                          onExport: () => _exportMemo(memo.id),
                        );
                      },
                    ),
        ),

        // 底部新建按钮（非回收站模式）
        if (!_isTrashMode)
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _createNewMemo,
                icon: const Icon(Icons.add),
                label: const Text('新建备忘录'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.brightness == Brightness.dark
                      ? AppColors.actionFill
                      : null,
                  foregroundColor: theme.brightness == Brightness.dark
                      ? AppColors.actionInk
                      : null,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    if (isNarrow) {
      return GlassPanel(
          level: GlassSurfaceLevel.solid,
          radius: 0,
          opacity: .78,
          child: content);
    }
    return ColoredBox(
      color: theme.colorScheme.onSurface.withValues(alpha: .035),
      child: content,
    );
  }

  Widget _buildSidebarHeader(ThemeData theme) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.note_rounded,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isTrashMode ? '回收站' : '备忘录',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // 回收站切换
          IconButton(
            icon: Icon(_isTrashMode ? Icons.note : Icons.delete_outline),
            onPressed: _toggleTrashMode,
            tooltip: _isTrashMode ? '返回备忘录' : '回收站',
            color: _isTrashMode ? theme.colorScheme.error : null,
          ),
          // 清空回收站
          if (_isTrashMode)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _emptyTrash,
              tooltip: '清空回收站',
              color: theme.colorScheme.error,
            ),
        ],
      ),
    );
  }

  Widget _buildTagFilter(ThemeData theme) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // 全部标签
          _TagFilterChip(
            label: '全部',
            isSelected: _selectedTag == null,
            color: null,
            onTap: () {
              setState(() => _selectedTag = null);
              _filterMemos();
            },
          ),
          // 各个标签
          ..._allTags.map((tag) {
            return _TagFilterChip(
              label: tag.name,
              isSelected: _selectedTag?.id == tag.id,
              color: Color(tag.colorArgb),
              onTap: () {
                setState(() => _selectedTag = tag);
                _filterMemos();
              },
            );
          }),
        ],
      ),
    );
  }

  Widget _buildEmptyListState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isTrashMode ? Icons.delete_outline : Icons.note_outlined,
            size: 64,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            _isTrashMode ? '回收站为空' : '还没有备忘录',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!_isTrashMode) ...[
            const SizedBox(height: 8),
            Text(
              '点击下方按钮创建新备忘录',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.edit_note_outlined,
            size: 64,
            color: theme.colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            '选择或创建一个备忘录',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '支持 Markdown 格式',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_sidebarCollapsed) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.view_sidebar, size: 18),
              label: const Text('显示列表'),
              onPressed: () {
                setState(() => _sidebarCollapsed = false);
                _saveSidebarWidth();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditor(ThemeData theme, {required bool isNarrow}) {
    final content = Column(
      children: [
        // 编辑器工具栏
        _buildEditorToolbar(theme, isNarrow: isNarrow),

        Expanded(
          child: LayoutBuilder(builder: (context, bounds) {
            final inset = bounds.maxWidth < 520 ? 20.0 : 40.0;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Padding(
                  padding:
                      EdgeInsets.fromLTRB(inset, isNarrow ? 12 : 24, inset, 16),
                  child: Column(children: [
                    // 标题输入
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: TextField(
                        controller: _titleController,
                        style: AppType.display(
                            size: 30,
                            weight: FontWeight.w600,
                            color: theme.colorScheme.onSurface),
                        decoration: const InputDecoration(
                          hintText: '备忘录名称',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (_) => _autoSave(),
                      ),
                    ),

                    Divider(
                        height: 1,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: .10)),

                    // 默认逐段预览；整篇源码模式保留给复杂 Markdown 编辑。
                    Expanded(
                      child: _isSourceMode
                          ? _buildEditArea(theme)
                          : LiveMarkdownEditor(
                              key: ValueKey(_selectedMemo?.id),
                              controller: _contentController,
                              onChanged: _autoSave,
                              styleSheet: _markdownStyleSheet(theme),
                            ),
                    ),
                  ]),
                ),
              ),
            );
          }),
        ),
      ],
    );
    if (isNarrow) {
      return GlassPanel(
          level: theme.colorScheme.brightness == Brightness.dark
              ? GlassSurfaceLevel.dark
              : GlassSurfaceLevel.solid,
          radius: 0,
          opacity: theme.colorScheme.brightness == Brightness.dark ? .43 : .76,
          child: content);
    }
    return content;
  }

  Widget _buildEditArea(ThemeData theme) {
    final dark = theme.colorScheme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: dark
              ? const Color(0xFF2A4351)
                  .withValues(alpha: _editorFocused ? .48 : .32)
              : Colors.white.withValues(alpha: _editorFocused ? .72 : .48),
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: _editorFocused ? .56 : .28)
                : AppColors.line.withValues(alpha: _editorFocused ? .9 : .55),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _contentController,
            focusNode: _contentFocus,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            cursorColor: dark ? AppColors.actionFill : AppColors.navy,
            style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.8, color: dark ? Colors.white : AppColors.ink),
            decoration: InputDecoration(
              hintText: '在这里开始写...',
              hintStyle: TextStyle(
                  color: dark
                      ? Colors.white.withValues(alpha: .70)
                      : AppColors.muted),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => _autoSave(),
          ),
        ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyleSheet(ThemeData theme) {
    return MarkdownStyleSheet(
      p: theme.textTheme.bodyLarge,
      h1: theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      h4: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      h5: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      h6: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      strong: theme.textTheme.bodyLarge?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      em: theme.textTheme.bodyLarge?.copyWith(
        fontStyle: FontStyle.italic,
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        backgroundColor:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      codeblockDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquote: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.primary,
            width: 4,
          ),
        ),
      ),
      listBullet: theme.textTheme.bodyLarge,
      tableHead: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.bold,
      ),
      tableBody: theme.textTheme.bodySmall,
      tableBorder: TableBorder.all(
        color: theme.colorScheme.outlineVariant,
        width: 1,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildEditorToolbar(ThemeData theme, {required bool isNarrow}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          if (isNarrow) ...[
            // 窄屏单栏模式：返回列表
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: '返回列表',
              onPressed: () => setState(() => _showEditorPane = false),
            ),
            const SizedBox(width: 4),
          ] else ...[
            // 宽屏：收起/展开侧栏，收起后编辑器占满全宽
            IconButton(
              icon: Icon(_sidebarCollapsed
                  ? Icons.view_sidebar
                  : Icons.view_sidebar_outlined),
              tooltip: _sidebarCollapsed ? '显示列表' : '收起列表',
              onPressed: () {
                setState(() => _sidebarCollapsed = !_sidebarCollapsed);
                _saveSidebarWidth();
              },
            ),
          ],
          Expanded(
              child: Text(
            _saveStatus ?? _selectedMemo?.formattedUpdatedAt ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _saveStatus == null
                  ? theme.colorScheme.onSurfaceVariant
                  : (_saveStatus!.startsWith('已保存')
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant),
            ),
          )),
          // 实时预览是默认阅读状态，复杂内容仍可整篇编辑源码。
          if (isNarrow)
            IconButton(
              onPressed: () => setState(() => _isSourceMode = !_isSourceMode),
              icon: Icon(_isSourceMode ? Icons.visibility : Icons.code),
              tooltip: _isSourceMode ? '实时预览' : '源码',
            )
          else
            TextButton.icon(
              onPressed: () => setState(() => _isSourceMode = !_isSourceMode),
              icon: Icon(_isSourceMode ? Icons.visibility : Icons.code),
              label: Text(_isSourceMode ? '实时预览' : '源码'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
          const SizedBox(width: 8),
          // 置顶按钮
          IconButton(
            icon: Icon(
              _selectedMemo?.isPinned == true
                  ? Icons.push_pin
                  : Icons.push_pin_outlined,
              color: _selectedMemo?.isPinned == true
                  ? theme.colorScheme.primary
                  : null,
            ),
            onPressed: _selectedMemo != null
                ? () => _togglePin(_selectedMemo!.id)
                : null,
            tooltip: '置顶',
          ),
          // 导出按钮
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _selectedMemo != null
                ? () => _exportMemo(_selectedMemo!.id)
                : null,
            tooltip: '导出',
          ),
          // 删除按钮
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.error,
            ),
            onPressed: _selectedMemo != null
                ? () => _deleteMemo(_selectedMemo!.id)
                : null,
            tooltip: '删除',
          ),
        ],
      ),
    );
  }

  Future<void> _selectMemo(Memo memo) async {
    if (_selectedMemo?.id != memo.id) await _flushPendingSave();
    if (!mounted) return;
    _saveDebounce?.cancel();
    setState(() {
      _selectedMemo = memo;
      _titleController.text = memo.title;
      _contentController.text = memo.content;
      _isSourceMode = false; // 打开已有备忘录时直接显示排版效果
      _showEditorPane = true; // 窄屏单栏模式切换到编辑页
      _saveStatus = null;
    });
  }

  // 自动保存（防抖 + 状态反馈）
  void _autoSave() {
    setState(() => _saveStatus = '未保存');
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted || _selectedMemo == null) return;
      setState(() => _saveStatus = '保存中…');
      await _saveMemo();
      if (mounted) {
        setState(() => _saveStatus = '已保存 ${_nowClock()}');
      }
    });
  }

  String _nowClock() {
    final t = DateTime.now();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${p2(t.hour)}:${p2(t.minute)}';
  }
}

/// 备忘录列表项
class _MemoListItem extends StatefulWidget {
  final Memo memo;
  final bool isSelected;
  final bool isTrashMode;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onRestore;
  final VoidCallback onTogglePin;
  final VoidCallback onExport;

  const _MemoListItem({
    required this.memo,
    required this.isSelected,
    required this.isTrashMode,
    required this.onTap,
    required this.onDelete,
    required this.onRestore,
    required this.onTogglePin,
    required this.onExport,
  });

  @override
  State<_MemoListItem> createState() => _MemoListItemState();
}

class _MemoListItemState extends State<_MemoListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 3),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? Colors.white.withValues(
                    alpha: theme.brightness == Brightness.dark ? .17 : .57)
                : _hovered
                    ? Colors.white.withValues(
                        alpha: theme.brightness == Brightness.dark ? .08 : .25)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  if (widget.memo.isPinned && !widget.isTrashMode) ...[
                    Icon(
                      Icons.push_pin,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      widget.memo.title.trim().isEmpty ||
                              widget.memo.title == '新备忘录' ||
                              widget.memo.title == '无标题'
                          ? '未命名备忘录 · ${widget.memo.createdAt.month}月${widget.memo.createdAt.day}日'
                          : widget.memo.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 操作按钮
                  if (widget.isTrashMode) _buildActionButtons(theme),
                ],
              ),
              const SizedBox(height: 4),
              // 摘要
              Text(
                widget.memo.summary,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              // 时间
              Text(
                widget.memo.formattedUpdatedAt,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    if (widget.isTrashMode) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore_from_trash),
            onPressed: widget.onRestore,
            tooltip: '恢复',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: theme.colorScheme.primary,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: widget.onDelete,
            tooltip: '永久删除',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: theme.colorScheme.error,
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            widget.memo.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
          ),
          onPressed: widget.onTogglePin,
          tooltip: widget.memo.isPinned ? '取消置顶' : '置顶',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        IconButton(
          icon: const Icon(Icons.download),
          onPressed: widget.onExport,
          tooltip: '导出',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: widget.onDelete,
          tooltip: '删除',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}

/// 标签筛选按钮
class _TagFilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? color;
  final VoidCallback onTap;

  const _TagFilterChip({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (color ?? theme.colorScheme.primary)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (color ?? theme.colorScheme.primary)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isSelected
                ? (theme.brightness == Brightness.dark
                    ? theme.colorScheme.onPrimary
                    : Colors.white)
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
