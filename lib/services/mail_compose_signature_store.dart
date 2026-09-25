import '../state/account_habits.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum MailComposeSignature { none, bnbuMe }

/// Account-scoped compose-signature preference. It holds only the selected
/// preset, never a name, mail body, or other personal profile data.
class MailComposeSignatureStore {
  MailComposeSignatureStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;

  String _key(String account) =>
      'mail.compose.signature.v1.${base64Url.encode(utf8.encode(account.trim().toLowerCase()))}';

  Future<MailComposeSignature> load(String account) async {
    final value = AccountHabits.shared.isFor(account)
        ? AccountHabits.shared.read('mail.compose.signature', 'none')
        : (await _preferencesLoader()).getString(_key(account));
    return value == 'bnbu-me'
        ? MailComposeSignature.bnbuMe
        : MailComposeSignature.none;
  }

  Future<void> save(String account, MailComposeSignature signature) async {
    if (AccountHabits.shared.isFor(account)) {
      await AccountHabits.shared.set(
        'mail.compose.signature',
        signature == MailComposeSignature.bnbuMe ? 'bnbu-me' : 'none',
      );
      return;
    }
    await (await _preferencesLoader()).setString(
      _key(account),
      signature == MailComposeSignature.bnbuMe ? 'bnbu-me' : 'none',
    );
  }
}
