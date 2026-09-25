import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/app_update.dart';
import 'package:bnbu_me/models/app_update_policy.dart';
import 'package:bnbu_me/state/app_update_controller.dart';
import 'package:bnbu_me/widgets/app_update_prompt.dart';
import 'package:bnbu_me/theme/app_theme.dart';

class Driver extends AppUpdateDriver {
  AppUpdateState value = const AppUpdateIdle();
  int checks = 0;
  @override
  AppUpdateState get state => value;
  @override
  UpdateCheckOptions get options => const UpdateCheckOptions(
    cacheSeconds: 60,
    triggers: {
      'startup': true,
      'resume': true,
      'login': false,
      'navigation': false,
      'periodic': true,
      'remote_event': true,
    },
  );
  void publish(bool mandatory) {
    value = AppUpdateAvailable(
      AppUpdateRelease(
        platform: AppUpdatePlatform.macos,
        version: '1.2.4.1',
        buildNumber: 2026091301,
        downloadUri: Uri.parse('https://bnbu.yunwai.cloud/downloads/app.dmg'),
        mandatory: mandatory,
        policyRevision: mandatory ? 2 : 3,
      ),
    );
    notifyListeners();
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<AppUpdateCheckOutcome> check() async {
    checks++;
    publish(false);
    return AppUpdateCheckOutcome.available;
  }

  @override
  Future<void> openDownloadPage() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'disabled actions do not fetch; normal actions obey cache; manual bypasses cache',
    () async {
      var time = DateTime.utc(2026, 9, 13);
      final driver = Driver(),
          controller = AppUpdateController(
            driverFactory: () async => driver,
            now: () => time,
          );
      addTearDown(controller.dispose);
      await controller.initialize();
      expect(driver.checks, 1);
      time = time.add(const Duration(minutes: 2));
      await controller.trigger(UpdateTrigger.navigation);
      expect(driver.checks, 1);
      await controller.trigger(UpdateTrigger.resume);
      expect(driver.checks, 2);
      await controller.trigger(UpdateTrigger.resume);
      expect(driver.checks, 2);
      await controller.checkForUpdates();
      expect(driver.checks, 3);
    },
  );
  testWidgets(
    'mandatory overrides deferral, cannot close, and withdrawal releases gate',
    (tester) async {
      final driver = Driver(),
          controller = AppUpdateController(driverFactory: () async => driver);
      await controller.initialize();
      await controller.deferAutomaticPrompt(controller.state.release!);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: AppUpdatePromptListener(controller: controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('软件更新'), findsNothing);
      driver.publish(true);
      await tester.pumpAndSettle();
      expect(find.text('必须更新'), findsOneWidget);
      expect(find.byKey(const ValueKey('app-update-later')), findsNothing);
      expect(find.byTooltip('关闭'), findsNothing);
      final scope = tester.widget<PopScope>(find.byType(PopScope));
      expect(scope.canPop, false);
      driver.value = const AppUpdateUpToDate();
      driver.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('必须更新'), findsNothing);
      expect(controller.requiresUpdate, false);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
