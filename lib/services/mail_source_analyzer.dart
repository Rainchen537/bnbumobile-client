part of 'mail_radar_analyzer.dart';

/// One mailbox collector and one result consumer share actual PEEK observations.
class MailSourceRadarAnalyzer extends SmallUMailRadarAnalyzer {
  MailSourceRadarAnalyzer({
    required super.assistantService,
    required super.radarService,
    required this.source,
    super.targetLanguageTagProvider,
    AccountSyncStorage? storage,
  }) : storage = storage ?? AccountSyncStorage.shared,
       super(
         attachmentProcessor: const MailRadarAttachmentProcessor(
           includeVisuals: false,
         ),
       );

  final MailSourceService source;
  final AccountSyncStorage storage;
  Map<String, dynamic> _records = {};
  Map<String, dynamic>? _policy;
  Future<void>? _loading;
  bool _loaded = false;
  static const _domain = 'mail-source.observations.v1';

  bool get hasSourceConsent =>
      _policy?['consent'] is Map &&
      _policy!['consent']['enabled'] == true &&
      _policy!['consent']['current'] == true;

  bool get maySynchronizeResults =>
      _policy?['consent'] is Map &&
      _policy!['consent']['approved'] == true &&
      _policy!['consent']['current'] == true;

  bool isSecretBlocked(String key) =>
      _records[key] is Map && _records[key]['status'] == 'blocked_secret';

  List<MailRadarItem> publishableSnapshot(List<MailRadarItem> items) => items
      .where(
        (item) =>
            !item.analysisPending &&
            !isSecretBlocked(item.key) &&
            !mailSourceContainsSecret(
              '${item.subject}\n${item.summaryZh}\n${item.deadlineEvidence}',
            ),
      )
      .toList(growable: false);

  bool isNotSelected(String key) {
    final record = _records[key];
    if (record is! Map) return false;
    if (record['status'] == 'blocked_secret') return true;
    return record['status'] == 'not_selected' &&
        record['policy_version'] == _policy?['version'] &&
        DateTime.tryParse(
              record['checked_at']?.toString() ?? '',
            )?.isAfter(DateTime.now().subtract(const Duration(minutes: 5))) ==
            true;
  }

  bool needsResultRefresh(MailRadarItem item) {
    final record = _records[item.key];
    if (record is! Map) return false;
    if (record['policy_version'] != _policy?['version']) return true;
    if (record['classification_pending'] != true &&
        record['analysis_pending'] != true) {
      return false;
    }
    final checked = DateTime.tryParse(record['checked_at']?.toString() ?? '');
    return checked == null ||
        checked.isBefore(DateTime.now().subtract(const Duration(minutes: 5)));
  }

  String? collectionError;

  Future<Map<String, dynamic>> policy(String username) async {
    _policy = await source.mailSourceRequest(username, 'policy');
    return _policy!;
  }

  Future<int> choose(
    String username,
    int days,
    Map<String, dynamic> policy,
  ) async {
    final result = await source.mailSourceRequest(
      username,
      'consent',
      body: {
        'enabled': days > 0,
        'lookback_days': days > 0 ? days : 7,
        'policy_version': policy['version'],
        'consent_version': policy['consent_version'],
      },
    );
    await this.policy(username);
    return result['settings_version'] as int;
  }

  Future<void> _load(String username) => _loading ??= (() async {
    if (_loaded) return;
    _records = await storage.read(username, _domain) ?? {};
    _loaded = true;
  })();

  Future<void> _save(String username, bool Function() active) => storage
      .writeIfCurrent(username, _domain, Map.of(_records), isCurrent: active);

  int _requireReady() {
    final policy = _policy;
    if (policy == null) {
      throw const MailSourceException('provider_not_configured');
    }
    final consent = policy['consent'];
    if (consent is! Map ||
        consent['enabled'] != true ||
        consent['current'] != true) {
      throw const MailSourceException('mail_source_consent_required');
    }
    if (consent['approved'] != true) {
      throw const MailSourceException('mail_source_device_approval_required');
    }
    if (policy['readiness'] != 'ready') {
      throw MailSourceException(policy['readiness'] as String);
    }
    return consent['epoch'] as int;
  }

