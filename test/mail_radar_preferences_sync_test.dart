import 'package:bnbu_me/services/sync/account_sync_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/services/mail_radar_store.dart';

void main() {
  test(
    'one account shares range and opt-out across independent devices',
    () async {
      final remote = _Remote();
      final a = SyncedMailRadarStore(local: _Local(), remote: remote);
      final b = SyncedMailRadarStore(local: _Local(), remote: remote);
      await a.setRangeChoice('student', 30);
      expect((await b.loadPreferences('student')).enabled, isTrue);
      expect((await b.loadPreferences('student')).lookbackDays, 30);
      await b.setRangeChoice('student', 7);
      expect((await a.loadPreferences('student')).lookbackDays, 7);
      await a.setRangeChoice('student', 0);
      final disabled = await b.loadPreferences('student');
      expect(disabled.enabled, isFalse);
      expect(disabled.hasConsent, isTrue);
      expect(disabled.lookbackDays, 7);
      expect(
        (await SyncedMailRadarStore(
          local: _Local(),
          remote: remote,
        ).loadPreferences('another')).hasConsent,
        isFalse,
      );
    },
  );
  test('untouched device defaults never replace existing choice', () async {
    final remote = _Remote();
    final a = SyncedMailRadarStore(local: _Local(), remote: remote);
    await a.loadPreferences('student');
    expect(remote.writes, 0);
    await a.setRangeChoice('student', 60);
    final b = SyncedMailRadarStore(local: _Local(), remote: remote);
    expect((await b.loadPreferences('student')).lookbackDays, 60);
    expect(remote.writes, 1);
  });
  test(
    'legacy consent migrates once and remote opt-out wins thereafter',
    () async {
      final remote = _Remote();
      final local = _Local()
        ..value = const MailRadarPreferences(
          hasConsent: true,
          enabled: true,
          lookbackDays: 60,
        );
      final a = SyncedMailRadarStore(local: local, remote: remote);
      expect((await a.loadPreferences('student')).lookbackDays, 60);
      await remote.saveRadarPreferences(
        'student',
        1,
        const MailRadarPreferences(
          hasConsent: true,
          enabled: false,
          lookbackDays: 7,
        ),
      );
      expect((await a.loadPreferences('student')).enabled, isFalse);
      expect(local.value.lookbackDays, 7);
      expect(remote.writes, 2);
    },
  );
  test(
    'offline reads use cached choice and failed edits never claim remote success',
    () async {
      final remote = _Remote();
      final local = _Local();
      final a = SyncedMailRadarStore(local: local, remote: remote);
      await a.setRangeChoice('student', 30);
      remote.offline = true;
      expect((await a.loadPreferences('student')).lookbackDays, 30);
      await expectLater(a.setRangeChoice('student', 7), throwsStateError);
      expect(local.value.lookbackDays, 30);
      remote.offline = false;
      await a.setRangeChoice('student', 0);
      expect(local.value.enabled, isFalse);
    },
  );
  test(
    'conflicting write reloads server revision and remains bounded',
    () async {
      final remote = _Remote()..conflicts = 1;
      final a = SyncedMailRadarStore(local: _Local(), remote: remote);
      await a.setRangeChoice('student', 7);
      expect((await a.loadPreferences('student')).lookbackDays, 7);
      remote.conflicts = 3;
      await expectLater(a.setRangeChoice('student', 60), throwsFormatException);
      expect(remote.conflicts, 1);
    },
  );
  test(
    'concurrent device operations serialize without resurrecting enabled state',
    () async {
      final a = SyncedMailRadarStore(local: _Local(), remote: _Remote());
      await Future.wait([
        a.setRangeChoice('student', 60),
        a.setRangeChoice('student', 0),
      ]);
      final value = await a.loadPreferences('student');
      expect(value.enabled, isFalse);
      expect(value.lookbackDays, 60);
    },
  );
  test(
    'offline stop survives store restart and stale intent cannot override a later enable',
    () async {
      final remote = _Remote();
      final journal = _Journal();
      final a = SyncedMailRadarStore(
        local: _Local(),
        remote: remote,
        journal: journal,
      );
      await a.setRangeChoice('student', 30);
      remote.offline = true;
      await a.setRangeChoice('student', 0);
      final restarted = SyncedMailRadarStore(
        local: _Local(),
        remote: remote,
        journal: journal,
      );
      expect((await restarted.loadPreferences('student')).enabled, false);
      remote.offline = false;
      await remote.saveRadarPreferences(
        'student',
        1,
        const MailRadarPreferences(
          hasConsent: true,
          enabled: true,
          lookbackDays: 7,
        ),
      );
      expect((await restarted.loadPreferences('student')).enabled, false);
      expect(remote.values['student']!.preferences.enabled, true);
      expect(restarted.syncError, contains('再次选择'));
      await restarted.setRangeChoice('student', 0);
      expect(remote.values['student']!.preferences.enabled, false);
    },
  );
}

class _Remote implements MailRadarPreferenceSyncService {
  final values = <String, MailRadarPreferenceSnapshot>{};
  int writes = 0;
  int conflicts = 0;
  bool offline = false;
  @override
  Future<MailRadarPreferenceSnapshot?> loadRadarPreferences(
    String username,
  ) async {
    if (offline) throw StateError('offline');
    return values[username];
  }

  @override
  Future<MailRadarPreferenceSnapshot> saveRadarPreferences(
    String username,
    int expectedVersion,
    MailRadarPreferences preferences,
  ) async {
    if (offline) throw StateError('offline');
    if (conflicts > 0) {
      conflicts--;
      throw MailRadarPreferenceConflict();
    }
    if ((values[username]?.version ?? 0) != expectedVersion) {
      throw MailRadarPreferenceConflict();
    }
    writes++;
    return values[username] = MailRadarPreferenceSnapshot(
      expectedVersion + 1,
      preferences,
    );
  }
}

class _Local implements MailRadarStore {
  MailRadarPreferences value = const MailRadarPreferences.initial();
  @override
  Future<MailRadarPreferences> loadPreferences(String username) async => value;
  @override
  Future<bool> hasConsent(String username) async => value.hasConsent;
  @override
  Future<void> grantConsent(String username) async {
    value = MailRadarPreferences(
      hasConsent: true,
      enabled: true,
      lookbackDays: value.lookbackDays,
    );
  }

  @override
  Future<void> revokeConsent(String username) async {
    value = MailRadarPreferences(
      hasConsent: false,
      enabled: false,
      lookbackDays: value.lookbackDays,
    );
  }

  @override
  Future<void> setEnabled(String username, bool enabled) async {
    value = MailRadarPreferences(
      hasConsent: value.hasConsent,
      enabled: enabled,
      lookbackDays: value.lookbackDays,
    );
  }

  @override
  Future<void> setLookbackDays(String username, int days) async {
    value = MailRadarPreferences(
      hasConsent: value.hasConsent,
      enabled: value.enabled,
      lookbackDays: days,
    );
  }

  @override
  Future<List<MailRadarItem>> load(String username) async => [];
  @override
  Future<void> save(String username, List<MailRadarItem> items) async {}
}

class _Journal extends AccountSyncStorage {
  final records = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>?> read(String owner, String domain) async =>
      records['$owner:$domain'];
  @override
  Future<void> write(
    String owner,
    String domain,
    Map<String, dynamic> value,
  ) async {
    records['$owner:$domain'] = value;
  }
}
