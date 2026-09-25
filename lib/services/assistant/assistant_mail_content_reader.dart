import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../models/assistant_content_page.dart';
import 'assistant_content_reader.dart';

import 'package:crypto/crypto.dart';

import '../../models/assistant_models.dart';
import '../../models/mail_models.dart';
import '../mail_service.dart';

class AssistantMailSearchRequest {
  const AssistantMailSearchRequest({
    this.query = '',
    this.sender = '',
    this.folders = const [MailFolder.inbox],
    this.lookbackDays = 7,
    this.officialSendersOnly = false,
    this.limit = 4,
    this.includeBody = true,
    this.cursor = '',
    this.searchScope = 'all',
  });

  final String query;
  final String sender;
  final List<MailFolder> folders;
  final int lookbackDays;
  final bool officialSendersOnly;
  final int limit;
  final bool includeBody;
  final String cursor;
  final String searchScope;
}

class AssistantMailContentReader {
  AssistantMailContentReader({
    required Future<MailAccessCredentials?> Function() credentialsLoader,
    required MailService mailService,
    DateTime Function()? now,
  }) : _credentialsLoader = credentialsLoader,
       _mailService = mailService,
       _now = now ?? DateTime.now;

  static const int _pageSize = 50;
  static const int _scanBudget = 200;
  static const int _bodySearchBudget = 24;
  static const int _maxBodyCharactersPerMessage = 12 * 1024;
  static const int _maxBodyBytesPerResult = 48 * 1024;
  final Map<String, _MailScan> _scans = {};
  String? _owner;
  final Map<String, (DateTime, String)> _attachmentTextCache = {};

  final Future<MailAccessCredentials?> Function() _credentialsLoader;
  final MailService _mailService;
  final DateTime Function() _now;