  /// Bound each background tick. Newest messages are considered first; known
  /// observations are skipped without downloading the body again.
  Future<void> collect({
    required String username,
    required MailAccessCredentials credentials,
    required MailService mailService,
    required bool Function() active,
  }) async {
    await _load(username);
    await policy(username);
    final epoch = _requireReady();
    final cutoff = DateTime.now().subtract(
      Duration(days: _policy!['source_days'] as int),
    );
    collectionError = null;
    var uploaded = 0;
    int? validity;
    for (var page = 1; page <= 100 && active(); page++) {
      final snapshot = await mailService.fetchFolder(
        credentials: credentials,
        folder: MailFolder.inbox,
        page: page,
        pageSize: 50,
        expectedMailboxUidValidity: validity,
      );
      validity ??= snapshot.mailboxUidValidity;
      var old = snapshot.messages.isNotEmpty;
      for (final summary in snapshot.messages) {
        if (!active()) return;
        if (summary.date == null) {
          old = false;
          continue;
        }
        if (summary.date!.isBefore(cutoff)) continue;
        old = false;
        final key = mailRadarMessageKey(
          summary.folder,
          summary.mailboxUidValidity ?? 0,
          summary.uid,
        );
        if (_records[key] is Map && _records[key]['epoch'] == epoch) {
          final record = _records[key] as Map;
          if (record['status'] != 'invalid_input') continue;
          if (record['ingest_revision'] == 2 &&
              record['policy_version'] == _policy?['version'] &&
              DateTime.tryParse(
                    record['retry_after']?.toString() ?? '',
                  )?.isAfter(DateTime.now()) ==
                  true) {
            collectionError = 'invalid_request';
            continue;
          }
          _records.remove(key);
        }
        final detail = await mailService.readMessage(
          credentials: credentials,
          folder: summary.folder,
          uid: summary.uid,
          expectedMailboxUidValidity: summary.mailboxUidValidity,
          markAsSeen: false,
        );
        try {
          await _observe(
            username,
            credentials,
            summary,
            detail,
            mailService,
            active,
          );
        } on MailSourceException catch (error) {
          if (error.code != 'invalid_request') rethrow;
          collectionError = error.code;
          _records[key] = {
            'epoch': epoch,
            'status': 'invalid_input',
            'ingest_revision': 2,
            'policy_version': _policy?['version'],
            'retry_after': DateTime.now()
                .add(const Duration(hours: 24))
                .toUtc()
                .toIso8601String(),
          };
          await _save(username, active);
        }
        if (++uploaded >= 12) return;
      }
      if (old ||
          snapshot.messages.isEmpty ||
          page * 50 >= snapshot.totalMessages) {
        return;
      }
    }
  }

