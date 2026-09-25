import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/state/mail_radar_controller.dart';

import '../tool/mobile_mail_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime.utc(2026, 9, 10);
  final credentials = MailReferenceFixture.credentials;

  Future<MailRadarController> create(
    ReferenceRadarStore store, {
    ReferenceMailService? service,
  }) async {
    final controller = MailRadarController(
      username: credentials.userId,
      credentials: credentials,
      mailService: service ?? ReferenceMailService(now),
      analyzer: ReferenceRadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();
    addTearDown(controller.dispose);
    return controller;
  }

  test('unknown message age is never treated as received today', () async {
    final service = ReferenceMailService(now)..messages.clear();
    service.messages.add(
      const MailMessageSummary(
        uid: 99,
        subject: 'Undated',
        sender: 'office@example.test',
        preview: '',
        hasHtmlBody: false,
        date: null,
        isSeen: false,
        mailboxUidValidity: 101,
      ),
    );
    final controller = await create(ReferenceRadarStore([]), service: service);
    await controller.setRangeChoice(60);
    await controller.scan();
    expect(controller.items, isEmpty);
  });

  test('legacy range clamps to 60 while disabled stays disabled', () async {
    final store = ReferenceRadarStore([])..days = 365;
    final controller = await create(store);
    expect(controller.lookbackDays, 60);
    expect(store.days, 60);
    expect(controller.enabled, isFalse);
    await expectLater(controller.setRangeChoice(90), throwsFormatException);
    expect(controller.enabled, isFalse);
  });

  test(
    'explicit exclusion survives scan and reopening; read is independent',
    () async {
      final service = ReferenceMailService(now);
      final store = ReferenceRadarStore([]);
      final controller = await create(store, service: service);
      final first = service.messages.first;
      await controller.excludeMessage(first);
      await controller.setRangeChoice(7);
      await controller.scan();
      expect(
        controller.visibleItems.any(
          (item) => item.uid == first.uid && item.sourceFolder == first.folder,
        ),
        isFalse,
      );
      expect(
        controller.items
            .firstWhere(
              (item) =>
                  item.uid == first.uid && item.sourceFolder == first.folder,
            )
            .membership,
        MailRadarMembership.excluded,
      );
      final reloaded = await create(store, service: service);
      expect(reloaded.visibleItems.any((item) => item.key == '101_1'), isFalse);
      await reloaded.includeMessage(first);
      await reloaded.scan();
      final included = reloaded.visibleItems.firstWhere(
        (item) => item.key == '101_1',
      );
      expect(included.originalIsSeen, isFalse);
      await reloaded.markOpened(included);
      expect(
        reloaded.items
            .firstWhere((item) => item.key == included.key)
            .originalIsSeen,
        isFalse,
      );
      await reloaded.recordOriginalReadState([first], true);
      final read = reloaded.items.firstWhere(
        (item) => item.key == included.key,
      );
      expect(read.toSummary().isSeen, isTrue);
      expect(read.completed, isFalse);
    },
  );

  test(
    'manual inclusion is folder scoped and never bypasses 60 day limit',
    () async {
      final service = ReferenceMailService(now);
      final controller = await create(
        ReferenceRadarStore([]),
        service: service,
      );
      await controller.setRangeChoice(7);
      await controller.scan();
      final sent = service.messages.firstWhere(
        (mail) => mail.folder == MailFolder.sent,
      );
      await controller.includeMessage(sent);
      await controller.scan();
      expect(
        controller.visibleItems.map((item) => item.key),
        containsAll(['101_1', 'sent:101_1']),
      );
      await expectLater(
        controller.includeMessage(
          sent.copyWith(date: now.subtract(const Duration(days: 61))),
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'fresh server flags propagate without body reads or task completion',
    () async {
      final service = _DelayedFlagsService(now);
      final store = ReferenceRadarStore([]);
      final controller = await create(store, service: service);
      await controller.excludeMessage(service.messages.first);
      await controller.setMessageMembership([
        service.messages.first,
      ], MailRadarMembership.automatic);
      service.flags = {service.messages.first.identity!: true};
      await controller.refreshOriginalReadStates();
      final item = controller.visibleItems.single;
      expect(item.originalIsSeen, isTrue);
      expect(item.completed, isFalse);
      expect(service.bodyReads, 0);
    },
  );

  test('late flag response cannot undo a newer user swipe', () async {
    final service = _DelayedFlagsService(now);
    final controller = await create(ReferenceRadarStore([]), service: service);
    final first = service.messages.first;
    await controller.excludeMessage(first);
    await controller.setMessageMembership([
      first,
    ], MailRadarMembership.automatic);
    service.pending = Completer<Map<MailMessageIdentity, bool>>();
    final refresh = controller.refreshOriginalReadStates();
    await controller.recordOriginalReadState([first], true);
    service.pending!.complete({first.identity!: false});
    await refresh;
    expect(controller.visibleItems.single.originalIsSeen, isTrue);
  });
}

class _DelayedFlagsService extends ReferenceMailService {
  _DelayedFlagsService(super.now);
  Map<MailMessageIdentity, bool> flags = {};
  Completer<Map<MailMessageIdentity, bool>>? pending;
  int bodyReads = 0;
  @override
  Future<Map<MailMessageIdentity, bool>> readSeenFlags({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
  }) => pending?.future ?? Future.value(flags);
  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) {
    bodyReads++;
    return super.readMessage(
      credentials: credentials,
      folder: folder,
      uid: uid,
      expectedMailboxUidValidity: expectedMailboxUidValidity,
      markAsSeen: markAsSeen,
    );
  }
}
