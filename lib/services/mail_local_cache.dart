import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/mail_models.dart';
import '../utils/mail_preview_text.dart';
import 'secure_storage_options.dart';

/// Optional, encrypted device cache. School state is still checked before any
/// mutation; cached records never contain credentials or transport sessions.
class MailLocalCache {
  MailLocalCache({
    Future<Directory> Function()? directory,
    Future<SecretKey> Function()? key,
    this.maxBytes = 128 * 1024 * 1024,
    this.maxEntries = 3000,
  }) : _directory = directory ?? _defaultDirectory,
       _key = key ?? _deviceKey;

  static final shared = MailLocalCache();
  static const _entryLimit = 8 * 1024 * 1024;
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    mOptions: macOsSecureStorageOptions,
  );
  static Future<SecretKey>? _keyFuture;
  final Future<Directory> Function() _directory;
  final Future<SecretKey> Function() _key;
  final int maxBytes;
  final int maxEntries;
  final _cipher = AesGcm.with256bits();
  Future<void> _queue = Future.value();
  int _writes = 0;

  static Future<Directory> _defaultDirectory() async => Directory(
    '${(await getApplicationSupportDirectory()).path}/mail-cache-v1',
  );

  static Future<SecretKey> _deviceKey() => _keyFuture ??= (() async {
    try {
      const name = 'bnbu.mail-cache.key.v1';
      final encoded = await _storage.read(key: name);
      if (encoded != null) {
        final bytes = base64Decode(encoded);
        if (bytes.length != 32) {
          throw const FormatException('Invalid cache key');
        }
        return SecretKey(bytes);
      }
      final key = await AesGcm.with256bits().newSecretKey();
      await _storage.write(
        key: name,
        value: base64Encode(await key.extractBytes()),
      );
      return key;
    } catch (_) {
      _keyFuture = null;
      rethrow;
    }
  })();

  Future<T?> _optional<T>(Future<T?> Function() action) {
    final result = _queue.then((_) async {
      try {
        return await action();
      } catch (_) {
        // A missing key, full disk or corrupt cache cannot break live mail.
        return null;
      }
    });
    _queue = result.then((_) {});
    return result;
  }

  String _owner(String account) =>
      sha256.convert(utf8.encode(account.trim().toLowerCase())).toString();
  String _folder(String account, MailFolder folder) =>
      '${_owner(account)}/${folder.name}';
  String _entry(String account, MailMessageIdentity id) =>
      '${_folder(account, id.folder)}/${id.mailboxUidValidity}/${id.uid}.bin';
  String _bodyEntry(String account, MailMessageIdentity id) =>
      '${_folder(account, id.folder)}/${id.mailboxUidValidity}/${id.uid}.body.bin';
  String _pageKey(
    int page,
    int size,
    bool unread,
    bool flagged,
    MailSortOrder sortOrder,
  ) => '$size:$unread:$flagged:${sortOrder.name}:$page';

  String _legacyPageKey(int page, int size, bool unread, bool flagged) =>
      '$size:$unread:$flagged:$page';

  Future<Map<String, dynamic>?> _read(String path) async {
    final file = File('${(await _directory()).path}/$path');
    if (!await file.exists() || await file.length() > _entryLimit + 1024) {
      return null;
    }
    try {
      final bytes = await _cipher.decrypt(
        SecretBox.fromConcatenation(
          await file.readAsBytes(),
          nonceLength: 12,
          macLength: 16,
        ),
        secretKey: await _key(),
        aad: utf8.encode(path),
      );
      final result = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      await file.setLastModified(DateTime.now());
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(String path, Map<String, dynamic> value) async {
    final bytes = utf8.encode(jsonEncode(value));
    if (bytes.length > _entryLimit) return;
    final box = await _cipher.encrypt(
      bytes,
      secretKey: await _key(),
      aad: utf8.encode(path),
    );
    final root = await _directory();
    final file = File('${root.path}/$path');
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await temporary.writeAsBytes(box.concatenation(), flush: true);
      await temporary.rename(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    if (++_writes % 25 == 0 ||
        bytes.length > 64 * 1024 ||
        maxBytes < 128 * 1024 * 1024 ||
        maxEntries < 3000) {
      await _trim(root);
    }
  }

  Future<void> _trim(Directory root) async {
    final files = <(File, FileStat)>[];
    var size = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      files.add((entity, stat));
      size += stat.size;
    }
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var count = files.length;
    for (final entry in files) {
      if (size <= maxBytes && count <= maxEntries) break;
      await entry.$1.delete();
      size -= entry.$2.size;
      count--;
    }
  }

  Future<Map<String, dynamic>?> _index(String account, MailFolder folder) =>
      _read('${_folder(account, folder)}/index.bin');

  Future<void> validateMailbox(
    String account,
    MailFolder folder,
    int? validity,
  ) async {
    if (validity == null) return;
    await _optional(() async {
      final old = await _index(account, folder);
      if (old?['validity'] == validity) return;
      await _write('${_folder(account, folder)}/index.bin', {
        'validity': validity,
        'pages': <String, dynamic>{},
      });
    });
  }

  Future<MailMessageSummary?> loadSummary(
    String account,
    MailMessageIdentity id,
  ) => _optional(() async {
    if ((await _index(account, id.folder))?['validity'] !=
        id.mailboxUidValidity) {
      return null;
    }
    final value = (await _read(_entry(account, id)))?['summary'];
    return value is Map<String, dynamic> ? _decodeSummary(value, id) : null;
  });

  Future<void> saveSummaries(
    String account,
    List<MailMessageSummary> summaries,
  ) async {
    await _optional(() async {
      for (final summary in summaries) {
        final id = summary.identity;
        if (id == null ||
            (await _index(account, id.folder))?['validity'] !=
                id.mailboxUidValidity) {
          continue;
        }
        final old = await _read(_entry(account, id)) ?? {};
        final prior = old['summary'];
        var saved = summary;
        if (!summary.previewLoaded &&
            prior is Map<String, dynamic> &&
            prior['previewLoaded'] == true) {
          saved = summary.copyWith(
            preview: prior['preview'] as String,
            previewLoaded: true,
            hasHtmlBody: prior['hasHtmlBody'] as bool,
            hasAttachments: prior['hasAttachments'] as bool,
          );
        }
        await _write(_entry(account, id), {
          ...old,
          'summary': _encodeSummary(saved),
        });
      }
    });
  }

  Future<void> savePage(
    String account,
    MailFolderSnapshot snapshot, {
    bool unreadOnly = false,
    bool flaggedOnly = false,
    MailSortOrder sortOrder = MailSortOrder.newestFirst,
  }) async {
    await validateMailbox(
      account,
      snapshot.folder,
      snapshot.mailboxUidValidity,
    );
    await saveSummaries(account, snapshot.messages);
    await _optional(() async {
      final index = await _index(account, snapshot.folder);
      if (index == null || index['validity'] != snapshot.mailboxUidValidity) {
        return;
      }
      final pages = Map<String, dynamic>.from(index['pages'] as Map);
      final key = _pageKey(
        snapshot.currentPage,
        snapshot.pageSize,
        unreadOnly,
        flaggedOnly,
        sortOrder,
      );
      final uids = snapshot.messages.map((m) => m.uid).toList();
      if (snapshot.currentPage == 1 &&
          pages.containsKey(key) &&
          jsonEncode(pages[key]?['uids']) != jsonEncode(uids)) {
        // Sequence-number pages shift when new messages arrive or are removed.
        pages.clear();
      }
      pages[key] = {
        'uids': uids,
        'total': snapshot.totalMessages,
        'unread': snapshot.mailboxUnreadCount,
        'fetched': snapshot.fetchedAt.toIso8601String(),
      };
      while (pages.length > 150) {
        pages.remove(pages.keys.first);
      }
      await _write('${_folder(account, snapshot.folder)}/index.bin', {
        ...index,
        'pages': pages,
      });
    });
  }

  Future<MailFolderSnapshot?> loadPage(
    String account,
    MailFolder folder, {
    int page = 1,
    int pageSize = 25,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    MailSortOrder sortOrder = MailSortOrder.newestFirst,
  }) => _optional(() async {
    final index = await _index(account, folder);
    final validity = index?['validity'] as int?;
    final pages = index?['pages'];
    dynamic data;
    if (pages is Map) {
      data =
          pages[_pageKey(page, pageSize, unreadOnly, flaggedOnly, sortOrder)];
      if (data == null && sortOrder == MailSortOrder.newestFirst) {
        data = pages[_legacyPageKey(page, pageSize, unreadOnly, flaggedOnly)];
      }
    }
    if (validity == null || data is! Map) return null;
    final messages = <MailMessageSummary>[];
    for (final uid in data['uids'] as List) {
      final id = MailMessageIdentity(
        folder: folder,
        uid: uid as int,
        mailboxUidValidity: validity,
      );
      final value = (await _read(_entry(account, id)))?['summary'];
      if (value is! Map<String, dynamic>) {
        return null; // Never present a partial page as complete.
      }
      messages.add(_decodeSummary(value, id));
    }
    return MailFolderSnapshot(
      emailAddress: account,
      incomingServer: 'imap.exmail.qq.com',
      outgoingServer: 'smtp.exmail.qq.com',
      messages: messages,
      fetchedAt: DateTime.parse(data['fetched'] as String),
      folder: folder,
      totalMessages: data['total'] as int,
      currentPage: page,
      pageSize: pageSize,
      mailboxUidValidity: validity,
      mailboxUnreadCount: data['unread'] as int?,
    );
  });

  Future<MailMessageDetail?> loadDetail(
    String account,
    MailMessageIdentity id,
  ) => _optional(() async {
    if ((await _index(account, id.folder))?['validity'] !=
        id.mailboxUidValidity) {
      return null;
    }
    final data = await _read(_entry(account, id));
    final detail = (await _read(_bodyEntry(account, id)))?['detail'];
    if (detail is! Map<String, dynamic>) return null;
    return _decodeDetail(
      detail,
      id,
      seen: (data?['summary']?['isSeen'] ?? data?['seen']) as bool?,
    );
  });

  Future<void> saveDetail(String account, MailMessageDetail detail) async {
    final validity = detail.mailboxUidValidity;
    if (validity == null) return;
    await _optional(() async {
      if ((await _index(account, detail.folder))?['validity'] != validity) {
        return;
      }
      final id = MailMessageIdentity(
        folder: detail.folder,
        uid: detail.uid,
        mailboxUidValidity: validity,
      );
      final old = await _read(_entry(account, id)) ?? {};
      final summary = old['summary'];
      if (summary is Map<String, dynamic>) summary['isSeen'] = detail.isSeen;
      await _write(_entry(account, id), {...old, 'seen': detail.isSeen});
      await _write(_bodyEntry(account, id), {'detail': _encodeDetail(detail)});
    });
  }

  Future<void> updateFlags(
    String account,
    List<MailMessageIdentity> ids, {
    bool? seen,
    bool? flagged,
  }) async {
    await _optional(() async {
      for (final id in ids) {
        final value = await _read(_entry(account, id));
        if (value == null) continue;
        final summary = value['summary'];
        if (summary is Map) {
          if (seen != null) summary['isSeen'] = seen;
          if (flagged != null) summary['isFlagged'] = flagged;
        }
        if (seen != null) value['seen'] = seen;
        await _write(_entry(account, id), value);
        final index = await _index(account, id.folder);
        if (index != null) {
          final pages = Map<String, dynamic>.from(index['pages'] as Map);
          pages.removeWhere((key, _) => key.contains(':true:'));
          await _write('${_folder(account, id.folder)}/index.bin', {
            ...index,
            'pages': pages,
          });
        }
      }
    });
  }

  Future<void> remove(String account, List<MailMessageIdentity> ids) async {
    await _optional(() async {
      for (final id in ids) {
        final file = File(
          '${(await _directory()).path}/${_entry(account, id)}',
        );
        if (await file.exists()) await file.delete();
        final body = File(
          '${(await _directory()).path}/${_bodyEntry(account, id)}',
        );
        if (await body.exists()) await body.delete();
        final index = await _index(account, id.folder);
        if (index != null) {
          await _write('${_folder(account, id.folder)}/index.bin', {
            ...index,
            'pages': {},
          });
        }
      }
    });
  }
}

Map<String, dynamic> _encodeSummary(MailMessageSummary m) => {
  'subject': m.subject,
  'sender': m.sender,
  'recipients': m.recipients,
  'preview': m.preview,
  'hasHtmlBody': m.hasHtmlBody,
  'date': m.date?.toIso8601String(),
  'isSeen': m.isSeen,
  'isFlagged': m.isFlagged,
  'hasAttachments': m.hasAttachments,
  'previewLoaded': m.previewLoaded,
  'messageId': m.messageId,
  'inReplyTo': m.inReplyTo,
  'references': m.references,
  'messageSizeBytes': m.messageSizeBytes,
};

MailMessageSummary _decodeSummary(
  Map<String, dynamic> m,
  MailMessageIdentity id,
) => MailMessageSummary(
  uid: id.uid,
  folder: id.folder,
  mailboxUidValidity: id.mailboxUidValidity,
  subject: m['subject'] as String,
  sender: m['sender'] as String,
  recipients: m['recipients'] as String,
  preview: normalizeMailPreviewText(m['preview'] as String),
  hasHtmlBody: m['hasHtmlBody'] as bool,
  date: DateTime.tryParse(m['date'] as String? ?? ''),
  isSeen: m['isSeen'] as bool,
  isFlagged: m['isFlagged'] as bool,
  hasAttachments: m['hasAttachments'] as bool,
  previewLoaded: m['previewLoaded'] as bool,
  messageId: m['messageId'] as String,
  inReplyTo: m['inReplyTo'] as String,
  references: m['references'] as String,
  messageSizeBytes: m['messageSizeBytes'] as int?,
);

Map<String, dynamic> _encodeDetail(MailMessageDetail d) => {
  'subject': d.subject,
  'sender': d.sender,
  'recipients': d.recipients,
  'cc': d.cc,
  'date': d.date?.toIso8601String(),
  'body': d.body,
  'htmlBody': d.htmlBody,
  'inlineImagesLoaded': d.inlineImagesLoaded,
  'isSeen': d.isSeen,
  'messageId': d.messageId,
  'inReplyTo': d.inReplyTo,
  'references': d.references,
  'listId': d.listId,
  'precedence': d.precedence,
  'messageSizeBytes': d.messageSizeBytes,
  'attachments': d.attachments
      .map(
        (a) => {
          'name': a.name,
          'size': a.size,
          'mimeType': a.mimeType,
          'contentId': a.contentId,
          'partId': a.partId,
        },
      )
      .toList(),
};

MailMessageDetail _decodeDetail(
  Map<String, dynamic> d,
  MailMessageIdentity id, {
  bool? seen,
}) => MailMessageDetail(
  uid: id.uid,
  folder: id.folder,
  mailboxUidValidity: id.mailboxUidValidity,
  subject: d['subject'] as String,
  sender: d['sender'] as String,
  recipients: d['recipients'] as String,
  cc: d['cc'] as String?,
  date: DateTime.tryParse(d['date'] as String? ?? ''),
  body: d['body'] as String,
  htmlBody: d['htmlBody'] as String?,
  inlineImagesLoaded:
      d['inlineImagesLoaded'] as bool? ??
      !RegExp(
        r'''src\s*=\s*['"]cid:''',
        caseSensitive: false,
      ).hasMatch(d['htmlBody'] as String? ?? ''),
  isSeen: seen ?? d['isSeen'] as bool,
  messageId: d['messageId'] as String?,
  inReplyTo: d['inReplyTo'] as String?,
  references: d['references'] as String?,
  listId: d['listId'] as String?,
  precedence: d['precedence'] as String?,
  messageSizeBytes: d['messageSizeBytes'] as int?,
  attachments: (d['attachments'] as List)
      .map(
        (a) => MailAttachment(
          name: a['name'] as String,
          size: a['size'] as int,
          mimeType: a['mimeType'] as String,
          contentId: a['contentId'] as String?,
          partId: a['partId'] as String?,
        ),
      )
      .toList(),
);
