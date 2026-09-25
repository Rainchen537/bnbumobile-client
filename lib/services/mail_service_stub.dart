import '../models/mail_models.dart';
import 'mail_service.dart';

MailService createPlatformMailService() => MailServiceImpl();

class MailServiceImpl extends MailService {
  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
    MailSearchScope searchScope = MailSearchScope.allText,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> markMessagesSeen({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<void> restoreMessages({
    required MailAccessCredentials credentials,
    required List<int> uids,
    required String userEmailAddress,
    int? expectedMailboxUidValidity,
  }) async {}

  @override
  Future<void> close() async {}
}
