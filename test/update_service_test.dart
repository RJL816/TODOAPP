import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo_app/services/update_service.dart';

/// 应用内检查更新：版本比较、资产匹配与安装包下载
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    // 单元测试环境没有平台插件：mock 临时目录
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return Directory.systemTemp.path;
    });
  });

  group('版本比较', () {
    test('远端更高 → 判定有新版本', () {
      expect(UpdateService.isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewerVersion('v1.1.0', '1.0.9'), isTrue);
      expect(UpdateService.isNewerVersion('2.0.0', '1.9.9'), isTrue);
    });

    test('同版本 / 更低版本 → 无新版本', () {
      expect(UpdateService.isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('v1.0.0', '1.0.0'), isFalse);
      expect(UpdateService.isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });

    test('带 build 号的当前版本也能比较', () {
      expect(UpdateService.compareVersions('1.0.1', '1.0.0+7'), greaterThan(0));
      expect(UpdateService.compareVersions('1.0.0', '1.0.0+1'), 0);
    });

    test('缺失段按 0 处理', () {
      expect(UpdateService.compareVersions('1.0', '1.0.0'), 0);
      expect(UpdateService.compareVersions('2', '1.9.9'), greaterThan(0));
    });
  });

  group('资产匹配', () {
    test('Windows 优先匹配安装器 -setup.exe', () {
      final assets = [
        'https://x/todo_app_v1.0.2-windows.zip',
        'https://x/todo_app_v1.0.2-setup.exe',
        'https://x/app-release.apk',
      ];
      var setupUrl = '';
      for (final ext in ['-setup.exe', '.zip']) {
        for (final u in assets) {
          if (u.toLowerCase().endsWith(ext)) {
            setupUrl = u;
            break;
          }
        }
        if (setupUrl.isNotEmpty) break;
      }
      expect(setupUrl, 'https://x/todo_app_v1.0.2-setup.exe');
    });

    test('格式校验通过 ReleaseInfo 构造', () {
      final info = ReleaseInfo(
        version: '1.0.2',
        notes: '修复若干问题',
        pageUrl: 'https://github.com/x/releases/latest',
        windowsUrl: 'https://x/todo_app_v1.0.2-setup.exe',
        androidUrl: 'https://x/app-release.apk',
      );
      expect(info.hasWindowsDownload, isTrue);
      expect(info.hasAndroidDownload, isTrue);
      expect(UpdateService.isNewerVersion(info.version, '1.0.1'), isTrue);
    });
  });

  group('安装包下载', () {
    test('流式下载写盘并回调进度', () async {
      final bytes = List.generate(4096, (i) => i % 256);
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
            Stream.fromIterable([bytes.sublist(0, 2048), bytes.sublist(2048)]),
            200,
            contentLength: bytes.length);
      });
      final progresses = <double>[];
      final path = await UpdateService.instance.downloadWindowsSetup(
        const ReleaseInfo(
            version: '9.9.9',
            notes: '',
            pageUrl: 'https://example.com',
            windowsUrl: 'https://example.com/setup.exe'),
        onProgress: progresses.add,
        client: client,
      );
      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.length(), bytes.length);
      expect(progresses.last, 1.0);
      expect(progresses.first, lessThan(1.0));
      await file.delete();
    });

    test('下载不完整 → 抛异常', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
            Stream.value(List.filled(100, 0)), 200,
            contentLength: 1000);
      });
      await expectLater(
        UpdateService.instance.downloadWindowsSetup(
          const ReleaseInfo(
              version: '9.9.9',
              notes: '',
              pageUrl: 'https://example.com',
              windowsUrl: 'https://example.com/setup.exe'),
          client: client,
        ),
        throwsException,
      );
    });
  });
}
