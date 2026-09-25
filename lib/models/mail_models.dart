import 'dart:typed_data';

import '../utils/mail_preview_text.dart';

class MailAccessCredentials {
  const MailAccessCredentials({
    required this.userId,
    required this.emailAddress,
    required this.password,
  });

  factory MailAccessCredentials.fromUserId({
    required String userId,
    required String password,
  }) {
    final normalizedUserId = userId.trim().split('@').first;
    return MailAccessCredentials(
      userId: normalizedUserId,
      emailAddress: '$normalizedUserId@mail.bnbu.edu.cn',
      password: password,
    );
  }

  final String userId;
  final String emailAddress;
  final String password;
}

enum MailFolder { inbox, sent, drafts, trash, junk }

/// Virtual views never replace a message's actual mailbox identity.
enum MailCollection { folder, topics, starred }

class MailFolderInfo {
  const MailFolderInfo({
    required this.folder,
    required this.total,
    required this.unread,
    this.canWrite = true,
    this.canFlag = true,
  });

  final MailFolder folder;
  final int total;
  final int unread;
  final bool canWrite;
  final bool canFlag;
}

enum MailSearchScope { allText, subject, from, to }

enum MailSortOrder { newestFirst, oldestFirst }

class MailMessageIdentity {
  const MailMessageIdentity({
    required this.folder,
    required this.uid,
    required this.mailboxUidValidity,
  });

  final MailFolder folder;
  final int uid;
  final int mailboxUidValidity;

  @override
  bool operator ==(Object other) =>
      other is MailMessageIdentity &&
      other.folder == folder &&
      other.uid == uid &&
      other.mailboxUidValidity == mailboxUidValidity;

  @override
  int get hashCode => Object.hash(folder, mailboxUidValidity, uid);
}

class MailAttachment {
  const MailAttachment({
    required this.name,
    required this.size,
    required this.mimeType,
    this.contentId,
    this.partId,
  });

  final String name;
  final int size;
  final String mimeType;
  final String? contentId;
  final String? partId;
}

class MailMessageSummary {
  const MailMessageSummary({
    required this.uid,
    required this.subject,
    required this.sender,
    required this.preview,
    required this.hasHtmlBody,
    required this.date,
    required this.isSeen,
    this.hasAttachments = false,
    this.isFlagged = false,
    this.previewLoaded = false,
    this.recipients = '',
    this.messageId = '',
    this.inReplyTo = '',
    this.references = '',
    this.folder = MailFolder.inbox,
    this.mailboxUidValidity,
    this.messageSizeBytes,
  });

  final int uid;
  final String subject;
  final String sender;
  final String recipients;
  final String preview;

  /// Covers legacy in-memory snapshots as well as freshly decoded mail.
  String get readablePreview => normalizeMailPreviewText(preview);
  final bool hasHtmlBody;
  final DateTime? date;
  final bool isSeen;
  final bool hasAttachments;
  final bool isFlagged;
  final bool previewLoaded;
  final String messageId;
  final String inReplyTo;
  final String references;
  final MailFolder folder;
  final int? mailboxUidValidity;
  final int? messageSizeBytes;

  String get correspondent =>
      (folder == MailFolder.sent || folder == MailFolder.drafts) &&
          recipients.trim().isNotEmpty
      ? recipients
      : sender;

  String get identityKey => '${folder.name}:${mailboxUidValidity ?? 0}:$uid';

  MailMessageIdentity? get identity => mailboxUidValidity == null
      ? null
      : MailMessageIdentity(
          folder: folder,
          uid: uid,
          mailboxUidValidity: mailboxUidValidity!,
        );

  MailMessageSummary copyWith({
    int? uid,
    String? subject,
    String? sender,
    String? recipients,
    String? preview,
    bool? hasHtmlBody,
    DateTime? date,
    bool? isSeen,
    bool? hasAttachments,
    bool? isFlagged,
    bool? previewLoaded,
    String? messageId,
    String? inReplyTo,
    String? references,
    MailFolder? folder,
    int? mailboxUidValidity,
    int? messageSizeBytes,
  }) {
    return MailMessageSummary(
      uid: uid ?? this.uid,
      subject: subject ?? this.subject,
      sender: sender ?? this.sender,
      recipients: recipients ?? this.recipients,
      preview: preview ?? this.preview,
      hasHtmlBody: hasHtmlBody ?? this.hasHtmlBody,
      date: date ?? this.date,
      isSeen: isSeen ?? this.isSeen,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      isFlagged: isFlagged ?? this.isFlagged,
      previewLoaded: previewLoaded ?? this.previewLoaded,
      messageId: messageId ?? this.messageId,
      inReplyTo: inReplyTo ?? this.inReplyTo,
      references: references ?? this.references,
      folder: folder ?? this.folder,
      mailboxUidValidity: mailboxUidValidity ?? this.mailboxUidValidity,
      messageSizeBytes: messageSizeBytes ?? this.messageSizeBytes,
    );
  }
}

