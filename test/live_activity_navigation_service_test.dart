import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/live_activity_navigation_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('冷启动时保留灵动岛目标，登录恢复后再打开对应页面', () async {
    const channel = MethodChannel('test/live_activity_navigation');
    final destinations = <String>['schedule'];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'takePendingDestination' || destinations.isEmpty) {
            return null;
          }
          return destinations.removeAt(0);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    final session = _TestSessionController();
    final shell = RootShellController();
    final service = LiveActivityNavigationService(
      sessionController: session,
      shellController: shell,
      channel: channel,
      supported: true,
    );
    addTearDown(service.dispose);
    addTearDown(shell.dispose);
    addTearDown(session.dispose);

    await service.start();
    expect(shell.selectedTab, AppTab.home);

    session.setLoggedIn(true);
    expect(shell.selectedTab, AppTab.schedule);
  });

  test('运行中按提醒类型跳到 iSpace、课表或安全首页', () {
    final session = _TestSessionController()..setLoggedIn(true);
    final shell = RootShellController();
    final service = LiveActivityNavigationService(
      sessionController: session,
      shellController: shell,
      supported: true,
    );
    addTearDown(service.dispose);
    addTearDown(shell.dispose);
    addTearDown(session.dispose);

    service.acceptDestination('ispace');
    expect(shell.selectedTab, AppTab.ispace);
    service.acceptDestination('schedule');
    expect(shell.selectedTab, AppTab.schedule);
    service.acceptDestination('future-kind');
    expect(shell.selectedTab, AppTab.home);
  });

  test('原生小组件导航在 iOS 与 macOS 均启用', () {
    expect(
      LiveActivityNavigationService.isPlatformSupported(TargetPlatform.iOS),
      isTrue,
    );
    expect(
      LiveActivityNavigationService.isPlatformSupported(TargetPlatform.macOS),
      isTrue,
    );
    expect(
      LiveActivityNavigationService.isPlatformSupported(TargetPlatform.android),
      isFalse,
    );
  });
}

class _TestSessionController extends AppSessionController {
  bool _loggedIn = false;

  @override
  bool get isLoggedIn => _loggedIn;

  void setLoggedIn(bool value) {
    _loggedIn = value;
    notifyListeners();
  }
}
