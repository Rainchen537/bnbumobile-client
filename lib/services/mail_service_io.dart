import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../config/app_config.dart';
import '../models/mail_models.dart';
import '../utils/mail_preview_text.dart';
import 'mail_html_sanitizer.dart';
import 'mail_service.dart';
import 'mail_local_cache.dart';
import 'mail_mutations.dart';
import 'mail_address_parser.dart';
import 'native_actions.dart';

part 'mail_service_organization.dart';

const mailListHeaderFetchCriteria =
    '(UID FLAGS RFC822.SIZE ENVELOPE '
    'BODY.PEEK[HEADER.FIELDS (SUBJECT FROM TO CC BCC REPLY-TO DATE MESSAGE-ID IN-REPLY-TO REFERENCES LIST-ID PRECEDENCE MIME-VERSION CONTENT-TYPE CONTENT-TRANSFER-ENCODING)])';

MailService createPlatformMailService({
  MailLocalCache? cache,
  MailClient Function(MailAccessCredentials)? clientFactory,
}) => _IoMailService(cache: cache, clientFactory: clientFactory);

/// Builds a standards-compliant outgoing message for both SMTP sends and IMAP
/// draft storage. When HTML and attachments are both present, the alternative
/// text bodies must be nested inside multipart/mixed; placing binary parts
/// directly in multipart/alternative makes some desktop and Android mail
/// clients hide either the body or the attachment.
MimeMessage buildOutgoingMailMimeMessage({
  required MailAccessCredentials credentials,
  required MailComposeData composeData,
}) {
  final htmlBody = composeData.htmlBody;
  final hasHtmlBody = htmlBody != null && htmlBody.isNotEmpty;
  final hasAttachments = composeData.attachments.isNotEmpty;

  late final MessageBuilder builder;
  if (hasAttachments) {
    builder = MessageBuilder.prepareMultipartMixedMessage();
    if (hasHtmlBody) {
      builder.addMultipartAlternative(
        plainText: composeData.body,
        htmlText: htmlBody,
      );
    } else {
      builder.addTextPlain(composeData.body);
    }
  } else if (hasHtmlBody) {
    builder = MessageBuilder.prepareMultipartAlternativeMessage(
      plainText: composeData.body,
      htmlText: htmlBody,
    );
  } else {
    builder = MessageBuilder.prepareMultipartMixedMessage()
      ..addTextPlain(composeData.body);
  }

  builder.from = [MailAddress(null, credentials.emailAddress)];
  if (composeData.to.isNotEmpty) {
    builder.to = parseMailRecipientAddresses(composeData.to);
  }
  if (composeData.cc != null && composeData.cc!.isNotEmpty) {
    builder.cc = parseMailRecipientAddresses(composeData.cc!);
  }
  if (composeData.bcc != null && composeData.bcc!.isNotEmpty) {
    builder.bcc = parseMailRecipientAddresses(composeData.bcc!);
  }
  builder.subject = composeData.subject;
  for (final attachment in composeData.attachments) {
    final fileName = safeAttachmentFileName(attachment.name);
    builder.addBinary(
      attachment.bytes,
      MediaType.guessFromFileName(fileName),
      filename: fileName,
    );
  }
  if (composeData.inReplyTo != null) {
    builder.addHeader('In-Reply-To', composeData.inReplyTo!);
  }
  if (composeData.references != null) {
    builder.addHeader('References', composeData.references!);
  }
  return builder.buildMimeMessage();
}

