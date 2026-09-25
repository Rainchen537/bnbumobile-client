import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_components.dart';
import 'package:bnbu_me/widgets/small_u_logo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SmallULogo keeps expected dimensions without overflow', (
    WidgetTester tester,
  ) async {
    for (final size in <double>[20, 28, 54, 76]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Center(child: SmallULogo(size: size)),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey('small-u-logo-body'))),
        Size.square(size),
      );
    }
  });

  testWidgets('SmallULogo switches theme assets and keeps stable semantics', (
    WidgetTester tester,
  ) async {
    final semantics = tester.ensureSemantics();

    for (final entry in <(ThemeData, String, String)>[
      (
        AppTheme.light,
        'small-u-logo-light',
        'assets/branding/small_u_light.png',
      ),
      (AppTheme.dark, 'small-u-logo-dark', 'assets/branding/small_u_dark.png'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(entry.$2),
          theme: entry.$1,
          themeAnimationDuration: Duration.zero,
          home: ColoredBox(
            color: entry.$1.scaffoldBackgroundColor,
            child: Center(child: SmallULogo(size: 54)),
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.key, ValueKey(entry.$2));
      expect((image.image as AssetImage).assetName, entry.$3);
      expect(image.fit, BoxFit.contain);
      await tester.runAsync(
        () => precacheImage(
          image.image,
          tester.element(find.byKey(const ValueKey('small-u-logo-body'))),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('小U'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    semantics.dispose();
  });

  testWidgets('SmallULogo running ring is outside the unchanged logo body', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Center(child: SmallULogo(size: 54, showRunningRing: true)),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('small-u-logo-running-ring'))),
      const Size.square(62),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('small-u-logo-body'))),
      const Size.square(54),
    );
  });

  testWidgets('design tokens expose light and dark Material 3 themes', (
    WidgetTester tester,
  ) async {
    expect(AppTheme.light.useMaterial3, isTrue);
    expect(AppTheme.dark.useMaterial3, isTrue);
    expect(AppTheme.light.colorScheme.primary, BnbuColorTokens.brandBlue);
    expect(
      AppTheme.dark.colorScheme.primary,
      BnbuThemeExtension.dark.brandBlue,
    );

    final lightTokens = AppTheme.light.extension<BnbuThemeExtension>()!;
    final darkTokens = AppTheme.dark.extension<BnbuThemeExtension>()!;
    expect(lightTokens.canvas, BnbuColorTokens.lightCanvas);
    expect(darkTokens.canvas, BnbuColorTokens.darkCanvas);
    expect(
      [
        lightTokens.space4,
        lightTokens.space8,
        lightTokens.space12,
        lightTokens.space16,
        lightTokens.space24,
        lightTokens.space32,
      ],
      [4, 8, 12, 16, 24, 32],
    );
    expect(
      [lightTokens.radius12, lightTokens.radius16, lightTokens.radius24],
      [10, 12, 20],
    );
    expect(lightTokens.minInteractiveDimension, 48);
  });

  testWidgets('shared display components handle text scale 2.0', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 900),
            textScaler: TextScaler.linear(2),
          ),
          child: BnbuPageScaffold(
            header: const BnbuPageHeader(
              title: 'BNBU.ME',
              trailing: BnbuStatusBadge(
                label: '同步中',
                kind: BnbuStatusKind.info,
              ),
            ),
            children: [
              const BnbuSectionHeader(title: '常用操作'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  BnbuCompactActionTile(
                    icon: Icons.mail_outline_rounded,
                    label: '邮箱',
                    onTap: () {},
                  ),
                  BnbuCompactActionTile(
                    icon: Icons.calendar_month_rounded,
                    label: '课表',
                    onTap: () {},
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const BnbuNotice(message: '网络较慢，内容仍可稍后刷新。'),
              const SizedBox(height: 16),
              const BnbuActionPreviewSurface(
                title: '操作预览',
                items: [
                  BnbuActionPreviewItem(
                    label: '收件人',
                    value: 'teacher@bnbu.edu.cn',
                  ),
                  BnbuActionPreviewItem(label: '主题', value: '课程咨询'),
                ],
                actions: [OutlinedButton(onPressed: null, child: Text('取消'))],
              ),
              const SizedBox(height: 16),
              BnbuEmptyState(
                message: '当前没有新的课程资料。',
                action: FilledButton(onPressed: () {}, child: const Text('刷新')),
              ),
              const SizedBox(height: 16),
              const BnbuLoadingState(),
              const SizedBox(height: 16),
              BnbuErrorState(
                message: '请检查网络后重试。',
                action: TextButton(onPressed: () {}, child: const Text('重试')),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('compact action tile enforces minimum interactive target', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Center(
          child: BnbuCompactActionTile(
            icon: Icons.open_in_new_rounded,
            label: '打开',
            size: 32,
            onTap: () {},
          ),
        ),
      ),
    );

    final tileBox = find
        .descendant(
          of: find.byType(BnbuCompactActionTile),
          matching: find.byType(SizedBox),
        )
        .first;
    expect(tester.getSize(tileBox), const Size.square(48));
  });

  testWidgets('compact action tile wraps labels without fitted scaling', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: Center(
            child: BnbuCompactActionTile(
              icon: Icons.account_balance_rounded,
              label: '统一门户',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FittedBox), findsNothing);
    final label = tester.widget<Text>(find.text('统一门户'));
    expect(label.maxLines, 2);
    expect(tester.takeException(), isNull);
  });
}
