import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/pages/user_page.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/mail_radar_background_coordinator.dart';
import 'package:bnbu_me/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (locale, general, radar, denied) in const [
    (Locale('zh', 'CN'), '通用设置', '邮件雷达', '管理员暂未开放此权限'),
    (Locale('zh', 'TW'), '通用設置', '郵件雷達', '管理員暫未開放此權限'),
    (
      Locale('en'),
      'General Settings',
      'Mail Radar',
      'This feature has not been enabled by the administrator',
    ),
  ]) {
    testWidgets('general settings and denied access follow $locale', (
      tester,
    ) async {
      final session = _LoggedInSessionController();
      final coordinator = MailRadarBackgroundCoordinator(
        sessionController: session,
        assistantService: _DeniedAssistantService(),
        mailService: _UnusedMailService(),
        pollInterval: Duration.zero,
      );
      addTearDown(() {
        coordinator.dispose();
        session.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: locale,
          supportedLocales: BnbuLocalizations.supportedLocales,
          localizationsDelegates: const [
            BnbuLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: UserPage(
            controller: session,
            mailRadarCoordinator: coordinator,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(general), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('general-settings-entry')));
      await tester.pumpAndSettle();

      expect(find.text(general), findsOneWidget);
      expect(find.text(radar), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mail-radar-range-selector')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mail-radar-range-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mail-radar-range-30')));
      await tester.pumpAndSettle();
      expect(find.text(denied), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _DeniedAssistantService implements AiAssistantService {
  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async =>
      const AssistantCapabilities(
        available: true,
        model: 'test',
        contextSources: {},
        actions: {},
        storesConversationContent: true,
        purchaseApiAvailable: false,
        mailRadarEnabled: false,
      );

  @override
  Future<AssistantQuota> loadQuota(String username) {
    throw UnimplementedError();
  }

  @override
  Future<bool> isEnabled(String username) async => true;

  @override
  Future<void> setEnabled(String username, bool enabled) async {}

  @override
  Future<AssistantChatResult> chat({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required AssistantContextPayload context,
    String? clientRequestId,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) => throw UnimplementedError();

  @override
  void dispose() {}
}

class _UnusedMailService extends MailService {
  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LoggedInSessionController extends AppSessionController {
  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student';

  @override
  Future<MailAccessCredentials?> loadMailAccessCredentials() async =>
      const MailAccessCredentials(
        userId: 'student',
        emailAddress: 'student@mail.bnbu.edu.cn',
        password: 'test-only',
      );
}