  Future<AssistantMailToolResultContext> findMessages(
    AssistantMailSearchRequest request, {
    int protocolVersion = 2,
  }) async {
    _validateSearchRequest(request);
    final credentials = await _requireCredentials();
    final observedAt = _now();
    final signature = _resultKey('search', {
      'query': request.query.trim().toLowerCase(),
      'sender': request.sender.trim().toLowerCase(),
      'folders': request.folders.map((f) => f.name).toList(),
      'lookback_days': request.lookbackDays,
      'official_senders_only': request.officialSendersOnly,
      'limit': request.limit,
      'include_body': request.includeBody,
      'search_scope': request.searchScope,
    });
    _scans.removeWhere(
      (_, scan) =>
          observedAt.difference(scan.observedAt) > const Duration(minutes: 20),
    );
    final previous = request.cursor.isEmpty ? null : _scans[request.cursor];
    if (request.cursor.isNotEmpty &&
        (previous == null || previous.signature != signature)) {
      throw const AssistantMailContentException('邮件搜索已过期或条件已变化，请重新搜索。');
    }
    final scan =
        previous?.copy() ??
        _MailScan(signature: signature, observedAt: observedAt);
    final cutoff = request.lookbackDays == 0
        ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        : scan.observedAt.subtract(Duration(days: request.lookbackDays));
    final matches = <MailMessageSummary>[];
    var scannedNow = 0;
    var bodyReads = 0;
    try {
      while (scan.folderIndex < request.folders.length &&
          scannedNow < _scanBudget &&
          bodyReads < _bodySearchBudget &&
          matches.length < request.limit) {
        final folder = request.folders[scan.folderIndex];
        final snapshot = await _mailService.fetchFolder(
          credentials: credentials,
          folder: folder,
          page: scan.page,
          pageSize: _pageSize,
          expectedMailboxUidValidity: scan.uidValidity,
        );
        if (scan.totalMessages != null &&
            snapshot.totalMessages != scan.totalMessages) {
          throw const AssistantMailContentException(
            '邮箱列表在搜索期间发生变化，请重新搜索以避免遗漏。',
          );
        }
        scan.uidValidity = snapshot.mailboxUidValidity;
        scan.totalMessages = snapshot.totalMessages;
        final pageMessages = snapshot.messages;
        if (pageMessages.isEmpty ||
            pageMessages.every(
              (m) => m.date != null && m.date!.isBefore(cutoff),
            )) {
          scan.nextFolder();
          continue;
        }
        while (scan.offset < pageMessages.length &&
            scannedNow < _scanBudget &&
            bodyReads < _bodySearchBudget &&
            matches.length < request.limit) {
          final message = pageMessages[scan.offset++];
          scan.scannedCount++;
          scannedNow++;
          if (!_insideLookback(message, cutoff) ||
              !_matchesSender(message, request) ||
              _summaryIdentity(message) == null) {
            continue;
          }
          var matched = _matchesSearch(message, request);
          if (request.query.trim().isNotEmpty &&
              request.searchScope != 'metadata' &&
              (request.searchScope == 'body' || !matched)) {
            bodyReads++;
            final details = await _mailService.readMessages(
              credentials: credentials,
              messages: [
                MailMessageIdentity(
                  folder: folder,
                  uid: message.uid,
                  mailboxUidValidity: message.mailboxUidValidity!,
                ),
              ],
              markAsSeen: false,
            );
            matched =
                details.isNotEmpty &&
                _containsTerms(details.single.body, request.query);
          }
          if (matched) {
            matches.add(message);
            scan.matchedCount++;
          }
        }
        if (scan.offset >= pageMessages.length) {
          if (scan.page * _pageSize >= snapshot.totalMessages) {
            scan.nextFolder();
          } else {
            scan.page++;
            scan.offset = 0;
          }
        }
      }
    } on MailServiceException catch (error) {
      throw AssistantMailContentException(error.message);
    }
    final scanComplete = scan.folderIndex >= request.folders.length;
    var nextCursor = '';
    if (!scanComplete) {
      nextCursor = base64Url.encode(
        List<int>.generate(24, (_) => Random.secure().nextInt(256)),
      );
      if (_scans.length >= 64) _scans.remove(_scans.keys.first);
      _scans[nextCursor] = scan.copy();
    }
    final messages = request.includeBody
        ? await _readSelected(credentials, matches)
        : matches.map(_metadataContext).toList(growable: false);
    final incompleteContent = messages.any(
      (m) =>
          m.contentState == 'truncated' ||
          m.contentState == 'unavailable' ||
          m.contentState == 'parse_failed',
    );
    return AssistantMailToolResultContext(
      protocolVersion: protocolVersion,
      resultKey: _resultKey('search', [signature, request.cursor]),
      kind: 'mail_search',
      observedAt: scan.observedAt,
      completeness: !scanComplete || incompleteContent
          ? 'truncated'
          : messages.isEmpty
          ? 'empty'
          : 'complete',
      messages: List.unmodifiable(messages),
      nextCursor: nextCursor,
      scanComplete: scanComplete,
      scannedCount: scan.scannedCount,
      matchedCount: scan.matchedCount,
    );
  }

  Future<AssistantMailToolResultContext> readMessages(
    List<MailMessageIdentity> identities, {
    int bodyOffset = 0,
    int protocolVersion = 2,
  }) async {
    if (bodyOffset < 0 || identities.isEmpty || identities.length > 8) {
      throw const AssistantMailContentException('小U单批可读取一至八封邮件；更多邮件请分批读取。');
    }
    final unique = identities
        .map(
          (identity) =>
              '${identity.folder.name}:${identity.mailboxUidValidity}:${identity.uid}',
        )
        .toSet();
    if (unique.length != identities.length ||
        identities.any(
          (identity) => identity.uid <= 0 || identity.mailboxUidValidity <= 0,
        )) {
      throw const AssistantMailContentException('小U邮件引用无效，请重新搜索邮件。');
    }
    final credentials = await _requireCredentials();
    try {
      final details = await _mailService.readMessages(
        credentials: credentials,
        messages: identities,
        markAsSeen: false,
      );
      final messages = <AssistantMailMessageContext>[];
      for (final detail in details) {
        final converted = _detailContext(
          detail,
          bodyByteBudget: _maxBodyBytesPerResult ~/ details.length,
          bodyOffset: bodyOffset,
        );
        messages.add(converted);
      }
      return AssistantMailToolResultContext(
        protocolVersion: protocolVersion,
        resultKey: _resultKey('messages', [
          unique.toList()..sort(),
          bodyOffset,
        ]),
        kind: 'mail_messages',
        observedAt: _now(),
        completeness:
            messages.any(
              (message) => const {
                'truncated',
                'unavailable',
                'parse_failed',
              }.contains(message.contentState),
            )
            ? 'truncated'
            : 'complete',
        messages: List.unmodifiable(messages),
      );
    } on MailServiceException {
      return AssistantMailToolResultContext(
        protocolVersion: protocolVersion,
        resultKey: _resultKey('messages', [
          unique.toList()..sort(),
          bodyOffset,
        ]),
        kind: 'mail_messages',
        observedAt: _now(),
        completeness: 'unavailable',
        messages: const [],
      );
    }
  }