class MailMessageDetail {
  const MailMessageDetail({
    required this.uid,
    required this.subject,
    required this.sender,
    required this.recipients,
    required this.cc,
    required this.date,
    required this.body,
    required this.htmlBody,
    required this.isSeen,
    this.attachments = const [],
    this.inlineImagesLoaded = true,
    this.messageId,
    this.inReplyTo,
    this.references,
    this.listId,
    this.precedence,
    this.mailboxUidValidity,
    this.folder = MailFolder.inbox,
    this.messageSizeBytes,
  });

  final int uid;
  final String subject;
  final String sender;
  final String recipients;
  final String? cc;
  final DateTime? date;
  final String body;
  final String? htmlBody;
  final bool isSeen;
  final bool inlineImagesLoaded;
  final List<MailAttachment> attachments;
  final String? messageId;
  final String? inReplyTo;
  final String? references;
  final String? listId;
  final String? precedence;
  final int? mailboxUidValidity;
  final MailFolder folder;
  final int? messageSizeBytes;

  MailMessageDetail withSeen(bool seen) => MailMessageDetail(
    uid: uid,
    subject: subject,
    sender: sender,
    recipients: recipients,
    cc: cc,
    date: date,
    body: body,
    htmlBody: htmlBody,
    isSeen: seen,
    inlineImagesLoaded: inlineImagesLoaded,
    attachments: attachments,
    messageId: messageId,
    inReplyTo: inReplyTo,
    references: references,
    listId: listId,
    precedence: precedence,
    mailboxUidValidity: mailboxUidValidity,
    folder: folder,
    messageSizeBytes: messageSizeBytes,
  );
  MailMessageDetail withInlineImages(String html) => MailMessageDetail(
    uid: uid,
    subject: subject,
    sender: sender,
    recipients: recipients,
    cc: cc,
    date: date,
    body: body,
    htmlBody: html,
    isSeen: isSeen,
    inlineImagesLoaded: true,
    attachments: attachments,
    messageId: messageId,
    inReplyTo: inReplyTo,
    references: references,
    listId: listId,
    precedence: precedence,
    mailboxUidValidity: mailboxUidValidity,
    folder: folder,
    messageSizeBytes: messageSizeBytes,
  );
}

class MailFolderSnapshot {
  const MailFolderSnapshot({
    required this.emailAddress,
    required this.incomingServer,
    required this.outgoingServer,
    required this.messages,
    required this.fetchedAt,
    required this.folder,
    required this.totalMessages,
    required this.currentPage,
    required this.pageSize,
    this.mailboxUnreadCount,
    this.mailboxUidValidity,
  });

  final String emailAddress;
  final String incomingServer;
  final String outgoingServer;
  final List<MailMessageSummary> messages;
  final DateTime fetchedAt;
  final MailFolder folder;
  final int totalMessages;
  final int currentPage;
  final int pageSize;
  final int? mailboxUidValidity;

  final int? mailboxUnreadCount;
  int get unreadCount =>
      mailboxUnreadCount ?? messages.where((message) => !message.isSeen).length;

  MailFolderSnapshot copyWith({
    String? emailAddress,
    String? incomingServer,
    String? outgoingServer,
    List<MailMessageSummary>? messages,
    DateTime? fetchedAt,
    MailFolder? folder,
    int? totalMessages,
    int? currentPage,
    int? pageSize,
    int? mailboxUnreadCount,
    int? mailboxUidValidity,
  }) {
    return MailFolderSnapshot(
      emailAddress: emailAddress ?? this.emailAddress,
      incomingServer: incomingServer ?? this.incomingServer,
      outgoingServer: outgoingServer ?? this.outgoingServer,
      messages: messages ?? this.messages,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      folder: folder ?? this.folder,
      totalMessages: totalMessages ?? this.totalMessages,
      currentPage: currentPage ?? this.currentPage,
      pageSize: pageSize ?? this.pageSize,
      mailboxUnreadCount: mailboxUnreadCount ?? this.mailboxUnreadCount,
      mailboxUidValidity: mailboxUidValidity ?? this.mailboxUidValidity,
    );
  }
}

class MailDraftIdentity {
  const MailDraftIdentity({
    required this.uid,
    required this.mailboxUidValidity,
    this.previousDraftRetained = false,
  });

  final int uid;
  final int mailboxUidValidity;
  final bool previousDraftRetained;
}

class MailComposeData {
  const MailComposeData({
    required this.to,
    this.cc,
    this.bcc,
    required this.subject,
    required this.body,
    this.attachments = const [],
    this.htmlBody,
    this.inReplyTo,
    this.references,
  });

  final String to;
  final String? cc;
  final String? bcc;
  final String subject;
  final String body;
  final List<MailComposeAttachment> attachments;
  final String? htmlBody;
  final String? inReplyTo;
  final String? references;
}

class MailComposeAttachment {
  const MailComposeAttachment({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}
