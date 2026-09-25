import 'package:bnbu_me/pages/file_preview_page.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:image/image.dart' as image;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/pages/mail_page.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';
import 'package:bnbu_me/services/mail_attachment_store.dart';
import 'package:bnbu_me/services/mail_sender_avatar_service.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/services/mail_radar_analyzer.dart';
import 'package:bnbu_me/services/native_actions.dart';
import 'package:bnbu_me/state/mail_radar_controller.dart';
import 'package:bnbu_me/widgets/assistant_context_scope.dart';
import 'package:bnbu_me/widgets/bnbu_components.dart';
import 'package:bnbu_me/widgets/bnbu_creation_form.dart';
import 'package:bnbu_me/widgets/mail_sender_avatar.dart';

// ─── Mock MailService ──────────────────────────────────────────────────────────

class _ComposeFakeFilePicker extends FilePicker {
  _ComposeFakeFilePicker({required this.files});

  final List<PlatformFile> files;
  bool? lastWithData;
  bool? lastWithReadStream;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    lastWithData = withData;
    lastWithReadStream = withReadStream;
    return FilePickerResult(files);
  }
}

class _MockMailService extends MailService {
  final List<MailMessageSummary> _inbox;
  final List<MailMessageSummary> _drafts;
  final List<MailMessageSummary> _trash;
  final int? _fakeTotal;

  final List<int> deletedUids = [];
  final List<int> restoredUids = [];
  final List<String> downloadedPartIds = [];
  int? savedDraftUid;
  int draftSaveUidValidity = 777;
  int? lastSaveExpectedUidValidity;
  int? lastDeleteExpectedUidValidity;
  MailComposeData? sentData;
  MailFolder? lastReadFolder;
  int? lastReadExpectedUidValidity;
  MailFolder? lastDownloadFolder;
  int? lastDownloadExpectedUidValidity;

  // Override readMessage to return a custom MailMessageDetail
  MailMessageDetail? Function(int uid)? readMessageOverride;

  // Capture last searchFolder call for assertions
  String? lastSearchQuery;
  MailSearchScope? lastSearchScope;

  // Capture pagination calls
  int fetchFolderCallCount = 0;
  int lastFetchedPage = 0;

  _MockMailService({
    List<MailMessageSummary>? inbox,
    List<MailMessageSummary>? drafts,
    List<MailMessageSummary>? trash,
    int? fakeTotal,
  }) : _inbox = inbox ?? [],
       _drafts = drafts ?? [],
       _trash = trash ?? [],
       _fakeTotal = fakeTotal;

  List<MailMessageSummary> _listForFolder(MailFolder folder) {
    switch (folder) {
      case MailFolder.drafts:
        return _drafts;
      case MailFolder.trash:
        return _trash;
      default:
        return _inbox;
    }
  }

  MailFolderSnapshot _makeSnapshot(
    MailFolder folder,
    List<MailMessageSummary> allMsgs,
    int page,
    int pageSize,
  ) {
    final total = _fakeTotal ?? allMsgs.length;
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, allMsgs.length);
    final mailboxUidValidity = 100 + folder.index;
    final pageMsgs = start < allMsgs.length
        ? allMsgs
              .sublist(start, end)
              .map(
                (message) => message.copyWith(
                  folder: folder,
                  mailboxUidValidity: mailboxUidValidity,
                ),
              )
              .toList(growable: false)
        : <MailMessageSummary>[];
    return MailFolderSnapshot(
      emailAddress: 'test@mail.bnbu.edu.cn',
      incomingServer: 'imap.example.com',
      outgoingServer: 'smtp.example.com',
      messages: pageMsgs,
      fetchedAt: DateTime.now(),
      folder: folder,
      totalMessages: total,
      currentPage: page,
      pageSize: pageSize,
      mailboxUidValidity: mailboxUidValidity,
    );
  }

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async {
    fetchFolderCallCount++;
    lastFetchedPage = page;
    final actualUidValidity = 100 + folder.index;
    if (expectedMailboxUidValidity != null &&
        expectedMailboxUidValidity != actualUidValidity) {
      throw const MailServiceException('邮箱内容已更新，请刷新后重试。');
    }
    final msgs = _listForFolder(folder);
    return _makeSnapshot(folder, msgs, page, pageSize);
  }

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) async {
    lastReadFolder = folder;
    lastReadExpectedUidValidity = expectedMailboxUidValidity;
    final override = readMessageOverride?.call(uid);
    if (override != null) return override;
    final all = [..._inbox, ..._drafts, ..._trash];
    final summary = all.firstWhere((m) => m.uid == uid);
    return MailMessageDetail(
      uid: summary.uid,
      subject: summary.subject,
      sender: summary.sender,
      recipients: 'test@mail.bnbu.edu.cn',
      cc: null,
      date: summary.date,
      body: 'Draft body content',
      htmlBody: null,
      isSeen: summary.isSeen,
      folder: folder,
      mailboxUidValidity: expectedMailboxUidValidity,
    );
  }

  @override
  Future<void> markMessagesSeen({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async {}

  @override
  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
    MailSearchScope searchScope = MailSearchScope.allText,
  }) async {
    lastSearchQuery = query;
    lastSearchScope = searchScope;
    return [];
  }

  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) async {
    sentData = composeData;
  }

  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  }) async {
    lastDownloadFolder = folder;
    lastDownloadExpectedUidValidity = expectedMailboxUidValidity;
    downloadedPartIds.add(partId);
    return [1, 2, 3];
  }

  @override
  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  }) async {
    lastSaveExpectedUidValidity = expectedMailboxUidValidity;
    savedDraftUid = (existingDraftUid ?? 0) + 1;
    return MailDraftIdentity(
      uid: savedDraftUid!,
      mailboxUidValidity: draftSaveUidValidity,
    );
  }

  @override
  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async {
    lastDeleteExpectedUidValidity = expectedMailboxUidValidity;
    deletedUids.addAll(uids);
  }

  @override
  Future<void> restoreMessages({
    required MailAccessCredentials credentials,
    required List<int> uids,
    required String userEmailAddress,
    int? expectedMailboxUidValidity,
  }) async {
    restoredUids.addAll(uids);
  }

  @override
  Future<void> close() async {}
}

class _UnusedMailRadarAnalyzer implements MailRadarAnalyzer {
  const _UnusedMailRadarAnalyzer();

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) => throw UnsupportedError('This analyzer must not run in this test.');
}

class _ControllableMailSenderAvatarService implements MailSenderAvatarService {
  final Completer<Uint8List?> completer = Completer<Uint8List?>();
  final List<String> requestedSenders = [];

  @override
  Future<Uint8List?> loadThumbnail(String sender) {
    requestedSenders.add(sender);
    return completer.future;
  }

  @override
  void dispose() {}
}

class _EmptyMailSenderAvatarService implements MailSenderAvatarService {
  @override
  Future<Uint8List?> loadThumbnail(String sender) async => null;

  @override
  void dispose() {}
}

class _DelayedFolderMailService extends _MockMailService {
  _DelayedFolderMailService({super.inbox, super.drafts});

  final Map<MailFolder, Completer<MailFolderSnapshot>> _pending = {};

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) {
    fetchFolderCallCount++;
    lastFetchedPage = page;
    final completer = Completer<MailFolderSnapshot>();
    _pending[folder] = completer;
    return completer.future;
  }

  void completeFolder(MailFolder folder) {
    final completer = _pending.remove(folder);
    if (completer == null) {
      throw StateError('No pending request for $folder');
    }
    completer.complete(_makeSnapshot(folder, _listForFolder(folder), 1, 25));
  }
}

class _CachedMailService extends _DelayedFolderMailService
    implements MailCacheReader {
  _CachedMailService({super.inbox});
  MailMessageDetail? cachedDetail;
  @override
  Future<MailFolderSnapshot?> readCachedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    int page = 1,
    int pageSize = 25,
    bool unreadOnly = false,
  }) async => _makeSnapshot(folder, _listForFolder(folder), page, pageSize);
  @override
  Future<MailMessageDetail?> readCachedMessage({
    required MailAccessCredentials credentials,
    required MailMessageIdentity identity,
  }) async => cachedDetail;
}

class _RecoveringFolderMailService extends _MockMailService {
  bool _shouldFail = true;

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) {
    if (_shouldFail) {
      _shouldFail = false;
      fetchFolderCallCount++;
      lastFetchedPage = page;
      return Future<MailFolderSnapshot>.error(
        const MailServiceException('Temporary IMAP failure'),
      );
    }
    return super.fetchFolder(
      credentials: credentials,
      folder: folder,
      page: page,
      pageSize: pageSize,
      expectedMailboxUidValidity: expectedMailboxUidValidity,
    );
  }
}

class _DelayedReadMailService extends _MockMailService {
  _DelayedReadMailService({super.inbox, super.drafts});

  final Completer<MailMessageDetail> _readCompleter =
      Completer<MailMessageDetail>();

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) {
    lastReadFolder = folder;
    lastReadExpectedUidValidity = expectedMailboxUidValidity;
    return _readCompleter.future;
  }

  void completeRead(MailMessageDetail detail) {
    _readCompleter.complete(detail);
  }
}

class _DelayedAttachmentMailService extends _MockMailService {
  _DelayedAttachmentMailService({super.inbox});

  final Completer<List<int>> _downloadCompleter = Completer<List<int>>();

  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  }) {
    lastDownloadFolder = folder;
    lastDownloadExpectedUidValidity = expectedMailboxUidValidity;
    downloadedPartIds.add(partId);
    return _downloadCompleter.future;
  }

  void completeDownload(List<int> bytes) {
    _downloadCompleter.complete(bytes);
  }
}

class _FakeMailAttachmentStore implements MailAttachmentStore {
  final Set<String> files = {};

  @override
  Future<bool> exists(String path) async => files.contains(path);