  Future<AssistantMailToolResultContext> readAttachment(
    MailMessageIdentity identity,
    String partId, {
    int offset = 0,
  }) async {
    final credentials = await _requireCredentials();
    final detail = await _mailService.readMessage(
      credentials: credentials,
      folder: identity.folder,
      uid: identity.uid,
      expectedMailboxUidValidity: identity.mailboxUidValidity,
      markAsSeen: false,
    );
    final attachments = detail.attachments
        .where((a) => a.partId == partId)
        .toList();
    if (attachments.length != 1) {
      throw const AssistantMailContentException('邮件附件引用已失效。');
    }
    final attachment = attachments.single;
    if (attachment.size > 64 * 1024 * 1024) {
      throw const AssistantMailContentException('附件超过本机解析内存预算。');
    }
    final owner = _owner;
    final cacheKey =
        '${identity.folder.name}:${identity.mailboxUidValidity}:${identity.uid}:$partId:${attachment.size}';
    final cached = _attachmentTextCache[cacheKey];
    String text;
    if (cached != null &&
        _now().difference(cached.$1) < const Duration(minutes: 2)) {
      text = cached.$2;
    } else {
      final bytes = await _mailService.downloadAttachment(
        credentials: credentials,
        folder: identity.folder,
        uid: identity.uid,
        partId: partId,
        expectedMailboxUidValidity: identity.mailboxUidValidity,
      );
      text = await const AssistantDocumentReader().extract(
        attachment.name,
        Uint8List.fromList(bytes),
      );
      if (_owner != owner) {
        throw const AssistantMailContentException('邮箱会话已变化。');
      }
      if (_attachmentTextCache.length >= 4) {
        _attachmentTextCache.remove(_attachmentTextCache.keys.first);
      }
      _attachmentTextCache[cacheKey] = (_now(), text);
    }
    final content = AssistantContentPage.slice(text, offset);
    return AssistantMailToolResultContext(
      resultKey: _resultKey('attachment', [
        identity.folder.name,
        identity.mailboxUidValidity,
        identity.uid,
        partId,
        offset,
      ]),
      kind: 'mail_attachment',
      observedAt: _now(),
      completeness: content.state == 'truncated' ? 'truncated' : 'complete',
      messages: [_detailContext(detail, bodyByteBudget: 4096)],
      content: content,
      attachmentPartId: partId,
      attachmentName: _limit(attachment.name, 255),
    );
  }

  Future<void> close() {
    _scans.clear();
    _attachmentTextCache.clear();
    _owner = null;
    return _mailService.close();
  }

  Future<List<AssistantMailMessageContext>> _readSelected(
    MailAccessCredentials credentials,
    List<MailMessageSummary> summaries,
  ) async {
    if (summaries.isEmpty) return const [];
    final identities = summaries
        .map(
          (summary) => MailMessageIdentity(
            folder: summary.folder,
            uid: summary.uid,
            mailboxUidValidity: summary.mailboxUidValidity!,
          ),
        )
        .toList(growable: false);
    try {
      final details = await _mailService.readMessages(
        credentials: credentials,
        messages: identities,
        markAsSeen: false,
      );
      final results = <AssistantMailMessageContext>[];
      for (final detail in details) {
        final converted = _detailContext(
          detail,
          bodyByteBudget: _maxBodyBytesPerResult ~/ details.length,
        );
        results.add(converted);
      }
      return results;
    } on MailServiceException {
      return summaries
          .map(
            (summary) => _metadataContext(summary, contentState: 'unavailable'),
          )
          .toList(growable: false);
    }
  }

