import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/mail_login_settings.dart';
import 'package:bnbu_me/state/mail_access_controller.dart';
import 'package:bnbu_me/widgets/mail_connection_panel.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/pages/mail_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('verified offline mailbox keeps its existing cache view', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final session = _OfflineSession();
    session.mailAccess.bind(
      owner: 'fixture',
      schoolPassword: 'school',
      settings: const MailLoginSettings(password: 'mail'),
      persist: (_) async {},
    );
    await session.mailAccess.ensureVerified();
    expect(session.mailAccess.status, MailAccessStatus.unavailable);
    final cache = _OfflineCacheService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MailPage.withService(
            controller: session,
            testCredentials: null,
            mailService: cache,
            radarPollInterval: Duration.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MailConnectionPanel), findsNothing);
    expect(find.text('Cached fixture mail'), findsOneWidget);
    expect(cache.password, 'mail');
    expect(session.mailAccess.status, MailAccessStatus.unavailable);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    session.dispose();
  });
  for (final width in [320.0, 390.0, 900.0, 1440.0]) {
    testWidgets('mail repair is bounded and skippable at $width', (
      tester,
    ) async {
      tester.view.resetPhysicalSize();
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final access = MailAccessController(
        verify: (credentials) async {
          if (credentials.password != ' 邮箱密碼 ') {
            throw const MailAuthenticationException();
          }
        },
      );
      addTearDown(access.dispose);
      access.bind(
        owner: 'fixture',
        schoolPassword: 'school',
        settings: const MailLoginSettings(needsPassword: true),
        persist: (_) async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MailConnectionGate(
            controller: access,
            ready: true,
            child: const Scaffold(body: Text('home')),
          ),
        ),
      );
      expect(find.text('接入学校邮箱'), findsOneWidget);
      final input = find.byKey(const ValueKey('mail-connection-password'));
      expect(tester.getSize(input).width, lessThanOrEqualTo(460));
      await tester.enterText(input, 'wrong');
      await tester.tap(find.byKey(const ValueKey('mail-connection-submit')));
      await tester.pumpAndSettle();
      expect(access.status, MailAccessStatus.needsPassword);
      expect(find.text('home'), findsNothing);
      await tester.enterText(input, ' 邮箱密碼 ');
      await tester.tap(find.byKey(const ValueKey('mail-connection-submit')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(access.credentials?.password, ' 邮箱密碼 ');
      expect(find.byKey(const ValueKey('mail-connection-skip')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('skip returns to app; mailbox retains a manual password entry', (
    tester,
  ) async {
    final access = MailAccessController(verify: (_) async {});
    addTearDown(access.dispose);
    access.bind(
      owner: 'fixture',
      schoolPassword: 'school',
      settings: const MailLoginSettings(needsPassword: true),
      persist: (_) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MailConnectionGate(
          controller: access,
          ready: true,
          child: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('mail-connection-skip')));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MailConnectionPanel(controller: access)),
      ),
    );
    expect(
      find.byKey(const ValueKey('mail-connection-password')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mail-connection-skip')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _OfflineSession extends AppSessionController {
  _OfflineSession()
    : super(
        mailVerifier: (_) async {
          throw const MailServiceException('offline fixture');
        },
      );
  @override
  bool get isLoggedIn => true;
  @override
  String get username => 'fixture';
}

class _OfflineCacheService implements MailService, MailCacheReader {
  String? password;
  @override
  Future<MailFolderSnapshot?> readCachedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    int page = 1,
    int pageSize = 25,
    bool unreadOnly = false,
  }) async {
    password = credentials.password;
    return MailFolderSnapshot(
      emailAddress: credentials.emailAddress,
      incomingServer: '',
      outgoingServer: '',
      messages: const [
        MailMessageSummary(
          uid: 1,
          subject: 'Cached fixture mail',
          sender: '',
          preview: 'Cached fixture',
          hasHtmlBody: false,
          date: null,
          isSeen: true,
          previewLoaded: true,
        ),
      ],
      fetchedAt: DateTime(2026),
      folder: folder,
      totalMessages: 1,
      currentPage: 1,
      pageSize: 25,
    );
  }

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async => throw const MailServiceException('offline fixture');
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
