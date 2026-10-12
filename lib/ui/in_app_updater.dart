import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';

/// Windows：下载安装器 → 覆盖安装 → 退出，安装器重新启动新版。
/// Android：打开 APK 下载入口，由系统处理下载与安装。
Future<void> runInAppUpdate(BuildContext context, ReleaseInfo release) async {
  if (Theme.of(context).platform != TargetPlatform.windows) {
    final address = Theme.of(context).platform == TargetPlatform.android
        ? release.androidUrl ?? release.pageUrl
        : release.pageUrl;
    try {
      final opened = await launchUrl(Uri.parse(address),
          mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('无法打开下载入口');
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开下载入口，请在关于与更新中重试。')));
      }
    }
    return;
  }
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _UpdateDialog(release: release),
  );
}

class _UpdateDialog extends StatefulWidget {
  final ReleaseInfo release;
  const _UpdateDialog({required this.release});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  String? _error;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final path = await UpdateService.instance.downloadWindowsSetup(
        widget.release,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _installing = true);
      // 留出一瞬间让用户看到"正在安装"提示
      await Future.delayed(const Duration(milliseconds: 1200));
      await Process.start(path, const [
        '/SILENT',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPPLICATIONS',
      ]);
      // 安装器已接管（会等待/关闭本进程并覆盖安装后自动重启新版）
      if (mounted) exit(0);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('软件更新'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_error != null) ...[
            const Icon(Icons.error_outline, size: 30, color: Color(0xFFA66A10)),
            const SizedBox(height: 12),
            const Text('自动更新失败，请检查网络后重试，或前往网页手动下载。'),
            const SizedBox(height: 10),
            Text(_error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
          ] else if (_installing) ...[
            const SizedBox(height: 8),
            const Row(children: [
              SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4)),
              SizedBox(width: 14),
              Expanded(child: Text('下载完成，正在安装更新…')),
            ]),
            const SizedBox(height: 10),
            const Text('应用将自动关闭，安装完成后会重新打开。'),
          ] else ...[
            const SizedBox(height: 8),
            Text('正在下载 v${widget.release.version} 更新包'),
            const SizedBox(height: 14),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text('${(_progress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall),
            ),
          ],
        ],
      ),
      actions: [
        if (_error != null) ...[
          TextButton(
            onPressed: () => launchUrl(Uri.parse(widget.release.pageUrl),
                mode: LaunchMode.externalApplication),
            child: const Text('打开下载页'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _error = null;
                _progress = 0;
              });
              _start();
            },
            child: const Text('重试'),
          ),
        ],
      ],
    );
  }
}
