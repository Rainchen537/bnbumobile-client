import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/theme/campus_reference_theme.dart';
import 'package:bnbu_me/widgets/bnbu_adaptive.dart';

void main() {
  for (final width in [648.0, 900.0, 1440.0]) {
    testWidgets('desktop header stays readable and clickable at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
          home: Builder(
            builder: (context) => Scaffold(
              appBar: BnbuSecondaryAppBar(
                bar: AppBar(
                  title: const Text('课程文件'),
                  actions: [
                    IconButton(
                      key: const ValueKey('refresh'),
                      onPressed: () {},
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              body: const SizedBox.expand(key: ValueKey('body')),
            ),
          ),
        ),
      );
      final box = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('refresh')),
      );
      final hitSize =
          box.localToGlobal(box.size.bottomRight(Offset.zero)) -
          box.localToGlobal(Offset.zero);
      expect(hitSize.dx, greaterThanOrEqualTo(44));
      expect(hitSize.dy, greaterThanOrEqualTo(44));
      expect(tester.getTopLeft(find.byKey(const ValueKey('body'))).dy, 44);
    });
  }

  for (final dark in [false, true]) {
    testWidgets('navigation and content use the same palette dark=$dark', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Builder(
            builder: (context) {
              expect(
                CampusReferenceTheme.of(context).canvas,
                context.bnbuTheme.canvas,
              );
              expect(
                CampusReferenceTheme.of(context).ink,
                context.bnbuTheme.textPrimary,
              );
              return const SizedBox();
            },
          ),
        ),
      );
    });
  }
}
