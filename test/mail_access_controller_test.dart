import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/mail_login_settings.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/state/mail_access_controller.dart';

void main() {
  test(
    'authentication classification never treats network/login context as rejection',
    () {
      for (final message in [
        'NO [AUTHENTICATIONFAILED] Authentication failed',
        'LOGIN failed',
        '用户名或密码错误',
      ]) {
        expect(isExplicitMailAuthenticationFailure(message), isTrue);
      }
      for (final message in [
        'authentication connection timeout',
        'login TLS certificate failed',
        'authentication temporarily unavailable',
        'password login connection closed',
        'permission denied on folder',
      ]) {
        expect(isExplicitMailAuthenticationFailure(message), isFalse);
      }
    },
  );
  test(
    'different password does not replace school password and skip is sticky',
    () async {
      final attempts = <String>[];
      MailLoginSettings saved = const MailLoginSettings();
      final access = MailAccessController(
        verify: (credentials) async {
          attempts.add(credentials.password);
          if (credentials.password != ' 邮箱密碼 ') {
            throw const MailAuthenticationException();
          }
        },
      );
      addTearDown(access.dispose);
      access.bind(
        owner: 'student',
        schoolPassword: 'school',
        settings: saved,
        persist: (value) async => saved = value,
      );
      await Future.wait([access.ensureVerified(), access.ensureVerified()]);
      expect(attempts, ['school']);
      expect(access.status, MailAccessStatus.needsPassword);
      expect(access.credentials, isNull);
      expect(access.shouldPrompt, isTrue);
      await access.skip();
      access.bind(
        owner: 'student',
        schoolPassword: 'school',
        settings: saved,
        persist: (value) async => saved = value,
      );
      await access.ensureVerified();
      expect(attempts, ['school']);
      expect(access.shouldPrompt, isFalse);
      await access.connect(' 邮箱密碼 ');
      expect(access.credentials?.password, ' 邮箱密碼 ');
      expect(saved.password, ' 邮箱密碼 ');
      expect(saved.skipped, isFalse);
      access.bind(
        owner: 'student',
        schoolPassword: 'new-school',
        settings: saved,
        persist: (value) async => saved = value,
      );
      await access.ensureVerified();
      expect(attempts.last, ' 邮箱密碼 ');
    },
  );

  test(
    'network failure never asks for a new password or erases saved choice',
    () async {
      final access = MailAccessController(
        verify: (_) async {
          throw const MailServiceException('network', isRetryable: true);
        },
      );
      addTearDown(access.dispose);
      var writes = 0;
      access.bind(
        owner: 'student',
        schoolPassword: 'school',
        settings: const MailLoginSettings(password: 'mail'),
        persist: (_) async {
          writes++;
        },
      );
      await access.ensureVerified();
      expect(access.status, MailAccessStatus.unavailable);
      expect(access.shouldPrompt, isFalse);
      expect(access.credentials?.password, 'mail');
      expect(writes, 0);
    },
  );

  test(
    'offline first login cannot claim an unverified mailbox is connected',
    () async {
      final access = MailAccessController(
        verify: (_) async {
          throw const MailServiceException('offline', isRetryable: true);
        },
      );
      addTearDown(access.dispose);
      access.bind(
        owner: 'student',
        schoolPassword: 'school',
        settings: const MailLoginSettings(),
        persist: (_) async {},
      );
      await access.ensureVerified();
      expect(access.status, MailAccessStatus.unavailable);
      expect(access.credentials, isNull);
      expect(access.shouldPrompt, isFalse);
    },
  );

  test(
    'logout or skip rejects late verification and late persistence',
    () async {
      final gate = Completer<void>();
      var writes = 0;
      final access = MailAccessController(verify: (_) => gate.future);
      addTearDown(access.dispose);
      access.bind(
        owner: 'one',
        schoolPassword: 'school',
        settings: const MailLoginSettings(),
        persist: (_) async {
          writes++;
        },
      );
      final pending = access.connect('private');
      access.reset();
      gate.complete();
      await pending;
      expect(writes, 0);
      expect(access.credentials, isNull);
      expect(access.status, MailAccessStatus.signedOut);
    },
  );

  test('connected mailbox cannot be disconnected with skip', () async {
    final access = MailAccessController(verify: (_) async {});
    addTearDown(access.dispose);
    access.bind(
      owner: 'student',
      schoolPassword: 'school',
      settings: const MailLoginSettings(),
      persist: (_) async {},
    );
    await access.ensureVerified();
    await access.skip();
    expect(access.status, MailAccessStatus.connected);
    final oldCredentials = access.credentials!;
    await access.reportAuthenticationFailure(oldCredentials);
    expect(access.status, MailAccessStatus.needsPassword);
    expect(access.credentials, isNull);
  });
}
