import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bnbu_me/state/app_theme_mode_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'theme mode defaults to system and persists the selected mode',
    () async {
      final controller = AppThemeModeController();
      addTearDown(controller.dispose);

      await controller.restore();
      expect(controller.themeMode, ThemeMode.system);

      await controller.setThemeMode(ThemeMode.dark);
      expect(controller.themeMode, ThemeMode.dark);

      final restored = AppThemeModeController();
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.themeMode, ThemeMode.dark);
    },
  );

  test('invalid stored theme values safely fall back to system', () async {
    SharedPreferences.setMockInitialValues({
      AppThemeModeController.preferenceKey: 'unsupported',
    });
    final controller = AppThemeModeController();
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.themeMode, ThemeMode.system);
  });

  test(
    'iOS 26 liquid glass defaults on and persists the user choice',
    () async {
      final controller = AppThemeModeController(
        liquidGlassSupportLoader: () async => true,
      );
      addTearDown(controller.dispose);

      await controller.restore();
      expect(controller.liquidGlassEnabled, isTrue);

      await controller.setLiquidGlassEnabled(false);
      expect(controller.liquidGlassEnabled, isFalse);

      final restored = AppThemeModeController(
        liquidGlassSupportLoader: () async => true,
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.liquidGlassEnabled, isFalse);
    },
  );

  test('older iOS defaults glass off and refuses enabling it', () async {
    SharedPreferences.setMockInitialValues({
      AppThemeModeController.liquidGlassPreferenceKey: true,
    });
    final controller = AppThemeModeController(
      liquidGlassSupportLoader: () async => false,
    );
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.liquidGlassSupported, isFalse);
    expect(controller.liquidGlassEnabled, isFalse);
    expect(await controller.setLiquidGlassEnabled(true), isFalse);
    expect(controller.liquidGlassEnabled, isFalse);
  });

  test('rapid theme changes persist the latest selection', () async {
    final controller = AppThemeModeController();
    addTearDown(controller.dispose);

    await Future.wait([
      controller.setThemeMode(ThemeMode.dark),
      controller.setThemeMode(ThemeMode.light),
    ]);

    final preferences = await SharedPreferences.getInstance();
    expect(controller.themeMode, ThemeMode.light);
    expect(
      preferences.getString(AppThemeModeController.preferenceKey),
      ThemeMode.light.name,
    );
  });

  test(
    'today highlight defaults on and persists color and visibility',
    () async {
      final controller = AppThemeModeController();
      addTearDown(controller.dispose);

      await controller.restore();
      expect(controller.scheduleTodayHighlightEnabled, isTrue);
      expect(controller.scheduleTodayAccent, ScheduleTodayAccent.blue);

      await controller.setScheduleTodayAccent(ScheduleTodayAccent.violet);
      await controller.setScheduleTodayHighlightEnabled(false);

      final restored = AppThemeModeController();
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.scheduleTodayHighlightEnabled, isFalse);
      expect(restored.scheduleTodayAccent, ScheduleTodayAccent.violet);
    },
  );

  test('invalid today accent safely falls back to blue', () async {
    SharedPreferences.setMockInitialValues({
      AppThemeModeController.scheduleTodayAccentPreferenceKey: 'neon',
    });
    final controller = AppThemeModeController();
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.scheduleTodayAccent, ScheduleTodayAccent.blue);
  });
}