  AssistantMailMessageContext _metadataContext(
    MailMessageSummary summary, {
    String contentState = 'metadata_only',
  }) {
    final sender = _senderParts(summary.sender);
    return AssistantMailMessageContext(
      uid: summary.uid,
      folder: summary.folder.name,
      mailboxUidValidity: summary.mailboxUidValidity!,
      senderName: _limit(sender.$1, 160),
      senderEmail: _limit(sender.$2, 254),
      recipients: '',
      cc: '',
      subject: _limit(summary.subject, 300),
      receivedAt: summary.date,
      bodyText: '',
      contentState: contentState,
    );
  }

  AssistantMailMessageContext _detailContext(
    MailMessageDetail detail, {
    required int bodyByteBudget,
    int bodyOffset = 0,
  }) {
    final sender = _senderParts(detail.sender);
    final normalizedBody = detail.body.trim();
    final bodyLimit = bodyByteBudget
        .clamp(0, _maxBodyCharactersPerMessage)
        .toInt();
    if ((bodyOffset >= normalizedBody.length && normalizedBody.isNotEmpty) ||
        (bodyOffset > 0 &&
            bodyOffset < normalizedBody.length &&
            normalizedBody.codeUnitAt(bodyOffset) >= 0xdc00 &&
            normalizedBody.codeUnitAt(bodyOffset) <= 0xdfff)) {
      throw const AssistantMailContentException('邮件正文读取位置无效，请使用上次返回的续读位置。');
    }
    final buffer = StringBuffer();
    var usedBytes = 0;
    var usedUnits = 0;
    for (final rune in normalizedBody.substring(bodyOffset).runes) {
      final text = String.fromCharCode(rune);
      final bytes = utf8.encode(text).length;
      if (usedBytes + bytes > bodyLimit ||
          usedUnits + text.length > _maxBodyCharactersPerMessage) {
        break;
      }
      buffer.write(text);
      usedBytes += bytes;
      usedUnits += text.length;
    }
    final bodyText = buffer.toString();
    final endOffset = bodyOffset + bodyText.length;
    final contentState = normalizedBody.isEmpty
        ? detail.htmlBody?.trim().isNotEmpty == true
              ? 'parse_failed'
              : detail.attachments.isEmpty
              ? 'empty'
              : 'attachment_only'
        : bodyOffset > 0 || endOffset < normalizedBody.length
        ? 'truncated'
        : 'complete';
    return AssistantMailMessageContext(
      uid: detail.uid,
      folder: detail.folder.name,
      mailboxUidValidity: detail.mailboxUidValidity!,
      senderName: _limit(sender.$1, 160),
      senderEmail: _limit(sender.$2, 254),
      recipients: _limit(detail.recipients, 1000),
      cc: _limit(detail.cc ?? '', 1000),
      subject: _limit(detail.subject, 300),
      receivedAt: detail.date,
      bodyText: bodyText,
      bodyOffset: bodyOffset,
      totalBodyCharacters: normalizedBody.length,
      nextBodyOffset: endOffset < normalizedBody.length ? endOffset : null,
      contentState: contentState,
      attachments: detail.attachments
          .where(
            (attachment) =>
                attachment.partId?.trim().isNotEmpty == true &&
                attachment.name.trim().isNotEmpty,
          )
          .take(16)
          .map(
            (attachment) => AssistantMailAttachmentContext(
              partId: _limit(attachment.partId!.trim(), 160),
              name: _limit(attachment.name.trim(), 255),
              size: attachment.size.clamp(0, 2_147_483_647).toInt(),
              mimeType: _limit(attachment.mimeType.trim(), 160),
            ),
          )
          .toList(growable: false),
    );
  }

