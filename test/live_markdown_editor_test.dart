import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/ui/live_markdown_editor.dart';

void main() {
  testWidgets('renders blocks and edits only the selected block',
      (tester) async {
    final controller = TextEditingController(
      text: '## 标题\n\n第一段 **重点**。\n\n- 条目一\n- 条目二',
    );
    addTearDown(controller.dispose);
    var changes = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: LiveMarkdownEditor(
              controller: controller,
              onChanged: () => changes++,
              styleSheet: MarkdownStyleSheet(),
            ),
          ),
          TextButton(onPressed: () {}, child: const Text('完成')),
        ]),
      ),
    ));

    expect(find.text('标题'), findsOneWidget);
    expect(find.text('## 标题'), findsNothing);
    await tester.tap(find.byKey(const Key('markdown-preview-block-0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('markdown-active-block')), findsOneWidget);
    expect(find.text('## 标题'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('markdown-active-block')), '## 新标题');
    await tester.pump();
    expect(controller.text, '## 新标题\n\n第一段 **重点**。\n\n- 条目一\n- 条目二');
    expect(
      tester
          .widgetList<MarkdownBody>(find.byType(MarkdownBody))
          .map((body) => body.data),
      contains('第一段 **重点**。'),
    );

    await tester.tap(find.byKey(const Key('markdown-preview-block-1')));
    await tester.pumpAndSettle();
    expect(find.text('新标题'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('markdown-active-block')), '第二段 **保留格式**。');
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('markdown-active-block')), findsNothing);
    expect(controller.text, '## 新标题\n\n第二段 **保留格式**。\n\n- 条目一\n- 条目二');
    expect(changes, 2);
  });

  testWidgets('an empty note opens ready to type and then renders',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(children: [
          Expanded(
            child: LiveMarkdownEditor(
              controller: controller,
              onChanged: () {},
              styleSheet: MarkdownStyleSheet(),
            ),
          ),
          TextButton(onPressed: () {}, child: const Text('完成')),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('markdown-active-block')), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('markdown-active-block')), '# 第一条笔记');
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(controller.text, '# 第一条笔记');
    expect(find.text('第一条笔记'), findsOneWidget);
  });
}
