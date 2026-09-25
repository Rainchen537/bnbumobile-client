part of 'mail_service_io.dart';

class _MailOrganizationSession {
  _MailOrganizationSession(this.owner);
  final _IoMailService owner;
  final Map<String, List<int>> _fallbackDateOrderCache = {};

  static const _headerFields = mailListHeaderFetchCriteria;

  Future<void> discoverFolders(MailClient client) async {
    final boxes = await client.listMailboxes();
    const flags = {
      MailFolder.inbox: MailboxFlag.inbox,
      MailFolder.sent: MailboxFlag.sent,
      MailFolder.drafts: MailboxFlag.drafts,
      MailFolder.trash: MailboxFlag.trash,
      MailFolder.junk: MailboxFlag.junk,
    };
    const aliases = {
      MailFolder.inbox: {'inbox'},
      MailFolder.sent: {'sent messages', 'sent', '已发送'},
      MailFolder.drafts: {'drafts', '草稿箱'},
      MailFolder.trash: {'deleted messages', 'trash', '已删除'},
      MailFolder.junk: {'junk', 'junk mail', 'junk e-mail', 'spam', '垃圾邮件'},
    };
    for (final folder in MailFolder.values) {
      final selectable = boxes.where(
        (box) => !box.flags.contains(MailboxFlag.noSelect),
      );
      final flagged = selectable.where(
        (box) => box.flags.contains(flags[folder]),
      );
      final named = selectable.where(
        (box) => aliases[folder]!.contains(box.path.toLowerCase()),
      );
      final found = flagged.isNotEmpty ? flagged.first : named.firstOrNull;
      if (found != null) owner._resolvedFolderPaths[folder] = found.path;
    }
  }

  Future<List<MailFolderInfo>> listFolders(MailAccessCredentials credentials) =>
      owner._serialize(() async {
        try {
          final client = await owner._ensureConnected(credentials);
          final imap = client.lowLevelIncomingMailClient as ImapClient;
          final result = <MailFolderInfo>[];
          for (final entry in owner._resolvedFolderPaths.entries) {
            final box = client.mailboxes
                ?.where((b) => b.path == entry.value)
                .firstOrNull;
            if (box == null) continue;
            final status = await imap.statusMailbox(box, [
              StatusFlags.messages,
              StatusFlags.unseen,
            ]);
            result.add(
              MailFolderInfo(
                folder: entry.key,
                total: status.messagesExists,
                unread: status.messagesUnseen,
              ),
            );
          }
          return result;
        } catch (error) {
          throw owner._mapError(error);
        }
      });