  Future<Map<String, dynamic>> _observe(
    String username,
    MailAccessCredentials credentials,
    MailMessageSummary summary,
    MailMessageDetail detail,
    MailService mailService,
    bool Function() active,
  ) async {
    if (!active()) throw const AiAssistantOperationCancelledException();
    final epoch = _requireReady();
    final validity = detail.mailboxUidValidity;
    if (validity == null || validity <= 0 || detail.date == null) {
      throw const FormatException('邮件身份或时间无效。');
    }
    final key = mailRadarMessageKey(detail.folder, validity, detail.uid);
    final known = _records[key];
    if (known is Map && known['epoch'] == epoch) {
      if (known['status'] == 'invalid_input') {
        throw const MailSourceException('invalid_request');
      }
      return Map<String, dynamic>.from(known);
    }
    final headers = <String, dynamic>{
      'folder': detail.folder.name,
      'uid_validity': validity,
      'uid': detail.uid,
      'received_at': detail.date!.toUtc().toIso8601String(),
      'subject': mailSourceLimit(detail.subject, 500),
      'sender': mailSourceLimit(detail.sender, 320),
      'recipients': mailSourceLimit(
        '${detail.recipients};${detail.cc ?? ''}',
        2000,
      ),
      'message_id': mailSourceLimit(detail.messageId ?? summary.messageId, 500),
      'in_reply_to': mailSourceLimit(detail.inReplyTo ?? '', 2000),
      'references': mailSourceLimit(detail.references ?? '', 4000),
    };
    // Narrow secret detection runs locally before any header/body transmission.
    if (mailSourceContainsSecret('${detail.subject}\n${detail.body}')) {
      _records[key] = {'epoch': epoch, 'status': 'blocked_secret'};
      await _save(username, active);
      return Map<String, dynamic>.from(_records[key]);
    }
    final preflight = await source.mailSourceRequest(
      username,
      'preflight',
      body: {'epoch': epoch, 'headers': headers},
      isOperationActive: active,
    );
    if (preflight['status'] == 'blocked_secret') {
      _records[key] = {'epoch': epoch, 'status': 'blocked_secret'};
      await _save(username, active);
      return Map<String, dynamic>.from(_records[key]);
    }
    final attachments = await _prepareAttachments(
      credentials: credentials,
      detail: detail,
      attachments: detail.attachments
          .where((a) => !a.mimeType.startsWith('image/'))
          .take(3)
          .toList(),
      mailService: mailService,
      isOperationActive: active,
    );
    if (attachments.any((a) => mailSourceContainsSecret(a.text))) {
      _records[key] = {'epoch': epoch, 'status': 'blocked_secret'};
      await _save(username, active);
      return Map<String, dynamic>.from(_records[key]);
    }
    final body = mailSourceBoundedText(
      mailSourceExcerpt(detail.body, 60000),
      128 * 1024,
    );
    final response = await source.mailSourceRequest(
      username,
      'observations',
      body: {
        'epoch': epoch,
        'headers': headers,
        'attachment_manifest': detail.attachments
            .take(100)
            .map((a) => mailSourceLimit(a.name, 200))
            .toList(),
        'attachment_count': detail.attachments.length,
        'ticket': preflight['ticket'],
        'body': body,
        'body_complete': body == detail.body,
        'source_links': extractMailRadarHttpLinks(
          detail,
        ).map((u) => u.toString()).where((u) => u.length <= 2000).toList(),
        'attachments': attachments
            .map(
              (a) => {
                'name': mailSourceLimit(a.name, 200),
                'text': mailSourceBoundedText(
                  mailSourceExcerpt(a.text, 12000),
                  20 * 1024,
                ),
                'complete':
                    a.sourceComplete &&
                    a.text.length <= 12000 &&
                    utf8.encode(a.text).length <= 20 * 1024,
              },
            )
            .toList(),
      },
      isOperationActive: active,
    );
    _records[key] = {...response, 'epoch': epoch};
    // Keep only bounded identity receipts, never mail bodies in this cache.
    if (_records.length > 10000) _records.remove(_records.keys.first);
    await _save(username, active);
    return Map<String, dynamic>.from(_records[key]);
  }

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
    bool manual = false,
  }) async {
    final active = isOperationActive ?? () => true;
    await _load(username);
    if (_policy == null) await policy(username);
    final epoch = _requireReady();
    final observed = await _observe(
      username,
      credentials,
      summary,
      detail,
      mailService,
      active,
    );
    if (observed['status'] == 'blocked_secret') throw const MailSourceSkipped();
    final key = mailRadarMessageKey(
      detail.folder,
      detail.mailboxUidValidity!,
      detail.uid,
    );
    if (!manual && isNotSelected(key)) {
      throw const MailSourceSkipped();
    }
    final response = await source.mailSourceRequest(
      username,
      'acquire',
      body: {
        'epoch': epoch,
        'observation_id': observed['observation_id'],
        'mode': manual ? 'manual' : 'automatic',
      },
      isOperationActive: active,
    );
    if (response['status'] == 'pending') throw const MailSourcePending();
    _records[key] = {
      ...observed,
      'status': response['status'],
      'policy_version': _policy?['version'],
      'classification_pending':
          response['result'] is Map &&
          response['result']['classification_pending'] == true,
      'analysis_pending':
          response['result'] is Map &&
          response['result']['analysis_pending'] == true,
      'checked_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _save(username, active);
    if (response['status'] == 'not_selected') throw const MailSourceSkipped();
    final result = response['result'] as Map;
    final radar = result['radar'] as Map;
    final language = normalizeMailRadarTargetLanguageTag(
      targetLanguageTagProvider(),
    );
    return MailRadarItem(
      key: key,
      sourceFolder: detail.folder,
      uid: detail.uid,
      mailboxUidValidity: detail.mailboxUidValidity!,
      subject: detail.subject,
      sender: detail.sender,
      recipients: detail.recipients,
      receivedAt: detail.date!,
      summaryZh: radar['summaries'][language] as String,
      translationZh: '',
      priority: MailRadarPriority.values.byName(radar['priority'] as String),
      category: MailRadarCategory.values.byName(radar['category'] as String),
      senderRole: MailRadarSenderRole.unknown,
      actionZh: mailSourceActionText(result, language),
      deadlineText: radar['deadline_text'] as String,
      relatedThreadKey: '',
      attachmentNotes: (result['missing_fields'] as List).cast<String>(),
      analyzedAt: DateTime.now(),
      deadlineAt: DateTime.tryParse(radar['deadline_at']?.toString() ?? ''),
      deadlineEvidence: radar['deadline_evidence'] as String,
      deadlinePrecision: radar['deadline_precision'] as String,
      analysisLanguageTag: language,
      bodyCoverage: result['complete'] == true ? 'complete' : 'partial',
      originalIsSeen: detail.isSeen,
      hasSourceAttachments: detail.attachments.isNotEmpty,
    );
  }
}

