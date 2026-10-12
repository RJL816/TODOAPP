import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_app/services/ai_service.dart';
import 'package:todo_app/ui/ai_settings_section.dart';

Future<void> showSettings(WidgetTester tester, AiService service,
    {String address = AiConfig.defaultBaseUrl}) async {
  SharedPreferences.setMockInitialValues({
    'ai_assistant_config': jsonEncode(
        AiConfig(enabled: true, apiKey: 'old-key', baseUrl: address).toJson())
  });
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SingleChildScrollView(
              child: AiSettingsSection(
                  onConfigChanged: () {}, service: service)))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('closing immediately saves drafts and privacy toggles preserve them',
      (tester) async {
    final client = MockClient((_) async => http.Response('{}', 200));
    addTearDown(client.close);
    await showSettings(tester, AiService.forTest(client));
    await tester.enterText(find.byType(TextField).at(1), 'latest-key');
    await tester.enterText(find.byType(TextField).at(2), 'glm-5.3');
    final courses = find.widgetWithText(FilterChip, '课程');
    await tester.ensureVisible(courses);
    await tester.tap(courses);
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        'latest-key');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    final saved = await AiService.instance.loadConfig();
    expect(saved.apiKey, 'latest-key');
    expect(saved.model, 'glm-5.3');
    expect(saved.scopeCourses, isFalse);
  });

  testWidgets('test connection uses all edited fields without submitting',
      (tester) async {
    http.Request? sent;
    final pending = Completer<http.Response>();
    final client = MockClient((request) {
      sent = request;
      return pending.future;
    });
    addTearDown(client.close);
    await showSettings(tester, AiService.forTest(client));
    await tester.enterText(
        find.byType(TextField).at(0), 'https://api.deepseek.com/v1');
    await tester.enterText(find.byType(TextField).at(1), 'new-key');
    await tester.enterText(find.byType(TextField).at(2), 'deepseek-flash');
    await tester.ensureVisible(find.text('测试连接'));
    await tester.tap(find.text('测试连接'));
    await tester.pump();
    expect(sent, isNotNull);
    expect(
        sent!.url.toString(), 'https://api.deepseek.com/v1/chat/completions');
    expect(sent!.headers['authorization'], 'Bearer new-key');
    expect(jsonDecode(sent!.body)['model'], 'deepseek-flash');
    await tester.pump(const Duration(seconds: 25));
    expect(find.text('正在等待模型…'), findsOneWidget);
    expect(find.textContaining('连接失败'), findsNothing);
    pending.complete(http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '连接成功'}
            }
          ]
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await tester.pumpAndSettle();
    expect(find.text('连接成功：连接成功'), findsOneWidget);
    final config = await AiService.instance.loadConfig();
    expect(config.apiKey, 'new-key');
    expect(config.model, 'deepseek-flash');
  });

  testWidgets(
      'save button persists typed key and preset preserves a custom gateway',
      (tester) async {
    final client = MockClient((_) async => http.Response('{}', 200));
    addTearDown(client.close);
    await showSettings(tester, AiService.forTest(client),
        address: 'https://proxy.example/v1');
    await tester.enterText(find.byType(TextField).at(1), 'new-key');
    await tester.tap(find.byTooltip('保存'));
    await tester.pump();
    expect((await AiService.instance.loadConfig()).apiKey, 'new-key');
    await tester.tap(find.byTooltip('常用模型预设'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('deepseek-flash'));
    await tester.tap(find.text('deepseek-flash'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).controller!.text,
        'https://proxy.example/v1');
    expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        'new-key');
    expect(
        tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
        'deepseek-flash');
    await tester.pump(const Duration(milliseconds: 400));
    expect((await AiService.instance.loadConfig()).model, 'deepseek-flash');
  });
}
