import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/app_update.dart';
import 'package:bnbu_me/state/app_update_controller.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final release = AppUpdateRelease(
    platform: AppUpdatePlatform.macos,
    version: '1.2.3',
    buildNumber: 2026082603,
    downloadUri: Uri.parse(
      'https://bnbu.yunwai.cloud/downloads/hands-bnbu-macos.dmg',
    ),
  );

  test('initialization performs one automatic version check', () async {
    final driver = _FakeUpdateDriver(release);
    final controller = AppUpdateController(driverFactory: () async => driver);
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(driver.checkCount, 1);
    expect(controller.state, isA<AppUpdateAvailable>());
    expect(controller.lastCheckWasManual, isFalse);
    expect(controller.statusLabel, '有新版本');

    await controller.initialize();
    expect(driver.checkCount, 1);
  });

  test('manual first check initializes and fetches only once', () async {
    final driver = _FakeUpdateDriver(release);
    final controller = AppUpdateController(driverFactory: () async => driver);
    addTearDown(controller.dispose);
    await controller.checkForUpdates();
    expect(driver.checkCount, 1);
    expect(controller.lastCheckWasManual, isTrue);
  });

  test('automatic check and deferred prompt survive app restart', () async {
    var now = DateTime.utc(2026, 9, 6);
    final first = AppUpdateController(
      driverFactory: () async => _FakeUpdateDriver(release),
      now: () => now,
    );
    await first.initialize();
    await first.deferAutomaticPrompt(release);
    first.dispose();
    final driver = _FakeUpdateDriver(release);
    final second = AppUpdateController(
      driverFactory: () async => driver,
      now: () => now,
    );
    addTearDown(second.dispose);
    await second.initialize();
    expect(driver.checkCount, 0);
    expect(second.shouldPromptAutomatically(release), isFalse);
    await second.checkForUpdates();
    expect(driver.checkCount, 1);
    now = now.add(const Duration(days: 1));
    expect(second.shouldPromptAutomatically(release), isTrue);
  });

  test('download action only opens the official URL externally', () async {
    final driver = _FakeUpdateDriver(release);
    final controller = AppUpdateController(driverFactory: () async => driver);
    addTearDown(controller.dispose);
    await controller.initialize();

    expect(await controller.openDownloadPage(), isTrue);
    expect(driver.openWebsiteCount, 1);
    expect(controller.state, isA<AppUpdateAvailable>());
  });

  test('manual checks are marked for direct user feedback', () async {
    final driver = _FakeUpdateDriver(release);
    final controller = AppUpdateController(driverFactory: () async => driver);
    addTearDown(controller.dispose);
    await controller.initialize();

    final outcome = await controller.checkForUpdates();

    expect(outcome, AppUpdateCheckOutcome.available);
    expect(controller.lastCheckWasManual, isTrue);
  });
}

class _FakeUpdateDriver extends AppUpdateDriver {
  _FakeUpdateDriver(this.release);

  final AppUpdateRelease release;
  AppUpdateState _state = const AppUpdateIdle();
  int checkCount = 0;
  int openWebsiteCount = 0;

  @override
  AppUpdateState get state => _state;

  @override
  Future<void> initialize() async {}

  @override
  Future<AppUpdateCheckOutcome> check() async {
    checkCount += 1;
    _setState(AppUpdateAvailable(release));
    return AppUpdateCheckOutcome.available;
  }

  @override
  Future<void> openDownloadPage() async {
    openWebsiteCount += 1;
    _setState(AppUpdateAvailable(release));
  }

  void _setState(AppUpdateState value) {
    _state = value;
    notifyListeners();
  }
}