bool mailSourceContainsSecret(String text) => [
  r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
  r'(?:验证码|驗證碼|一次性密码|verification code|one.time password|your (?:login |security )?code)\s*(?:is|为|為|:|：)?\s*[:：]?\s*(?=[A-Z0-9]{4,12}(?:\b|[。；，\n]))(?=[A-Z0-9]*[0-9])[A-Z0-9]{4,12}(?:\b|[。；，\n])',
  r'(?:api[_ -]?key|access[_ -]?token|临时密码|初始密码|temporary password)\s*[:=：]\s*[A-Za-z0-9_+/=-]{8,}',
  r'https?://[^\s<>]+(?:reset|magic.login|verify)[^\s<>]*[?&](?:token|code|ticket)=[A-Za-z0-9_%.-]{8,}',
].any((pattern) => RegExp(pattern, caseSensitive: false).hasMatch(text));

// Bound actual UTF-8 payload size, including CJK, while retaining deadline tails.
String mailSourceBoundedText(String value, int maxBytes) {
  final bytes = utf8.encode(value);
  if (bytes.length <= maxBytes) return utf8.decode(bytes);
  final half = (maxBytes - 64) ~/ 2;
  return '${utf8.decode(bytes.sublist(0, half), allowMalformed: true)}\n[content omitted]\n${utf8.decode(bytes.sublist(bytes.length - half), allowMalformed: true)}';
}

// Scalar-safe excerpts never split an emoji into invalid JSON surrogates.
Iterable<int> _mailSourceScalars(String value) =>
    value.runes.map((rune) => rune >= 0xd800 && rune <= 0xdfff ? 0xfffd : rune);
String mailSourceLimit(String value, int limit) {
  final safe = String.fromCharCodes(_mailSourceScalars(value));
  if (safe.length <= limit) return safe;
  var end = limit;
  if (end > 0 &&
      safe.codeUnitAt(end - 1) >= 0xd800 &&
      safe.codeUnitAt(end - 1) <= 0xdbff) {
    end--;
  }
  return safe.substring(0, end);
}

String mailSourceExcerpt(String value, int limit) {
  final safe = String.fromCharCodes(_mailSourceScalars(value));
  if (safe.length <= limit) return safe;
  if (limit < 80) return mailSourceLimit(safe, limit);
  var head = (limit * .7).floor();
  var tailStart = safe.length - (limit - head - 18);
  if (safe.codeUnitAt(head - 1) >= 0xd800 &&
      safe.codeUnitAt(head - 1) <= 0xdbff) {
    head--;
  }
  if (safe.codeUnitAt(tailStart) >= 0xdc00 &&
      safe.codeUnitAt(tailStart) <= 0xdfff) {
    tailStart++;
  }
  // Preserve v1 excerpts byte-for-byte when already valid, so an existing
  // mailbox observation retains its content fingerprint after an upgrade.
  return '${safe.substring(0, head)}\n...[中间省略]...\n${safe.substring(tailStart)}';
}

String mailSourceActionText(Map result, String language) {
  if (result['action_items'] is! List) {
    return (result['actions'] as List).join('\n');
  }
  const labels = {
    'required': {'zh-Hans': '必须处理', 'zh-Hant': '必須處理', 'en': 'Required'},
    'conditional_required': {
      'zh-Hans': '条件必办',
      'zh-Hant': '條件必辦',
      'en': 'Required if applicable',
    },
    'optional': {'zh-Hans': '自愿参与', 'zh-Hant': '自願參與', 'en': 'Optional'},
    'informational': {
      'zh-Hans': '仅供知悉',
      'zh-Hant': '僅供知悉',
      'en': 'For information',
    },
    'unknown': {'zh-Hans': '待确认', 'zh-Hant': '待確認', 'en': 'Uncertain'},
  };
  return (result['action_items'] as List)
      .whereType<Map>()
      .map((a) {
        final label =
            labels[a['obligation']]?[language] ?? labels['unknown']![language]!;
        return [
          '$label · ${a['action']}',
          a['applies_to'],
          a['condition'],
          a['deadline_text'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
      })
      .join('\n');
}
