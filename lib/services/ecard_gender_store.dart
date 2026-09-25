import 'package:flutter/foundation.dart';
import '../models/ecard_gender_preferences.dart';
import 'sync/account_sync_storage.dart';

/// No HTTP, sync scheduler, analytics or plaintext preference cache.
class EcardGenderStore extends ChangeNotifier {
  EcardGenderStore({AccountSyncStorage? storage})
    : _storage = storage ?? AccountSyncStorage.shared;
  static final shared = EcardGenderStore();
  static const domain = 'ecard-gender-display.v1';
  final AccountSyncStorage _storage;

  Future<EcardGenderPreferences> read(String owner) async {
    if (AccountSyncStorage.account(owner).isEmpty) {
      throw StateError('Missing owner');
    }
    final record = await _storage.read(owner, domain);
    return record == null
        ? const EcardGenderPreferences()
        : EcardGenderPreferences.fromJson(record);
  }

  Future<void> save(
    String owner,
    EcardGenderPreferences value, {
    required bool Function() isCurrent,
  }) async {
    if (AccountSyncStorage.account(owner).isEmpty || !isCurrent()) {
      throw StateError('Stale owner');
    }
    await _storage.writeIfCurrent(
      owner,
      domain,
      value.toJson(),
      isCurrent: isCurrent,
    );
    notifyListeners();
  }
}