  // Startup prefetch and radar scanning keep bounded sequence pages. Only
  // an explicitly sorted inbox view needs the complete lightweight date index.
  Future<MailFolderSnapshot> fetchFilteredFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) => owner._serialize(() async {
    try {
      final client = await owner._ensureConnected(credentials);
      final imap = client.lowLevelIncomingMailClient as ImapClient;
      final box = await client.selectMailboxByPath(
        owner._mapFolderToPath(folder),
      );
      owner._verifyMailboxIdentity(
        folder: folder,
        actualUidValidity: box.uidValidity,
        expectedUidValidity: expectedMailboxUidValidity,
        requireExpected: page > 1,
      );
      await owner._discardStaleMailboxCache(folder, box.uidValidity);
      final status = await imap.statusMailbox(box, [
        StatusFlags.messages,
        StatusFlags.unseen,
      ]);
      final query = [if (unreadOnly) 'UNSEEN', if (flaggedOnly) 'FLAGGED'];
      List<MimeMessage> messages;
      int total;
      if (query.isEmpty) {
        total = status.messagesExists;
        final last = total - (page - 1) * pageSize;
        if (last <= 0) {
          messages = [];
        } else {
          final first = (last - pageSize + 1).clamp(1, last);
          final fetched = await imap.fetchMessagesByCriteria(
            '$first:$last (UID FLAGS)',
          );
          messages = fetched.messages;
        }
      } else {
        List<int>? uids;
        try {
          final search = await imap.uidSearchMessages(
            searchCriteria: query.join(' '),
          );
          uids = search.matchingSequence?.toList() ?? [];
          // Some exmail deployments return a spurious empty SEARCH result.
          if (unreadOnly &&
              !flaggedOnly &&
              uids.isEmpty &&
              status.messagesUnseen > 0) {
            uids = null;
          }
        } on ImapException {
          uids = null;
        }
        if (uids == null) {
          final matching = <MimeMessage>[];
          for (var last = status.messagesExists; last > 0; last -= 200) {
            final first = (last - 199).clamp(1, last);
            final fetched = await imap.fetchMessagesByCriteria(
              '$first:$last (UID FLAGS)',
            );
            matching.addAll(
              fetched.messages.where(
                (message) =>
                    message.uid != null &&
                    (!unreadOnly || !message.isSeen) &&
                    (!flaggedOnly || message.isFlagged),
              ),
            );
          }
          matching.sort(owner._sortMessagesDesc);
          total = matching.length;
          messages = matching
              .skip((page - 1) * pageSize)
              .take(pageSize)
              .toList();
        } else {
          uids.sort((a, b) => b.compareTo(a));
          total = uids.length;
          final selected = uids
              .skip((page - 1) * pageSize)
              .take(pageSize)
              .toList();
          messages = selected.isEmpty
              ? []
              : (await imap.uidFetchMessages(
                  MessageSequence.fromIds(selected, isUid: true),
                  '(UID FLAGS)',
                )).messages;
        }
      }
      final valid = messages.where((message) => message.uid != null).toList()
        ..sort(owner._sortMessagesDesc);
      final summaries = <int, MailMessageSummary>{};
      final missing = <int>[];
      for (final message in valid) {
        final stored = box.uidValidity == null
            ? null
            : await owner._localCache.loadSummary(
                credentials.emailAddress,
                MailMessageIdentity(
                  folder: folder,
                  uid: message.uid!,
                  mailboxUidValidity: box.uidValidity!,
                ),
              );
        if (stored == null) {
          missing.add(message.uid!);
        } else {
          summaries[message.uid!] = stored.copyWith(
            isSeen: message.isSeen,
            isFlagged: message.isFlagged,
          );
        }
      }
      if (missing.isNotEmpty) {
        final fetched = await imap.uidFetchMessages(
          MessageSequence.fromIds(missing, isUid: true),
          _headerFields,
        );
        owner._cacheEnvelopeMessages(folder, box.uidValidity, fetched.messages);
        for (final message in fetched.messages) {
          if (message.uid == null) continue;
          summaries[message.uid!] = owner._toSummary(
            message,
            folder: folder,
            mailboxUidValidity: box.uidValidity,
          );
        }
      }
      final snapshot = MailFolderSnapshot(
        emailAddress: credentials.emailAddress,
        incomingServer: _IoMailService._incomingServer,
        outgoingServer: _IoMailService._outgoingServer,
        folder: folder,
        fetchedAt: DateTime.now(),
        totalMessages: total,
        currentPage: page,
        pageSize: pageSize,
        mailboxUidValidity: box.uidValidity,
        mailboxUnreadCount: status.messagesUnseen,
        messages: valid
            .map((m) => summaries[m.uid])
            .whereType<MailMessageSummary>()
            .toList(),
      );
      await owner._localCache.savePage(
        credentials.emailAddress,
        snapshot,
        unreadOnly: unreadOnly,
        flaggedOnly: flaggedOnly,
      );
      return snapshot;
    } catch (error) {
      throw owner._mapError(error);
    }
  });

  Future<MailFolderSnapshot> fetchSortedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required MailSortOrder sortOrder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) => owner._serialize(() async {
    try {
      final client = await owner._ensureConnected(credentials);
      final imap = client.lowLevelIncomingMailClient as ImapClient;
      final box = await client.selectMailboxByPath(
        owner._mapFolderToPath(folder),
      );
      owner._verifyMailboxIdentity(
        folder: folder,
        actualUidValidity: box.uidValidity,
        expectedUidValidity: expectedMailboxUidValidity,
        requireExpected: page > 1,
      );
      await owner._discardStaleMailboxCache(folder, box.uidValidity);
      final status = await imap.statusMailbox(box, [
        StatusFlags.messages,
        StatusFlags.unseen,
      ]);
      final query = [if (unreadOnly) 'UNSEEN', if (flaggedOnly) 'FLAGGED'];
      var orderedUids = await _orderedUidsByDate(
        imap: imap,
        credentials: credentials,
        folder: folder,
        mailboxUidValidity: box.uidValidity,
        query: query,
        status: status,
      );
      if (sortOrder == MailSortOrder.newestFirst) {
        orderedUids = orderedUids.reversed.toList(growable: false);
      }
      final total = orderedUids.length;
      final selected = orderedUids
          .skip((page - 1) * pageSize)
          .take(pageSize)
          .toList();
      final messages = selected.isEmpty
          ? <MimeMessage>[]
          : (await imap.uidFetchMessages(
              MessageSequence.fromIds(selected, isUid: true),
              '(UID FLAGS)',
            )).messages;
      final byUid = {
        for (final message in messages.where((message) => message.uid != null))
          message.uid!: message,
      };
      final valid = selected
          .map((uid) => byUid[uid])
          .whereType<MimeMessage>()
          .toList();
      final summaries = <int, MailMessageSummary>{};
      final missing = <int>[];
      for (final message in valid) {
        final stored = box.uidValidity == null
            ? null
            : await owner._localCache.loadSummary(
                credentials.emailAddress,
                MailMessageIdentity(
                  folder: folder,
                  uid: message.uid!,
                  mailboxUidValidity: box.uidValidity!,
                ),
              );
        if (stored == null) {
          missing.add(message.uid!);
        } else {
          summaries[message.uid!] = stored.copyWith(
            isSeen: message.isSeen,
            isFlagged: message.isFlagged,
          );
        }
      }
      if (missing.isNotEmpty) {
        final fetched = await imap.uidFetchMessages(
          MessageSequence.fromIds(missing, isUid: true),
          _headerFields,
        );
        owner._cacheEnvelopeMessages(folder, box.uidValidity, fetched.messages);
        for (final message in fetched.messages) {
          if (message.uid == null) continue;
          summaries[message.uid!] = owner._toSummary(
            message,
            folder: folder,
            mailboxUidValidity: box.uidValidity,
          );
        }
      }
      final snapshot = MailFolderSnapshot(
        emailAddress: credentials.emailAddress,
        incomingServer: _IoMailService._incomingServer,
        outgoingServer: _IoMailService._outgoingServer,
        folder: folder,
        fetchedAt: DateTime.now(),
        totalMessages: total,
        currentPage: page,
        pageSize: pageSize,
        mailboxUidValidity: box.uidValidity,
        mailboxUnreadCount: status.messagesUnseen,
        messages: valid
            .map((m) => summaries[m.uid])
            .whereType<MailMessageSummary>()
            .toList(),
      );
      await owner._localCache.savePage(
        credentials.emailAddress,
        snapshot,
        unreadOnly: unreadOnly,
        flaggedOnly: flaggedOnly,
        sortOrder: sortOrder,
      );
      return snapshot;
    } catch (error) {
      throw owner._mapError(error);
    }
  });

  Future<List<int>> _orderedUidsByDate({
    required ImapClient imap,
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int? mailboxUidValidity,
    required List<String> query,
    required Mailbox status,
  }) async {
    final searchCriteria = query.isEmpty ? 'ALL' : query.join(' ');
    var supportsServerSort = false;
    try {
      supportsServerSort = imap.serverInfo.supports('SORT');
    } on Object {
      // Deterministic injected clients may omit the connection handshake.
      // Their path still exercises the metadata-only fallback below.
    }
    if (supportsServerSort) {
      try {
        final sorted =
            (await imap.uidSortMessages(
              'DATE',
              searchCriteria,
            )).matchingSequence?.toList() ??
            <int>[];
        if (!(query.contains('UNSEEN') &&
            !query.contains('FLAGGED') &&
            sorted.isEmpty &&
            status.messagesUnseen > 0)) {
          return sorted;
        }
      } on ImapException {
        // Some deployments advertise SORT but reject it for selected boxes.
      }
    }

    List<int>? uids;
    if (query.isEmpty) {
      final all = <int>[];
      for (var last = status.messagesExists; last > 0; last -= 200) {
        final first = (last - 199).clamp(1, last);
        final fetched = await imap.fetchMessagesByCriteria(
          '$first:$last (UID FLAGS)',
        );
        all.addAll(
          fetched.messages.map((message) => message.uid).whereType<int>(),
        );
      }
      uids = all.toSet().toList(growable: false);
    } else {
      try {
        final search = await imap.uidSearchMessages(
          searchCriteria: searchCriteria,
        );
        uids = search.matchingSequence?.toList() ?? <int>[];
        if (query.contains('UNSEEN') &&
            !query.contains('FLAGGED') &&
            uids.isEmpty &&
            status.messagesUnseen > 0) {
          uids = null;
        }
      } on ImapException {
        uids = null;
      }
    }
    if (uids == null) {
      final matching = <int>[];
      for (var last = status.messagesExists; last > 0; last -= 200) {
        final first = (last - 199).clamp(1, last);
        final fetched = await imap.fetchMessagesByCriteria(
          '$first:$last (UID FLAGS)',
        );
        matching.addAll(
          fetched.messages
              .where((message) {
                return message.uid != null &&
                    (!query.contains('UNSEEN') || !message.isSeen) &&
                    (!query.contains('FLAGGED') || message.isFlagged);
              })
              .map((message) => message.uid!),
        );
      }
      uids = matching;
    }

    final validity = mailboxUidValidity ?? 0;
    final resolvedUids = uids;
    final signature = Object.hashAll(resolvedUids);
    final key =
        '${folder.name}:$validity:$searchCriteria:${resolvedUids.length}:$signature';
    final cachedOrder = _fallbackDateOrderCache[key];
    if (cachedOrder != null) return List<int>.of(cachedOrder);

    final summaries = <int, MailMessageSummary>{};
    final missing = <int>[];
    for (final uid in resolvedUids) {
      final stored = mailboxUidValidity == null
          ? null
          : await owner._localCache.loadSummary(
              credentials.emailAddress,
              MailMessageIdentity(
                folder: folder,
                uid: uid,
                mailboxUidValidity: mailboxUidValidity,
              ),
            );
      if (stored == null) {
        missing.add(uid);
      } else {
        summaries[uid] = stored;
      }
    }
    for (var offset = 0; offset < missing.length; offset += 200) {
      final batch = missing.skip(offset).take(200).toList();
      final fetched = await imap.uidFetchMessages(
        MessageSequence.fromIds(batch, isUid: true),
        _headerFields,
      );
      owner._cacheEnvelopeMessages(
        folder,
        mailboxUidValidity,
        fetched.messages,
      );
      for (final message in fetched.messages) {
        if (message.uid == null) continue;
        summaries[message.uid!] = owner._toSummary(
          message,
          folder: folder,
          mailboxUidValidity: mailboxUidValidity,
        );
      }
    }
    await owner._localCache.saveSummaries(
      credentials.emailAddress,
      summaries.values.toList(growable: false),
    );
    final order = List<int>.of(resolvedUids)
      ..sort((left, right) {
        final leftDate = summaries[left]?.date;
        final rightDate = summaries[right]?.date;
        if (leftDate != null && rightDate != null) {
          final dateResult = leftDate.compareTo(rightDate);
          if (dateResult != 0) return dateResult;
        } else if (leftDate != null) {
          return 1;
        } else if (rightDate != null) {
          return -1;
        }
        return left.compareTo(right);
      });
    _fallbackDateOrderCache
      ..removeWhere((oldKey, _) => oldKey.startsWith('${folder.name}:'))
      ..[key] = List<int>.of(order);
    return order;
  }

  Future<List<MailMessageSummary>> loadPreviews(
    MailAccessCredentials credentials,
    List<MailMessageSummary> summaries,
  ) async {
    final output = <MailMessageSummary>[];
    for (final summary in summaries) {
      if (summary.mailboxUidValidity == null) continue;
      final existing = await owner._localCache.loadSummary(
        credentials.emailAddress,
        summary.identity!,
      );
      if (existing != null && existing.previewLoaded) {
        output.add(
          summary.copyWith(
            preview: existing.preview,
            previewLoaded: true,
            hasHtmlBody: existing.hasHtmlBody,
            hasAttachments: existing.hasAttachments,
          ),
        );
        continue;
      }
      try {
        final preview = await owner._serialize(() async {
          final client = await owner._ensureConnected(credentials);
          final box = await client.selectMailboxByPath(
            owner._mapFolderToPath(summary.folder),
          );
          owner._verifyMailboxIdentity(
            folder: summary.folder,
            actualUidValidity: box.uidValidity,
            expectedUidValidity: summary.mailboxUidValidity,
            requireExpected: true,
          );
          final envelope = await owner._loadMessageEnvelope(
            client: client,
            mailbox: box,
            folder: summary.folder,
            mailboxUidValidity: box.uidValidity,
            uid: summary.uid,
          );
          final structured = await owner._loadMessageStructure(
            client: client,
            mailbox: box,
            folder: summary.folder,
            mailboxUidValidity: box.uidValidity,
            uid: summary.uid,
            message: envelope,
          );
          final complete = await owner._loadTextParts(
            client,
            structured,
            summary.folder,
            box.uidValidity,
            budget: 256 * 1024,
          );
          final content = structured;
          if (complete) {
            await owner._localCache.saveDetail(
              credentials.emailAddress,
              owner._toDetail(
                content,
                folder: summary.folder,
                mailboxUidValidity: box.uidValidity,
              ),
            );
          }
          return summary.copyWith(
            preview: owner._buildPreview(owner._extractReadableText(content)),
            previewLoaded: true,
            hasHtmlBody: owner._extractHtmlSource(content).isNotEmpty,
            hasAttachments: structured.hasAttachments(),
          );
        }, background: true);
        await owner._localCache.saveSummaries(credentials.emailAddress, [
          preview,
        ]);
        output.add(preview);
      } catch (_) {
        // A transient preview failure does not poison the cache or block rows.
      }
    }
    return output;
  }

  Future<void> setFlag(
    MailAccessCredentials credentials,
    List<MailMessageIdentity> messages,
    String flag,
    bool enabled,
  ) => owner._serialize(() async {
    try {
      final client = await owner._ensureConnected(credentials);
      final imap = client.lowLevelIncomingMailClient as ImapClient;
      for (final group in _groups(messages).values) {
        final source = group.first;
        final box = await client.selectMailboxByPath(
          owner._mapFolderToPath(source.folder),
        );
        owner._verifyMailboxIdentity(
          folder: source.folder,
          actualUidValidity: box.uidValidity,
          expectedUidValidity: source.mailboxUidValidity,
          requireExpected: true,
        );
        if (!box.isReadWrite ||
            (box.permanentMessageFlags.isNotEmpty &&
                !box.permanentMessageFlags.contains(flag))) {
          throw const MailServiceException('当前邮箱不允许修改该标记。');
        }
        await imap.uidStore(
          MessageSequence.fromIds(
            group.map((m) => m.uid).toList(),
            isUid: true,
          ),
          [flag],
          action: enabled ? StoreAction.add : StoreAction.remove,
          silent: true,
        );
        for (final message in group) {
          final cached =
              owner._messageCache[(
                source.folder,
                source.mailboxUidValidity,
                message.uid,
              )];
          if (flag == MessageFlags.seen) cached?.isSeen = enabled;
          if (flag == MessageFlags.flagged) cached?.isFlagged = enabled;
          await owner._localCache.updateFlags(
            credentials.emailAddress,
            [message],
            seen: flag == MessageFlags.seen ? enabled : null,
            flagged: flag == MessageFlags.flagged ? enabled : null,
          );
        }
      }
    } catch (error) {
      throw owner._mapError(error);
    }
  });

  Future<Map<MailMessageIdentity, bool>> readSeenFlags(
    MailAccessCredentials credentials,
    List<MailMessageIdentity> messages,
  ) => owner._serialize(() async {
    try {
      final client = await owner._ensureConnected(credentials);
      final imap = client.lowLevelIncomingMailClient as ImapClient;
      final result = <MailMessageIdentity, bool>{};
      for (final group in _groups(messages).values) {
        final source = group.first;
        final box = await client.selectMailboxByPath(
          owner._mapFolderToPath(source.folder),
        );
        owner._verifyMailboxIdentity(
          folder: source.folder,
          actualUidValidity: box.uidValidity,
          expectedUidValidity: source.mailboxUidValidity,
          requireExpected: true,
        );
        for (var offset = 0; offset < group.length; offset += 200) {
          final batch = group.skip(offset).take(200).toList();
          final flags = await imap.uidFetchMessages(
            MessageSequence.fromIds(
              batch.map((message) => message.uid).toList(),
              isUid: true,
            ),
            '(UID FLAGS)',
          );
          final byUid = {
            for (final message in flags.messages) message.uid: message.isSeen,
          };
          for (final identity in batch) {
            final seen = byUid[identity.uid];
            if (seen != null) result[identity] = seen;
          }
        }
      }
      return result;
    } catch (error) {
      throw owner._mapError(error);
    }
  });

  Future<void> moveMessages(
    MailAccessCredentials credentials,
    List<MailMessageIdentity> messages,
    MailFolder target,
  ) => owner._serialize(() async {
    try {
      final client = await owner._ensureConnected(credentials);
      final transport = _ImapMutationTransport(
        client.lowLevelIncomingMailClient as ImapClient,
      );
      for (final group in _groups(messages).values) {
        final source = group.first;
        if (source.folder == target) continue;
        final box = await client.selectMailboxByPath(
          owner._mapFolderToPath(source.folder),
        );
        owner._verifyMailboxIdentity(
          folder: source.folder,
          actualUidValidity: box.uidValidity,
          expectedUidValidity: source.mailboxUidValidity,
          requireExpected: true,
        );
        await moveMailSafely(
          transport,
          group.map((m) => m.uid).toList(),
          owner._mapFolderToPath(target),
        );
        await owner._localCache.remove(credentials.emailAddress, group);
        for (final message in group) {
          owner._messageCache.remove((
            source.folder,
            source.mailboxUidValidity,
            message.uid,
          ));
        }
      }
    } catch (error) {
      throw owner._mapError(error);
    }
  });

  Map<String, List<MailMessageIdentity>> _groups(
    List<MailMessageIdentity> messages,
  ) {
    final groups = <String, List<MailMessageIdentity>>{};
    for (final message in messages) {
      groups
          .putIfAbsent(
            '${message.folder.name}:${message.mailboxUidValidity}',
            () => [],
          )
          .add(message);
    }
    return groups;
  }
}

class _ImapMutationTransport implements MailMutationTransport {
  _ImapMutationTransport(this.client);
  final ImapClient client;
  @override
  bool get supportsMove => client.serverInfo.supportsMove;
  @override
  bool get supportsUidExpunge => client.serverInfo.supportsUidPlus;
  MessageSequence _sequence(List<int> uids) =>
      MessageSequence.fromIds(uids, isUid: true);
  @override
  Future<void> move(List<int> uids, String target) async {
    await client.uidMove(_sequence(uids), targetMailboxPath: target);
  }

  @override
  Future<void> copy(List<int> uids, String target) async {
    await client.uidCopy(_sequence(uids), targetMailboxPath: target);
  }

  @override
  Future<void> markDeleted(List<int> uids) async {
    await client.uidStore(
      _sequence(uids),
      [MessageFlags.deleted],
      action: StoreAction.add,
      silent: true,
    );
  }

  @override
  Future<void> expungeUids(List<int> uids) async {
    await client.uidExpunge(_sequence(uids));
  }
}
