import '../models/mail_models.dart';

abstract interface class MailAuthenticationVerifier {
  Future<void> verifyCredentials(MailAccessCredentials credentials);
}

abstract class MailService {
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  });

  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  });

  Future<List<MailMessageDetail>> readMessages({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    bool markAsSeen = true,
  }) async {
    final results = <MailMessageDetail>[];
    for (final message in messages) {
      results.add(
        await readMessage(
          credentials: credentials,
          folder: message.folder,
          uid: message.uid,
          expectedMailboxUidValidity: message.mailboxUidValidity,
          markAsSeen: markAsSeen,
        ),
      );
    }
    return List.unmodifiable(results);
  }

  Future<void> markMessagesSeen({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  });

  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
    MailSearchScope searchScope = MailSearchScope.allText,
  });

  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  });

  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  });

  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  });

  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  });

  Future<void> restoreMessages({
    required MailAccessCredentials credentials,
    required List<int> uids,
    required String userEmailAddress,
    int? expectedMailboxUidValidity,
  });

  Future<void> close();
}

abstract interface class MailInboxMonitor {
  Stream<void> get inboxChanges;

  Future<void> startInboxMonitoring({
    required MailAccessCredentials credentials,
  });

  Future<void> stopInboxMonitoring();
}

/// Reads server flags without downloading bodies or marking mail as read.
abstract interface class MailFlagReader {
  Future<Map<MailMessageIdentity, bool>> readSeenFlags({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
  });
}

abstract interface class MailCacheReader {
  Future<MailFolderSnapshot?> readCachedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    int page = 1,
    int pageSize = 25,
    bool unreadOnly = false,
  });

  Future<MailMessageDetail?> readCachedMessage({
    required MailAccessCredentials credentials,
    required MailMessageIdentity identity,
  });
}

abstract interface class MailInlineImageLoader {
  Future<MailMessageDetail> loadInlineImages({
    required MailAccessCredentials credentials,
    required MailMessageDetail detail,
  });
}

/// Optional extension keeps older injected mail clients compatible while the
/// production service exposes mailbox capabilities and complete flag queries.
abstract interface class MailOrganizationService {
  Future<List<MailFolderInfo>> listFolders(MailAccessCredentials credentials);
  Future<MailFolderSnapshot> fetchFilteredFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  });
  Future<List<MailMessageSummary>> loadPreviews({
    required MailAccessCredentials credentials,
    required List<MailMessageSummary> messages,
  });
  Future<void> setMessagesSeen({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    required bool seen,
  });
  Future<void> setMessagesFlagged({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    required bool flagged,
  });
  Future<void> moveMessages({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    required MailFolder target,
  });
}

/// Optional ordered pagination keeps older injected mail services compatible.
/// The production implementation sorts the complete result using only IMAP
/// metadata and never downloads every message body for a date change.
abstract interface class MailSortedFolderReader {
  Future<MailFolderSnapshot> fetchSortedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required MailSortOrder sortOrder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  });

  Future<MailFolderSnapshot?> readCachedSortedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required MailSortOrder sortOrder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
  });
}

class MailServiceException implements Exception {
  const MailServiceException(this.message, {this.isRetryable = false});

  final String message;
  final bool isRetryable;

  @override
  String toString() => message;
}

class MailAuthenticationException extends MailServiceException {
  const MailAuthenticationException() : super('邮箱验证失败，请输入邮箱密码；也请确认学校邮箱已开通。');
}

/// Only explicit authentication rejection, never a generic login/SSL failure.
bool isExplicitMailAuthenticationFailure(String message) {
  final value = message.toLowerCase();
  if (RegExp(
    r'timeout|timed out|connection|socket|network|certificate|tls|ssl',
  ).hasMatch(value)) {
    return false;
  }
  return RegExp(
    r'authenticationfailed|authentication failed|authentication failure|'
    r'authentication unsuccessful|invalid credentials|invalid password|'
    r'incorrect password|login failed|login failure|login denied|'
    r'authorization failed|用户名或密码错误|密码错误',
  ).hasMatch(value);
}

/// Optional capability kept separate from ordinary mail/cache consumers.
abstract interface class MeVerificationMailReader {
  Future<String?> readMeVerificationCode({
    required MailAccessCredentials credentials,
    required String challengeId,
    required DateTime since,
  });
}

extension MeVerificationMailAccess on MailService {
  Future<String?> readMeVerificationCode({
    required MailAccessCredentials credentials,
    required String challengeId,
    required DateTime since,
  }) async {
    final service = this;
    if (service is! MeVerificationMailReader) return null;
    return (service as MeVerificationMailReader).readMeVerificationCode(
      credentials: credentials,
      challengeId: challengeId,
      since: since,
    );
  }
}
