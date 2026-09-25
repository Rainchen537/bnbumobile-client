import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';

import '../models/mail_models.dart';
import '../models/mail_radar_models.dart';
import '../models/assistant_models.dart';
import '../services/ai_assistant_service.dart';
import '../services/mail_radar_analyzer.dart';
import '../services/mail_radar_store.dart';
import '../services/mail_radar_rule_store.dart';
import '../services/mail_service.dart';
import '../services/mail_source_service.dart';

class MailRadarInlineImage {
  const MailRadarInlineImage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class MailRadarController extends ChangeNotifier {
  static const defaultAnalysisTimeout = Duration(seconds: 90);
  static const maxConcurrentAnalyses = 2;
  static const maxAnalysisPasses = 2;
  static const providerRetryCooldown = Duration(minutes: 2);

  MailRadarController({
    required this.username,
    required this.credentials,
    required this.mailService,
    required this.analyzer,
    this.syncService,
    this.ruleStore = const MailRadarRuleStore(),
    MailRadarStore? store,
    DateTime Function()? now,
    Duration analysisTimeout = defaultAnalysisTimeout,
    Future<void> Function(Duration)? retryDelay,
    String Function()? targetLanguageTagProvider,
    this.onRemoteAccessUnavailable,
  }) : store =
           store ??
           (syncService is MailRadarPreferenceSyncService
               ? SyncedMailRadarStore(
                   local: const SharedPreferencesMailRadarStore(),
                   remote: syncService as MailRadarPreferenceSyncService,
                 )
               : const SharedPreferencesMailRadarStore()),
       _now = now ?? DateTime.now,
       _analysisTimeout = analysisTimeout,
       _retryDelay = retryDelay ?? Future<void>.delayed,
       _targetLanguageTagProvider =
           targetLanguageTagProvider ?? _defaultTargetLanguageTag;

  final String username;
  final MailAccessCredentials credentials;
  final MailService mailService;
  final MailRadarAnalyzer analyzer;
  final AiAssistantMailRadarSyncService? syncService;
  final VoidCallback? onRemoteAccessUnavailable;
  final MailRadarStore store;
  final MailRadarRuleStore ruleStore;
  List<MailRadarRule> _rules = [];
  List<MailRadarRule> get rules => List.unmodifiable(_rules);
  final DateTime Function() _now;
  final Duration _analysisTimeout;
  final Future<void> Function(Duration) _retryDelay;
  final String Function() _targetLanguageTagProvider;
  final Map<String, Future<List<MailRadarInlineImage>>> _inlineImageCache = {};
  final Map<String, Future<MailMessageDetail>> _messageDetailCache = {};
  final Map<String, Future<List<MailAttachment>>> _attachmentListCache = {};
  final Map<String, String> _activeSubjects = {};
  int _analysesInFlight = 0;
  final List<Completer<void>> _analysisWaiters = [];
  Future<void> _storeMutationQueue = Future<void>.value();
  Future<void>? _activeScan;
  bool _scanRequestedWhileBusy = false;
  bool _stopCurrentScanForProvider = false;
  DateTime? _providerRetryAt;

  List<MailRadarItem> _items = const [];
  bool _hasConsent = false;
  bool _accountStopObserved = false;
  bool _enabled = false;
  int _lookbackDays = mailRadarDefaultLookbackDays;
  bool _isLoading = true;
  bool _isScanning = false;
  bool _disposed = false;
  int _processed = 0;
  int _checked = 0;
  int _total = 0;
  int _failed = 0;
  int _inboxTotal = 0;
  int _eligibleTotal = 0;
  bool _isRetryPass = false;
  String? _error;
  int _operationGeneration = 0;
  int _remoteVersion = 0;

  List<MailRadarItem> get items => _items;
  List<MailRadarItem> get visibleItems {
    final cutoff = _now().subtract(Duration(days: _lookbackDays));
    return _items
        .where(
          (item) =>
              !(analyzer is MailSourceRadarAnalyzer &&
                  (analyzer as MailSourceRadarAnalyzer).isSecretBlocked(
                    item.key,
                  )) &&
              !(analyzer is MailSourceRadarAnalyzer &&
                  item.membership != MailRadarMembership.included &&
                  (analyzer as MailSourceRadarAnalyzer).isNotSelected(
                    item.key,
                  )) &&
              item.membership != MailRadarMembership.excluded &&
              !item.receivedAt.isBefore(
                _now().subtract(const Duration(days: 60)),
              ) &&
              (item.membership == MailRadarMembership.included ||
                  !item.receivedAt.isBefore(cutoff)),
        )
        .toList(growable: false);
  }

  bool get hasConsent => _hasConsent;

  Future<void> setRangeChoice(int days) async {
    if (days == 0) {
      await setEnabled(false);
      return;
    }
    if (!mailRadarAllowedLookbackDays.contains(days)) {
      throw const FormatException('邮件雷达最多分析近60天。');
    }
    if (store case final SyncedMailRadarStore synced) {
      await synced.setRangeChoice(username, days);
    } else {
      await store.setLookbackDays(username, days);
      if (!_hasConsent) await store.grantConsent(username);
      await store.setEnabled(username, true);
    }
    _operationGeneration++;
    _accountStopObserved = false;
    _hasConsent = true;
    _enabled = true;
    _lookbackDays = days;
    _scanRequestedWhileBusy = false;
    _clearProviderRetry();
    _notify();
    unawaited(scan());
  }

  Future<void> acceptSourceRangeChoice(int days, int serverVersion) async {
    _operationGeneration++;
    _scanRequestedWhileBusy = false;
    _clearProviderRetry();
    if (store case final SyncedMailRadarStore synced) {
      await synced.acceptConsentReceipt(
        username,
        MailRadarPreferenceSnapshot(
          serverVersion,
          MailRadarPreferences(
            hasConsent: true,
            enabled: days > 0,
            lookbackDays: days > 0 ? days : _lookbackDays,
          ),
        ),
      );
      await refreshPreferences();
      if (_enabled) unawaited(scan());
    } else {
      await setRangeChoice(days);
    }
  }

  Future<void> includeMessage(MailMessageSummary message) =>
      setMessageMembership([message], MailRadarMembership.included);

  Future<void> excludeMessage(MailMessageSummary message) =>
      setMessageMembership([message], MailRadarMembership.excluded);

  Future<void> setMessageMembership(
    List<MailMessageSummary> messages,
    MailRadarMembership membership,
  ) async {
    if (_disposed || messages.isEmpty) return;
    if (membership == MailRadarMembership.included &&
        (!_hasConsent || !_enabled)) {
      throw const FormatException('请先选择邮件雷达的分析天数。');
    }
    if (!_hasConsent) return;
    if (messages.any(
      (message) =>
          message.mailboxUidValidity == null ||
          (membership == MailRadarMembership.included &&
              (message.date == null ||
                  message.date!.isBefore(
                    _now().subtract(const Duration(days: 60)),
                  ))),
    )) {
      throw const FormatException('只能加入近60天且身份有效的邮件。');
    }
    // A batch creates missing tombstones once and publishes a single user edit.
    await _ensureEveryCandidateIsListed(messages);
    final keys = messages
        .map(
          (message) => mailRadarMessageKey(
            message.folder,
            message.mailboxUidValidity!,
            message.uid,
          ),
        )
        .toSet();
    await _withStoreMutation(() async {
      final next = _items
          .map(
            (item) => !keys.contains(item.key)
                ? item
                : item.copyWith(
                    membership: membership,
                    analysisPending:
                        analyzer is MailSourceRadarAnalyzer &&
                            membership == MailRadarMembership.included
                        ? true
                        : item.analysisPending,
                    userFieldTimes: _stamp(item, 'membership'),
                    updatedAt: _now(),
                  ),
          )
          .toList();
      await _persistItems(next);
      _notify();
    });
    if (membership == MailRadarMembership.included) unawaited(scan());
  }

  Future<void> refreshOriginalReadStates() async {
    final service = mailService;
    if (service is! MailFlagReader || !_hasConsent || _disposed) return;
    final generation = _operationGeneration;
    final requested = {for (final item in visibleItems) item.key: item};
    if (requested.isEmpty) return;
    final flags = await (service as MailFlagReader).readSeenFlags(
      credentials: credentials,
      messages: requested.values
          .map(
            (item) => MailMessageIdentity(
              folder: item.sourceFolder,
              uid: item.uid,
              mailboxUidValidity: item.mailboxUidValidity,
            ),
          )
          .toList(),
    );
    if (_disposed || generation != _operationGeneration) return;
    await _withStoreMutation(() async {
      if (_disposed || generation != _operationGeneration) return;
      var changed = false;
      final byKey = {
        for (final entry in flags.entries)
          mailRadarMessageKey(
            entry.key.folder,
            entry.key.mailboxUidValidity,
            entry.key.uid,
          ): entry.value,
      };
      final next = _items.map((item) {
        final original = requested[item.key];
        final seen = byKey[item.key];
        // A late server read must not undo a newer swipe or remote merge.
        if (original == null ||
            seen == null ||
            seen == item.originalIsSeen ||
            original.originalIsSeen != item.originalIsSeen ||
            original.userFieldTimes['original_read'] !=
                item.userFieldTimes['original_read']) {
          return item;
        }
        changed = true;
        return item.copyWith(
          originalIsSeen: seen,
          userFieldTimes: _stamp(item, 'original_read'),
          updatedAt: _now(),
        );
      }).toList();
      if (changed) {
        await _persistItems(next);
        _notify();
      }
    });
  }

  Future<void> recordOriginalReadState(
    List<MailMessageSummary> messages,
    bool seen,
  ) => _withStoreMutation(() async {
    final keys = messages
        .where((message) => message.mailboxUidValidity != null)
        .map(
          (message) => mailRadarMessageKey(
            message.folder,
            message.mailboxUidValidity!,
            message.uid,
          ),
        )
        .toSet();
    if (!_items.any((item) => keys.contains(item.key))) return;
    final next = _items
        .map(
          (item) => !keys.contains(item.key)
              ? item
              : item.copyWith(
                  originalIsSeen: seen,
                  userFieldTimes: _stamp(item, 'original_read'),
                  updatedAt: _now(),
                ),
        )
        .toList();
    await _persistItems(next);
    _notify();
  });
  bool get enabled => _enabled;
  int get lookbackDays => _lookbackDays;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  int get processed => _processed;
  int get checked => _checked;
  int get total => _total;
  int get failed => _failed;
  int get inboxTotal => _inboxTotal;
  int get eligibleTotal => _eligibleTotal;
  int get analyzedCount =>
      visibleItems.where((item) => !item.analysisPending).length;
  int get pendingCount =>
      visibleItems.where((item) => item.analysisPending).length;
  List<({MailRadarItem item, AssistantMemorySuggestion suggestion})>
  get pendingMemorySuggestions => [
    for (final item in visibleItems)
      for (final suggestion in item.memorySuggestions)
        if (suggestion.isPending) (item: item, suggestion: suggestion),
  ];
  bool get isRetryPass => _isRetryPass;
  int get activeAnalyses => _activeSubjects.length;
  bool get isWaitingForProvider => _providerRetryAt != null;
  DateTime? get providerRetryAt => _providerRetryAt;
  String? get currentSubject =>
      _activeSubjects.isEmpty ? null : _activeSubjects.values.first;
  String? get error => _error;

  static String _defaultTargetLanguageTag() =>
      mailRadarDefaultTargetLanguageTag;

  String get targetLanguageTag =>
      normalizeMailRadarTargetLanguageTag(_targetLanguageTagProvider());

  bool needsDetailTranslationRefresh(MailRadarItem item) =>
      !item.analysisPending &&
      !item.isRecallNotice &&
      (item.translationZh.trim().isEmpty || item.bodyCoverage == 'unknown') &&
      item.analysisContractVersion != mailRadarAnalysisContractVersion;

  /// Lazily upgrades an old completed result when the user opens its detail.
  /// This avoids spending quota on a full historical rescan while ensuring a
  /// foreign-language message can receive the translation introduced by the
  /// current analysis contract.
  Future<MailRadarItem> prepareItemForDetail(MailRadarItem item) async {
    if (!needsDetailTranslationRefresh(item) ||
        !_hasConsent ||
        !_enabled ||
        _disposed) {
      return item;
    }
    final generation = _operationGeneration;
    try {
      final refreshed = await _analyzeMessage(item.toSummary(), generation);
      if (!_isOperationCurrent(generation)) return item;
      await _persistAnalyzedItem(refreshed);
      return _items.firstWhere(
        (candidate) => candidate.key == item.key,
        orElse: () => refreshed,
      );
    } on AiAssistantMailRadarUnavailableException catch (error) {
      _handleRemoteAccessUnavailable(accountStopped: error.stoppedByPreference);
      return item;
    }
  }

  Future<void> initialize() async {
    final preferences = await store.loadPreferences(username);
    try {
      _rules = await ruleStore.load(username);
    } catch (_) {
      _error = '分类规则暂时无法读取。';
    }
    _hasConsent = preferences.hasConsent;
    _enabled = preferences.enabled;
    _lookbackDays =
        mailRadarAllowedLookbackDays.contains(preferences.lookbackDays)
        ? preferences.lookbackDays
        : preferences.lookbackDays > 60
        ? 60
        : mailRadarDefaultLookbackDays;
    if (_lookbackDays != preferences.lookbackDays) {
      await store.setLookbackDays(username, _lookbackDays);
    }
    _items = (await store.load(username)).toList(growable: false);
    if (_hasConsent && syncService != null) {
      try {
        await _synchronizeRemote();
      } on AiAssistantMailRadarUnavailableException catch (error) {
        _handleRemoteAccessUnavailable(
          accountStopped: error.stoppedByPreference,
        );
      } catch (error) {
        _error = '暂时无法同步其他设备的雷达结果：${_displayError(error)}';
      }
    }
    _sort();
    _isLoading = false;
    _notify();
  }

  Future<void> refreshPreferences() async {
    final rules = await ruleStore.load(username);
    if (_disposed) return;
    _rules = rules;
    if (store is! SyncedMailRadarStore || _disposed) return;
    final preferences = await store.loadPreferences(username);
    if (store is SyncedMailRadarStore) {
      _error = (store as SyncedMailRadarStore).syncError;
    }
    if (_disposed) return;
    if (_accountStopObserved &&
        (store is! SyncedMailRadarStore ||
            !(store as SyncedMailRadarStore).remoteConfirmed)) {
      _enabled = false;
      _notify();
      return;
    }
    _accountStopObserved = false;
    if (_hasConsent == preferences.hasConsent &&
        _enabled == preferences.enabled &&
        _lookbackDays == preferences.lookbackDays) {
      _notify();
      return;
    }
    _operationGeneration++;
    _hasConsent = preferences.hasConsent;
    _enabled = preferences.enabled;
    _lookbackDays = preferences.lookbackDays;
    _scanRequestedWhileBusy = false;
    _clearProviderRetry();
    _notify();
  }

  Future<void> grantConsentAndScan() async {
    await store.grantConsent(username);
    _accountStopObserved = false;
    _hasConsent = true;
    _enabled = true;
    _notify();
    if (syncService != null) {
      try {
        await _synchronizeRemote();
      } on AiAssistantMailRadarUnavailableException catch (error) {
        _handleRemoteAccessUnavailable(
          accountStopped: error.stoppedByPreference,
        );
        return;
      }
    }
    await scan();
  }

  Future<void> setEnabled(bool enabled) async {
    if (!_hasConsent || (_enabled == enabled && enabled)) return;
    if (!enabled) {
      _enabled = false;
      _operationGeneration++;
      _scanRequestedWhileBusy = false;
      _clearProviderRetry();
      _notify();
    }
    await store.setEnabled(username, enabled);
    _enabled = enabled;
    if (enabled) _accountStopObserved = false;
    if (store is SyncedMailRadarStore) {
      _error = (store as SyncedMailRadarStore).syncError;
    }
    _operationGeneration++;
    _scanRequestedWhileBusy = false;
    _clearProviderRetry();
    _notify();
    if (enabled) await scan();
  }

  Future<void> setLookbackDays(int days) async {
    if (!mailRadarAllowedLookbackDays.contains(days) || days == _lookbackDays) {
      return;
    }
    await store.setLookbackDays(username, days);
    _lookbackDays = days;
    _operationGeneration++;
    _scanRequestedWhileBusy = false;
    _clearProviderRetry();
    _notify();
    if (_hasConsent && _enabled) await scan();
  }

  Future<void> revokeConsent() async {
    await store.revokeConsent(username);
    _operationGeneration++;
    _scanRequestedWhileBusy = false;
    _clearProviderRetry();
    _hasConsent = false;
    _enabled = false;
    _isScanning = false;
    _activeSubjects.clear();
    _notify();
  }

  Future<void> scan() => _startScan(forceProviderRetry: false);

  Future<void> retryNow() => _startScan(forceProviderRetry: true);

  Future<void> _startScan({required bool forceProviderRetry}) {
    if (!_hasConsent || !_enabled || _disposed) return Future<void>.value();
    final retryAt = _providerRetryAt;
    if (!forceProviderRetry && retryAt != null && _now().isBefore(retryAt)) {
      return Future<void>.value();
    }
    final activeScan = _activeScan;
    if (activeScan != null) {
      if (!_stopCurrentScanForProvider) _scanRequestedWhileBusy = true;
      return activeScan;
    }
    _clearProviderRetry();
    final completer = Completer<void>();
    _activeScan = completer.future;
    unawaited(() async {
      try {
        do {
          _scanRequestedWhileBusy = false;
          final generation = _operationGeneration;
          await _scanOnce(generation);
        } while (_scanRequestedWhileBusy &&
            _providerRetryAt == null &&
            !_disposed &&
            _hasConsent &&
            _enabled);
        _activeScan = null;
        completer.complete();
      } catch (error, stackTrace) {
        _activeScan = null;
        completer.completeError(error, stackTrace);
      }
    }());
    return completer.future;
  }

  Future<void> _scanOnce(int generation) async {
    _stopCurrentScanForProvider = false;
    _isScanning = true;
    _processed = 0;
    _checked = 0;
    _total = 0;
    _failed = 0;
    _error = null;
    _isRetryPass = false;
    _notify();
    try {
      if (syncService != null) await _synchronizeRemote();
      if (!_isOperationCurrent(generation)) return;
      if (analyzer case final MailSourceRadarAnalyzer source) {
        try {
          await source.collect(
            username: username,
            credentials: credentials,
            mailService: mailService,
            active: () => _isOperationCurrent(generation),
          );
          if (source.collectionError != null) {
            _error = const MailSourceException('invalid_request').toString();
          }
        } on MailSourceException catch (error) {
          // Collection uses provider budget; acquiring existing results does not.
          // Consent/device/epoch failures still stop the entire flow.
          if (!{
            'platform_budget_exceeded',
            'provider_unavailable',
            'provider_http_429',
            'provider_http_403',
            'invalid_request',
          }.contains(error.code)) {
            rethrow;
          }
          _error = error.toString();
        }
      }
      if (!_isOperationCurrent(generation)) return;
      final candidates = await _loadInboxWithinRange(generation);
      if (!_isOperationCurrent(generation)) return;
      _eligibleTotal = candidates.length;
      await _ensureEveryCandidateIsListed(candidates);
      final existingByKey = {for (final item in _items) item.key: item};
      final currentLanguageTag = targetLanguageTag;
      final pending =
          candidates
              .where((message) {
                final validity = message.mailboxUidValidity;
                if (validity == null) return false;
                final existing =
                    existingByKey[mailRadarMessageKey(
                      message.folder,
                      validity,
                      message.uid,
                    )];
                return existing?.membership != MailRadarMembership.excluded &&
                    (existing == null ||
                        (analyzer is MailSourceRadarAnalyzer &&
                            (analyzer as MailSourceRadarAnalyzer)
                                .needsResultRefresh(existing)) ||
                        existing.analysisPending ||
                        existing.analysisLanguageTag != currentLanguageTag);
              })
              .toList(growable: false)
            ..sort((a, b) {
              final receivedOrder = (b.date ?? DateTime(1970)).compareTo(
                a.date ?? DateTime(1970),
              );
              if (receivedOrder != 0) return receivedOrder;
              final speedOrder = _analysisSpeedRank(
                a,
              ).compareTo(_analysisSpeedRank(b));
              if (speedOrder != 0) return speedOrder;
              return b.uid.compareTo(a.uid);
            });
      _total = pending.length;
      _notify();
      var pass = 1;
      var passQueue = pending;
      while (_isOperationCurrent(generation) && passQueue.isNotEmpty) {
        _isRetryPass = pass > 1;
        _notify();
        final deferred = <MailMessageSummary>[];
        var nextIndex = 0;
        Future<void> runWorker() async {
          while (_isOperationCurrent(generation)) {
            // An IMAP IDLE event or foreground refresh may have discovered a
            // newer message while the current workers were busy. Do not keep
            // taking older backlog entries; finish active requests, then let
            // the queued scan rebuild a newest-first queue.
            if (_scanRequestedWhileBusy || _stopCurrentScanForProvider) return;
            final index = nextIndex;
            if (index >= passQueue.length) return;
            nextIndex++;
            final retryLater = await _processPendingMessage(
              passQueue[index],
              allowDeferredRetry: pass < maxAnalysisPasses,
              countAsChecked: pass == 1,
              generation: generation,
            );
            if (retryLater) deferred.add(passQueue[index]);
          }
        }

        final workerCount = passQueue.length < maxConcurrentAnalyses
            ? passQueue.length
            : maxConcurrentAnalyses;
        await Future.wait([
          for (var index = 0; index < workerCount; index++) runWorker(),
        ]);
        if (_scanRequestedWhileBusy) break;
        if (deferred.isEmpty || !_isOperationCurrent(generation)) break;
        pass++;
        passQueue = List<MailMessageSummary>.of(deferred, growable: false);
        await _retryDelay(const Duration(milliseconds: 800));
      }
    } on AiAssistantMailRadarUnavailableException catch (error) {
      _handleRemoteAccessUnavailable(accountStopped: error.stoppedByPreference);
    } catch (error) {
      _error = error.toString();
    } finally {
      _activeSubjects.clear();
      _isRetryPass = false;
      _isScanning = false;
      _notify();
    }
  }

  Future<bool> _processPendingMessage(
    MailMessageSummary summary, {
    required bool allowDeferredRetry,
    required bool countAsChecked,
    required int generation,
  }) async {
    final activeKey = mailRadarMessageKey(
      summary.folder,
      summary.mailboxUidValidity ?? 0,
      summary.uid,
    );
    _activeSubjects[activeKey] = summary.subject;
    _notify();
    var retryLater = false;
    try {
      final item = await _analyzeMessage(summary, generation);
      if (_isOperationCurrent(generation)) {
        await _persistAnalyzedItem(item);
      }
    } on AiAssistantMailRadarUnavailableException catch (error) {
      _handleRemoteAccessUnavailable(accountStopped: error.stoppedByPreference);
    } on MailSourcePending {
      // The durable server job continues; the normal scheduler polls later.
    } on MailSourceSkipped {
      // Classification is separate from user membership and local completion.
    } on AiAssistantMailRadarNewRequestRequiredException catch (error) {
      _stopCurrentScanForProvider = true;
      _scanRequestedWhileBusy = false;
      _providerRetryAt ??= _now().add(providerRetryCooldown);
      if (_isOperationCurrent(generation)) {
        await _replaceAnalysisRequestId(
          activeKey,
          createAssistantClientRequestId(),
        );
      }
      // The dedicated server request has already exhausted its bounded
      // Provider recovery. Retrying immediately would keep all worker slots
      // occupied during a shared upstream outage and eventually surface the
      // controller's 90-second guard as a misleading mail timeout. Keep the
      // item pending with its fresh request ID; the next background scan will
      // retry it after the provider has had time to recover.
      _failed++;
      _error = _displayError(error);
    } catch (error) {
      retryLater = allowDeferredRetry && _shouldRetry(error);
      if (!retryLater) {
        _failed++;
        _error = _displayError(error);
      }
    } finally {
      _activeSubjects.remove(activeKey);
      if (countAsChecked) _checked++;
      if (!retryLater) _processed++;
      _notify();
    }
    return retryLater;
  }

  Future<MailRadarItem> _analyzeMessage(
    MailMessageSummary summary,
    int generation,
  ) async {
    while (_analysesInFlight >= maxConcurrentAnalyses) {
      if (!_isOperationCurrent(generation)) {
        throw const AiAssistantOperationCancelledException();
      }
      final waiter = Completer<void>();
      _analysisWaiters.add(waiter);
      await waiter.future;
    }
    if (!_isOperationCurrent(generation)) {
      throw const AiAssistantOperationCancelledException();
    }
    _analysesInFlight++;
    try {
      return await _analyzeMessageWithinSlot(summary, generation);
    } finally {
      _analysesInFlight--;
      if (_analysisWaiters.isNotEmpty) _analysisWaiters.removeAt(0).complete();
    }
  }

  Future<MailRadarItem> _analyzeMessageWithinSlot(
    MailMessageSummary summary,
    int generation,
  ) async {
    final key = mailRadarMessageKey(
      summary.folder,
      summary.mailboxUidValidity ?? 0,
      summary.uid,
    );
    MailRadarItem? pendingItem;
    for (final item in _items) {
      if (item.key == key) {
        pendingItem = item;
        break;
      }
    }
    var clientRequestId = pendingItem?.analysisRequestId ?? '';
    final currentLanguageTag = targetLanguageTag;
    if (pendingItem?.analysisLanguageTag != currentLanguageTag ||
        pendingItem?.analysisContractVersion !=
            mailRadarAnalysisContractVersion) {
      clientRequestId = '';
    }
    if (clientRequestId.trim().isEmpty) {
      clientRequestId = createStableMailRadarClientRequestId(
        username: username,
        mailboxUidValidity: summary.mailboxUidValidity!,
        uid: summary.uid,
        folder: summary.folder,
        targetLanguageTag: currentLanguageTag,
      );
      await _ensureAnalysisRequestId(
        key,
        clientRequestId,
        languageTag: currentLanguageTag,
      );
    }
    var operationActive = true;
    try {
      return await (() async {
        final detail = await mailService.readMessage(
          credentials: credentials,
          folder: summary.folder,
          uid: summary.uid,
          expectedMailboxUidValidity: summary.mailboxUidValidity,
          markAsSeen: false,
        );
        if (analyzer case final MailSourceRadarAnalyzer source) {
          return source.analyze(
            clientRequestId: clientRequestId,
            username: username,
            credentials: credentials,
            summary: summary,
            detail: detail,
            mailService: mailService,
            manual: pendingItem?.membership == MailRadarMembership.included,
            isOperationActive: () =>
                operationActive && _isOperationCurrent(generation),
          );
        }
        return analyzer.analyze(
          clientRequestId: clientRequestId,
          username: username,
          credentials: credentials,
          summary: summary,
          detail: detail,
          mailService: mailService,
          isOperationActive: () =>
              operationActive && _isOperationCurrent(generation),
        );
      })().timeout(
        _analysisTimeout,
        onTimeout: () {
          operationActive = false;
          throw TimeoutException('单封邮件分析超过安全时限，已释放该分析位置；刷新后会自动重试。');
        },
      );
    } finally {
      operationActive = false;
    }
  }

  Future<void> _persistAnalyzedItem(MailRadarItem item) {
    return _withStoreMutation(() async {
      final existingIndex = _items.indexWhere(
        (candidate) => candidate.key == item.key,
      );
      if (existingIndex >= 0 &&
          !_items[existingIndex].analysisPending &&
          _items[existingIndex].analysisLanguageTag ==
              item.analysisLanguageTag &&
          _items[existingIndex].analysisContractVersion ==
              item.analysisContractVersion) {
        return;
      }
      final rule = _rules.where((rule) => rule.matches(item)).firstOrNull;
      if (rule != null) item = item.copyWith(category: rule.category);
      final next = [..._items];
      if (existingIndex >= 0) {
        final existing = _items[existingIndex];
        next[existingIndex] = item.copyWith(
          membership: existing.membership,
          originalIsSeen: existing.originalIsSeen,
          isUnread: existing.isUnread,
          completed: existing.completed,
          taskStatus: existing.effectiveStatus,
          snoozedUntil: existing.snoozedUntil,
          category: existing.userCorrectedCategory
              ? existing.category
              : item.category,
          userCorrectedCategory: existing.userCorrectedCategory,
          userFieldTimes: existing.userFieldTimes,
          memorySuggestions: item.memorySuggestions.map((suggestion) {
            final old = existing.memorySuggestions
                .where(
                  (entry) =>
                      entry.content == suggestion.content &&
                      entry.memoryType == suggestion.memoryType,
                )
                .firstOrNull;
            return old == null
                ? suggestion
                : suggestion.copyWith(status: old.status);
          }).toList(),
          updatedAt: _now(),
        );
      } else {
        next.add(item.copyWith(isUnread: true, updatedAt: _now()));
      }
      _sortItems(next);
      await _persistItems(next);
      _notify();
    });
  }

  Future<void> _ensureAnalysisRequestId(
    String key,
    String requestId, {
    required String languageTag,
  }) {
    return _withStoreMutation(() async {
      final index = _items.indexWhere((item) => item.key == key);
      if (index < 0) return;
      final existing = _items[index];
      // A completed legacy item is refreshed lazily when its detail opens.
      // Do not mark that old result as current before the new analysis has
      // actually returned, or _persistAnalyzedItem would discard the result.
      if (!existing.analysisPending) return;
      if (existing.analysisRequestId == requestId &&
          existing.analysisLanguageTag == languageTag &&
          existing.analysisContractVersion ==
              mailRadarAnalysisContractVersion) {
        return;
      }
      final next = [..._items];
      next[index] = existing.copyWith(
        analysisRequestId: requestId,
        analysisLanguageTag: languageTag,
        analysisContractVersion: mailRadarAnalysisContractVersion,
        updatedAt: _now(),
      );
      await _persistItems(next);
      _notify();
    });
  }

  Future<void> _replaceAnalysisRequestId(String key, String requestId) {
    return _withStoreMutation(() async {
      final index = _items.indexWhere((item) => item.key == key);
      if (index < 0 || !_items[index].analysisPending) return;
      final next = [..._items];
      next[index] = next[index].copyWith(
        analysisRequestId: requestId,
        analysisLanguageTag: targetLanguageTag,
        analysisContractVersion: mailRadarAnalysisContractVersion,
        updatedAt: _now(),
      );
      await _persistItems(next);
      _notify();
    });
  }

  Future<void> _ensureEveryCandidateIsListed(
    List<MailMessageSummary> candidates,
  ) {
    return _withStoreMutation(() async {
      final existingKeys = _items.map((item) => item.key).toSet();
      final additions = <MailRadarItem>[];
      for (final summary in candidates) {
        final validity = summary.mailboxUidValidity;
        if (validity == null) continue;
        final key = mailRadarMessageKey(summary.folder, validity, summary.uid);
        if (!existingKeys.add(key)) continue;
        additions.add(
          MailRadarItem(
            sourceFolder: summary.folder,
            originalIsSeen: summary.isSeen,
            key: key,
            uid: summary.uid,
            mailboxUidValidity: validity,
            subject: summary.subject,
            sender: summary.sender,
            recipients: summary.recipients,
            receivedAt: summary.date ?? _now(),
            summaryZh: '等待小U分析',
            translationZh: '',
            priority: MailRadarPriority.normal,
            category: MailRadarCategory.notice,
            senderRole: MailRadarSenderRole.unknown,
            actionZh: '',
            deadlineText: '',
            relatedThreadKey: '',
            attachmentNotes: const [],
            analyzedAt: _now(),
            updatedAt: _now(),
            isUnread: true,
            analysisPending: true,
            analysisRequestId: createStableMailRadarClientRequestId(
              username: username,
              mailboxUidValidity: validity,
              uid: summary.uid,
              folder: summary.folder,
              targetLanguageTag: targetLanguageTag,
            ),
            analysisLanguageTag: targetLanguageTag,
          ),
        );
      }
      if (additions.isEmpty) return;
      final next = [..._items, ...additions];
      _sortItems(next);
      await _persistItems(next);
      _notify();
    });
  }

  bool _shouldRetry(Object error) =>
      !_disposed &&
      error is! AiAssistantQuotaExceededException &&
      error is! AiAssistantConsentRequiredException &&
      error is! AiAssistantOperationCancelledException &&
      error is! TimeoutException;

  int _analysisSpeedRank(MailMessageSummary summary) {
    if (looksLikeMailRecallSubject(summary.subject)) return 0;
    return summary.hasAttachments ? 2 : 1;
  }

  String _displayError(Object error) => error is TimeoutException
      ? error.message ?? '单封邮件分析超过安全时限。'
      : error.toString();

  Future<List<MailMessageSummary>> _loadInboxWithinRange(int generation) async {
    const pageSize = 50;
    final cutoff = _now().subtract(Duration(days: _lookbackDays));
    final results = <String, MailMessageSummary>{};
    int? uidValidity;
    for (var page = 1; ; page++) {
      if (!_isOperationCurrent(generation)) break;
      final snapshot = await mailService.fetchFolder(
        credentials: credentials,
        folder: MailFolder.inbox,
        page: page,
        pageSize: pageSize,
        expectedMailboxUidValidity: page == 1 ? null : uidValidity,
      );
      uidValidity ??= snapshot.mailboxUidValidity;
      _inboxTotal = snapshot.totalMessages;
      var pageIsEntirelyBeforeCutoff = snapshot.messages.isNotEmpty;
      for (final message in snapshot.messages) {
        final date = message.date;
        if (date == null) {
          // Unknown age cannot prove the selected consent window. Continue
          // paging because later headers may still have valid recent dates.
          pageIsEntirelyBeforeCutoff = false;
          continue;
        }
        if (date.isBefore(cutoff)) {
          continue;
        }
        pageIsEntirelyBeforeCutoff = false;
        final validity = message.mailboxUidValidity;
        results['${validity ?? 'unknown'}_${message.uid}'] = message;
      }
      final exhausted = page * pageSize >= snapshot.totalMessages;
      if (exhausted ||
          snapshot.messages.isEmpty ||
          pageIsEntirelyBeforeCutoff) {
        break;
      }
    }
    for (final item in _items) {
      if (item.membership == MailRadarMembership.included &&
          !item.receivedAt.isBefore(
            _now().subtract(const Duration(days: 60)),
          )) {
        results[item.key] = item.toSummary();
      }
    }
    final excluded = _items
        .where((item) => item.membership == MailRadarMembership.excluded)
        .map((item) => item.key)
        .toSet();
    final sorted = results.values
        .where(
          (message) => !excluded.contains(
            mailRadarMessageKey(
              message.folder,
              message.mailboxUidValidity ?? 0,
              message.uid,
            ),
          ),
        )
        .toList(growable: false);
    sorted.sort(
      (a, b) => (b.date ?? DateTime(1970)).compareTo(a.date ?? DateTime(1970)),
    );
    return sorted;
  }

  bool _isOperationCurrent(int generation) =>
      !_disposed &&
      _hasConsent &&
      _enabled &&
      generation == _operationGeneration;

  Future<AssistantMailToolResultContext> queryTasks(
    Map<String, dynamic> args,
  ) async {
    final status = args['status'] ?? 'active';
    final offset = args['offset'] ?? 0;
    if (!_hasConsent ||
        _disposed ||
        status is! String ||
        !{
          'active',
          'all',
          ...MailRadarTaskStatus.values.map((s) => s.name),
        }.contains(status) ||
        offset is! int ||
        offset < 0 ||
        offset > 10000 ||
        args.keys.any((key) => key != 'status' && key != 'offset')) {
      throw const AiAssistantException('邮件雷达不可用或查询参数无效。');
    }
    try {
      await _synchronizeRemote();
    } on AiAssistantMailRadarUnavailableException catch (error) {
      _handleRemoteAccessUnavailable(accountStopped: error.stoppedByPreference);
      rethrow;
    }
    if (!_hasConsent || _disposed) {
      throw const AiAssistantException('邮件雷达不可用。');
    }
    final filtered = visibleItems
        .where(
          (item) =>
              !item.analysisPending &&
              (status == 'all' ||
                  status == 'active' && !item.isResolved ||
                  item.taskStatusAt(_now()).name == status),
        )
        .toList();
    final selected = filtered.skip(offset).take(8).toList();
    final more = offset + selected.length < filtered.length;
    final observed = _now();
    return AssistantMailToolResultContext(
      resultKey:
          'mail-radar:${sha256.convert(utf8.encode('$username:$status:$offset:${observed.toIso8601String()}'))}',
      kind: 'mail_radar',
      observedAt: observed,
      completeness: more
          ? 'truncated'
          : selected.isEmpty
          ? 'empty'
          : 'complete',
      scanComplete: !more,
      nextCursor: more ? '${offset + selected.length}' : '',
      matchedCount: filtered.length,
      scannedCount: visibleItems.length,
      radarLookbackDays: _lookbackDays,
      radarPendingCount: pendingCount,
      messages: [
        for (final item in selected)
          AssistantMailMessageContext(
            uid: item.uid,
            folder: item.sourceFolder.name,
            mailboxUidValidity: item.mailboxUidValidity,
            senderName: item.sender,
            senderEmail: '',
            recipients: '',
            cc: '',
            subject: item.subject,
            receivedAt: item.receivedAt,
            bodyText: '',
            contentState: 'metadata_only',
          ),
      ],
      radarItems: [
        for (final item in selected)
          {
            'folder': item.sourceFolder.name,
            'uid': item.uid,
            'mailbox_uid_validity': item.mailboxUidValidity,
            'status': item.taskStatusAt(_now()).name,
            'summary': item.summaryZh,
            'action': item.actionZh,
            'category': item.category.name,
            'deadline_at': item.deadlineAt?.toUtc().toIso8601String(),
            'deadline_evidence': item.deadlineEvidence,
            'deadline_precision': item.deadlinePrecision,
            'deadline_text': item.deadlineText,
            'body_coverage': item.bodyCoverage,
            'snoozed_until': item.snoozedUntil?.toUtc().toIso8601String(),
            'analyzed_at': item.analyzedAt.toUtc().toIso8601String(),
          },
      ],
    );
  }

  Map<String, String> _stamp(MailRadarItem item, String field) => {
    // Initialize untouched fields from the previous version, never this edit.
    for (final name in [
      'status',
      'category',
      'read',
      'memory',
      'membership',
      'original_read',
    ])
      name:
          item.userFieldTimes[name] ??
          item.syncUpdatedAt.toUtc().toIso8601String(),
    field: _now().toUtc().toIso8601String(),
  };

  Future<void> setTaskStatus(
    MailRadarItem item,
    MailRadarTaskStatus status, {
    DateTime? until,
  }) async {
    if (status == MailRadarTaskStatus.completed) {
      return setCompleted(item, true);
    }
    if (status == MailRadarTaskStatus.snoozed &&
        (until == null || !until.isAfter(_now()))) {
      throw const FormatException('请选择未来时间。');
    }
    await _withStoreMutation(() async {
      final next = _items
          .map(
            (current) => current.key == item.key
                ? current.copyWith(
                    completed: false,
                    taskStatus: status,
                    snoozedUntil: until,
                    updatedAt: _now(),
                    userFieldTimes: _stamp(current, 'status'),
                  )
                : current,
          )
          .toList();
      _sortItems(next);
      await _persistItems(next);
      _notify();
    });
  }

  Future<void> setCompleted(MailRadarItem item, bool completed) async {
    if (completed) {
      await mailService.markMessagesSeen(
        credentials: credentials,
        folder: item.sourceFolder,
        uids: [item.uid],
        expectedMailboxUidValidity: item.mailboxUidValidity,
      );
    }
    await _withStoreMutation(() async {
      final next = _items
          .map(
            (candidate) => candidate.key == item.key
                ? candidate.copyWith(
                    completed: completed,
                    originalIsSeen: completed ? true : candidate.originalIsSeen,
                    taskStatus: completed
                        ? MailRadarTaskStatus.completed
                        : MailRadarTaskStatus.pending,
                    userFieldTimes: {
                      ..._stamp(candidate, 'status'),
                      if (completed)
                        'original_read': _now().toUtc().toIso8601String(),
                      if (completed) 'read': _now().toUtc().toIso8601String(),
                    },
                    isUnread: completed ? false : candidate.isUnread,
                    updatedAt: _now(),
                  )
                : candidate,
          )
          .toList(growable: false);
      _sortItems(next);
      await _persistItems(next);
      _notify();
    });
  }

  Future<void> markOpened(MailRadarItem item) async {
    if (!item.isUnread) return;
    await _withStoreMutation(() async {
      final next = _items
          .map(
            (candidate) => candidate.key == item.key
                ? candidate.copyWith(
                    isUnread: false,
                    updatedAt: _now(),
                    userFieldTimes: _stamp(candidate, 'read'),
                  )
                : candidate,
          )
          .toList(growable: false);
      await _persistItems(next);
      _notify();
    });
  }

  Future<void> saveRule(MailRadarRule rule) async {
    if (MailRadarRule.senderAddress(rule.sender) != rule.sender) {
      throw const FormatException('发件人地址无效。');
    }
    await _withStoreMutation(() async {
      final next = [
        ..._rules.where((entry) => entry.sender != rule.sender),
        rule,
      ];
      await ruleStore.save(username, next);
      _rules = next;
      _notify();
    });
  }

  Future<void> deleteRule(String sender) async {
    await _withStoreMutation(() async {
      final next = _rules.where((rule) => rule.sender != sender).toList();
      await ruleStore.save(username, next);
      _rules = next;
      _notify();
    });
  }

  Future<void> correctCategory(
    MailRadarItem item,
    MailRadarCategory category,
  ) async {
    await _withStoreMutation(() async {
      final next = _items
          .map(
            (candidate) => candidate.key == item.key
                ? candidate.copyWith(
                    category: category,
                    userCorrectedCategory: true,
                    userFieldTimes: _stamp(candidate, 'category'),
                    updatedAt: _now(),
                  )
                : candidate,
          )
          .toList(growable: false);
      _sortItems(next);
      await _persistItems(next);
      _notify();
    });
  }

  Future<void> resolveMemorySuggestion(
    MailRadarItem item,
    AssistantMemorySuggestion suggestion, {
    required AssistantMemorySuggestionStatus status,
    String? content,
  }) async {
    if (!suggestion.isPending) return;
    final normalized = (content ?? suggestion.content).trim();
    if (normalized.isEmpty) return;
    await _withStoreMutation(() async {
      final next = _items
          .map((candidate) {
            if (candidate.key != item.key) return candidate;
            var replaced = false;
            final suggestions = candidate.memorySuggestions
                .map((current) {
                  final same =
                      !replaced &&
                      current.isPending &&
                      current.content == suggestion.content &&
                      current.memoryType == suggestion.memoryType;
                  if (!same) return current;
                  replaced = true;
                  return current.copyWith(content: normalized, status: status);
                })
                .toList(growable: false);
            return candidate.copyWith(
              memorySuggestions: suggestions,
              userFieldTimes: _stamp(candidate, 'memory'),
              updatedAt: _now(),
            );
          })
          .toList(growable: false);
      await _persistItems(next);
      _notify();
    });
  }

  List<MailRadarItem> relatedTo(MailRadarItem item) {
    if (item.analysisPending ||
        (item.relatedThreadKey.trim().isEmpty && item.messageHash.isEmpty)) {
      return const [];
    }
    return _items
        .where(
          (candidate) =>
              candidate.key != item.key &&
              (item.isStronglyRelated(candidate) ||
                  (item.relatedThreadKey.isNotEmpty &&
                      candidate.relatedThreadKey == item.relatedThreadKey)),
        )
        .toList(growable: false)
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
  }

  Future<List<MailRadarInlineImage>> loadInlineImages(
    MailRadarItem item,
  ) async {
    if (!item.hasInlineImages || item.isRecallNotice) return const [];
    final existing = _inlineImageCache[item.key];
    if (existing != null) return existing;
    final loading = _downloadInlineImages(item);
    _inlineImageCache[item.key] = loading;
    try {
      return await loading;
    } catch (_) {
      _inlineImageCache.remove(item.key);
      rethrow;
    }
  }

  Future<List<MailRadarInlineImage>> _downloadInlineImages(
    MailRadarItem item,
  ) async {
    const sourceLimit = 20 * 1024 * 1024;
    final detail = await _loadMessageDetail(item);
    final images = <MailRadarInlineImage>[];
    for (final attachment in detail.attachments) {
      if (!looksLikeInlineImageAttachment(
            attachment.name,
            attachment.mimeType,
          ) ||
          attachment.size > sourceLimit) {
        continue;
      }
      final partId = attachment.partId?.trim() ?? '';
      if (partId.isEmpty) continue;
      try {
        final bytes = await mailService.downloadAttachment(
          credentials: credentials,
          folder: item.sourceFolder,
          uid: item.uid,
          partId: partId,
          expectedMailboxUidValidity: item.mailboxUidValidity,
        );
        if (bytes.isNotEmpty && bytes.length <= sourceLimit) {
          images.add(
            MailRadarInlineImage(
              name: attachment.name,
              bytes: Uint8List.fromList(bytes),
            ),
          );
        }
      } catch (_) {
        // One broken image must not prevent the remaining attachments loading.
      }
    }
    return images;
  }

  Future<List<MailAttachment>> loadDownloadableAttachments(MailRadarItem item) {
    if (item.isRecallNotice) {
      return Future<List<MailAttachment>>.value(const []);
    }
    return _attachmentListCache.putIfAbsent(item.key, () async {
      final detail = await _loadMessageDetail(item);
      return detail.attachments
          .where((attachment) => attachment.partId?.trim().isNotEmpty == true)
          .toList(growable: false);
    });
  }

  Future<Uint8List> downloadAttachment(
    MailRadarItem item,
    MailAttachment attachment,
  ) async {
    final partId = attachment.partId?.trim() ?? '';
    if (partId.isEmpty || item.isRecallNotice) {
      throw const FormatException('附件参数无效。');
    }
    final detail = await _loadMessageDetail(item);
    final matching = detail.attachments.where(
      (candidate) =>
          candidate.partId?.trim() == partId &&
          candidate.name.trim() == attachment.name.trim(),
    );
    if (matching.length != 1) {
      throw const FormatException('附件已变化，请刷新邮件后重试。');
    }
    final bytes = await mailService.downloadAttachment(
      credentials: credentials,
      folder: item.sourceFolder,
      uid: item.uid,
      partId: partId,
      expectedMailboxUidValidity: item.mailboxUidValidity,
    );
    return Uint8List.fromList(bytes);
  }

  Future<Uri> resolveActionLink(
    MailRadarItem item,
    MailRadarActionLink actionLink,
  ) async {
    final detail = await _loadMessageDetail(item);
    final links = extractMailRadarHttpLinks(detail);
    final index = actionLink.sourceIndex - 1;
    if (index < 0 || index >= links.length) {
      throw const FormatException('邮件中的外部链接已变化，请刷新后重试。');
    }
    return links[index];
  }

  /// Loads the original message without changing its server unread state.
  Future<MailMessageDetail> loadMessageDetail(MailRadarItem item) =>
      _loadMessageDetail(item);

  Future<MailMessageDetail> _loadMessageDetail(MailRadarItem item) {
    final existing = _messageDetailCache[item.key];
    if (existing != null) return existing;
    final loading = mailService.readMessage(
      credentials: credentials,
      folder: item.sourceFolder,
      uid: item.uid,
      expectedMailboxUidValidity: item.mailboxUidValidity,
      markAsSeen: false,
    );
    _messageDetailCache[item.key] = loading;
    return loading.catchError((Object error) {
      _messageDetailCache.remove(item.key);
      throw error;
    });
  }

  Future<T> _withStoreMutation<T>(Future<T> Function() operation) async {
    final previous = _storeMutationQueue;
    final completer = Completer<void>();
    _storeMutationQueue = completer.future;
    await previous;
    try {
      return await operation();
    } finally {
      completer.complete();
    }
  }

  Future<void> _persistItems(List<MailRadarItem> next) async {
    await store.save(username, next);
    _items = next;
    final remote = syncService;
    if (!_hasConsent || remote == null) return;
    try {
      await _pushRemote(remote, next);
    } on AiAssistantMailRadarUnavailableException catch (error) {
      _handleRemoteAccessUnavailable(accountStopped: error.stoppedByPreference);
      rethrow;
    } catch (error) {
      _error = '雷达结果已保存在本机，远端同步稍后重试：${_displayError(error)}';
    }
  }

  Future<void> _synchronizeRemote() =>
      _withStoreMutation(_synchronizeRemoteUnsafe);

  Future<void> _synchronizeRemoteUnsafe() async {
    if (analyzer is MailSourceRadarAnalyzer &&
        !(analyzer as MailSourceRadarAnalyzer).maySynchronizeResults) {
      return;
    }
    final remote = syncService;
    if (!_hasConsent || remote == null) return;
    var snapshot = await remote.loadMailRadar(username);
    _remoteVersion = snapshot.version;
    var merged = _mergeItems(_items, snapshot.items);
    _sortItems(merged);
    await store.save(username, merged);
    _items = merged;
    if (!_sameItems(merged, snapshot.items)) {
      await _pushRemote(remote, merged);
    }
  }

  Future<void> _pushRemote(
    AiAssistantMailRadarSyncService remote,
    List<MailRadarItem> desired,
  ) async {
    if (analyzer is MailSourceRadarAnalyzer &&
        !(analyzer as MailSourceRadarAnalyzer).maySynchronizeResults) {
      return;
    }
    var merged = List<MailRadarItem>.of(desired, growable: true);
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final saved = await remote.saveMailRadar(
          username,
          expectedVersion: _remoteVersion,
          items: analyzer is MailSourceRadarAnalyzer
              ? (analyzer as MailSourceRadarAnalyzer).publishableSnapshot(
                  merged,
                )
              : merged,
        );
        _remoteVersion = saved.version;
        final reconciled = _mergeItems(merged, saved.items);
        _sortItems(reconciled);
        if (!_sameItems(_items, reconciled)) {
          await store.save(username, reconciled);
          _items = reconciled;
        }
        return;
      } on AiAssistantMailRadarConflictException {
        final latest = await remote.loadMailRadar(username);
        _remoteVersion = latest.version;
        merged = _mergeItems(merged, latest.items);
        _sortItems(merged);
        await store.save(username, merged);
        _items = merged;
      }
    }
    throw const AiAssistantException('邮件雷达多端同步冲突，请稍后刷新。');
  }

  List<MailRadarItem> _mergeItems(
    List<MailRadarItem> local,
    List<MailRadarItem> remote,
  ) {
    final merged = <String, MailRadarItem>{};
    for (final item in [...local, ...remote]) {
      final existing = merged[item.key];
      if (existing == null) {
        merged[item.key] = item;
        continue;
      }
      merged[item.key] = mergeMailRadarItem(existing, item);
    }
    return merged.values.toList(growable: true);
  }

  bool _sameItems(List<MailRadarItem> left, List<MailRadarItem> right) {
    if (left.length != right.length) return false;
    final leftByKey = {for (final item in left) item.key: item.toJson()};
    for (final item in right) {
      final existing = leftByKey[item.key];
      if (existing == null ||
          jsonEncode(existing) != jsonEncode(item.toJson())) {
        return false;
      }
    }
    return true;
  }

  void _sort() => _sortItems(_items);

  void _sortItems(List<MailRadarItem> items) {
    items.sort((a, b) {
      if (a.isResolved != b.isResolved) return a.isResolved ? 1 : -1;
      final aSnoozed = a.snoozedUntil?.isAfter(_now()) == true;
      final bSnoozed = b.snoozedUntil?.isAfter(_now()) == true;
      if (aSnoozed != bSnoozed) return aSnoozed ? 1 : -1;
      final priority = a.priority.index.compareTo(b.priority.index);
      if (priority != 0) return priority;
      return b.receivedAt.compareTo(a.receivedAt);
    });
  }

  void _clearProviderRetry() {
    for (final waiter in _analysisWaiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
    _analysisWaiters.clear();
    _providerRetryAt = null;
    _stopCurrentScanForProvider = false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _handleRemoteAccessUnavailable({bool accountStopped = false}) {
    if (accountStopped) {
      _accountStopObserved = true;
      _enabled = false;
      _operationGeneration++;
      _scanRequestedWhileBusy = false;
      _clearProviderRetry();
      _isScanning = false;
      _notify();
      unawaited(refreshPreferences());
      return;
    }
    _operationGeneration++;
    _clearProviderRetry();
    _stopCurrentScanForProvider = true;
    _scanRequestedWhileBusy = false;
    _error = null;
    onRemoteAccessUnavailable?.call();
  }

  @override
  void dispose() {
    _disposed = true;
    _operationGeneration++;
    _scanRequestedWhileBusy = false;
    _clearProviderRetry();
    _inlineImageCache.clear();
    _messageDetailCache.clear();
    _attachmentListCache.clear();
    super.dispose();
  }
}
