import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/mail_startup_coordinator.dart';
import '../tool/mobile_mail_preview.dart';

class _Session extends AppSessionController {
  String? account;
  @override
  bool get isLoggedIn => account != null;
  @override
  String? get username => account;
  @override
  Future<MailAccessCredentials?> loadMailAccessCredentials() async =>
      account == null
      ? null
      : MailAccessCredentials(
          userId: account!,
          emailAddress: '$account@example.test',
          password: 'fixture',
        );
  void change(String? value) {
    account = value;
    notifyListeners();
  }
}

class _Mail extends ReferenceMailService implements MailInboxMonitor {
  _Mail() : super(DateTime(2026, 9, 7));
  final previews = <String>[];
  final accounts = <String>[];
  Completer<void>? gate;
  int closed = 0;
  final changes = StreamController<void>.broadcast();
  @override
  Stream<void> get inboxChanges => changes.stream;
  @override
  Future<void> startInboxMonitoring({
    required MailAccessCredentials credentials,
  }) async {}
  @override
  Future<void> stopInboxMonitoring() async {}
  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async {
    accounts.add(credentials.emailAddress);
    await gate?.future;
    return super.fetchFolder(
      credentials: credentials,
      folder: folder,
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<List<MailMessageSummary>> loadPreviews({
    required MailAccessCredentials credentials,
    required List<MailMessageSummary> messages,
  }) async {
    previews.add(credentials.emailAddress);
    return messages;
  }

  @override
  Future<void> close() async {
    closed++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'public contacts start before login; ordinary mail warms without a page or radar',
    () async {
      final session = _Session();
      final mail = _Mail();
      var contactStarts = 0;
      final coordinator = MailStartupCoordinator(
        sessionController: session,
        mailService: mail,
        pollInterval: Duration.zero,
        warmContacts: () async {
          contactStarts++;
        },
      );
      coordinator.start();
      expect(contactStarts, 1);
      expect(mail.accounts, isEmpty);
      session.change('student');
      await coordinator.refresh();
      expect(mail.accounts, contains('student@example.test'));
      expect(mail.previews, isNotEmpty);
      coordinator.setForeground(false);
      final previous = mail.accounts.length;
      await coordinator.refresh();
      expect(mail.accounts.length, previous);
      session.change(null);
      expect(mail.closed, greaterThan(0));
      coordinator.dispose();
      session.dispose();
      await mail.changes.close();
    },
  );

  test(
    'account switch cancels old warming and coalesces the next account',
    () async {
      final session = _Session()..change('first');
      final mail = _Mail()..gate = Completer<void>();
      final coordinator = MailStartupCoordinator(
        sessionController: session,
        mailService: mail,
        pollInterval: Duration.zero,
        warmContacts: () async {},
      );
      coordinator.start();
      await Future<void>.delayed(Duration.zero);
      session.change('second');
      mail.gate!.complete();
      await coordinator.refresh();
      await Future<void>.delayed(Duration.zero);
      await coordinator.refresh();
      expect(mail.previews, isNot(contains('first@example.test')));
      expect(mail.previews, contains('second@example.test'));
      coordinator.dispose();
      session.dispose();
      await mail.changes.close();
    },
  );
}
