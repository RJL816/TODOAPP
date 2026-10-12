import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/services/update_service.dart';
import 'package:todo_app/ui/in_app_updater.dart';

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  for (final hasApk in [true, false]) {
    testWidgets('Android update opens ${hasApk ? 'APK' : 'release page'}',
        (tester) async {
      String? opened;
      bool? embedded;
      var completed = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
          (call) async {
        if (call.method == 'launch') {
          opened = call.arguments['url'] as String;
          embedded = call.arguments['useWebView'] as bool;
        }
        return true;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final release = ReleaseInfo(
        version: '1.0.8', notes: '', pageUrl: 'https://example.com/releases/v1.0.8',
        windowsUrl: 'https://example.com/todo_app_v1.0.8-setup.exe',
        androidUrl: hasApk ? 'https://example.com/app-release.apk' : null,
      );
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(body: Builder(builder: (context) => TextButton(
          onPressed: () async {
            await runInAppUpdate(context, release);
            completed = true;
          },
          child: const Text('下载更新'),
        ))),
      ));
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(opened, hasApk ? release.androidUrl : release.pageUrl);
      expect(embedded, isFalse);
      expect(completed, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed Android launch leaves a visible retry message', (tester) async {
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => runInAppUpdate(context, const ReleaseInfo(
            version: '1.0.8', notes: '', pageUrl: 'https://example.com/releases')),
        child: const Text('下载更新'),
      ))),
    ));
    await tester.tap(find.text('下载更新'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('无法打开下载入口，请在关于与更新中重试。'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
