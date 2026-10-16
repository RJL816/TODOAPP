import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ai_service.dart';
import '../services/food_estimation_service.dart';

class FoodEstimationPanel extends StatefulWidget {
  const FoodEstimationPanel(
      {super.key,
      required this.foodController,
      required this.onEstimate,
      required this.onBusy});
  final TextEditingController foodController;
  final ValueChanged<FoodEstimate> onEstimate;
  final ValueChanged<bool> onBusy;
  @override
  State<FoodEstimationPanel> createState() => _FoodEstimationPanelState();
}

class _FoodEstimationPanelState extends State<FoodEstimationPanel> {
  bool _busy = false;
  int _revision = 0;
  String? _message;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    widget.foodController.addListener(_changed);
    if (Platform.isAndroid) unawaited(_recover());
  }

  void _changed() => _revision++;
  @override
  void dispose() {
    widget.foodController.removeListener(_changed);
    super.dispose();
  }

  Future<void> _recover() async {
    try {
      final lost = await _picker.retrieveLostData();
      if (mounted && lost.files?.isNotEmpty == true && !_busy) {
        await _run(() => _photo(lost.files!.first));
      }
    } catch (_) {
      if (mounted) setState(() => _message = '未恢复到照片，可重新拍摄或选择图片');
    }
  }

  Future<void> _run(Future<FoodEstimate?> Function() action) async {
    if (_busy) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _message = null;
    });
    widget.onBusy(true);
    try {
      final result = await action();
      if (!mounted || result == null) return;
      if (_revision != revision) {
        setState(() => _message = '食物描述已修改，未覆盖现有记录，请重新估算');
        return;
      }
      widget.onEstimate(result);
      if (mounted) setState(() => _message = result.explanation);
    } catch (e) {
      if (mounted)
        setState(() => _message = e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusy(false);
      }
    }
  }

  Future<FoodEstimate?> _photo(XFile file) async {
    if (await file.length() > 5 * 1024 * 1024)
      throw Exception('图片需小于 5 MB，请换一张图片');
    final bytes = await file.readAsBytes();
    final mime = _mime(bytes);
    if (mime == null) throw Exception('请选择 JPEG、PNG 或 WebP 图片');
    final config = await AiService.instance.loadConfig();
    if (!mounted) return null;
    if (!config.enabled || config.apiKey.trim().isEmpty)
      throw Exception('请先在主设置启用 AI 并填写支持图片的模型');
    final host = AiService.chatEndpoint(config.baseUrl).host;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('发送照片进行估算'),
              scrollable: true,
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.memory(bytes,
                    height: 160,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text('图片无法预览')),
                const SizedBox(height: 12),
                Text('此照片及食物描述将发送到你配置的 AI 服务：$host。'
                    '模型：${config.visionModel.trim().isEmpty ? config.model : config.visionModel}。'
                    '请确认照片中没有不希望发送的内容。估算后仍需核对份量与热量。'),
              ]),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('发送并估算'))
              ],
            ));
    if (confirmed != true || !mounted) return null;
    return FoodEstimationService().byPhoto(bytes, mime, config,
        description: widget.foodController.text.trim());
  }

  static String? _mime(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255) return 'image/jpeg';
    if (bytes.length >= 8 &&
        bytes.take(8).join(',') == '137,80,78,71,13,10,26,10')
      return 'image/png';
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP')
      return 'image/webp';
    return null;
  }

  Future<FoodEstimate?> _pick(ImageSource source) async {
    final file = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
        requestFullMetadata: false);
    if (file == null || !mounted) return null;
    return _photo(file);
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, children: [
          TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async => FoodEstimationService().byName(
                      widget.foodController.text.trim(),
                      await AiService.instance.loadConfig())),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('按名称估算')),
          if (Platform.isAndroid || Platform.isIOS)
            TextButton.icon(
                onPressed:
                    _busy ? null : () => _run(() => _pick(ImageSource.camera)),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('拍照估算')),
          TextButton.icon(
              onPressed:
                  _busy ? null : () => _run(() => _pick(ImageSource.gallery)),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: const Text('选图估算')),
        ]),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Text(_message!, style: Theme.of(context).textTheme.bodySmall),
        Text('名称中写明份量更准确，例如“米饭 150g”；照片估算需要支持图片输入的 AI 模型。',
            style: Theme.of(context).textTheme.bodySmall),
      ]);
}