  @override
  Future<void> publish({required String path, required List<int> bytes}) async {
    files.add(path);
  }
}

class _DelayedDraftMailService extends _MockMailService {
  final Completer<MailDraftIdentity?> _saveCompleter =
      Completer<MailDraftIdentity?>();

  @override
  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  }) {
    lastSaveExpectedUidValidity = expectedMailboxUidValidity;
    savedDraftUid = (existingDraftUid ?? 0) + 1;
    return _saveCompleter.future;
  }

  void completeSave({required int uid, required int mailboxUidValidity}) {
    _saveCompleter.complete(
      MailDraftIdentity(uid: uid, mailboxUidValidity: mailboxUidValidity),
    );
  }
}

class _DelayedSearchMailService extends _MockMailService {
  _DelayedSearchMailService({super.inbox, super.drafts});

  final Completer<List<MailMessageSummary>> _searchCompleter =
      Completer<List<MailMessageSummary>>();
  MailFolder? searchedFolder;

  @override
  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
    MailSearchScope searchScope = MailSearchScope.allText,
  }) {
    lastSearchQuery = query;
    lastSearchScope = searchScope;
    searchedFolder = folder;
    return _searchCompleter.future;
  }

  void completeSearch(List<MailMessageSummary> messages) {
    _searchCompleter.complete(messages);
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Widget _wrapInApp(Widget child) => MaterialApp(home: child);

MailMessageSummary _makeSummary({
  required int uid,
  String subject = 'Test Subject',
  String sender = 'Sender <sender@example.com>',
  bool isSeen = true,
}) => MailMessageSummary(
  uid: uid,
  subject: subject,
  sender: sender,
  preview: 'Preview',
  hasHtmlBody: false,
  date: DateTime(2026, 3, 17),
  isSeen: isSeen,
);

MailAccessCredentials _creds() => MailAccessCredentials(
  userId: 'testuser',
  emailAddress: 'testuser@mail.bnbu.edu.cn',
  password: 'password',
);

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  const scopePreviews = bool.fromEnvironment('MAIL_SCOPE_PREVIEWS');
  setUpAll(() async {
    if (!scopePreviews) return;
    for (final family in ['Ahem', 'Roboto', '.SF UI Text', '.SF UI Display']) {
      await (FontLoader(family)..addFont(
            Future.value(
              ByteData.sublistView(
                await File(
                  '/System/Library/Fonts/STHeiti Light.ttc',
                ).readAsBytes(),
              ),
            ),
          ))
          .load();
    }
    await (FontLoader('packages/lucide_icons_flutter/Lucide300')..addFont(
          rootBundle.load(
            'packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf',
          ),
        ))
        .load();
  });

  testWidgets(
    'cached list is visible before IMAP finishes and survives offline refresh',
    (tester) async {
      final service = _CachedMailService(
        inbox: [_makeSummary(uid: 12, subject: 'Persisted subject')],
      );
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: service,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Persisted subject'), findsOneWidget);
      expect(service._pending, contains(MailFolder.inbox));
      service._pending
          .remove(MailFolder.inbox)!
          .completeError(const MailServiceException('Offline fixture'));
      await tester.pumpAndSettle();
      expect(find.text('Persisted subject'), findsOneWidget);
    },
  );

  testWidgets(
    'cached body stays readable while live identity check is unavailable',
    (tester) async {
      final service = _CachedMailService()
        ..cachedDetail = const MailMessageDetail(
          uid: 12,
          subject: 'Persisted subject',
          sender: 'Teacher',
          recipients: 'Student',
          cc: null,
          date: null,
          body: 'Persisted body without another download',
          htmlBody: null,
          isSeen: false,
          mailboxUidValidity: 100,
        );
      final pending = Completer<MailMessageDetail>();
      await tester.pumpWidget(
        _wrapInApp(
          MailDetailPage.loading(
            summary: _makeSummary(
              uid: 12,
              subject: 'Persisted subject',
            ).copyWith(mailboxUidValidity: 100),
            loadDetail: () => pending.future,
            timeFormat: DateFormat('yyyy-MM-dd HH:mm'),
            mailService: service,
            credentials: _creds(),
            attachmentStore: _FakeMailAttachmentStore(),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('Persisted body without another download'),
        findsOneWidget,
      );
      pending.completeError(const MailServiceException('Offline fixture'));
      await tester.pumpAndSettle();
      expect(
        find.text('Persisted body without another download'),
        findsOneWidget,
      );
      expect(find.text('邮件暂时无法读取'), findsNothing);
    },
  );

  // ── Test 1: Toolbar equal-width sections ──────────────────────────────────

  group('Toolbar layout', () {
    testWidgets(
      'wide mailbox starts with compose and omits duplicate branding',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final svc = _MockMailService();

        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final workspace = find.byKey(const ValueKey('mail-desktop-workspace'));
        final compose = find.byKey(const ValueKey('mail-desktop-compose'));
        expect(workspace, findsOneWidget);
        expect(compose, findsOneWidget);
        expect(find.text('邮箱'), findsNothing);
        expect(find.byIcon(LucideIcons.mail300), findsNothing);
        expect(
          tester.getTopLeft(compose).dy - tester.getTopLeft(workspace).dy,
          closeTo(0, 0.1),
        );
      },
    );

    testWidgets('wide mailbox opens a reading canvas without a route push', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final svc = _MockMailService(
        inbox: [
          _makeSummary(uid: 71, subject: 'Three pane message', isSeen: false),
        ],
      );
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('选择一封邮件'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mail-desktop-row-71')));
      await tester.pumpAndSettle();

      expect(svc.lastReadFolder, MailFolder.inbox);
      expect(
        find.byKey(const ValueKey('mail-desktop-reading-pane')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mail-desktop-reading-title')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mail-detail-expanded-header')),
        findsNothing,
      );
      expect(find.byType(MailDetailPage), findsNothing);
    });

    testWidgets(
      'desktop mailbox uses two panes at 880 and adds folders at 1100',
      (tester) async {
        addTearDown(tester.view.reset);
        for (final width in [880.0, 900.0, 1100.0, 1440.0]) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          final svc = _MockMailService(
            inbox: [_makeSummary(uid: width.toInt(), subject: 'Width $width')],
          );
          await tester.pumpWidget(
            _wrapInApp(
              MailPage.withService(
                controller: null,
                mailService: svc,
                testCredentials: _creds(),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('mail-desktop-workspace')),
            findsOneWidget,
          );
          final listRect = tester.getRect(
            find.byKey(const ValueKey('mail-desktop-message-list')),
          );
          expect(listRect.width, inInclusiveRange(280, 330));
          expect(
            find.text('星标邮件'),
            width >= 1100 ? findsOneWidget : findsNothing,
          );
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );

    testWidgets(
      'desktop rows keep avatar-only interaction and use a blue active state',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final svc = _MockMailService(
          inbox: [
            _makeSummary(uid: 74, sender: 'Blue selection <blue@example.com>'),
            _makeSummary(uid: 75, sender: 'Second <second@example.com>'),
          ],
        );
        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('mail-desktop-row-74'));
        expect(
          find.descendant(of: row, matching: find.byType(Checkbox)),
          findsNothing,
        );

        await tester.tap(row);
        await tester.pumpAndSettle();
        expect(tester.widget<Material>(row).color, const Color(0xFF3187F4));

        await tester.longPress(row);
        await tester.pumpAndSettle();
        expect(find.byType(Checkbox), findsNothing);
      },
    );

    testWidgets('wide reading command bar replies to all recipients', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final summary = _makeSummary(
        uid: 72,
        subject: 'Reply everyone',
      ).copyWith(mailboxUidValidity: 902);
      final svc = _MockMailService(inbox: [summary])
        ..readMessageOverride = (_) => const MailMessageDetail(
          uid: 72,
          subject: 'Reply everyone',
          sender: 'Sender <sender@example.com>',
          recipients: 'first@example.com, testuser@mail.bnbu.edu.cn',
          cc: 'copy@example.com',
          date: null,
          body: 'Original',
          htmlBody: null,
          isSeen: false,
          folder: MailFolder.inbox,
          mailboxUidValidity: 902,
        );
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mail-desktop-row-72')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mail-desktop-reply-all')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(svc.sentData?.to, 'sender@example.com');
      expect(svc.sentData?.cc, contains('first@example.com'));
      expect(svc.sentData?.cc, contains('copy@example.com'));
      expect(svc.sentData?.cc, isNot(contains('testuser@mail.bnbu.edu.cn')));
    });

    testWidgets(
      'wide reading command bar forwards safe HTML and deletes selected mail',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final summary = _makeSummary(
          uid: 73,
          subject: 'Forward safely',
        ).copyWith(mailboxUidValidity: 903);
        final svc = _MockMailService(inbox: [summary])
          ..readMessageOverride = (_) => const MailMessageDetail(
            uid: 73,
            subject: 'Forward safely',
            sender: 'Sender <sender@example.com>',
            recipients: 'student@example.com',
            cc: null,
            date: null,
            body: 'Original body',
            htmlBody:
                '<p>Original <strong>HTML</strong><script>alert(1)</script></p>',
            isSeen: false,
            folder: MailFolder.inbox,
            mailboxUidValidity: 903,
          );
        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mail-desktop-row-73')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mail-desktop-forward')));
        await tester.pumpAndSettle();
        final subject = tester.widget<TextField>(
          find.byKey(const ValueKey('compose-subject-field')),
        );
        expect(subject.controller?.text, 'Fwd: Forward safely');
        await tester.enterText(
          find.byKey(const ValueKey('compose-recipient-field')),
          'recipient@example.com',
        );
        await tester.pump();
        final send = tester.widget<BnbuCreationAction>(
          find.byKey(const ValueKey('compose-send')),
        );
        expect(send.onPressed, isNotNull);
        await tester.tap(find.byKey(const ValueKey('compose-send')));
        await tester.pumpAndSettle();
        expect(
          svc.sentData?.htmlBody,
          contains('Original <strong>HTML</strong>'),
        );
        expect(svc.sentData?.htmlBody, isNot(contains('<script>')));

        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mail-desktop-row-73')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('mail-desktop-delete-or-restore')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('删除').last);
        await tester.pumpAndSettle();
        expect(svc.deletedUids, contains(73));
        expect(svc.lastDeleteExpectedUidValidity, 100);
      },
    );

    testWidgets('mailbox refresh is pull-only', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.refresh_rounded), findsNothing);
      expect(find.byTooltip('刷新邮箱'), findsNothing);
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('compact mailbox top bar keeps search and compose aligned', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final topBar = tester.getRect(
        find.byKey(const ValueKey('mail-compact-top-bar')),
      );
      final search = tester.getRect(
        find.byKey(const ValueKey('mail-search-control')),
      );
      final compose = tester.getRect(
        find.byKey(const ValueKey('mail-compose-action')),
      );
      expect(topBar.height, 60);
      expect(search.height, closeTo(40, 2));
      expect(search.center.dx, closeTo(topBar.center.dx, 0.1));
      expect(compose.size, const Size.square(44));
      expect(search.center.dy, closeTo(compose.center.dy, 0.1));
    });

    testWidgets(
      'compact inbox keeps its controls fixed while messages scroll',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final svc = _MockMailService(
          inbox: List.generate(
            30,
            (index) => _makeSummary(
              uid: index + 1,
              subject: 'Scrollable message $index',
            ),
          ),
        );
        final radarController = MailRadarController(
          username: 'student',
          credentials: _creds(),
          mailService: svc,
          analyzer: const _UnusedMailRadarAnalyzer(),
        );
        await radarController.initialize();
        await radarController.setRangeChoice(30);
        addTearDown(radarController.dispose);
        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
              radarController: radarController,
            ),
          ),
        );
        await tester.pumpAndSettle();

        const topBarKey = ValueKey('mail-compact-top-bar');
        const radarKey = ValueKey('mail-radar-mobile-tile');
        const folderToolbarKey = ValueKey('mail-folder-toolbar');
        final topBefore = tester.getTopLeft(find.byKey(topBarKey)).dy;
        final radarBefore = tester.getTopLeft(find.byKey(radarKey)).dy;
        final toolbarBefore = tester
            .getTopLeft(find.byKey(folderToolbarKey))
            .dy;
        expect(find.byKey(radarKey).hitTestable(), findsOneWidget);
        expect(find.byKey(folderToolbarKey).hitTestable(), findsOneWidget);

        await tester.drag(
          find.byKey(const ValueKey('mail-compact-message-list')),
          const Offset(0, -360),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(find.byKey(topBarKey)).dy,
          closeTo(topBefore, 0.1),
        );
        expect(
          tester.getTopLeft(find.byKey(radarKey)).dy,
          closeTo(radarBefore, 0.1),
        );
        expect(
          tester.getTopLeft(find.byKey(folderToolbarKey)).dy,
          closeTo(toolbarBefore, 0.1),
        );
        expect(
          find.byKey(const ValueKey('mail-search-control')).hitTestable(),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'compact radar keeps both control rows pinned while radar messages scroll',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({});
        final svc = _MockMailService();
        final radarController = MailRadarController(
          username: 'student',
          credentials: _creds(),
          mailService: svc,
          analyzer: const _UnusedMailRadarAnalyzer(),
        );
        await radarController.initialize();
        await radarController.setRangeChoice(30);
        addTearDown(radarController.dispose);
        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
              radarController: radarController,
              radarPollInterval: Duration.zero,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('mail-radar-mobile-tile')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('mail-radar-scroll')), findsOneWidget);
        const topBarKey = ValueKey('mail-compact-top-bar');
        const radarKey = ValueKey('mail-radar-mobile-tile');
        const folderToolbarKey = ValueKey('mail-folder-toolbar');
        final topBefore = tester.getTopLeft(find.byKey(topBarKey)).dy;
        expect(
          find.byKey(const ValueKey('mail-search-control')).hitTestable(),
          findsOneWidget,
        );
        expect(find.byKey(radarKey).hitTestable(), findsOneWidget);
        expect(find.byKey(folderToolbarKey).hitTestable(), findsOneWidget);

        await tester.drag(
          find.byKey(const ValueKey('mail-radar-scroll')),
          const Offset(0, -420),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(find.byKey(topBarKey)).dy,
          closeTo(topBefore, 0.1),
        );
        expect(find.byKey(radarKey).hitTestable(), findsOneWidget);
        expect(find.byKey(folderToolbarKey).hitTestable(), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mail-search-control')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mail-compose-action')).hitTestable(),
          findsOneWidget,
        );

        await tester.drag(
          find.byKey(const ValueKey('mail-radar-scroll')),
          const Offset(0, 420),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('mail-search-control')).hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.getTopLeft(find.byKey(topBarKey)).dy,
          closeTo(topBefore, 0.1),
        );
        expect(find.byKey(radarKey).hitTestable(), findsOneWidget);
        expect(find.byKey(folderToolbarKey).hitTestable(), findsOneWidget);
      },
    );

    testWidgets('initial mailbox error remains pull-to-refreshable', (
      tester,
    ) async {
      final svc = _RecoveringFolderMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Temporary IMAP failure'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);
      final refreshableState = find.byKey(
        const ValueKey('mail-refreshable-state'),
      );
      expect(refreshableState, findsOneWidget);

      await tester.drag(refreshableState, const Offset(0, 320));
      await tester.pumpAndSettle();

      expect(svc.fetchFolderCallCount, 2);
      expect(find.textContaining('Temporary IMAP failure'), findsNothing);
      expect(find.text('没有匹配的邮件'), findsOneWidget);
    });

    testWidgets(
      'toolbar exposes folder, unread and selection in reading order',
      (tester) async {
        final svc = _MockMailService(
          inbox: [_makeSummary(uid: 1, isSeen: false)],
        );
        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final folder = tester.getCenter(find.text('收件箱'));
        final unread = tester.getCenter(find.text('未读'));
        final selection = tester.getCenter(find.text('多选'));
        expect(folder.dx, lessThan(unread.dx));
        expect(unread.dx, lessThan(selection.dx));
        expect(folder.dy, closeTo(unread.dy, 1));
        expect(selection.dy, closeTo(unread.dy, 1));
      },
    );
  });

  group('Compact mail typography', () {
    testWidgets('mail list keeps sender, subject and preview compact', (
      tester,
    ) async {
      final svc = _MockMailService(
        inbox: [
          _makeSummary(
            uid: 1,
            sender: 'Campus Office <office@bnbu.edu.cn>',
            subject: 'Registration reminder',
          ),
        ],
      );
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      final sender = tester.widget<Text>(find.text('Campus Office'));
      final subject = tester.widget<Text>(find.text('Registration reminder'));
      final preview = tester.widget<Text>(find.text('Preview'));

      expect(sender.style?.fontSize, 17);
      expect(subject.style?.fontSize, 14);
      expect(preview.maxLines, 1);
    });

    testWidgets('only sender is bold and unread state stays on avatar', (
      tester,
    ) async {
      final svc = _MockMailService(
        inbox: [
          _makeSummary(
            uid: 11,
            sender: 'Campus Office <office@bnbu.edu.cn>',
            subject: 'Unread registration reminder',
            isSeen: false,
          ),
        ],
      );
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      final sender = tester.widget<Text>(find.text('Campus Office'));
      final subject = tester.widget<Text>(
        find.text('Unread registration reminder'),
      );
      final preview = tester.widget<Text>(find.text('Preview'));
      expect(sender.style?.fontWeight, FontWeight.w500);
      expect(subject.style?.fontWeight, FontWeight.w400);
      expect(preview.style?.fontWeight, FontWeight.w400);

      final avatar = find.byKey(const ValueKey('mail-avatar-11'));
      final unread = find.byKey(const ValueKey('mail-unread-indicator-11'));
      expect(avatar, findsOneWidget);
      expect(unread, findsOneWidget);
      expect(
        tester.getCenter(unread).dx,
        greaterThan(tester.getCenter(avatar).dx),
      );
      expect(
        tester.getCenter(unread).dy,
        lessThan(tester.getCenter(avatar).dy),
      );
    });

    testWidgets(
      'official sender avatars use functional groups and show abbreviations',
      (tester) async {
        final avatarService = _EmptyMailSenderAvatarService();
        final svc = _MockMailService(
          inbox: [
            _makeSummary(
              uid: 21,
              sender: 'AR <ar@bnbu.edu.cn>',
              subject: 'Academic Registry',
            ),
            _makeSummary(
              uid: 22,
              sender: 'UGSS <ugss@bnbu.edu.cn>',
              subject: 'Student services',
            ),
            _makeSummary(
              uid: 23,
              sender: 'Library <library@bnbu.edu.cn>',
              subject: 'Library notice',
            ),
            _makeSummary(
              uid: 24,
              sender: '工商管理学院 <fbm@bnbu.edu.cn>',
              subject: 'Faculty notice',
            ),
            _makeSummary(
              uid: 25,
              sender: 'Teacher <teacher.name@bnbu.edu.cn>',
              subject: 'Teacher notice',
            ),
            _makeSummary(
              uid: 26,
              sender: 'External Partner <partner@example.com>',
              subject: 'External notice',
            ),
          ],
        );
        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
              senderAvatarService: avatarService,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(LucideIcons.clipboardCheck300), findsOneWidget);
        expect(find.byIcon(LucideIcons.graduationCap300), findsOneWidget);
        expect(find.byIcon(LucideIcons.bookOpen300), findsOneWidget);
        expect(find.byIcon(LucideIcons.landmark300), findsOneWidget);
        expect(find.byIcon(LucideIcons.building2300), findsOneWidget);
        for (final badge in ['AR', 'UGS', 'LIB', 'FBM', 'TN']) {
          expect(
            find.byKey(ValueKey('mail-organization-$badge')),
            findsOneWidget,
          );
        }

        expect(
          find.descendant(
            of: find.byKey(const ValueKey('mail-avatar-26')),
            matching: find.byType(Text),
          ),
          findsOneWidget,
        );

        expect(
          resolveMailSenderAvatarAppearance('AR <ar@bnbu.edu.cn>').accentColor,
          isNot(
            resolveMailSenderAvatarAppearance(
              'UGSS <ugss@bnbu.edu.cn>',
            ).accentColor,
          ),
        );
      },
    );

    testWidgets(
      'official teacher portrait replaces fallback without shifting the row',
      (tester) async {
        final avatarService = _ControllableMailSenderAvatarService();
        final svc = _MockMailService(
          inbox: [
            _makeSummary(
              uid: 27,
              sender: 'Teacher Chen <teacher.chen@bnbu.edu.cn>',
              subject: 'Teacher notice',
            ),
          ],
        );
        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
              senderAvatarService: avatarService,
            ),
          ),
        );
        await tester.pump();

        final avatarFinder = find.byKey(const ValueKey('mail-avatar-27'));
        expect(avatarFinder, findsOneWidget);
        final initialRect = tester.getRect(avatarFinder);
        expect(find.byIcon(LucideIcons.building2300), findsOneWidget);

        final source = image.Image(width: 96, height: 96);
        image.fill(source, color: image.ColorRgb8(50, 100, 150));
        avatarService.completer.complete(
          Uint8List.fromList(image.encodePng(source)),
        );
        await tester.pumpAndSettle();

        expect(
          find.descendant(of: avatarFinder, matching: find.byType(Image)),
          findsOneWidget,
        );
        expect(tester.getRect(avatarFinder), initialRect);
        expect(avatarService.requestedSenders, [
          'Teacher Chen <teacher.chen@bnbu.edu.cn>',
        ]);
      },
    );

    testWidgets('mail detail reuses the official teacher portrait', (
      tester,
    ) async {
      final avatarService = _ControllableMailSenderAvatarService();
      final source = image.Image(width: 96, height: 96);
      image.fill(source, color: image.ColorRgb8(50, 100, 150));
      avatarService.completer.complete(
        Uint8List.fromList(image.encodePng(source)),
      );

      await tester.pumpWidget(
        _wrapInApp(
          MailDetailPage(
            detail: const MailMessageDetail(
              uid: 28,
              subject: 'Teacher detail',
              sender: 'Teacher Chen <teacher.chen@bnbu.edu.cn>',
              recipients: 'student@mail.bnbu.edu.cn',
              cc: null,
              date: null,
              body: 'Course update.',
              htmlBody: null,
              isSeen: true,
              folder: MailFolder.inbox,
              mailboxUidValidity: 100,
            ),
            timeFormat: DateFormat('yyyy-MM-dd HH:mm'),
            onReply: () {},
            mailService: _MockMailService(),
            credentials: _creds(),
            attachmentStore: _FakeMailAttachmentStore(),
            senderAvatarService: avatarService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('mail-detail-expanded-header')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
    });

    testWidgets('plain text detail uses an immersive reading scale', (
      tester,
    ) async {
      const detail = MailMessageDetail(
        uid: 1,
        subject: 'A concise subject',
        sender: 'office@bnbu.edu.cn',
        recipients: 'student@mail.bnbu.edu.cn',
        cc: null,
        date: null,
        body: 'A compact mail body.',
        htmlBody: null,
        isSeen: true,
        folder: MailFolder.inbox,
        mailboxUidValidity: 100,
      );
      await tester.pumpWidget(
        _wrapInApp(
          MailDetailPage(
            detail: detail,
            timeFormat: DateFormat('yyyy-MM-dd HH:mm'),
            onReply: () {},
            mailService: _MockMailService(),
            credentials: _creds(),
            attachmentStore: _FakeMailAttachmentStore(),
          ),
        ),
      );

      final subject = tester.widget<Text>(find.text('A concise subject'));
      final body = tester.widget<Text>(find.text('A compact mail body.'));
      final sender = tester.widget<Text>(find.text('office'));
      final avatar = tester.widget<MailSenderAvatar>(
        find.byType(MailSenderAvatar),
      );
      expect(subject.style?.fontSize, closeTo(18.7, 0.01));
      expect(body.style?.fontSize, 14);
      expect(sender.style?.fontSize, closeTo(14, 0.01));
      expect(avatar.diameter, 20);
      expect(
        subject.style!.fontSize! / body.style!.fontSize!,
        closeTo(18.7 / 14, 0.01),
      );
    });

    testWidgets(
      'detail header collapses into a single-line subject on scroll',
      (tester) async {
        const subject = '关于 T2-106 初选面包店停止营业的通知';
        final longBody = List<String>.filled(
          30,
          '邮件正文保持紧凑、清晰，并跟随滚动进入沉浸阅读模式。',
        ).join('\n\n');
        await tester.pumpWidget(
          _wrapInApp(
            MailDetailPage(
              detail: MailMessageDetail(
                uid: 2,
                subject: subject,
                sender: 'BNBU EMO <emo@bnbu.edu.cn>',
                recipients: 'all_staff，all_students',
                cc: null,
                date: DateTime(2026, 7, 23),
                body: longBody,
                htmlBody: null,
                isSeen: true,
                folder: MailFolder.inbox,
                mailboxUidValidity: 100,
              ),
              timeFormat: DateFormat('yyyy-MM-dd HH:mm'),
              onReply: () {},
              mailService: _MockMailService(),
              credentials: _creds(),
              attachmentStore: _FakeMailAttachmentStore(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('mail-detail-expanded-header')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('mail-detail-collapsed-subject-text')),
          findsNothing,
        );

        await tester.drag(
          find.byKey(const ValueKey('mail-detail-plain-scroll')),
          const Offset(0, -260),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('mail-detail-expanded-header')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('mail-detail-collapsed-subject-text')),
          findsOneWidget,
        );
        final collapsed = tester.widget<Text>(
          find.byKey(const ValueKey('mail-detail-collapsed-subject-text')),
        );
        expect(collapsed.maxLines, 1);
        expect(collapsed.overflow, TextOverflow.ellipsis);
        expect(collapsed.style?.fontSize, closeTo(18.7, 0.01));
      },
    );
  });

  testWidgets(
    'assistant mail summary loader includes drafts while inbox is visible',
    (tester) async {
      final coordinator = AssistantContextCoordinator();
      final svc = _MockMailService(
        inbox: [
          MailMessageSummary(
            uid: 1,
            subject: 'Inbox message',
            sender: 'teacher@bnbu.edu.cn',
            preview: 'Inbox preview',
            hasHtmlBody: false,
            date: DateTime.utc(2026, 8, 4, 8),
            isSeen: false,
          ),
        ],
        drafts: [
          MailMessageSummary(
            uid: 9,
            subject: 'Draft message',
            sender: 'testuser@mail.bnbu.edu.cn',
            preview: 'Draft preview',
            hasHtmlBody: false,
            date: DateTime.utc(2026, 8, 4, 9),
            isSeen: true,
          ),
        ],
      );
      addTearDown(coordinator.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: AssistantContextScope(
            coordinator: coordinator,
            child: MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final summaries = await coordinator.loadMailSummaries();

      expect(summaries.map((item) => item.folder), contains('inbox'));
      expect(summaries.map((item) => item.folder), contains('drafts'));
      expect(
        summaries.singleWhere((item) => item.folder == 'drafts').subject,
        'Draft message',
      );
    },
  );

  // ── Test 2: ComposeMailPage has From field ─────────────────────────────────

  group('ComposeMailPage fields', () {
    testWidgets(
      'compact compose fills the viewport and keeps header text readable',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _wrapInApp(
            ComposeMailPage(
              mailService: _MockMailService(),
              credentials: _creds(),
            ),
          ),
        );
        await tester.pump();

        final editor = tester.getRect(
          find.byKey(const ValueKey('compose-compact-editor')),
        );
        expect(editor.left, 0);
        expect(editor.right, 390);
        expect(tester.getCenter(find.text('新建邮件')).dx, closeTo(195, .1));
        expect(
          tester
              .widget<TextButton>(find.byKey(const ValueKey('compose-send')))
              .onPressed,
          isNull,
        );
        expect(find.text('0 个附件'), findsNothing);
        final toolbar = tester.getRect(
          find.byKey(const ValueKey('compose-editor-toolbar')),
        );
        final body = tester.getRect(find.byKey(const ValueKey('compose-body')));
        expect(toolbar.top, greaterThanOrEqualTo(body.bottom));
        expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('compose-body')))
              .decoration
              ?.hintText,
          isNull,
        );
      },
    );

    testWidgets('tapping outside a compose field releases its focus', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: _MockMailService(),
            credentials: _creds(),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('compose-subject-field')));
      await tester.pump();

      bool hasFocusedEditor() => tester
          .widgetList<EditableText>(find.byType(EditableText))
          .any((editable) => editable.focusNode.hasFocus);
      expect(hasFocusedEditor(), isTrue);

      await tester.tap(find.text('新建邮件'));
      await tester.pump();

      expect(hasFocusedEditor(), isFalse);
    });

    testWidgets(
      'compact compose recipient and subject labels keep page inset',
      (tester) async {
        await tester.pumpWidget(
          _wrapInApp(
            ComposeMailPage(
              mailService: _MockMailService(),
              credentials: _creds(),
            ),
          ),
        );
        await tester.pump();

        final recipientLeft = tester.getTopLeft(find.text('收件人：')).dx;
        final subjectLeft = tester.getTopLeft(find.text('主题：')).dx;

        expect(recipientLeft, greaterThanOrEqualTo(15));
        expect(subjectLeft, closeTo(recipientLeft, 1.1));
      },
    );

    testWidgets(
      'compose reads streamed picker files and sanitizes file names',
      (tester) async {
        final picker = _ComposeFakeFilePicker(
          files: [
            PlatformFile(
              name: '../report?.pdf',
              size: 3,
              readStream: Stream<List<int>>.value([1, 2, 3]),
            ),
          ],
        );
        await tester.pumpWidget(
          _wrapInApp(
            ComposeMailPage(
              mailService: _MockMailService(),
              credentials: _creds(),
              filePicker: picker,
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.byKey(const ValueKey('compose-add-attachment')));
        await tester.pumpAndSettle();

        expect(picker.lastWithData, isFalse);
        expect(picker.lastWithReadStream, isTrue);
        expect(find.text('report_.pdf'), findsOneWidget);
        expect(find.byType(InputChip), findsOneWidget);
      },
    );

    testWidgets('shows sender account below the centered title', (
      tester,
    ) async {
      final svc = _MockMailService();
      final creds = _creds();
      await tester.pumpWidget(
        _wrapInApp(ComposeMailPage(mailService: svc, credentials: creds)),
      );
      await tester.pump();

      expect(find.text('新建邮件'), findsOneWidget);
      expect(find.text('发件人：'), findsNothing);
      // Should show the user's email in the From field
      expect(
        find.textContaining('testuser@mail.bnbu.edu.cn'),
        findsWidgets,
        reason: 'From field should display the sender email',
      );
    });

    testWidgets('shows 收件人 (To) editable field', (tester) async {
      final svc = _MockMailService();
      final creds = _creds();
      await tester.pumpWidget(
        _wrapInApp(ComposeMailPage(mailService: svc, credentials: creds)),
      );
      await tester.pump();

      expect(find.text('收件人：'), findsOneWidget);
      // Can type into the To field
      await tester.enterText(
        find
            .byWidgetPredicate(
              (w) => w is TextField && (w.controller?.text ?? '').isEmpty,
              description: 'empty TextField for To',
            )
            .first,
        'recipient@example.com',
      );
      expect(find.text('recipient@example.com'), findsOneWidget);
    });

    testWidgets('pre-fills a confirmed assistant draft', (tester) async {
      final svc = _MockMailService();
      final creds = _creds();
      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: svc,
            credentials: creds,
            initialRecipient: 'teacher@bnbu.edu.cn',
            initialSubject: 'Course question',
            initialBody: 'Dear teacher,',
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('teacher@bnbu.edu.cn'), findsWidgets);
      expect(find.textContaining('Course question'), findsWidgets);
      expect(find.textContaining('Dear teacher,'), findsWidgets);
    });

    testWidgets('uses a flat native layout with optional cc and bcc rows', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: _MockMailService(),
            credentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(BnbuSurfaceCard), findsNothing);
      expect(find.byKey(const ValueKey('compose-close')), findsOneWidget);
      expect(find.byKey(const ValueKey('compose-send')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('compose-add-attachment')),
        findsOneWidget,
      );
      expect(find.text('密送：'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('compose-toggle-cc-bcc')));
      await tester.pump();
      expect(find.text('抄送：'), findsOneWidget);
      expect(find.text('密送：'), findsOneWidget);
    });

    testWidgets('close asks whether unsaved content should become a draft', (
      tester,
    ) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(ComposeMailPage(mailService: svc, credentials: _creds())),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('compose-subject-field')),
        'Unsaved subject',
      );

      await tester.tap(find.byKey(const ValueKey('compose-close')));
      await tester.pumpAndSettle();

      expect(find.text('保存草稿？'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('compose-exit-discard')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('compose-exit-save')), findsOneWidget);
      expect(svc.savedDraftUid, isNull);
    });

    testWidgets(
      'save and close persists the draft and shows the global notice',
      (tester) async {
        final svc = _MockMailService();
        await tester.pumpWidget(
          _wrapInApp(ComposeMailPage(mailService: svc, credentials: _creds())),
        );
        await tester.pump();
        await tester.enterText(
          find.byKey(const ValueKey('compose-subject-field')),
          'Save this draft',
        );
        await tester.tap(find.byKey(const ValueKey('compose-close')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('compose-exit-save')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(svc.savedDraftUid, 1);
        expect(find.byKey(const ValueKey('bnbu-notice')), findsOneWidget);
        expect(find.text('草稿已保存'), findsOneWidget);
      },
    );

    testWidgets('draft detail takes priority over assistant initial values', (
      tester,
    ) async {
      final svc = _MockMailService();
      final creds = _creds();
      const draftDetail = MailMessageDetail(
        uid: 42,
        subject: 'Saved draft',
        sender: 'testuser@mail.bnbu.edu.cn',
        recipients: 'saved@bnbu.edu.cn',
        cc: null,
        date: null,
        body: 'Saved body',
        htmlBody: null,
        isSeen: true,
      );
      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: svc,
            credentials: creds,
            draftDetail: draftDetail,
            initialRecipient: 'guessed@bnbu.edu.cn',
            initialSubject: 'AI subject',
            initialBody: 'AI body',
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('saved@bnbu.edu.cn'), findsWidgets);
      expect(find.textContaining('Saved draft'), findsWidgets);
      expect(find.textContaining('Saved body'), findsWidgets);
      expect(find.textContaining('guessed@bnbu.edu.cn'), findsNothing);
      expect(find.textContaining('AI subject'), findsNothing);
    });

    testWidgets('pre-fills fields when draftDetail provided', (tester) async {
      final svc = _MockMailService();
      final creds = _creds();
      const draftDetail = MailMessageDetail(
        uid: 42,
        subject: 'My Draft Subject',
        sender: 'testuser@mail.bnbu.edu.cn',
        recipients: 'somebody@example.com',
        cc: 'cc@example.com',
        date: null,
        body: 'Draft body text',
        htmlBody: null,
        isSeen: true,
      );
      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: svc,
            credentials: creds,
            draftDetail: draftDetail,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.textContaining('somebody@example.com'),
        findsWidgets,
        reason: 'To field should be pre-filled from draftDetail.recipients',
      );
      expect(
        find.textContaining('My Draft Subject'),
        findsWidgets,
        reason: 'Subject field should be pre-filled',
      );
      expect(
        find.textContaining('Draft body text'),
        findsWidgets,
        reason: 'Body should be pre-filled',
      );
    });

    testWidgets('auto-saved draft keeps UIDVALIDITY for replacement and send', (
      tester,
    ) async {
      final svc = _MockMailService()..draftSaveUidValidity = 900;
      final creds = _creds();
      const draftDetail = MailMessageDetail(
        uid: 42,
        subject: 'Draft Subject',
        sender: 'testuser@mail.bnbu.edu.cn',
        recipients: 'somebody@example.com',
        cc: null,
        date: null,
        body: 'Initial body',
        htmlBody: null,
        isSeen: true,
        folder: MailFolder.drafts,
        mailboxUidValidity: 500,
      );
      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: svc,
            credentials: creds,
            draftDetail: draftDetail,
          ),
        ),
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.key == const ValueKey('compose-body'),
        ),
        'Updated body',
      );

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(svc.lastSaveExpectedUidValidity, 500);
      expect(svc.savedDraftUid, 43);

      await tester.tap(find.text('发送'));
      await tester.pump();
      await tester.pump();

      expect(svc.deletedUids, [43]);
      expect(svc.lastDeleteExpectedUidValidity, 900);
    });

    testWidgets('send waits for an in-flight draft save identity', (
      tester,
    ) async {
      final svc = _DelayedDraftMailService();
      final creds = _creds();
      const draftDetail = MailMessageDetail(
        uid: 42,
        subject: 'Draft Subject',
        sender: 'testuser@mail.bnbu.edu.cn',
        recipients: 'somebody@example.com',
        cc: null,
        date: null,
        body: 'Initial body',
        htmlBody: null,
        isSeen: true,
        folder: MailFolder.drafts,
        mailboxUidValidity: 500,
      );
      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: svc,
            credentials: creds,
            draftDetail: draftDetail,
          ),
        ),
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.key == const ValueKey('compose-body'),
        ),
        'Updated body',
      );
      await tester.pump(const Duration(minutes: 1));

      await tester.tap(find.text('发送'));
      await tester.pump();
      expect(svc.sentData, isNull);

      svc.completeSave(uid: 43, mailboxUidValidity: 900);
      await tester.pump();
      await tester.pump();

      expect(svc.sentData, isNotNull);
      expect(svc.deletedUids, [43]);
      expect(svc.lastDeleteExpectedUidValidity, 900);
    });
  });

  // ── Test 3: Draft folder opens compose, not detail ─────────────────────────

  group('Draft folder behavior', () {
    testWidgets('tapping draft message opens ComposeMailPage not detail', (
      tester,
    ) async {
      final draft = _makeSummary(uid: 99, subject: 'My Draft', isSeen: true);
      final svc = _MockMailService(drafts: [draft]);

      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump(); // initState triggers fetchFolder(inbox)

      // Switch to drafts folder via the folder selector
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('草稿箱'));
      await tester.pumpAndSettle();
      await tester.pump(); // fetchFolder(drafts) completes

      // Tap the draft message
      await tester.tap(find.text('My Draft'));
      await tester.pumpAndSettle();

      // Should show ComposeMailPage, not a detail page.
      expect(
        find.text('邮件详情'),
        findsNothing,
        reason: 'Draft taps should NOT open detail page',
      );
      expect(
        find.byKey(const ValueKey('compose-close')),
        findsOneWidget,
        reason: 'Draft taps SHOULD open compose page',
      );
    });
  });

  group('Mailbox request identity', () {
    testWidgets('message route opens before its detail request completes', (
      tester,
    ) async {
      final svc = _DelayedReadMailService(
        inbox: [_makeSummary(uid: 7, subject: 'Immediate detail')],
      );
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Immediate detail'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(MailDetailPage), findsOneWidget);
      expect(find.byKey(const ValueKey('mail-detail-loading')), findsOneWidget);
      expect(find.text('Immediate detail'), findsOneWidget);
      expect(find.text('Loaded body'), findsNothing);
      expect(svc.lastReadExpectedUidValidity, 100);

      svc.completeRead(
        const MailMessageDetail(
          uid: 7,
          subject: 'Immediate detail',
          sender: 'sender@example.com',
          recipients: 'test@mail.bnbu.edu.cn',
          cc: null,
          date: null,
          body: 'Loaded body',
          htmlBody: null,
          isSeen: true,
          folder: MailFolder.inbox,
          mailboxUidValidity: 100,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Loaded body'), findsOneWidget);
    });

    testWidgets('stale folder refresh cannot publish under a new folder', (
      tester,
    ) async {
      final svc = _DelayedFolderMailService(
        inbox: [_makeSummary(uid: 1, subject: 'Stale Inbox Message')],
        drafts: [_makeSummary(uid: 2, subject: 'Current Draft')],
      );
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .onSelected!('drafts');
      await tester.pump();

      svc.completeFolder(MailFolder.inbox);
      await tester.pump();
      expect(find.text('Stale Inbox Message'), findsNothing);
      expect(find.text('草稿箱'), findsOneWidget);

      svc.completeFolder(MailFolder.drafts);
      await tester.pump();
      expect(find.text('Current Draft'), findsOneWidget);
      expect(find.text('Stale Inbox Message'), findsNothing);
    });

    testWidgets('message open keeps the tapped mailbox identity', (
      tester,
    ) async {
      final svc = _DelayedReadMailService(
        inbox: [_makeSummary(uid: 7, subject: 'Inbox Message')],
        drafts: [_makeSummary(uid: 8, subject: 'Draft Message')],
      );
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Inbox Message'));
      await tester.pump();
      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .onSelected!('drafts');
      await tester.pump();

      svc.completeRead(
        const MailMessageDetail(
          uid: 7,
          subject: 'Inbox Message',
          sender: 'sender@example.com',
          recipients: 'test@mail.bnbu.edu.cn',
          cc: null,
          date: null,
          body: 'Inbox body',
          htmlBody: null,
          isSeen: true,
          folder: MailFolder.inbox,
          mailboxUidValidity: 100,
        ),
      );
      await tester.pumpAndSettle();

      expect(svc.lastReadFolder, MailFolder.inbox);
      expect(svc.lastReadExpectedUidValidity, 100);
      expect(find.byTooltip('返回邮箱'), findsOneWidget);
      expect(find.text('继续编辑'), findsNothing);
    });

    testWidgets('stale search result cannot publish after folder switch', (
      tester,
    ) async {
      final svc = _DelayedSearchMailService(
        inbox: [_makeSummary(uid: 1, subject: 'Inbox Message')],
        drafts: [_makeSummary(uid: 2, subject: 'Draft Message')],
      );
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.key == const ValueKey('mail-search-control'),
        ),
        'stale',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(svc.searchedFolder, MailFolder.inbox);

      tester
          .widget<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))
          .onSelected!('drafts');
      await tester.pump();

      svc.completeSearch([
        _makeSummary(uid: 9, subject: 'Stale Search Result'),
      ]);
      await tester.pump();

      expect(find.text('Stale Search Result'), findsNothing);
      expect(find.text('Draft Message'), findsOneWidget);
    });
  });

  // ── Test 4: Search scope behavior ─────────────────────────────────────────

  group('Search scope behavior', () {
    for (final variant in [
      (900.0, false, const Locale('zh', 'CN')),
      (1180.0, false, const Locale('zh', 'CN')),
      (1440.0, false, const Locale('zh', 'CN')),
      (900.0, true, const Locale('en')),
      (1440.0, true, const Locale('en')),
    ]) {
      final (width, dark, locale) = variant;
      testWidgets('desktop scope matches search slot at $variant', (
        tester,
      ) async {
        if (scopePreviews) {
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = true);
        }
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final svc = _MockMailService();
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('mail-scope-preview'),
            child: MaterialApp(
              theme: dark ? AppTheme.dark : AppTheme.light,
              locale: locale,
              supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
              debugShowCheckedModeBanner: false,
              localizationsDelegates: const [
                BnbuLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              home: MailPage.withService(
                controller: null,
                mailService: svc,
                testCredentials: _creds(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('mail-search-control'));
        await tester.tap(search);
        await tester.pumpAndSettle();
        final before = tester.getRect(search);
        expect(before.width, closeTo(260, .1));
        final status = find.byKey(const ValueKey('mail-desktop-status'));
        final statusBefore = tester.getRect(status);
        expect(
          before.left,
          closeTo(statusBefore.right + 1, .1),
          reason: 'Search must start at the reading-pane divider',
        );
        await tester.enterText(search, 'hello');
        await tester.pumpAndSettle();
        final after = tester.getRect(search);
        expect(tester.getRect(status), statusBefore);
        expect(after, before, reason: 'Opening scopes must not resize search');
        final scope = tester.getRect(
          find.byKey(const ValueKey('mail-desktop-search-scopes')),
        );
        expect(scope.left, closeTo(after.left, .1));
        expect(scope.right, closeTo(after.right, .1));
        expect(scope.top, closeTo(after.bottom + 4, .1));
        // Wide Ahem glyphs may wrap each English option; each row still has
        // one 44px target, with only the existing 8px inter-row gap.
        expect(
          scope.height,
          lessThanOrEqualTo(locale.languageCode == 'en' ? 3 * 44 + 2 * 8 : 44),
        );
        final l10n = tester.element(search).l10n;
        final labels = ['仅主题', '按发件人', '按收件人'].map(l10n.text).toList();
        final rects = labels
            .map((label) => tester.getRect(find.text(label)))
            .toList();
        for (final rect in rects) {
          expect(rect.left, greaterThanOrEqualTo(scope.left));
          expect(rect.right, lessThanOrEqualTo(scope.right));
        }
        if (scopePreviews) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('mail-scope-preview')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final directory = Directory('build/mail-scope-previews');
            await directory.create(recursive: true);
            await File(
              '${directory.path}/$width-$dark.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.text(labels[1]));
        await tester.pumpAndSettle();
        expect(find.text(l10n.text('发件人邮箱：')), findsOneWidget);
        final expanded = tester.getRect(
          find.byKey(const ValueKey('mail-desktop-search-scopes')),
        );
        expect(expanded.left, closeTo(after.left, .1));
        expect(expanded.right, closeTo(after.right, .1));
        expect(tester.getRect(status), statusBefore);
        await tester.tap(find.text(labels[1]));
        await tester.pumpAndSettle();
        expect(find.text(l10n.text('发件人邮箱：')), findsNothing);
        await tester.tap(find.text(labels[2]));
        await tester.pumpAndSettle();
        expect(find.text(l10n.text('收件人邮箱：')), findsOneWidget);
        expect(tester.getRect(status), statusBefore);
        await tester.tap(find.text(labels[2]));
        await tester.pumpAndSettle();
        await tester.enterText(search, '');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('mail-desktop-search-scopes')),
          findsNothing,
        );
        expect(tester.getRect(status), statusBefore);
        expect(tester.takeException(), isNull);
        await tester.enterText(search, 'resize');
        await tester.pumpAndSettle();
        for (final resizedWidth in [1000.0, 1440.0, 900.0]) {
          tester.view.physicalSize = Size(resizedWidth, 900);
          await tester.pumpAndSettle();
          final resizedSearch = tester.getRect(search);
          final resizedScope = tester.getRect(
            find.byKey(const ValueKey('mail-desktop-search-scopes')),
          );
          expect(resizedSearch.width, closeTo(260, .1));
          expect(
            resizedSearch.left,
            closeTo(tester.getRect(status).right + 1, .1),
          );
          expect(resizedScope.left, closeTo(resizedSearch.left, .1));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        if (scopePreviews) debugDisableShadows = true;
      });
    }

    testWidgets('scope chips hidden when search bar is empty', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('仅主题'), findsNothing);
      expect(find.text('按发件人'), findsNothing);
      expect(find.text('按收件人'), findsNothing);
    });

    testWidgets('scope chips appear when search bar has text', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      // Find the search TextField (first one in the widget tree)
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.key == const ValueKey('mail-search-control'),
        ),
        'hello',
      );
      await tester.pump();

      expect(find.text('仅主题'), findsOneWidget);
      expect(find.text('按发件人'), findsOneWidget);
      expect(find.text('按收件人'), findsOneWidget);
    });

    testWidgets('default scope uses allText (no secondary input visible)', (
      tester,
    ) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.key == const ValueKey('mail-search-control'),
        ),
        'hello',
      );
      await tester.pump();

      // No secondary "发件人邮箱：" or "收件人邮箱：" input should appear
      expect(find.text('发件人邮箱：'), findsNothing);
      expect(find.text('收件人邮箱：'), findsNothing);
    });

    testWidgets('按发件人 chip shows secondary sender input field', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      // Open search
      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.key == const ValueKey('mail-search-control'),
        ),
        'hello',
      );
      await tester.pump();

      // Tap 按发件人
      await tester.tap(find.text('按发件人'));
      await tester.pump();

      // Secondary sender input should appear
      expect(
        find.text('发件人邮箱：'),
        findsOneWidget,
        reason: '按发件人 chip must show a secondary sender input',
      );
      expect(find.text('收件人邮箱：'), findsNothing);
    });

    testWidgets('按收件人 chip shows secondary recipient input field', (
      tester,
    ) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.key == const ValueKey('mail-search-control'),
        ),
        'hello',
      );
      await tester.pump();

      await tester.tap(find.text('按收件人'));
      await tester.pump();

      expect(
        find.text('收件人邮箱：'),
        findsOneWidget,
        reason: '按收件人 chip must show a secondary recipient input',
      );
      expect(find.text('发件人邮箱：'), findsNothing);
    });

    testWidgets(
      '按发件人 chip stays visible even when main search bar is cleared',
      (tester) async {
        final svc = _MockMailService();
        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
            ),
          ),
        );
        await tester.pump();

        final searchField = find.byWidgetPredicate(
          (w) =>
              w is TextField && w.key == const ValueKey('mail-search-control'),
        );

        await tester.enterText(searchField, 'hello');
        await tester.pump();
        await tester.tap(find.text('按发件人'));
        await tester.pump();

        // Clear the main search bar
        await tester.enterText(searchField, '');
        await tester.pump();

        // Scope chips and sender input should still be visible
        expect(
          find.text('发件人邮箱：'),
          findsOneWidget,
          reason: 'Sender input must remain visible when 按发件人 is active',
        );
      },
    );

    testWidgets('default search triggers with allText scope', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      await tester.enterText(
        find.byWidgetPredicate(
          (w) =>
              w is TextField && w.key == const ValueKey('mail-search-control'),
        ),
        'hello',
      );
      // Advance past debounce
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(
        svc.lastSearchScope,
        equals(MailSearchScope.allText),
        reason: 'Default search must use allText scope',
      );
      expect(svc.lastSearchQuery, equals('hello'));
    });

    testWidgets('仅主题 chip triggers subject-scoped search', (tester) async {
      final svc = _MockMailService();
      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.key == const ValueKey('mail-search-control'),
      );
      await tester.enterText(searchField, 'test query');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Now tap 仅主题
      await tester.tap(find.text('仅主题'));
      await tester.pumpAndSettle();

      expect(
        svc.lastSearchScope,
        equals(MailSearchScope.subject),
        reason: '仅主题 chip must switch scope to subject',
      );
    });
  });

  // ── Test 5: Trash restore ──────────────────────────────────────────────────

  group('Trash restore', () {
    testWidgets(
      'trash selection exposes permanent delete and original-folder recovery through Move',
      (tester) async {
        final trashMsg = _makeSummary(uid: 10, subject: 'Deleted email');
        final svc = _MockMailService(trash: [trashMsg]);

        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
            ),
          ),
        );
        await tester.pump(); // initial inbox load

        // Switch to trash folder
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('已删除'));
        await tester.pumpAndSettle();
        await tester.pump(); // fetchFolder(trash) completes

        // Long-press to enter multi-select (auto-selects uid=10)
        await tester.longPress(find.text('Deleted email'));
        await tester.pump();

        expect(find.text('删除'), findsOneWidget);
        expect(find.text('移动'), findsOneWidget);
        await tester.tap(find.text('移动'));
        await tester.pumpAndSettle();
        expect(find.text('恢复到原文件夹'), findsOneWidget);
      },
    );

    testWidgets('tapping 恢复 calls restoreMessages with selected UIDs', (
      tester,
    ) async {
      final trashMsg = _makeSummary(uid: 10, subject: 'Deleted email');
      final svc = _MockMailService(trash: [trashMsg]);

      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump();

      // Switch to trash
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('已删除'));
      await tester.pumpAndSettle();
      await tester.pump();

      // Long-press to enter multi-select (selects uid=10)
      await tester.longPress(find.text('Deleted email'));
      await tester.pump();

      await tester.tap(find.text('移动'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复到原文件夹'));
      await tester.pumpAndSettle();

      // Confirmation dialog should appear
      expect(find.byType(AlertDialog), findsOneWidget);

      // Tap the dialog's 恢复 confirm button
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('恢复'),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        svc.restoredUids,
        contains(10),
        reason: 'restoreMessages should have been called with uid=10',
      );
    });
  });

  // ── Test 6: Reply HTML format ──────────────────────────────────────────────

  group('Reply HTML format', () {
    testWidgets('ComposeMailPage in reply mode shows quoted original section', (
      tester,
    ) async {
      final svc = _MockMailService();
      final creds = _creds();

      const replyTo = MailMessageDetail(
        uid: 5,
        subject: 'Original Subject',
        sender: 'original@example.com',
        recipients: 'testuser@mail.bnbu.edu.cn',
        cc: null,
        date: null,
        body: 'Original message body text',
        htmlBody: null,
        isSeen: true,
      );

      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: svc,
            credentials: creds,
            replyTo: replyTo,
          ),
        ),
      );
      await tester.pump();

      // The quoted section must show the original body text — this cannot come
      // from the To/Subject pre-fill so it only appears if the quoted block exists.
      expect(
        find.textContaining('Original message body text'),
        findsOneWidget,
        reason:
            'Reply compose should show original body text in quoted section',
      );
    });

    testWidgets('sendEmail called with htmlBody when replying', (tester) async {
      final svc = _MockMailService();
      final creds = _creds();

      const replyTo = MailMessageDetail(
        uid: 5,
        subject: 'Original Subject',
        sender: 'original@example.com',
        recipients: 'testuser@mail.bnbu.edu.cn',
        cc: null,
        date: null,
        body: 'Original body',
        htmlBody: null,
        isSeen: true,
      );

      await tester.pumpWidget(
        _wrapInApp(
          ComposeMailPage(
            mailService: svc,
            credentials: creds,
            replyTo: replyTo,
          ),
        ),
      );
      await tester.pump();

      // Type reply text in the body field
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.key == const ValueKey('compose-body'),
        ),
        'My reply text',
      );

      // Tap send
      await tester.tap(find.text('发送'));
      await tester.pump(); // start async op
      await tester.pump(); // complete async op (mock is instant)

      expect(
        svc.sentData?.htmlBody,
        isNotNull,
        reason: 'Reply email should include htmlBody',
      );
      expect(
        svc.sentData?.htmlBody,
        contains('original@example.com'),
        reason: 'HTML body should include original sender info',
      );
    });
  });

  // ── Test 7: Pagination ─────────────────────────────────────────────────────

  group('Pagination', () {
    testWidgets('load more calls fetchFolder with incremented page', (
      tester,
    ) async {
      // 3 inbox messages but fakeTotal=50 → hasMore is true after page 1
      final msgs = List.generate(
        3,
        (i) => _makeSummary(uid: i + 1, subject: 'Message ${i + 1}'),
      );
      final svc = _MockMailService(inbox: msgs, fakeTotal: 50);

      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump(); // initial load page 1

      final initialCallCount = svc.fetchFolderCallCount;

      // "加载更多" button should be visible (hasMore = 1*25 < 50 = true)
      expect(
        find.text('加载更多'),
        findsOneWidget,
        reason: '"加载更多" should appear when hasMore is true',
      );

      // Tap load more
      await tester.tap(find.text('加载更多'));
      await tester.pump(); // start async
      await tester.pump(); // complete

      expect(
        svc.lastFetchedPage,
        equals(2),
        reason: 'Load more should request page 2, not page 1 again',
      );
      expect(
        svc.fetchFolderCallCount,
        greaterThan(initialCallCount),
        reason: 'fetchFolder should have been called for page 2',
      );
    });
  });

  // ── Test 8: Mail attachment display ───────────────────────────────────────

  group('Mail attachment display', () {
    testWidgets('UI shows attachment section with filename and 附件 label', (
      tester,
    ) async {
      final msg = _makeSummary(uid: 1, subject: 'Has Attachment');
      final svc = _MockMailService(inbox: [msg]);
      svc.readMessageOverride = (uid) => const MailMessageDetail(
        uid: 1,
        subject: 'Has Attachment',
        sender: 'sender@example.com',
        recipients: 'testuser@mail.bnbu.edu.cn',
        cc: null,
        date: null,
        body: 'Body text',
        htmlBody: null,
        isSeen: true,
        attachments: [
          MailAttachment(
            name: 'report.pdf',
            size: 0,
            mimeType: 'application/pdf',
            partId: '2',
          ),
        ],
        mailboxUidValidity: 100,
      );

      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
          ),
        ),
      );
      await tester.pump(); // initial load

      // Tap the message to open detail
      await tester.tap(find.text('Has Attachment'));
      await tester.pumpAndSettle();

      // Attachment section should be visible
      expect(
        find.text('report.pdf'),
        findsOneWidget,
        reason: 'Detail page should show attachment filename',
      );
    });

    testWidgets('tapping attachment chip calls downloadAttachment', (
      tester,
    ) async {
      const cacheDirectoryPath = '/mail-cache/download';
      final attachmentStore = _FakeMailAttachmentStore();
      final msg = _makeSummary(uid: 2, subject: 'Attachment Email');
      final svc = _MockMailService(inbox: [msg]);
      svc.readMessageOverride = (uid) => const MailMessageDetail(
        uid: 2,
        subject: 'Attachment Email',
        sender: 'sender@example.com',
        recipients: 'testuser@mail.bnbu.edu.cn',
        cc: null,
        date: null,
        body: 'Body text',
        htmlBody: null,
        isSeen: true,
        attachments: [
          MailAttachment(
            name: 'document.pdf',
            size: 0,
            mimeType: 'application/pdf',
            partId: '2',
          ),
        ],
        mailboxUidValidity: 100,
      );

      // Mock the native_actions channel
      final openedPaths = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('ispace/native_actions'),
            (call) async {
              if (call.method == 'getMailAttachmentCacheDir') {
                return cacheDirectoryPath;
              }
              if (call.method == 'openFile') {
                openedPaths.add((call.arguments as Map)['path'] as String);
              }
              return null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('ispace/native_actions'),
              null,
            ),
      );

      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
            attachmentStore: attachmentStore,
          ),
        ),
      );
      await tester.pump(); // initial load

      // Tap the message to open detail
      await tester.tap(find.text('Attachment Email'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('document.pdf'));
      await tester.pumpAndSettle();

      expect(
        svc.downloadedPartIds,
        contains('2'),
        reason: 'downloadAttachment should have been called with partId=2',
      );
      expect(openedPaths, isEmpty);
      expect(find.byType(FilePreviewPage), findsOneWidget);
      final preview = tester.widget<FilePreviewPage>(
        find.byType(FilePreviewPage),
      );
      expect(attachmentStore.files, contains(preview.path));
    });

    testWidgets(
      'attachment preview returns to mail and reuses downloaded cache',
      (tester) async {
        final attachmentStore = _FakeMailAttachmentStore();
        final svc = _MockMailService(
          inbox: [_makeSummary(uid: 2, subject: 'Open failure')],
        );
        svc.readMessageOverride = (_) => const MailMessageDetail(
          uid: 2,
          subject: 'Open failure',
          sender: 'sender@example.com',
          recipients: 'testuser@mail.bnbu.edu.cn',
          cc: null,
          date: null,
          body: 'Body text',
          htmlBody: null,
          isSeen: true,
          mailboxUidValidity: 100,
          attachments: [
            MailAttachment(
              name: 'document.pdf',
              size: 3,
              mimeType: 'application/pdf',
              partId: '2',
            ),
          ],
        );
        var openAttempts = 0;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel('ispace/native_actions');
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getMailAttachmentCacheDir') {
            return '/mail-cache/retry';
          }
          if (call.method == 'openFile') {
            openAttempts++;
            if (openAttempts == 1) {
              throw PlatformException(
                code: 'no_presenter',
                message: 'No view controller available to open the file',
              );
            }
          }
          return null;
        });
        addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
        await tester.pumpWidget(
          _wrapInApp(
            MailPage.withService(
              controller: null,
              mailService: svc,
              testCredentials: _creds(),
              attachmentStore: attachmentStore,
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.text('Open failure'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('document.pdf'));
        await tester.pumpAndSettle();
        expect(find.byType(FilePreviewPage), findsOneWidget);
        expect(find.textContaining('PlatformException'), findsNothing);
        expect(find.textContaining('下载失败'), findsNothing);
        expect(attachmentStore.files, hasLength(1));
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('document.pdf'));
        await tester.pumpAndSettle();
        expect(openAttempts, 0);
        expect(svc.downloadedPartIds, ['2']);
      },
    );

    testWidgets('cached attachment opens without another mail download', (
      tester,
    ) async {
      const cacheDirectoryPath = '/mail-cache/cached';
      final attachmentStore = _FakeMailAttachmentStore();
      final msg = _makeSummary(uid: 3, subject: 'Cached Attachment');
      final svc = _MockMailService(inbox: [msg]);
      const detail = MailMessageDetail(
        uid: 3,
        subject: 'Cached Attachment',
        sender: 'sender@example.com',
        recipients: 'testuser@mail.bnbu.edu.cn',
        cc: null,
        date: null,
        body: 'Body text',
        htmlBody: null,
        isSeen: true,
        messageId: '<cached@example.com>',
        mailboxUidValidity: 100,
        attachments: [
          MailAttachment(
            name: 'cached.pdf',
            size: 3,
            mimeType: 'application/pdf',
            partId: '2.1',
          ),
        ],
      );
      svc.readMessageOverride = (_) => detail;
      final cacheFileName = mailAttachmentCacheFileName(
        accountId: _creds().emailAddress,
        mailbox: MailFolder.inbox.name,
        messageId: detail.messageId,
        mailboxUidValidity: detail.mailboxUidValidity,
        messageUid: detail.uid,
        partId: '2.1',
        originalName: 'cached.pdf',
      );
      final cacheFilePath = '$cacheDirectoryPath/$cacheFileName';
      attachmentStore.files.add(cacheFilePath);
      final openedPaths = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('ispace/native_actions'),
            (call) async {
              if (call.method == 'getMailAttachmentCacheDir') {
                return cacheDirectoryPath;
              }
              if (call.method == 'openFile') {
                openedPaths.add((call.arguments as Map)['path'] as String);
              }
              return null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('ispace/native_actions'),
              null,
            ),
      );

      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
            attachmentStore: attachmentStore,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Cached Attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('cached.pdf'));
      await tester.pumpAndSettle();

      expect(svc.downloadedPartIds, isEmpty);
      expect(openedPaths, isEmpty);
      expect(
        tester.widget<FilePreviewPage>(find.byType(FilePreviewPage)).path,
        cacheFilePath,
      );
    });

    testWidgets('attachment completion does not open over compose page', (
      tester,
    ) async {
      const cacheDirectoryPath = '/mail-cache/route';
      final attachmentStore = _FakeMailAttachmentStore();
      final msg = _makeSummary(uid: 4, subject: 'Delayed Attachment');
      final svc = _DelayedAttachmentMailService(inbox: [msg]);
      const detail = MailMessageDetail(
        uid: 4,
        subject: 'Delayed Attachment',
        sender: 'sender@example.com',
        recipients: 'testuser@mail.bnbu.edu.cn',
        cc: null,
        date: null,
        body: 'Body text',
        htmlBody: null,
        isSeen: true,
        mailboxUidValidity: 100,
        attachments: [
          MailAttachment(
            name: 'delayed.pdf',
            size: 3,
            mimeType: 'application/pdf',
            partId: '2.1',
          ),
        ],
      );
      svc.readMessageOverride = (_) => detail;
      final openedPaths = <String>[];
      final cacheFileName = mailAttachmentCacheFileName(
        accountId: _creds().emailAddress,
        mailbox: MailFolder.inbox.name,
        messageId: detail.messageId,
        mailboxUidValidity: detail.mailboxUidValidity,
        messageUid: detail.uid,
        partId: '2.1',
        originalName: 'delayed.pdf',
      );
      final cachedFilePath = '$cacheDirectoryPath/$cacheFileName';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('ispace/native_actions'),
            (call) async {
              if (call.method == 'getMailAttachmentCacheDir') {
                return cacheDirectoryPath;
              }
              if (call.method == 'openFile') {
                openedPaths.add((call.arguments as Map)['path'] as String);
              }
              return null;
            },
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('ispace/native_actions'),
              null,
            ),
      );

      await tester.pumpWidget(
        _wrapInApp(
          MailPage.withService(
            controller: null,
            mailService: svc,
            testCredentials: _creds(),
            attachmentStore: attachmentStore,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Delayed Attachment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('delayed.pdf'));
      await tester.pump();
      await tester.pump();
      expect(svc.downloadedPartIds, ['2.1']);

      await tester.tap(find.byTooltip('回复'));
      await tester.pumpAndSettle();
      svc.completeDownload([1, 2, 3]);
      await tester.pumpAndSettle();

      expect(find.text('回复邮件'), findsOneWidget);
      expect(attachmentStore.files, contains(cachedFilePath));
      expect(openedPaths, isEmpty);
    });
  });

  group('Mail detail assistant handoff', () {
    testWidgets('小U creates a fresh mail-reference handoff', (tester) async {
      final coordinator = AssistantContextCoordinator();
      var openCount = 0;
      AssistantMailReference? reference;
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AssistantContextScope(
            coordinator: coordinator,
            openAssistantWithMailReference: (value) async {
              openCount++;
              reference = value;
            },
            child: MailDetailPage(
              detail: const MailMessageDetail(
                uid: 41,
                subject: 'Printing quota',
                sender: 'ITSC Support <support@external.example>',
                recipients: 'student@mail.bnbu.edu.cn',
                cc: null,
                date: null,
                body: 'The quota will be reset next month.',
                htmlBody: null,
                isSeen: true,
                folder: MailFolder.inbox,
                mailboxUidValidity: 812,
              ),
              timeFormat: DateFormat('yyyy-MM-dd HH:mm'),
              onReply: () {},
              mailService: _MockMailService(),
              credentials: _creds(),
              attachmentStore: _FakeMailAttachmentStore(),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('小U'));
      await tester.pumpAndSettle();
      expect(find.text('询问小U'), findsOneWidget);
      expect(find.text('智能翻译'), findsOneWidget);
      await tester.tap(find.text('询问小U'));
      await tester.pumpAndSettle();

      expect(openCount, 1);
      expect(reference?.kind, AssistantMailReferenceKind.message);
      expect(reference?.uid, 41);
      expect(reference?.mailboxUidValidity, 812);
      expect(reference?.subject, 'Printing quota');
    });

    testWidgets('detail load error stays in page and retry resolves it', (
      tester,
    ) async {
      var attempts = 0;
      await tester.pumpWidget(
        _wrapInApp(
          MailDetailPage.loading(
            summary: _makeSummary(uid: 52, subject: 'Retry this mail'),
            loadDetail: () async {
              attempts++;
              if (attempts == 1) {
                throw const MailServiceException('Temporary IMAP failure');
              }
              return const MailMessageDetail(
                uid: 52,
                subject: 'Retry this mail',
                sender: 'sender@example.com',
                recipients: 'student@mail.bnbu.edu.cn',
                cc: null,
                date: null,
                body: 'Recovered mail body',
                htmlBody: null,
                isSeen: true,
                folder: MailFolder.inbox,
                mailboxUidValidity: 100,
              );
            },
            timeFormat: DateFormat('yyyy-MM-dd HH:mm'),
            mailService: _MockMailService(),
            credentials: _creds(),
            attachmentStore: _FakeMailAttachmentStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('邮件暂时无法读取'), findsOneWidget);
      expect(find.textContaining('Temporary IMAP failure'), findsOneWidget);
      expect(find.byType(MailDetailPage), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();

      expect(attempts, 2);
      expect(find.text('Recovered mail body'), findsOneWidget);
    });
  });
}