class _IoMailService
    implements
        MailService,
        MeVerificationMailReader,
        MailAuthenticationVerifier,
        MailInboxMonitor,
        MailOrganizationService,
        MailSortedFolderReader,
        MailFlagReader,
        MailCacheReader,
        MailInlineImageLoader {
  _IoMailService({
    MailLocalCache? cache,
    MailClient Function(MailAccessCredentials)? clientFactory,
  }) : _localCache = cache ?? MailLocalCache.shared,
       _clientFactory = clientFactory;
  final MailLocalCache _localCache;
  final MailClient Function(MailAccessCredentials)? _clientFactory;

  @override
  Future<void> verifyCredentials(MailAccessCredentials credentials) =>
      _serialize(() async {
        try {
          await _ensureConnected(credentials);
        } catch (error) {
          throw _mapError(error);
        }
      });

  @override
  Future<MailFolderSnapshot?> readCachedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    int page = 1,
    int pageSize = 25,
    bool unreadOnly = false,
  }) => _localCache.loadPage(
    credentials.emailAddress,
    folder,
    page: page,
    pageSize: pageSize,
    unreadOnly: unreadOnly,
  );

  @override
  Future<MailFolderSnapshot?> readCachedSortedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required MailSortOrder sortOrder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
  }) => _localCache.loadPage(
    credentials.emailAddress,
    folder,
    page: page,
    pageSize: pageSize,
    unreadOnly: unreadOnly,
    flaggedOnly: flaggedOnly,
    sortOrder: sortOrder,
  );

  @override
  Future<MailMessageDetail?> readCachedMessage({
    required MailAccessCredentials credentials,
    required MailMessageIdentity identity,
  }) => _localCache.loadDetail(credentials.emailAddress, identity);
  late final _MailOrganizationSession _organization = _MailOrganizationSession(
    this,
  );
  final Map<MailFolder, String> _resolvedFolderPaths = {};

  @override
  Future<Map<MailMessageIdentity, bool>> readSeenFlags({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
  }) => _organization.readSeenFlags(credentials, messages);

  @override
  Future<List<MailFolderInfo>> listFolders(MailAccessCredentials credentials) =>
      _organization.listFolders(credentials);

  @override
  Future<MailFolderSnapshot> fetchFilteredFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) => _organization.fetchFilteredFolder(
    credentials: credentials,
    folder: folder,
    unreadOnly: unreadOnly,
    flaggedOnly: flaggedOnly,
    page: page,
    pageSize: pageSize,
    expectedMailboxUidValidity: expectedMailboxUidValidity,
  );

  @override
  Future<MailFolderSnapshot> fetchSortedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required MailSortOrder sortOrder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) => _organization.fetchSortedFolder(
    credentials: credentials,
    folder: folder,
    sortOrder: sortOrder,
    unreadOnly: unreadOnly,
    flaggedOnly: flaggedOnly,
    page: page,
    pageSize: pageSize,
    expectedMailboxUidValidity: expectedMailboxUidValidity,
  );

  @override
  Future<List<MailMessageSummary>> loadPreviews({
    required MailAccessCredentials credentials,
    required List<MailMessageSummary> messages,
  }) => _organization.loadPreviews(credentials, messages);

  @override
  Future<void> setMessagesSeen({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    required bool seen,
  }) => _organization.setFlag(credentials, messages, MessageFlags.seen, seen);

  @override
  Future<void> setMessagesFlagged({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    required bool flagged,
  }) => _organization.setFlag(
    credentials,
    messages,
    MessageFlags.flagged,
    flagged,
  );

  @override
  Future<void> moveMessages({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    required MailFolder target,
  }) => _organization.moveMessages(credentials, messages, target);
  static final String _incomingServer = AppConfig.normalizedMailHost(
    AppConfig.mailIncomingServer,
    settingName: 'BNBU_MAIL_IMAP_HOST',
  );
  static final String _outgoingServer = AppConfig.normalizedMailHost(
    AppConfig.mailOutgoingServer,
    settingName: 'BNBU_MAIL_SMTP_HOST',
  );

  MailClient? _client;
  MailAccessCredentials? _activeCredentials;
  int _connectionGeneration = 0;
  final Queue<Future<void> Function()> _interactiveOperations = Queue();
  final Queue<Future<void> Function()> _backgroundOperations = Queue();
  bool _drainingOperations = false;
  final _loadedMimeParts = Expando<Set<String>>();
  final Set<(MailFolder, int?, int)> _completeText = {};
  final Set<(MailFolder, int?, int)> _pendingInlineImages = {};
  final StreamController<void> _inboxChanges =
      StreamController<void>.broadcast();
  StreamSubscription<MailEvent>? _mailEventSubscription;
  bool _inboxMonitoringDesired = false;
  final Map<(MailFolder, int?, int), MimeMessage> _messageCache =
      <(MailFolder, int?, int), MimeMessage>{};

  @override
  Stream<void> get inboxChanges => _inboxChanges.stream;

  @override
  Future<void> startInboxMonitoring({
    required MailAccessCredentials credentials,
  }) {
    _inboxMonitoringDesired = true;
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        await client.selectInbox();
        if (!client.isPolling()) {
          await client.startPolling();
        }
      } catch (error) {
        throw _mapError(error);
      }
    }).catchError((Object error) {
      _inboxMonitoringDesired = false;
      throw error;
    });
  }

  @override
  Future<void> stopInboxMonitoring() {
    _inboxMonitoringDesired = false;
    return _serialize(() async {
      final client = _client;
      if (client == null) return;
      try {
        await client.stopPollingIfNeeded();
      } catch (_) {
        // A lost connection is already handled by the periodic fallback scan.
      }
    });
  }

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) => _organization.fetchFilteredFolder(
    credentials: credentials,
    folder: folder,
    page: page,
    pageSize: pageSize,
    expectedMailboxUidValidity: expectedMailboxUidValidity,
  );

  @override
  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
    MailSearchScope searchScope = MailSearchScope.allText,
  }) {
    final lowerQuery = query.trim().toLowerCase();
    if (lowerQuery.isEmpty) return Future.value(const []);
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        final folderPath = _mapFolderToPath(folder);
        final mailbox = await client.selectMailboxByPath(folderPath);
        final uidValidity = mailbox.uidValidity;
        await _discardStaleMailboxCache(folder, uidValidity);

        final total = mailbox.messagesExists;
        if (total == 0) return const <MailMessageSummary>[];

        // Fetch all messages with envelope (from/subject/date/flags only)
        // for fast client-side filtering, since QQ exmail does not support
        // IMAP SEARCH criteria properly.
        final messages = await client.fetchMessages(
          mailbox: mailbox,
          count: total,
          fetchPreference: FetchPreference.envelope,
        );
        final validMessages = messages
            .where((message) => message.uid != null)
            .toList(growable: false);
        _cacheEnvelopeMessages(folder, uidValidity, validMessages);

        final summaries =
            validMessages
                .where(
                  (message) => _messageMatchesSearch(
                    message,
                    lowerQuery,
                    searchScope,
                    folder,
                    uidValidity,
                  ),
                )
                .map(
                  (message) => _toSummary(
                    message,
                    folder: folder,
                    mailboxUidValidity: uidValidity,
                  ),
                )
                .toList(growable: false)
              ..sort(_sortSummariesDesc);

        return summaries;
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  bool _messageMatchesSearch(
    MimeMessage message,
    String lowerQuery,
    MailSearchScope scope,
    MailFolder folder,
    int? mailboxUidValidity,
  ) {
    switch (scope) {
      case MailSearchScope.allText:
        return _subjectContains(message, lowerQuery) ||
            _fromContains(message, lowerQuery) ||
            _toContains(message, lowerQuery) ||
            _bodyContains(message, lowerQuery, folder, mailboxUidValidity);
      case MailSearchScope.subject:
        return _subjectContains(message, lowerQuery);
      case MailSearchScope.from:
        return _fromContains(message, lowerQuery);
      case MailSearchScope.to:
        return _toContains(message, lowerQuery);
    }
  }

  bool _subjectContains(MimeMessage message, String query) =>
      (message.decodeSubject()?.toLowerCase() ?? '').contains(query);

  bool _fromContains(MimeMessage message, String query) =>
      _addressListContains(message.from, query);

  bool _toContains(MimeMessage message, String query) =>
      _addressListContains(message.to, query) ||
      _addressListContains(message.cc, query);

  bool _addressListContains(List<MailAddress>? addresses, String query) {
    if (addresses == null || addresses.isEmpty) return false;
    return addresses.any(
      (addr) =>
          (addr.email.toLowerCase()).contains(query) ||
          (addr.personalName?.toLowerCase() ?? '').contains(query),
    );
  }

  bool _bodyContains(
    MimeMessage message,
    String query,
    MailFolder folder,
    int? mailboxUidValidity,
  ) {
    // Body is only available for fully-fetched cached messages.
    final uid = message.uid;
    if (uid == null) return false;
    final cached = _messageCache[(folder, mailboxUidValidity, uid)];
    if (cached == null) return false;
    final plain = cached.decodeTextPlainPart()?.toLowerCase() ?? '';
    return plain.contains(query);
  }

  @override
  Future<String?> readMeVerificationCode({
    required MailAccessCredentials credentials,
    required String challengeId,
    required DateTime since,
  }) => _serialize(() async {
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(challengeId)) return null;
    final client = await _ensureConnected(credentials);
    final mailbox = await client.selectMailboxByPath(
      _mapFolderToPath(MailFolder.inbox),
    );
    if (mailbox.messagesExists == 0) return null;
    final imap = client.lowLevelIncomingMailClient as ImapClient;
    final first = (mailbox.messagesExists - 9).clamp(1, mailbox.messagesExists);
    final fetched = await imap.fetchMessages(
      MessageSequence.fromRange(first, mailbox.messagesExists),
      '(UID RFC822.SIZE BODY.PEEK[HEADER.FIELDS (SUBJECT DATE X-BNBU-ME-CHALLENGE)])',
    );
    for (final message in fetched.messages.reversed) {
      if (message.decodeHeaderValue('X-BNBU-ME-Challenge')?.trim() !=
              challengeId ||
          (message.size == null || message.size! > 16384) ||
          message.uid == null) {
        continue;
      }
      final detail = await imap.uidFetchMessages(
        MessageSequence.fromId(message.uid!),
        'BODY.PEEK[]',
      );
      for (final item in detail.messages) {
        final body = item.decodeTextPlainPart() ?? '';
        if (!body.contains(challengeId)) continue;
        final match = RegExp(r'BNBU.ME 验证码：[ ]*([0-9]{6})').firstMatch(body);
        if (match != null) return match.group(1);
      }
    }
    return null;
  });

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) {
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        final mailbox = await client.selectMailboxByPath(
          _mapFolderToPath(folder),
        );
        final uidValidity = mailbox.uidValidity;
        _verifyMailboxIdentity(
          folder: folder,
          actualUidValidity: uidValidity,
          expectedUidValidity: expectedMailboxUidValidity,
          requireExpected: true,
        );
        await _discardStaleMailboxCache(folder, uidValidity);

        final cached = await _readStoredDetail(
          client,
          credentials,
          folder,
          uidValidity,
          uid,
          markAsSeen,
        );
        if (cached != null) return cached;
        final message = await _loadMessageEnvelope(
          client: client,
          mailbox: mailbox,
          folder: folder,
          mailboxUidValidity: uidValidity,
          uid: uid,
        );
        final loadedMessage = await _loadMessageDetailContents(
          client: client,
          mailbox: mailbox,
          folder: folder,
          mailboxUidValidity: uidValidity,
          uid: uid,
          message: message,
          markAsSeen: markAsSeen,
        );
        _messageCache[(folder, uidValidity, uid)] = loadedMessage;
        final detail = _toDetail(
          loadedMessage,
          folder: folder,
          mailboxUidValidity: uidValidity,
        );
        await _localCache.saveDetail(credentials.emailAddress, detail);
        return detail;
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<List<MailMessageDetail>> readMessages({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    bool markAsSeen = true,
  }) {
    if (messages.isEmpty) return Future.value(const []);
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        final grouped = <MailFolder, List<MailMessageIdentity>>{};
        for (final message in messages) {
          grouped.putIfAbsent(message.folder, () => []).add(message);
        }

        final detailsByIdentity = <(MailFolder, int, int), MailMessageDetail>{};
        for (final entry in grouped.entries) {
          final folder = entry.key;
          final identities = entry.value;
          final expectedValidities = identities
              .map((message) => message.mailboxUidValidity)
              .toSet();
          if (expectedValidities.length != 1) {
            throw const MailServiceException('同一邮箱文件夹的身份版本不一致，请刷新后重试。');
          }
          final mailbox = await client.selectMailboxByPath(
            _mapFolderToPath(folder),
          );
          final uidValidity = mailbox.uidValidity;
          _verifyMailboxIdentity(
            folder: folder,
            actualUidValidity: uidValidity,
            expectedUidValidity: expectedValidities.single,
            requireExpected: true,
          );
          await _discardStaleMailboxCache(folder, uidValidity);

          for (final identity in identities) {
            final cached = await _readStoredDetail(
              client,
              credentials,
              folder,
              uidValidity,
              identity.uid,
              markAsSeen,
            );
            if (cached != null) {
              detailsByIdentity[(
                    folder,
                    expectedValidities.single,
                    identity.uid,
                  )] =
                  cached;
              continue;
            }
            final message = await _loadMessageEnvelope(
              client: client,
              mailbox: mailbox,
              folder: folder,
              mailboxUidValidity: uidValidity,
              uid: identity.uid,
            );
            final loaded = await _loadMessageDetailContents(
              client: client,
              mailbox: mailbox,
              folder: folder,
              mailboxUidValidity: uidValidity,
              uid: identity.uid,
              message: message,
              markAsSeen: markAsSeen,
            );
            _messageCache[(folder, uidValidity, identity.uid)] = loaded;
            detailsByIdentity[(
              folder,
              expectedValidities.single,
              identity.uid,
            )] = _toDetail(
              loaded,
              folder: folder,
              mailboxUidValidity: uidValidity,
            );
            await _localCache.saveDetail(
              credentials.emailAddress,
              detailsByIdentity[(
                folder,
                expectedValidities.single,
                identity.uid,
              )]!,
            );
          }
        }

        return List.unmodifiable(
          messages.map((identity) {
            final detail =
                detailsByIdentity[(
                  identity.folder,
                  identity.mailboxUidValidity,
                  identity.uid,
                )];
            if (detail == null) {
              throw const MailServiceException('未找到这封邮件，请先刷新后重试。');
            }
            return detail;
          }),
        );
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<void> markMessagesSeen({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) {
    return _serialize(() async {
      if (uids.isEmpty) return;
      try {
        final client = await _ensureConnected(credentials);
        final mailbox = await client.selectMailboxByPath(
          _mapFolderToPath(folder),
        );
        _verifyMailboxIdentity(
          folder: folder,
          actualUidValidity: mailbox.uidValidity,
          expectedUidValidity: expectedMailboxUidValidity,
          requireExpected: true,
        );
        await client.markSeen(MessageSequence.fromIds(uids, isUid: true));
        await _localCache.updateFlags(
          credentials.emailAddress,
          uids
              .map(
                (uid) => MailMessageIdentity(
                  folder: folder,
                  uid: uid,
                  mailboxUidValidity: mailbox.uidValidity!,
                ),
              )
              .toList(),
          seen: true,
        );
        for (final uid in uids) {
          final cached = _messageCache[(folder, mailbox.uidValidity, uid)];
          if (cached != null) cached.isSeen = true;
        }
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  }) {
    return _serialize(() async {
      try {
        if (partId.trim().isEmpty) {
          throw const MailServiceException('附件参数错误。');
        }

        final client = await _ensureConnected(credentials);
        final mailbox = await client.selectMailboxByPath(
          _mapFolderToPath(folder),
        );
        final uidValidity = mailbox.uidValidity;
        _verifyMailboxIdentity(
          folder: folder,
          actualUidValidity: uidValidity,
          expectedUidValidity: expectedMailboxUidValidity,
          requireExpected: true,
        );
        await _discardStaleMailboxCache(folder, uidValidity);

        var message = await _loadMessageEnvelope(
          client: client,
          mailbox: mailbox,
          folder: folder,
          mailboxUidValidity: uidValidity,
          uid: uid,
        );
        message = await _loadMessageStructure(
          client: client,
          mailbox: mailbox,
          folder: folder,
          mailboxUidValidity: uidValidity,
          uid: uid,
          message: message,
        );

        final attachmentInfos = _attachmentContentInfos(message);
        if (attachmentInfos.isNotEmpty) {
          ContentInfo? attachmentInfo;
          for (final info in attachmentInfos) {
            if (info.fetchId == partId) {
              attachmentInfo = info;
              break;
            }
          }
          if (attachmentInfo == null) {
            throw const MailServiceException('未找到该附件。');
          }
          final loadedPart =
              message.getPart(attachmentInfo.fetchId) ??
              await client.fetchMessagePart(message, attachmentInfo.fetchId);
          final body = message.body;
          if (body != null &&
              body.fetchId == null &&
              (body.parts == null || body.parts!.isEmpty) &&
              attachmentInfo.fetchId == '1') {
            _applyBodyPartHeaders(loadedPart, body);
          }
          _messageCache[(folder, uidValidity, uid)] = message;
          return loadedPart.decodeContentBinary() ?? const [];
        }

        final index = int.tryParse(partId);
        if (index == null || index < 0) {
          throw const MailServiceException('附件参数错误。');
        }
        final allParts = message.allPartsFlat;
        if (index >= allParts.length) {
          throw const MailServiceException('未找到该附件。');
        }
        final part = allParts[index];
        final contentDisposition =
            part.decodeHeaderValue('Content-Disposition')?.toLowerCase() ?? '';
        if (!contentDisposition.contains('attachment')) {
          throw const MailServiceException('未找到该附件。');
        }
        return part.decodeContentBinary() ?? const [];
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) {
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);

        final mimeMessage = buildOutgoingMailMimeMessage(
          credentials: credentials,
          composeData: composeData,
        );
        await client.sendMessage(mimeMessage);
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) {
    if (uids.isEmpty) return Future.value();
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        if (client.mailboxes == null) {
          await client.listMailboxes();
        }
        final mailbox = await client.selectMailboxByPath(
          _mapFolderToPath(folder),
        );
        final uidValidity = mailbox.uidValidity;
        _verifyMailboxIdentity(
          folder: folder,
          actualUidValidity: uidValidity,
          expectedUidValidity: expectedMailboxUidValidity,
          requireExpected: true,
        );
        final transport = _ImapMutationTransport(
          client.lowLevelIncomingMailClient as ImapClient,
        );
        if (folder == MailFolder.trash) {
          await deleteMailPermanentlySafely(transport, uids);
        } else {
          await moveMailSafely(
            transport,
            uids,
            _mapFolderToPath(MailFolder.trash),
          );
        }

        if (uidValidity != null) {
          await _localCache.remove(
            credentials.emailAddress,
            uids
                .map(
                  (uid) => MailMessageIdentity(
                    folder: folder,
                    uid: uid,
                    mailboxUidValidity: uidValidity,
                  ),
                )
                .toList(),
          );
        }
        for (final uid in uids) {
          _messageCache.remove((folder, uidValidity, uid));
        }
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  }) {
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        final draftsMailbox = await client.selectMailboxByPath(
          _mapFolderToPath(MailFolder.drafts),
        );
        final draftsUidValidity = draftsMailbox.uidValidity;
        _discardStaleMailboxCache(MailFolder.drafts, draftsUidValidity);

        // A UID is only meaningful within the exact Drafts UIDVALIDITY epoch.
        if (existingDraftUid != null) {
          if (expectedMailboxUidValidity == null || draftsUidValidity == null) {
            throw const MailServiceException('草稿箱身份不可用，请刷新草稿箱后重试。');
          }
          _verifyMailboxIdentity(
            folder: MailFolder.drafts,
            actualUidValidity: draftsUidValidity,
            expectedUidValidity: expectedMailboxUidValidity,
          );
        }

        final mimeMessage = buildOutgoingMailMimeMessage(
          credentials: credentials,
          composeData: composeData,
        );

        // Save the new content exactly once before touching the previous copy.
        // An ambiguous APPEND must not be retried against another folder path.
        final uidResponse = await client.appendMessage(
          mimeMessage,
          draftsMailbox,
          flags: [MessageFlags.draft, MessageFlags.seen],
        );
        final newUid = uidResponse?.targetSequence.toList(null).firstOrNull;
        if (uidResponse == null || newUid == null) return null;
        var previousDraftRetained = existingDraftUid != null;
        if (existingDraftUid != null &&
            uidResponse.uidValidity == draftsUidValidity) {
          try {
            await deleteMailPermanentlySafely(
              _ImapMutationTransport(
                client.lowLevelIncomingMailClient as ImapClient,
              ),
              [existingDraftUid],
            );
            previousDraftRetained = false;
            if (draftsUidValidity != null) {
              await _localCache.remove(credentials.emailAddress, [
                MailMessageIdentity(
                  folder: MailFolder.drafts,
                  uid: existingDraftUid,
                  mailboxUidValidity: draftsUidValidity,
                ),
              ]);
            }
            _messageCache.remove((
              MailFolder.drafts,
              draftsUidValidity,
              existingDraftUid,
            ));
          } catch (_) {
            // The new identity remains authoritative even if cleanup failed.
            // Returning it prevents autosave from duplicating the new content.
          }
        }
        return MailDraftIdentity(
          uid: newUid,
          mailboxUidValidity: uidResponse.uidValidity,
          previousDraftRetained: previousDraftRetained,
        );
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  @override
  Future<void> restoreMessages({
    required MailAccessCredentials credentials,
    required List<int> uids,
    required String userEmailAddress,
    int? expectedMailboxUidValidity,
  }) {
    if (uids.isEmpty) return Future.value();
    return _serialize(() async {
      try {
        final client = await _ensureConnected(credentials);
        final imapClient = client.lowLevelIncomingMailClient as ImapClient;

        // Select trash so subsequent IMAP commands operate on it.
        final mailbox = await client.selectMailboxByPath(
          _mapFolderToPath(MailFolder.trash),
        );
        final uidValidity = mailbox.uidValidity;
        _verifyMailboxIdentity(
          folder: MailFolder.trash,
          actualUidValidity: uidValidity,
          expectedUidValidity: expectedMailboxUidValidity,
          requireExpected: true,
        );
        final sequence = MessageSequence.fromIds(uids, isUid: true);

        // Fetch FLAGS + FROM for each UID to determine the restore target folder.
        final fetchResult = await imapClient.uidFetchMessages(
          sequence,
          '(UID FLAGS ENVELOPE)',
        );

        // Group UIDs by their inferred restore target folder.
        final Map<String, List<int>> byFolder = {};
        final Set<int> foundUids = {};
        for (final msg in fetchResult.messages) {
          final uid = msg.uid;
          if (uid == null) continue;
          foundUids.add(uid);
          final targetPath = _inferRestoreFolder(msg, userEmailAddress);
          byFolder.putIfAbsent(targetPath, () => []).add(uid);
        }

        // Any UIDs not returned by the server fall back to INBOX.
        for (final uid in uids) {
          if (!foundUids.contains(uid)) {
            byFolder.putIfAbsent('INBOX', () => []).add(uid);
          }
        }

        final transport = _ImapMutationTransport(imapClient);
        for (final entry in byFolder.entries) {
          await moveMailSafely(transport, entry.value, entry.key);
        }

        if (uidValidity != null) {
          await _localCache.remove(
            credentials.emailAddress,
            uids
                .map(
                  (uid) => MailMessageIdentity(
                    folder: MailFolder.trash,
                    uid: uid,
                    mailboxUidValidity: uidValidity,
                  ),
                )
                .toList(),
          );
        }
        for (final uid in uids) {
          _messageCache.remove((MailFolder.trash, uidValidity, uid));
        }
      } catch (error) {
        throw _mapError(error);
      }
    });
  }

  /// Infers the folder a trash message originally came from.
  ///
  /// Priority (checked in order):
  ///   1. Message has `\Draft` flag → 'Drafts'
  ///   2. FROM address matches [userEmailAddress] → 'Sent Messages'
  ///   3. Otherwise → 'INBOX'
  String _inferRestoreFolder(MimeMessage message, String userEmailAddress) {
    final flags = message.flags;
    if (flags != null && flags.contains(MessageFlags.draft)) {
      return 'Drafts';
    }
    final from = message.from;
    if (from != null) {
      for (final addr in from) {
        if (addr.email.toLowerCase() == userEmailAddress.toLowerCase()) {
          return 'Sent Messages';
        }
      }
    }
    return 'INBOX';
  }

  Future<T> _serialize<T>(
    Future<T> Function() operation, {
    bool background = false,
  }) {
    final completer = Completer<T>();
    (background ? _backgroundOperations : _interactiveOperations).add(() async {
      try {
        completer.complete(
          await (() async {
            final client = _client;
            final resumeMonitoring =
                _inboxMonitoringDesired && (client?.isPolling() ?? false);
            if (resumeMonitoring) await client!.stopPollingIfNeeded();
            try {
              return await operation();
            } finally {
              final activeClient = _client;
              if (_inboxMonitoringDesired &&
                  resumeMonitoring &&
                  activeClient != null &&
                  activeClient.isConnected &&
                  !activeClient.isPolling()) {
                try {
                  await activeClient.startPolling();
                } catch (_) {
                  // The fallback scan reconnects if IMAP IDLE cannot resume.
                }
              }
            }
          })(),
        );
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    unawaited(_drainOperations());
    return completer.future;
  }

  Future<void> _drainOperations() async {
    if (_drainingOperations) return;
    _drainingOperations = true;
    try {
      while (_interactiveOperations.isNotEmpty ||
          _backgroundOperations.isNotEmpty) {
        final queue = _interactiveOperations.isNotEmpty
            ? _interactiveOperations
            : _backgroundOperations;
        await queue.removeFirst()();
      }
    } finally {
      _drainingOperations = false;
    }
  }

  void _verifyMailboxIdentity({
    required MailFolder folder,
    required int? actualUidValidity,
    required int? expectedUidValidity,
    bool requireExpected = false,
  }) {
    if (expectedUidValidity == null) {
      if (!requireExpected) return;
      throw MailServiceException('${_folderDisplayName(folder)}身份不可用，请刷新后重试。');
    }
    if (actualUidValidity == expectedUidValidity) return;
    throw MailServiceException('${_folderDisplayName(folder)}已更新，请刷新后重试。');
  }

  Future<void> _discardStaleMailboxCache(
    MailFolder folder,
    int? mailboxUidValidity,
  ) async {
    final account = _activeCredentials?.emailAddress;
    if (account != null) {
      await _localCache.validateMailbox(account, folder, mailboxUidValidity);
    }
    _messageCache.removeWhere(
      (key, _) => key.$1 == folder && key.$2 != mailboxUidValidity,
    );
  }

  void _cacheEnvelopeMessages(
    MailFolder folder,
    int? mailboxUidValidity,
    Iterable<MimeMessage> messages,
  ) {
    for (final message in messages) {
      final uid = message.uid;
      if (uid == null) continue;
      _messageCache.putIfAbsent((
        folder,
        mailboxUidValidity,
        uid,
      ), () => message);
    }
  }

  Future<MailMessageDetail?> _readStoredDetail(
    MailClient client,
    MailAccessCredentials credentials,
    MailFolder folder,
    int? validity,
    int uid,
    bool markAsSeen,
  ) async {
    if (validity == null) return null;
    final identity = MailMessageIdentity(
      folder: folder,
      uid: uid,
      mailboxUidValidity: validity,
    );
    final detail = await _localCache.loadDetail(
      credentials.emailAddress,
      identity,
    );
    if (detail == null) return null;
    final sequence = MessageSequence.fromIds([uid], isUid: true);
    final flags = await (client.lowLevelIncomingMailClient as ImapClient)
        .uidFetchMessages(sequence, '(UID FLAGS)');
    final current = flags.messages.where((m) => m.uid == uid).firstOrNull;
    if (current == null) {
      await _localCache.remove(credentials.emailAddress, [identity]);
      throw const MailServiceException('未找到这封邮件，请先刷新后重试。');
    }
    if (markAsSeen && !current.isSeen) await client.markSeen(sequence);
    await _localCache.updateFlags(credentials.emailAddress, [
      identity,
    ], seen: markAsSeen || current.isSeen);
    return detail.withSeen(markAsSeen || current.isSeen);
  }

  Future<MimeMessage> _loadMessageEnvelope({
    required MailClient client,
    required Mailbox mailbox,
    required MailFolder folder,
    required int? mailboxUidValidity,
    required int uid,
  }) async {
    final key = (folder, mailboxUidValidity, uid);
    final cached = _messageCache[key];
    if (cached != null) return cached;

    final fetched = await (client.lowLevelIncomingMailClient as ImapClient)
        .uidFetchMessages(
          MessageSequence.fromIds([uid], isUid: true),
          mailListHeaderFetchCriteria,
        );
    for (final message in fetched.messages) {
      if (message.uid == uid) {
        _messageCache[key] = message;
        return message;
      }
    }
    throw const MailServiceException('未找到这封邮件，请先刷新后重试。');
  }

  Future<MimeMessage> _loadMessageStructure({
    required MailClient client,
    required Mailbox mailbox,
    required MailFolder folder,
    required int? mailboxUidValidity,
    required int uid,
    required MimeMessage message,
  }) async {
    if (message.body != null) return message;

    final messages = await client.fetchMessageSequence(
      MessageSequence.fromIds([uid], isUid: true),
      mailbox: mailbox,
      fetchPreference: FetchPreference.bodystructure,
    );
    for (final structuredMessage in messages) {
      if (structuredMessage.uid != uid) continue;
      message
        ..body = structuredMessage.body
        ..flags = structuredMessage.flags ?? message.flags
        ..size = structuredMessage.size ?? message.size;
      if (message.body == null) {
        throw const MailServiceException('无法读取邮件结构，请稍后重试。');
      }
      _messageCache[(folder, mailboxUidValidity, uid)] = message;
      return message;
    }
    throw const MailServiceException('未找到这封邮件，请先刷新后重试。');
  }

  Future<MimeMessage> _loadMessageDetailContents({
    required MailClient client,
    required Mailbox mailbox,
    required MailFolder folder,
    required int? mailboxUidValidity,
    required int uid,
    required MimeMessage message,
    required bool markAsSeen,
  }) async {
    final loadedMessage = await _loadMessageStructure(
      client: client,
      mailbox: mailbox,
      folder: folder,
      mailboxUidValidity: mailboxUidValidity,
      uid: uid,
      message: message,
    );
    await _loadTextParts(
      client,
      loadedMessage,
      folder,
      mailboxUidValidity,
      budget: 8 * 1024 * 1024,
      requireComplete: true,
    );
    if (markAsSeen && !loadedMessage.isSeen) {
      await client.store(MessageSequence.fromMessage(loadedMessage), [
        MessageFlags.seen,
      ], action: StoreAction.add);
      loadedMessage.isSeen = true;
    }
    return loadedMessage;
  }

  List<BodyPart> _readableParts(BodyPart body, MediaToptype type) {
    if (body.contentDisposition?.disposition == ContentDisposition.attachment) {
      return [];
    }
    if (body.contentType?.mediaType.top == type) return [body];
    if (body.contentType?.mediaType.top != MediaToptype.multipart) return [];
    return [
      for (final child in body.parts ?? <BodyPart>[])
        ..._readableParts(child, type),
    ];
  }

  Future<bool> _loadTextParts(
    MailClient client,
    MimeMessage message,
    MailFolder folder,
    int? validity, {
    required int budget,
    bool requireComplete = false,
  }) async {
    final key = (folder, validity, message.uid!);
    if (_completeText.contains(key)) return true;
    final body = message.body!;
    final parts = _readableParts(body, MediaToptype.text);
    var remaining = budget;
    final accepted = <BodyPart>[];
    for (final part in parts) {
      final size = part.size;
      if (size == null || size > remaining) continue;
      accepted.add(part);
      remaining -= size;
    }
    final complete = accepted.length == parts.length;
    if (!complete && requireComplete) {
      throw const MailServiceException('邮件正文超过安全读取上限。');
    }
    await _fetchParts(client, message, accepted);
    if (complete) _completeText.add(key);
    if (_readableParts(body, MediaToptype.image).isNotEmpty) {
      _pendingInlineImages.add(key);
    }
    return complete;
  }

  Future<void> _fetchParts(
    MailClient client,
    MimeMessage message,
    List<BodyPart> parts,
  ) async {
    if (parts.isEmpty) return;
    final loaded = _loadedMimeParts[message] ??= <String>{};
    final missing = parts
        .where((part) => !loaded.contains(part.fetchId ?? '1'))
        .toList();
    if (missing.isEmpty) return;
    final result = await (client.lowLevelIncomingMailClient as ImapClient)
        .uidFetchMessages(
          MessageSequence.fromIds([message.uid!], isUid: true),
          '(UID FLAGS ${missing.map((part) => 'BODY.PEEK[${part.fetchId ?? '1'}]').join(' ')})',
        );
    final fetched = result.messages
        .where((m) => m.uid == message.uid)
        .firstOrNull;
    if (fetched == null) throw const MailServiceException('邮件内容暂时不可用。');
    // Do not replace already complete mail headers with partial FETCH data.
    for (final body in missing) {
      final id = body.fetchId ?? '1';
      final part = fetched.getPart(id);
      if (part == null) throw const MailServiceException('邮件正文片段暂时不可用。');
      _applyBodyPartHeaders(part, body);
      part.addHeader('Content-Transfer-Encoding', body.encoding);
      if (body.cid != null) part.addHeader('Content-ID', body.cid);
      message.setPart(id, part);
      loaded.add(id);
      if (body.fetchId == null && body.parts?.isNotEmpty != true) {
        message.mimeData = part.mimeData;
        _applyBodyPartHeaders(message, body);
        message.addHeader('Content-Transfer-Encoding', body.encoding);
      }
    }
    message.flags = fetched.flags ?? message.flags;
  }

  @override
  Future<MailMessageDetail> loadInlineImages({
    required MailAccessCredentials credentials,
    required MailMessageDetail detail,
  }) => _serialize(() async {
    final client = await _ensureConnected(credentials);
    final box = await client.selectMailboxByPath(
      _mapFolderToPath(detail.folder),
    );
    _verifyMailboxIdentity(
      folder: detail.folder,
      actualUidValidity: box.uidValidity,
      expectedUidValidity: detail.mailboxUidValidity,
      requireExpected: true,
    );
    final message = await _loadMessageEnvelope(
      client: client,
      mailbox: box,
      folder: detail.folder,
      mailboxUidValidity: box.uidValidity,
      uid: detail.uid,
    );
    await _loadMessageStructure(
      client: client,
      mailbox: box,
      folder: detail.folder,
      mailboxUidValidity: box.uidValidity,
      uid: detail.uid,
      message: message,
    );
    var remaining = 2 * 1024 * 1024;
    final images = <BodyPart>[];
    for (final image in _readableParts(message.body!, MediaToptype.image)) {
      if (image.cid == null || image.size == null || image.size! > remaining) {
        continue;
      }
      images.add(image);
      remaining -= image.size!;
    }
    await _fetchParts(client, message, images);
    _pendingInlineImages.remove((detail.folder, box.uidValidity, detail.uid));
    final html = html_parser.parse(detail.htmlBody ?? '');
    for (final image in images) {
      final bytes = message
          .getPart(image.fetchId ?? '1')
          ?.decodeContentBinary();
      if (bytes == null) continue;
      final cid = image.cid!.replaceAll(RegExp(r'[<>]'), '');
      for (final node in html.querySelectorAll('img[src]')) {
        if (node.attributes['src'] == 'cid:$cid') {
          node.attributes['src'] =
              'data:${image.contentType!.mediaType.text};base64,${base64Encode(bytes)}';
        }
      }
    }
    final enriched = detail
        .withInlineImages(html.outerHtml)
        .withSeen(message.isSeen);
    await _localCache.saveDetail(credentials.emailAddress, enriched);
    return enriched;
  }, background: true);

  void _applyBodyPartHeaders(MimePart part, BodyPart body) {
    final contentType = body.contentType;
    if (contentType != null &&
        part.decodeHeaderValue(MailConventions.headerContentType) == null) {
      part.addHeader(MailConventions.headerContentType, contentType.render());
    }
    final contentDisposition = body.contentDisposition;
    if (contentDisposition != null &&
        part.decodeHeaderValue(MailConventions.headerContentDisposition) ==
            null) {
      part.addHeader(
        MailConventions.headerContentDisposition,
        contentDisposition.render(),
      );
    }
    final encoding = body.encoding;
    if (encoding != null &&
        part.decodeHeaderValue(MailConventions.headerContentTransferEncoding) ==
            null) {
      part.addHeader(MailConventions.headerContentTransferEncoding, encoding);
    }
  }

  @override
  Future<void> close() {
    _inboxMonitoringDesired = false;
    return _serialize(_closeConnection);
  }

  Future<void> _closeConnection() async {
    _connectionGeneration++;
    _messageCache.clear();
    _completeText.clear();
    _pendingInlineImages.clear();
    _activeCredentials = null;
    final client = _client;
    _client = null;
    await _mailEventSubscription?.cancel();
    _mailEventSubscription = null;
    if (client == null) {
      return;
    }
    try {
      await client.disconnect();
    } catch (_) {
      // Ignore disconnect failures during teardown.
    }
  }

  Future<MailClient> _ensureConnected(MailAccessCredentials credentials) async {
    final activeCredentials = _activeCredentials;
    final client = _client;
    final sameCredentials =
        activeCredentials?.emailAddress == credentials.emailAddress &&
        activeCredentials?.password == credentials.password;
    if (client != null && sameCredentials && client.isConnected) {
      return client;
    }

    await _closeConnection();
    final connectionGeneration = ++_connectionGeneration;
    final nextClient =
        _clientFactory?.call(credentials) ??
        MailClient(
          MailAccount.fromManualSettings(
            name: 'BNBU Mail',
            email: credentials.emailAddress,
            userName: credentials.userId,
            incomingHost: _incomingServer,
            outgoingHost: _outgoingServer,
            password: credentials.password,
            outgoingClientDomain: 'mail.bnbu.edu.cn',
          ),
          downloadSizeLimit: 64 * 1024,
        );
    try {
      await nextClient.connect(timeout: const Duration(seconds: 20));
      if (connectionGeneration != _connectionGeneration) {
        try {
          await nextClient.disconnect();
        } catch (_) {
          // Ignore teardown failures for a superseded connection.
        }
        throw const MailServiceException('邮箱连接已关闭，请重试。');
      }
      _client = nextClient;
      _activeCredentials = credentials;
      _resolvedFolderPaths.clear();
      await _organization.discoverFolders(nextClient);
      _mailEventSubscription = nextClient.eventBus.on<MailEvent>().listen((
        event,
      ) {
        if (event is MailLoadEvent ||
            (event is MailConnectionReEstablishedEvent &&
                event.isManualSynchronizationRequired)) {
          if (!_inboxChanges.isClosed) _inboxChanges.add(null);
        }
      });
      return nextClient;
    } catch (_) {
      try {
        await nextClient.disconnect();
      } catch (_) {
        // Ignore cleanup failures for an incomplete connection.
      }
      if (connectionGeneration == _connectionGeneration) {
        _activeCredentials = null;
      }
      rethrow;
    }
  }

  String _folderDisplayName(MailFolder folder) {
    switch (folder) {
      case MailFolder.inbox:
        return '收件箱';
      case MailFolder.sent:
        return '已发送';
      case MailFolder.drafts:
        return '草稿箱';
      case MailFolder.trash:
        return '已删除';
      case MailFolder.junk:
        return '垃圾邮件';
    }
  }

  String _mapFolderToPath(MailFolder folder) {
    final discovered = _resolvedFolderPaths[folder];
    if (discovered != null) return discovered;
    switch (folder) {
      case MailFolder.inbox:
        return 'INBOX';
      case MailFolder.sent:
        return 'Sent Messages';
      case MailFolder.drafts:
        return 'Drafts';
      case MailFolder.trash:
        return 'Deleted Messages';
      case MailFolder.junk:
        throw const MailServiceException('学校邮箱未提供可用的垃圾邮件箱。');
    }
  }

  MailMessageSummary _toSummary(
    MimeMessage message, {
    required MailFolder folder,
    required int? mailboxUidValidity,
  }) {
    final plainText = _extractPlainText(message);
    final htmlBody = _extractHtmlSource(message);
    return MailMessageSummary(
      uid: message.uid!,
      subject: _resolvedSubject(message),
      sender: _resolvedSender(message),
      recipients: _joinAddresses(message.to),
      preview: _buildPreview(plainText),
      hasHtmlBody: htmlBody.isNotEmpty,
      date: message.decodeDate(),
      isSeen: message.isSeen,
      isFlagged: message.isFlagged,
      messageId: message.getHeaderValue('Message-ID') ?? '',
      inReplyTo: message.getHeaderValue('In-Reply-To') ?? '',
      references: message.getHeaderValue('References') ?? '',
      hasAttachments: message.hasAttachments(),
      folder: folder,
      mailboxUidValidity: mailboxUidValidity,
      messageSizeBytes: message.size,
    );
  }

  List<ContentInfo> _attachmentContentInfos(MimeMessage message) {
    final body = message.body;
    if (body == null) return const [];
    final result = <ContentInfo>[];
    body.collectContentInfo(ContentDisposition.attachment, result);
    if (result.isEmpty &&
        (body.parts == null || body.parts!.isEmpty) &&
        body.contentDisposition?.disposition == ContentDisposition.attachment) {
      final contentDisposition = body.contentDisposition;
      if (contentDisposition != null && contentDisposition.size == null) {
        contentDisposition.size = body.size;
      }
      result.add(
        ContentInfo('1')
          ..contentDisposition = contentDisposition
          ..contentType = body.contentType
          ..cid = body.cid,
      );
    }
    return result
        .where((info) => info.fetchId.trim().isNotEmpty)
        .toList(growable: false);
  }

  MailMessageDetail _toDetail(
    MimeMessage message, {
    required MailFolder folder,
    required int? mailboxUidValidity,
  }) {
    final recipients = _joinAddresses(message.to);
    final cc = _joinAddresses(message.cc);
    final plainText = _extractPlainText(message);
    final htmlBody = _buildRenderableHtml(message);

    final attachments = <MailAttachment>[];
    final attachmentInfos = _attachmentContentInfos(message);
    if (attachmentInfos.isNotEmpty) {
      for (final info in attachmentInfos) {
        attachments.add(
          MailAttachment(
            name: info.fileName ?? '未命名附件',
            size: info.size ?? 0,
            mimeType: info.mediaType?.toString() ?? 'application/octet-stream',
            contentId: info.cid,
            partId: info.fetchId,
          ),
        );
      }
    } else {
      final allParts = message.allPartsFlat;
      for (var i = 0; i < allParts.length; i++) {
        final part = allParts[i];
        final contentDisposition =
            part.decodeHeaderValue('Content-Disposition')?.toLowerCase() ?? '';
        if (contentDisposition.contains('attachment')) {
          attachments.add(
            MailAttachment(
              name: part.decodeFileName() ?? '未命名附件',
              size: 0,
              mimeType:
                  part.decodeHeaderValue('Content-Type') ??
                  'application/octet-stream',
              contentId: part.decodeHeaderValue('Content-ID'),
              partId: i.toString(),
            ),
          );
        }
      }
    }

    return MailMessageDetail(
      uid: message.uid ?? 0,
      subject: _resolvedSubject(message),
      sender: _resolvedSender(message),
      recipients: recipients.isEmpty ? '未解析到收件人' : recipients,
      cc: cc.isEmpty ? null : cc,
      date: message.decodeDate(),
      body: plainText.isNotEmpty
          ? _normalizeReadableText(plainText)
          : _extractReadableText(message),
      htmlBody: htmlBody.isEmpty ? null : htmlBody,
      inlineImagesLoaded: !_pendingInlineImages.contains((
        folder,
        mailboxUidValidity,
        message.uid,
      )),
      isSeen: message.isSeen,
      attachments: attachments,
      messageId: message.getHeaderValue('Message-Id'),
      inReplyTo: message.getHeaderValue('In-Reply-To'),
      references: message.getHeaderValue('References'),
      listId: message.getHeaderValue('List-Id'),
      precedence: message.getHeaderValue('Precedence'),
      mailboxUidValidity: mailboxUidValidity,
      folder: folder,
      messageSizeBytes: message.size,
    );
  }

  int _sortMessagesDesc(MimeMessage left, MimeMessage right) {
    final leftDate = left.decodeDate();
    final rightDate = right.decodeDate();
    if (leftDate != null && rightDate != null) {
      return rightDate.compareTo(leftDate);
    }
    return (right.uid ?? 0).compareTo(left.uid ?? 0);
  }

  int _sortSummariesDesc(MailMessageSummary left, MailMessageSummary right) {
    final leftDate = left.date;
    final rightDate = right.date;
    if (leftDate != null && rightDate != null) {
      return rightDate.compareTo(leftDate);
    }
    return right.uid.compareTo(left.uid);
  }

  String _resolvedSubject(MimeMessage message) {
    final subject = message.decodeSubject()?.trim() ?? '';
    return subject.isEmpty ? '(无主题)' : subject;
  }

  String _resolvedSender(MimeMessage message) {
    final from = message.from;
    if (from == null || from.isEmpty) {
      return '未知发件人';
    }
    final primary = from.first;
    final personalName = primary.personalName?.trim() ?? '';
    if (personalName.isNotEmpty) {
      return '$personalName <${primary.email}>';
    }
    return primary.email;
  }

  String _joinAddresses(List<MailAddress>? addresses) {
    if (addresses == null || addresses.isEmpty) {
      return '';
    }
    return addresses
        .map((address) {
          final personalName = address.personalName?.trim() ?? '';
          if (personalName.isNotEmpty) {
            return '$personalName <${address.email}>';
          }
          return address.email;
        })
        .join('，');
  }

  String _buildPreview(String plainText) {
    final body = normalizeMailPreviewText(plainText);
    if (body.isEmpty) {
      return '';
    }
    final codePoints = body.runes;
    if (codePoints.length <= 88) return body;
    return '${String.fromCharCodes(codePoints.take(88))}...';
  }

  String _extractReadableText(MimeMessage message) {
    final plainText = _extractPlainText(message);
    if (plainText.isNotEmpty) {
      return _normalizeReadableText(plainText);
    }
    final htmlText = _extractHtmlSource(message);
    if (htmlText.isEmpty) {
      return '';
    }
    return _extractReadableHtml(htmlText);
  }

  String? _decodeFetchedText(MimeMessage message, MediaSubtype subtype) {
    final body = message.body;
    if (body == null) return null;
    for (final part in _readableParts(body, MediaToptype.text)) {
      if (part.contentType?.mediaType.sub != subtype) continue;
      final data = message.getPart(part.fetchId ?? '1')?.mimeData;
      if (data != null) return data.decodeText(part.contentType, part.encoding);
    }
    return null;
  }

  String _extractPlainText(MimeMessage message) {
    return (_decodeFetchedText(message, MediaSubtype.textPlain) ??
                message.decodeTextPlainPart())
            ?.trim() ??
        '';
  }

  String _extractHtmlSource(MimeMessage message) {
    return (_decodeFetchedText(message, MediaSubtype.textHtml) ??
                message.decodeTextHtmlPart())
            ?.trim() ??
        '';
  }

  String _buildRenderableHtml(MimeMessage message) {
    // The isolation-critical sanitization lives in the shared, dependency-light
    // buildRenderableMailHtml so it can be unit tested and reused by every
    // renderer. Do not reintroduce a local element-stripping pass here.
    return buildRenderableMailHtml(_extractHtmlSource(message));
  }

  String _extractReadableHtml(String htmlText) {
    final normalizedHtml = htmlText
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(
          RegExp(
            r'</(p|div|li|tr|section|article|h[1-6])>',
            caseSensitive: false,
          ),
          '\n',
        );
    final parsed = html_parser.parse(normalizedHtml);
    for (final element in parsed.querySelectorAll(
      'script,style,head,title,meta,link',
    )) {
      element.remove();
    }
    final text = _flattenHtmlText(parsed.body ?? parsed.documentElement);
    return _normalizeReadableText(text);
  }

  String _flattenHtmlText(dom.Node? node) {
    if (node == null) {
      return '';
    }
    if (node is dom.Text) {
      return node.text;
    }
    if (node is! dom.Element) {
      return node.text ?? '';
    }
    final buffer = StringBuffer();
    final tag = node.localName?.toLowerCase();
    final isBlock = const {
      'p',
      'div',
      'section',
      'article',
      'header',
      'footer',
      'aside',
      'main',
      'ul',
      'ol',
      'li',
      'table',
      'tr',
      'td',
      'th',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
    }.contains(tag);
    if (tag == 'br') {
      return '\n';
    }
    for (final child in node.nodes) {
      buffer.write(_flattenHtmlText(child));
      if (child is dom.Element && child.localName?.toLowerCase() == 'br') {
        continue;
      }
    }
    if (isBlock) {
      buffer.write('\n');
    }
    return buffer.toString();
  }

  String _normalizeReadableText(String input) {
    return input
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[ \t\f\v]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  MailServiceException _mapError(Object error) {
    if (error is MailServiceException) {
      return error;
    }
    if (error is SocketException || error is TimeoutException) {
      _discardBrokenConnection();
      return const MailServiceException(
        '邮箱服务器连接失败，请检查网络后重试。',
        isRetryable: true,
      );
    }
    if (error is MailException) {
      final message = (error.message ?? '').toLowerCase();
      if (_looksLikeConnectionFailure(message) ||
          error.details is SocketException ||
          error.details is TimeoutException) {
        _discardBrokenConnection();
        return const MailServiceException(
          '邮箱连接中断，正在重新建立连接。',
          isRetryable: true,
        );
      }
      if (isExplicitMailAuthenticationFailure(message)) {
        return const MailAuthenticationException();
      }
      // Never render raw server/command errors: they can echo LOGIN arguments.
      return const MailServiceException('邮箱服务暂时不可用，请稍后重试。');
    }
    return const MailServiceException('邮箱加载失败，请稍后重试。');
  }

  bool _looksLikeConnectionFailure(String message) {
    return message.contains('socket') ||
        message.contains('connection') ||
        message.contains('connect') ||
        message.contains('closed') ||
        message.contains('timeout') ||
        message.contains('timed out') ||
        message.contains('network');
  }

  void _discardBrokenConnection() {
    _connectionGeneration++;
    _messageCache.clear();
    _completeText.clear();
    _pendingInlineImages.clear();
    _activeCredentials = null;
    final client = _client;
    _client = null;
    if (client != null) {
      unawaited(client.disconnect().catchError((_) {}));
    }
  }
}
