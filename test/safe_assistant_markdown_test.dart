import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/safe_assistant_markdown.dart';

void main() {
  testWidgets('renders safe Markdown and resolves only same-message actions', (
    tester,
  ) async {
    AssistantAction? tapped;
    const action = AssistantAction(
      type: AssistantActionType.openMail,
      title: '打开邮件',
      requiresConfirmation: false,
      targetId: '',
      url: '',
      recipient: '',
      subject: '',
      body: '',
      placeQuery: '',
      actionId: 'mail-1',
      mailUid: 17,
      mailFolder: 'inbox',
      mailboxUidValidity: 9001,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: '# 重点\n\n**课程更新**：[打开邮件](assistant-action:mail-1)',
            actions: const [action],
            onAction: (value) => tapped = value,
          ),
        ),
      ),
    );

    expect(find.text('重点'), findsOneWidget);
    expect(find.textContaining('课程更新'), findsOneWidget);
    await tester.tap(find.text('打开邮件'));
    expect(tapped, same(action));
  });

  testWidgets('external links, images, and unknown actions stay inert', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data:
                '[外部链接](https://evil.example)\n\n'
                '[脚本](javascript:evil)\n\n'
                '[未知动作](assistant-action:missing)\n\n'
                '![远程图片](https://evil.example/image.png)\n\n'
                '<a href="https://evil.example">raw html</a>',
            actions: const [],
            onAction: (_) => taps++,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    for (final label in ['外部链接', '脚本', '未知动作']) {
      await tester.tap(find.text(label));
    }
    expect(taps, 0);
    expect(find.textContaining('raw html'), findsOneWidget);
  });

  testWidgets('duplicate action IDs cannot be activated from Markdown', (
    tester,
  ) async {
    var taps = 0;
    const first = AssistantAction(
      type: AssistantActionType.openCourse,
      title: '课程一',
      requiresConfirmation: false,
      targetId: '1',
      url: '',
      recipient: '',
      subject: '',
      body: '',
      placeQuery: '',
      actionId: 'duplicate',
    );
    const second = AssistantAction(
      type: AssistantActionType.openCourse,
      title: '课程二',
      requiresConfirmation: false,
      targetId: '2',
      url: '',
      recipient: '',
      subject: '',
      body: '',
      placeQuery: '',
      actionId: 'duplicate',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: '[打开课程](assistant-action:duplicate)',
            actions: const [first, second],
            onAction: (_) => taps++,
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开课程'));
    expect(taps, 0);
  });

  testWidgets(
    'official calendar PDF URL stays visible and inert as inline code',
    (tester) async {
      const url = 'https://ar.bnbu.edu.cn/calendar.pdf';
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeAssistantMarkdown(
              data: 'Academic Calendar：`$url`',
              actions: const [],
              onAction: (_) => taps++,
            ),
          ),
        ),
      );

      expect(find.textContaining(url), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
      expect(taps, 0);
    },
  );

  testWidgets('code and quotes follow light and dark semantic colors', (
    tester,
  ) async {
    Future<void> pumpTheme(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: Scaffold(
            body: SafeAssistantMarkdown(
              data:
                  '课程 `Data Structures and Algorithms`\n\n'
                  '> 核对依据\n\n'
                  '```dart\nfinal course = "C#";\n```',
              actions: const [],
              onAction: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final markdown = find.byType(SafeAssistantMarkdown);
      final richTexts = tester.widgetList<RichText>(
        find.descendant(of: markdown, matching: find.byType(RichText)),
      );
      final inlineCodeSpan = richTexts
          .map((widget) => widget.text)
          .map((span) => _findTextSpan(span, 'Data Structures and Algorithms'))
          .whereType<TextSpan>()
          .single;
      final tokens = theme.extension<BnbuThemeExtension>()!;
      expect(inlineCodeSpan.style?.backgroundColor, tokens.surfaceMuted);
      expect(inlineCodeSpan.style?.color, tokens.textPrimary);

      final quote = tester.widget<Container>(
        find
            .ancestor(of: find.text('核对依据'), matching: find.byType(Container))
            .first,
      );
      final quoteDecoration = quote.decoration as BoxDecoration;
      final quoteBorder = quoteDecoration.border! as Border;
      expect(quoteDecoration.color, tokens.surfaceMuted);
      expect(quoteBorder.left.color, tokens.border);

      final codeBlock = tester.widget<Container>(
        find
            .ancestor(
              of: find.byType(SelectableText),
              matching: find.byType(Container),
            )
            .first,
      );
      final codeDecoration = codeBlock.decoration as BoxDecoration;
      final codeBorder = codeDecoration.border! as Border;
      expect(codeDecoration.color, tokens.surfaceMuted);
      expect(codeBorder.top.color, tokens.border);
      final code = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(code.style?.color, tokens.textPrimary);
    }

    await pumpTheme(AppTheme.light);
    await pumpTheme(AppTheme.dark);
  });

  testWidgets(
    'study content can reduce every Markdown type size by 20 percent',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SafeAssistantMarkdown(
              data: '# 标题\n\n正文\n\n```\ncode\n```',
              actions: const [],
              onAction: (_) {},
              fontScale: 0.8,
            ),
          ),
        ),
      );

      final texts = tester.widgetList<Text>(
        find.descendant(
          of: find.byType(SafeAssistantMarkdown),
          matching: find.byType(Text),
        ),
      );
      final heading = texts.singleWhere(
        (widget) => widget.textSpan?.toPlainText() == '标题',
      );
      final body = texts.singleWhere(
        (widget) => widget.textSpan?.toPlainText() == '正文',
      );
      final code = tester.widget<SelectableText>(find.byType(SelectableText));

      expect(heading.textSpan?.style?.fontSize, closeTo(17.6, 0.001));
      expect(body.textSpan?.style?.fontSize, closeTo(12, 0.001));
      expect(code.style?.fontSize, closeTo(10.4, 0.001));
    },
  );

  testWidgets('renders GFM tables without leaking the separator row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: SafeAssistantMarkdown(
              data:
                  '| 课程 | 状态 | 说明 |\n'
                  '| :--- | :---: | ---: |\n'
                  '| Data Structures | **进行中** | `12` 周 |\n'
                  r'| AI | $\begin{bmatrix}a & b \\ c & d\end{bmatrix}$ | 很长很长很长很长很长很长很长的说明 |',
              actions: const [],
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Table), findsOneWidget);
    expect(find.text('课程'), findsOneWidget);
    expect(find.text('Data Structures'), findsOneWidget);
    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(':---'), findsNothing);
    expect(tester.getSize(find.byType(Table)).width, greaterThan(280));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders common inline emphasis and escaped markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: '*斜体*、~~删除~~、***重点***、\\*原样星号\\*',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(SafeAssistantMarkdown),
        matching: find.byType(RichText),
      ),
    );
    final italic = _findTextSpan(richText.text, '斜体');
    final strike = _findTextSpan(richText.text, '删除');
    final emphasized = _findTextSpan(richText.text, '重点');
    expect(italic?.style?.fontStyle, FontStyle.italic);
    expect(strike?.style?.decoration, TextDecoration.lineThrough);
    expect(emphasized?.style?.fontStyle, FontStyle.italic);
    expect(emphasized?.style?.fontWeight, FontWeight.w700);
    expect(richText.text.toPlainText(), contains('*原样星号*'));
  });

  testWidgets('renders extended headings, thematic breaks, and task lists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data:
                '#### 四级标题\n\n'
                '## C#\n\n'
                '---\n\n'
                '- [x] 已完成\n'
                '  - [ ] 子任务',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('四级标题'), findsOneWidget);
    expect(find.text('C#'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('子任务'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assistant-markdown-task-checked')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assistant-markdown-task-unchecked')),
      findsOneWidget,
    );
  });

  testWidgets('keeps explicit ordered-list numbers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: '3. 第三步\n4. 第四步',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('3.'), findsOneWidget);
    expect(find.text('4.'), findsOneWidget);
    expect(find.text('1.'), findsNothing);
  });

  testWidgets('renders inline dollar and parenthesized TeX formulas', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: r'函数 $f(x)=x^2$ 的导数是 \(f^\prime(x)=2x\)。',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(2));
    final inlineViewports = tester.widgetList<SingleChildScrollView>(
      find.byWidgetPredicate(
        (widget) =>
            widget is SingleChildScrollView &&
            widget.scrollDirection == Axis.horizontal,
      ),
    );
    expect(inlineViewports, hasLength(2));
    final inlineViewportFinder = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(tester.getSize(inlineViewportFinder.first).width, lessThan(160));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders display TeX in an independent horizontal viewport', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SizedBox(
              width: 320,
              child: SafeAssistantMarkdown(
                data: r'''
$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$
''',
                actions: const [],
                onAction: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final horizontalViewport = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(horizontalViewport, findsOneWidget);
    expect(
      find.descendant(of: horizontalViewport, matching: find.byType(Math)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid TeX falls back to selectable source text', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: r'$$\definitelyUnknownCommand{$$',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.textContaining(r'\definitelyUnknownCommand{'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('escaped dollars and code spans do not become formulas', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: r'费用是 \$20，代码 `$x$`，公式 $x+1$。',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    final richText = tester
        .widgetList<RichText>(
          find.descendant(
            of: find.byType(SafeAssistantMarkdown),
            matching: find.byType(RichText),
          ),
        )
        .singleWhere((widget) => widget.text.toPlainText().contains('费用是'));
    expect(richText.text.toPlainText(), contains(r'费用是 $20'));
    expect(richText.text.toPlainText(), contains(r'$x$'));
  });

  testWidgets('renders common calculus and matrix notation', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: r'''
\[
\lim_{x \to 0}\frac{\sin x}{x}=1
\]

$$
\int_a^b f(x)\,dx + \sum_{n=1}^{\infty}\frac{1}{n^2}
$$

$$
\begin{bmatrix}a & b \\ c & d\end{bmatrix}
$$
''',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNWidgets(3));
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('oversized TeX stays selectable instead of being parsed', (
    tester,
  ) async {
    final oversized = List.filled(4097, 'x').join();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: '\$\$$oversized\$\$',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(Math), findsNothing);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long inline TeX scrolls locally without widening the message', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: SafeAssistantMarkdown(
              data:
                  r'结果 $\displaystyle\sum_{n=1}^{\infty}\frac{1}{n^2}+\int_{-\infty}^{\infty}e^{-x^2}\,dx=\frac{\pi^2}{6}+\sqrt{\pi}$。',
              actions: const [],
              onAction: (_) {},
            ),
          ),
        ),
      ),
    );

    final viewport = find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );
    expect(viewport, findsOneWidget);
    expect(tester.getSize(viewport).width, lessThanOrEqualTo(200));
    expect(find.byType(Math), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('math follows the active theme and content font scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data:
                r'$x^2$'
                '\n\n'
                r'$$\frac{1}{2}$$',
            actions: const [],
            onAction: (_) {},
            fontScale: 0.8,
          ),
        ),
      ),
    );

    final maths = tester.widgetList<Math>(find.byType(Math)).toList();
    final tokens = AppTheme.dark.extension<BnbuThemeExtension>()!;
    expect(maths, hasLength(2));
    expect(maths[0].textStyle?.color, tokens.textPrimary);
    expect(maths[0].textStyle?.fontSize, closeTo(12, 0.001));
    expect(maths[1].textStyle?.color, tokens.textPrimary);
    expect(maths[1].textStyle?.fontSize, closeTo(13.6, 0.001));
  });

  testWidgets('repeated rich blocks keep independent widget identities', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: r'''
| A | B |
|---|---|
| 1 | 2 |

---

```
first
```

| C | D |
|---|---|
| 3 | 4 |

---

```
second
```
''',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(Table), findsNWidgets(2));
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.byType(SelectableText), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
  testWidgets('preserves hard breaks and single-symbol math', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data:
                'first  \nsecond\n\n'
                r'$x$ and $y$',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('first\nsecond'), findsOneWidget);
    expect(find.byType(Math), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('code fence closes only on a bare matching fence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeAssistantMarkdown(
            data: '```text\nfirst\n```literal\nlast\n```',
            actions: const [],
            onAction: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('first\n```literal\nlast'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

TextSpan? _findTextSpan(InlineSpan span, String text) {
  if (span is! TextSpan) {
    return null;
  }
  if (span.text == text) {
    return span;
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    final match = _findTextSpan(child, text);
    if (match != null) {
      return match;
    }
  }
  return null;
}