  bool _insideLookback(MailMessageSummary message, DateTime cutoff) {
    final date = message.date;
    return date == null || !date.isBefore(cutoff);
  }

  bool _matchesSender(
    MailMessageSummary message,
    AssistantMailSearchRequest request,
  ) {
    final sender = _senderParts(message.sender);
    final senderText = '${sender.$1} ${sender.$2}'.toLowerCase();
    return (request.sender.trim().isEmpty ||
            senderText.contains(request.sender.trim().toLowerCase())) &&
        (!request.officialSendersOnly || _isOfficialSender(sender.$2));
  }

  bool _matchesSearch(
    MailMessageSummary message,
    AssistantMailSearchRequest request,
  ) => _containsTerms(
    '${message.sender} ${message.subject} ${message.preview}',
    request.query,
  );

  bool _containsTerms(String text, String query) => query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .every(text.toLowerCase().contains);

  bool _isOfficialSender(String email) {
    final normalized = email.trim().toLowerCase();
    return normalized.endsWith('@bnbu.edu.cn') &&
        !normalized.endsWith('@mail.bnbu.edu.cn');
  }

  String? _summaryIdentity(MailMessageSummary message) {
    final validity = message.mailboxUidValidity;
    if (message.uid <= 0 || validity == null || validity <= 0) return null;
    return '${message.folder.name}:$validity:${message.uid}';
  }

  (String, String) _senderParts(String raw) {
    final value = raw.trim();
    final match = RegExp(r'^(.*?)\s*<([^<>]+)>$').firstMatch(value);
    if (match != null) {
      return (
        (match.group(1) ?? '').trim().replaceAll(RegExp(r'^"|"$'), ''),
        (match.group(2) ?? '').trim().toLowerCase(),
      );
    }
    if (value.contains('@') && !value.contains(' ')) {
      return ('', value.toLowerCase());
    }
    return (value, '');
  }

  String _resultKey(String kind, Object canonicalValue) {
    final digest = sha256.convert(utf8.encode(jsonEncode(canonicalValue)));
    return 'mail-$kind:$digest';
  }

  String _limit(String value, int maxLength) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);

  Future<MailAccessCredentials> _requireCredentials() async {
    final credentials = await _credentialsLoader();
    if (credentials == null) {
      throw const AssistantMailContentException('请先登录后再读取邮箱。');
    }
    final owner = sha256
        .convert(
          utf8.encode('${credentials.emailAddress}:${credentials.password}'),
        )
        .toString();
    if (_owner != owner) {
      _scans.clear();
      _attachmentTextCache.clear();
      _owner = owner;
    }
    return credentials;
  }

  void _validateSearchRequest(AssistantMailSearchRequest request) {
    if (request.query.trim().length > 300 ||
        request.sender.trim().length > 254 ||
        request.folders.isEmpty ||
        request.folders.length > MailFolder.values.length ||
        request.folders.toSet().length != request.folders.length ||
        request.lookbackDays < 0 ||
        request.lookbackDays > 36500 ||
        request.limit < 1 ||
        request.limit > 8 ||
        !const {'all', 'metadata', 'body'}.contains(request.searchScope) ||
        request.cursor.length > 160) {
      throw const AssistantMailContentException('小U邮件搜索参数无效。');
    }
  }
}

class AssistantMailContentException implements Exception {
  const AssistantMailContentException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _MailScan {
  _MailScan({required this.signature, required this.observedAt});
  final String signature;
  final DateTime observedAt;
  int folderIndex = 0;
  int page = 1;
  int offset = 0;
  int? uidValidity;
  int? totalMessages;
  int scannedCount = 0;
  int matchedCount = 0;
  void nextFolder() {
    folderIndex++;
    page = 1;
    offset = 0;
    uidValidity = null;
    totalMessages = null;
  }

  _MailScan copy() => _MailScan(signature: signature, observedAt: observedAt)
    ..folderIndex = folderIndex
    ..page = page
    ..offset = offset
    ..uidValidity = uidValidity
    ..totalMessages = totalMessages
    ..scannedCount = scannedCount
    ..matchedCount = matchedCount;
}
