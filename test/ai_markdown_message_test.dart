import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/ui/ai_markdown_message.dart';

void main() {
  for (final width in [320.0, 800.0]) {
    testWidgets('AI Markdown is selectable and fits width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
        body: SingleChildScrollView(
            child: Padding(
          padding: EdgeInsets.all(20),
          child: AiMarkdownMessage(text: '''# 今日安排

**先完成重点任务**，再休息。

- 阅读
- 训练

> 注意休息

| 时间 | 事项 |
| --- | --- |
| 上午 | 阅读 |

```dart
final veryLongExample = 'abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz';
```

[参考链接](https://example.com)
![图片说明](https://example.com/image.png)
'''),
        )),
      )));
      await tester.pump();
      expect(find.byType(MarkdownBody), findsOneWidget);
      final rendered = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((text) => text.data ?? text.textSpan!.toPlainText())
          .join('\n');
      expect(rendered, contains('今日安排'));
      expect(rendered, isNot(contains('# 今日安排')));
      expect(rendered, contains('先完成重点任务'));
      expect(rendered, isNot(contains('**先完成重点任务**')));
      expect(find.byType(Table), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('图片说明'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
