import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/memo_service.dart';
import '../models/memo.dart';

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
  bool _isPreviewMode = false; // 预览模式

  // 搜索控制器
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';

  // 当前选中的备忘录
  Memo? _selectedMemo;

  // 编辑控制器
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initService();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  void _initService() {
    final isar = MemoService.instance.isar;
    _memoService.init(isar);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final memos = _isTrashMode
        ? await _memoService.getDeletedMemos()
        : await _memoService.getAllMemos();

    final tags = await _memoService.getAllTags();

    setState(() {
      _memos = memos;
      _allTags = tags;
      _filteredMemos = memos;
      _isLoading = false;
    });

    await _filterMemos();
  }

  void _onSearchChanged() {
    setState(() => _searchKeyword = _searchController.text);
    _filterMemos();
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
    final newMemo = Memo.create(
      title: '新备忘录',
      content: '',
    );

    final id = await _memoService.addMemo(newMemo);
    newMemo.id = id;

    setState(() {
      _selectedMemo = newMemo;
      _titleController.text = newMemo.title;
      _contentController.text = newMemo.content;
      _isPreviewMode = false; // 新建备忘录默认编辑模式
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

  Future<void> _deleteMemo(int id) async {
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
        _isPreviewMode = false;
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

  void _toggleTrashMode() {
    setState(() {
      _isTrashMode = !_isTrashMode;
      _selectedTag = null;
      _selectedMemo = null;
      _titleController.clear();
      _contentController.clear();
      _isPreviewMode = false;
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

    return Container(
      color: theme.colorScheme.surface.withOpacity(0.5),
      child: Row(
        children: [
          // 左侧列表（更窄，占约25%）
          _buildSidebar(theme),

          // 右侧编辑器/预览（占约75%）
          Expanded(
            child: _selectedMemo == null
                ? _buildEmptyState(theme)
                : _buildEditor(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(ThemeData theme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isNarrowScreen = screenWidth < 800;
    // 侧边栏更窄：窄屏 220px，宽屏 280px
    final sidebarWidth = isNarrowScreen ? 220.0 : 280.0;

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      child: Column(
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
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
        ],
      ),
    );
  }

  Widget _buildEditor(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          // 编辑器工具栏
          _buildEditorToolbar(theme),

          // 标题输入
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _titleController,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                hintText: '标题',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => _autoSave(),
            ),
          ),

          const Divider(height: 1),

          // 内容区域（编辑或预览）
          Expanded(
            child: _isPreviewMode ? _buildPreview(theme) : _buildEditArea(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildEditArea(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _contentController,
        maxLines: null,
        expands: true,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontFamily: 'monospace', // 使用等宽字体便于编辑 Markdown
        ),
        decoration: const InputDecoration(
          hintText: '开始输入...',
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => _autoSave(),
      ),
    );
  }

  Widget _buildPreview(ThemeData theme) {
    if (_contentController.text.trim().isEmpty) {
      return Center(
        child: Text(
          '预览模式\n内容为空',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: MarkdownBody(
        data: _contentController.text,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
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
            backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
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
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
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
        ),
      ),
    );
  }

  Widget _buildEditorToolbar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            _selectedMemo?.formattedUpdatedAt ?? '',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          // 编辑/预览切换
          TextButton.icon(
            onPressed: () {
              setState(() => _isPreviewMode = !_isPreviewMode);
            },
            icon: Icon(_isPreviewMode ? Icons.edit : Icons.visibility),
            label: Text(_isPreviewMode ? '编辑' : '预览'),
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

  void _selectMemo(Memo memo) {
    setState(() {
      _selectedMemo = memo;
      _titleController.text = memo.title;
      _contentController.text = memo.content;
      _isPreviewMode = false; // 选择备忘录时默认编辑模式
    });
  }

  // 自动保存（防抖）
  DateTime? _lastSaveTime;
  void _autoSave() {
    final now = DateTime.now();
    if (_lastSaveTime != null &&
        now.difference(_lastSaveTime!).inSeconds < 2) {
      return;
    }
    _lastSaveTime = now;
    _saveMemo();
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
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isSelected
                ? theme.colorScheme.primary.withOpacity(0.5)
                : Colors.transparent,
          ),
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
                    widget.memo.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 操作按钮
                _buildActionButtons(theme),
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
                : theme.colorScheme.outlineVariant.withOpacity(0.5),
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isSelected
                ? Colors.white
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
