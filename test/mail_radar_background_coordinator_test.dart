import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/mail_radar_store.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/app_language_controller.dart';
import 'package:bnbu_me/state/mail_radar_background_coordinator.dart';

late DateTime _fixtureNow;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _fixtureNow = DateTime.now();
  });

  test('旧同意不继承且新同意默认30天支持暂停与撤回', () async {
    const username = 'student';
    const store = SharedPreferencesMailRadarStore();
    await store.grantConsent(username);
    final shared = await SharedPreferences.getInstance();
    final consentKey = shared.getKeys().singleWhere(
      (key) => key.startsWith('mail_radar_consent_'),
    );
    await shared.setString(consentKey, '2026-08-10-mail-radar-v1');

    var preferences = await store.loadPreferences(username);
    expect(preferences.hasConsent, isFalse);
    expect(preferences.enabled, isFalse);
    expect(preferences.lookbackDays, mailRadarDefaultLookbackDays);

    await store.grantConsent(username);
    await store.setLookbackDays(username, 60);
    await store.setEnabled(username, false);
    preferences = await store.loadPreferences(username);
    expect(preferences.hasConsent, isTrue);
    expect(preferences.enabled, isFalse);
    expect(preferences.lookbackDays, 60);

    await store.revokeConsent(username);
    preferences = await store.loadPreferences(username);
    expect(preferences.hasConsent, isFalse);
    expect(preferences.enabled, isFalse);
    expect(preferences.lookbackDays, 60);
  });

  test('设置页可区分管理员未授权与临时权限检查失败', () async {
    final deniedSession = _BackgroundSessionController();
    final deniedCoordinator = MailRadarBackgroundCoordinator(
      sessionController: deniedSession,
      assistantService: _BackgroundAssistantService(mailRadarEnabled: false),
      mailService: _MonitoringMailService(),
      pollInterval: Duration.zero,
    );
    addTearDown(() {
      deniedCoordinator.dispose();
      deniedSession.dispose();
    });

    expect(await deniedCoordinator.prepareForSettings(), isNull);
    expect(deniedCoordinator.availabilityKnown, isTrue);
    expect(deniedCoordinator.isFeatureAvailable, isFalse);
    expect(deniedCoordinator.featureAvailabilityError, isNull);
    expect(deniedCoordinator.isEffectivelyEnabled, isFalse);

    final failedSession = _BackgroundSessionController();
    final failedAssistant = _BackgroundAssistantService()
      ..failCapabilities = true;
    final failedCoordinator = MailRadarBackgroundCoordinator(
      sessionController: failedSession,
      assistantService: failedAssistant,
      mailService: _MonitoringMailService(),
      pollInterval: Duration.zero,
    );
    addTearDown(() {
      failedCoordinator.dispose();
      failedSession.dispose();
    });

    expect(await failedCoordinator.prepareForSettings(), isNull);
    expect(failedCoordinator.availabilityKnown, isFalse);
    expect(failedCoordinator.isFeatureAvailable, isFalse);
    expect(failedCoordinator.featureAvailabilityError, isNotNull);
  });

  test('本机选择不使用会立即撤销有效雷达状态', () async {
    const username = 'student';
    await const SharedPreferencesMailRadarStore().grantConsent(username);
    final session = _BackgroundSessionController();
    final coordinator = MailRadarBackgroundCoordinator(
      sessionController: session,
      assistantService: _BackgroundAssistantService(),
      mailService: _MonitoringMailService(),
      pollInterval: Duration.zero,
    );
    addTearDown(() {
      coordinator.dispose();
      session.dispose();
    });

    final controller = await coordinator.prepareForSettings();
    expect(controller, isNotNull);
    expect(coordinator.isEffectivelyEnabled, isTrue);

    await controller!.setRangeChoice(0);
    expect(controller.enabled, isFalse);
    expect(coordinator.isEffectivelyEnabled, isFalse);
  });

  test(
    'consented radar starts before the mail page and reacts to new mail',
    () async {
      const username = 'student';
      await const SharedPreferencesMailRadarStore().grantConsent(username);
      final session = _BackgroundSessionController();
      final mail = _MonitoringMailService();
      final coordinator = MailRadarBackgroundCoordinator(
        sessionController: session,
        assistantService: _BackgroundAssistantService(),
        mailService: mail,
        pollInterval: Duration.zero,
      );
      addTearDown(() {
        coordinator.dispose();
        session.dispose();
      });

      coordinator.start();
      final controller = await coordinator.ensureReady();
      await _waitUntil(() => controller?.analyzedCount == 1);

      expect(mail.monitorStarts, 1);
      expect(controller?.items.map((item) => item.uid), contains(1));

      mail.messages.insert(0, _summary(2));
      mail.emitNewMail();
      await _waitUntil(() => controller?.analyzedCount == 2);

      expect(controller?.items.map((item) => item.uid), containsAll([1, 2]));
      expect(
        controller?.items.firstWhere((item) => item.uid == 2).isUnread,
        isTrue,
      );
    },
  );

  test(
    'logout stops inbox monitoring and releases the radar runtime',
    () async {
      const username = 'student';
      await const SharedPreferencesMailRadarStore().grantConsent(username);
      final session = _BackgroundSessionController();
      final mail = _MonitoringMailService();
      final coordinator = MailRadarBackgroundCoordinator(
        sessionController: session,
        assistantService: _BackgroundAssistantService(),
        mailService: mail,
        pollInterval: Duration.zero,
      );
      addTearDown(() {
        coordinator.dispose();
        session.dispose();
      });

      coordinator.start();
      await coordinator.ensureReady();
      await _waitUntil(() => mail.monitorStarts == 1);

      session.simulateLogout();
      await _waitUntil(() => mail.monitorStops == 1);

      expect(coordinator.controller, isNull);
    },
  );

  test('切换应用语言后后台邮件雷达立即按新语言重跑缓存结果', () async {
    const username = 'student';
    await const SharedPreferencesMailRadarStore().grantConsent(username);
    final session = _BackgroundSessionController();
    final language = AppLanguageController();
    await language.restore(preferredLocales: const [Locale('zh', 'CN')]);
    final assistant = _BackgroundAssistantService();
    final coordinator = MailRadarBackgroundCoordinator(
      sessionController: session,
      assistantService: assistant,
      languageController: language,
      mailService: _MonitoringMailService(),
      pollInterval: Duration.zero,
    );
    addTearDown(() {
      coordinator.dispose();
      language.dispose();
      session.dispose();
    });

    coordinator.start();
    await _waitUntil(
      () =>
          coordinator.controller?.items.length == 1 &&
          coordinator.controller?.items.single.analysisLanguageTag == 'zh-Hans',
    );

    await language.setMode(AppLanguageMode.english);
    await _waitUntil(
      () =>
          coordinator.controller?.items.length == 1 &&
          coordinator.controller?.items.single.analysisLanguageTag == 'en',
    );

    expect(assistant.targetLanguages, ['zh-Hans', 'en']);
  });

  test('switching account replaces the radar runtime', () async {
    await const SharedPreferencesMailRadarStore().grantConsent('student');
    await const SharedPreferencesMailRadarStore().grantConsent('student2');
    final session = _BackgroundSessionController();
    final mail = _MonitoringMailService();
    final coordinator = MailRadarBackgroundCoordinator(
      sessionController: session,
      assistantService: _BackgroundAssistantService(),
      mailService: mail,
      pollInterval: Duration.zero,
    );
    addTearDown(() {
      coordinator.dispose();
      session.dispose();
    });

    coordinator.start();
    await _waitUntil(() => coordinator.controller?.username == 'student');

    session.simulateAccountSwitch('student2');
    await _waitUntil(() => coordinator.controller?.username == 'student2');

    expect(mail.monitorStops, 1);
    expect(mail.monitorStarts, 2);
  });

  test(
    'fallback refresh retries inbox monitoring after a startup failure',
    () async {
      await const SharedPreferencesMailRadarStore().grantConsent('student');
      final session = _BackgroundSessionController();
      final mail = _MonitoringMailService()..monitorFailuresRemaining = 1;
      final coordinator = MailRadarBackgroundCoordinator(
        sessionController: session,
        assistantService: _BackgroundAssistantService(),
        mailService: mail,
        pollInterval: const Duration(milliseconds: 10),
      );
      addTearDown(() {
        coordinator.dispose();
        session.dispose();
      });

      coordinator.start();
      await _waitUntil(() => mail.monitorStarts >= 2);

      expect(coordinator.controller, isNotNull);
    },
  );

  test('remote access disabled keeps radar unavailable and idle', () async {
    await const SharedPreferencesMailRadarStore().grantConsent('student');
    final session = _BackgroundSessionController();
    final mail = _MonitoringMailService();
    final coordinator = MailRadarBackgroundCoordinator(
      sessionController: session,
      assistantService: _BackgroundAssistantService(mailRadarEnabled: false),
      mailService: mail,
      pollInterval: Duration.zero,
    );
    addTearDown(() {
      coordinator.dispose();
      session.dispose();
    });

    coordinator.start();
    await _waitUntil(() => coordinator.availabilityKnown);

    expect(coordinator.isFeatureAvailable, isFalse);
    expect(coordinator.controller, isNull);
    expect(mail.monitorStarts, 0);
  });

  test(
    'temporary capability failure keeps the last trusted availability',
    () async {
      await const SharedPreferencesMailRadarStore().grantConsent('student');
      final session = _BackgroundSessionController();
      final assistant = _BackgroundAssistantService();
      final coordinator = MailRadarBackgroundCoordinator(
        sessionController: session,
        assistantService: assistant,
        mailService: _MonitoringMailService(),
        pollInterval: Duration.zero,
      );
      addTearDown(() {
        coordinator.dispose();
        session.dispose();
      });

      coordinator.start();
      await coordinator.ensureReady();
      expect(coordinator.isFeatureAvailable, isTrue);

      assistant.failCapabilities = true;

      expect(await coordinator.refreshFeatureAvailability(), isTrue);
      expect(coordinator.isFeatureAvailable, isTrue);
      expect(coordinator.controller, isNotNull);
    },
  );

  test(
    'revocation between capability check and snapshot leaves no runtime',
    () async {
      await const SharedPreferencesMailRadarStore().grantConsent('student');
      final session = _BackgroundSessionController();
      final mail = _MonitoringMailService();
      final coordinator = MailRadarBackgroundCoordinator(
        sessionController: session,
        assistantService: _RevokedSnapshotAssistantService(),
        mailService: mail,
        pollInterval: Duration.zero,
      );
      addTearDown(() {
        coordinator.dispose();
        session.dispose();
      });

      coordinator.start();
      expect(await coordinator.ensureReady(), isNull);

      expect(coordinator.isFeatureAvailable, isFalse);
      expect(coordinator.controller, isNull);
      expect(mail.monitorStarts, 0);
    },
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for background mail-radar state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

MailMessageSummary _summary(int uid) => MailMessageSummary(
  uid: uid,
  subject: 'Mail $uid',
  sender: 'BNBU <notice@bnbu.edu.cn>',
  preview: '',
  hasHtmlBody: false,
  // These tests exercise background coordination, not the lookback boundary.
  date: _fixtureNow
      .subtract(const Duration(days: 1))
      .add(Duration(minutes: uid)),
  isSeen: false,
  hasAttachments: false,
  folder: MailFolder.inbox,
  mailboxUidValidity: 77,
);

class _BackgroundSessionController extends AppSessionController {
  bool _loggedIn = true;
  String _username = 'student';

  @override
  bool get isLoggedIn => _loggedIn;

  @override
  String? get username => _loggedIn ? _username : null;

  @override
  Future<MailAccessCredentials?> loadMailAccessCredentials() async => _loggedIn
      ? MailAccessCredentials(
          userId: _username,
          emailAddress: '$_username@mail.bnbu.edu.cn',
          password: 'test-only',
        )
      : null;

  void simulateAccountSwitch(String username) {
    _username = username;
    notifyListeners();
  }

  void simulateLogout() {
    _loggedIn = false;
    notifyListeners();
  }
}

class _MonitoringMailService extends MailService implements MailInboxMonitor {
  final messages = <MailMessageSummary>[_summary(1)];
  final _changes = StreamController<void>.broadcast();
  int monitorStarts = 0;
  int monitorStops = 0;
  int monitorFailuresRemaining = 0;

  @override
  Stream<void> get inboxChanges => _changes.stream;

  void emitNewMail() => _changes.add(null);

  @override
  Future<void> startInboxMonitoring({
    required MailAccessCredentials credentials,
  }) async {
    monitorStarts++;
    if (monitorFailuresRemaining > 0) {
      monitorFailuresRemaining--;
      throw const MailServiceException('monitor unavailable');
    }
  }

  @override
  Future<void> stopInboxMonitoring() async {
    monitorStops++;
  }

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async => MailFolderSnapshot(
    emailAddress: credentials.emailAddress,
    incomingServer: 'mail.bnbu.edu.cn',
    outgoingServer: 'mail.bnbu.edu.cn',
    messages: page == 1 ? List.of(messages) : const [],
    fetchedAt: _fixtureNow,
    folder: folder,
    totalMessages: messages.length,
    currentPage: page,
    pageSize: pageSize,
    mailboxUidValidity: 77,
  );

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) async => MailMessageDetail(
    uid: uid,
    subject: 'Mail $uid',
    sender: 'BNBU <notice@bnbu.edu.cn>',
    recipients: credentials.emailAddress,
    cc: null,
    date: _summary(uid).date,
    body: 'Campus notice.',
    htmlBody: null,
    isSeen: false,
    attachments: const [],
    folder: folder,
    mailboxUidValidity: 77,
  );

  @override
  Future<void> close() async {
    await _changes.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BackgroundAssistantService
    implements
        AiAssistantService,
        AiAssistantAttachmentService,
        AiAssistantMailRadarService {
  _BackgroundAssistantService({this.mailRadarEnabled = true});

  final bool mailRadarEnabled;
  final List<String> targetLanguages = [];
  bool failCapabilities = false;

  @override
  Future<AssistantCapabilities> loadCapabilities(String username) async {
    if (failCapabilities) {
      throw const AiAssistantNetworkException('temporary capability failure');
    }
    return AssistantCapabilities(
      available: true,
      model: 'ci-model',
      contextSources: const {},
      actions: const {},
      storesConversationContent: true,
      purchaseApiAvailable: false,
      mailRadarEnabled: mailRadarEnabled,
    );
  }

  @override
  Future<bool> isEnabled(String username) async => true;

  @override
  Future<AssistantChatResult> chat({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required AssistantContextPayload context,
    String? clientRequestId,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async => _result();

  @override
  Future<AssistantChatResult> chatWithAttachments({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required AssistantContextPayload context,
    required List<AssistantInputAttachment> attachments,
    String? clientRequestId,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async => _result();

  @override
  Future<MailRadarRemoteAnalysis> analyzeMailRadar({
    required String username,
    required MailRadarRemoteRequest request,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    targetLanguages.add(request.targetLanguageTag);
    return MailRadarRemoteAnalysis(
      clientRequestId: request.clientRequestId,
      result: {
        'summary_zh': request.targetLanguageTag == 'en'
            ? 'Campus notice'
            : '校园通知',
        'needs_translation': false,
        'translation_zh': '',
        'priority': 'normal',
        'category': 'notice',
        'is_direct_correspondence': false,
        'sender_role': 'department',
        'action_zh': '',
        'deadline_text': '',
        'related_thread_key': 'notice',
      },
      toolUses: const [],
      memorySuggestions: const [],
    );
  }

  AssistantChatResult _result() => AssistantChatResult(
    requestId: 'background-radar',
    answer:
        '{"summary_zh":"校园通知","needs_translation":false,"translation_zh":"","priority":"normal","category":"notice","is_direct_correspondence":false,"sender_role":"department","action_zh":"","deadline_text":"","related_thread_key":"notice"}',
    actions: const [],
    usage: const AssistantTokenUsage(
      inputTokens: 1,
      outputTokens: 1,
      totalTokens: 2,
    ),
    quota: AssistantQuota(
      periodStart: DateTime(2026, 8, 1),
      periodEnd: DateTime(2026, 9, 1),
      monthlyQuotaTokens: 100,
      creditBalanceTokens: 0,
      usedTokens: 2,
      reservedTokens: 0,
      remainingTokens: 98,
    ),
  );

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RevokedSnapshotAssistantService extends _BackgroundAssistantService
    implements AiAssistantMailRadarSyncService {
  @override
  Future<MailRadarSnapshot> loadMailRadar(String username) {
    throw const AiAssistantMailRadarUnavailableException();
  }

  @override
  Future<MailRadarSnapshot> saveMailRadar(
    String username, {
    required int expectedVersion,
    required List<MailRadarItem> items,
  }) {
    throw const AiAssistantMailRadarUnavailableException();
  }
}
