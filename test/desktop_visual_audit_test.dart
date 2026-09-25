import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/pages/ispace_page.dart';
import 'package:bnbu_me/pages/mail_page.dart';
import 'package:bnbu_me/pages/schedule_page.dart';
import 'package:bnbu_me/pages/user_page.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/services/campus_directory_service.dart';
import 'package:bnbu_me/services/mail_recipient_directory.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_creation_form.dart';
import 'package:bnbu_me/widgets/mail_sender_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpDesktopPage(
    WidgetTester tester, {
    required Widget page,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: page,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  testWidgets('mail desktop visual audit', (tester) async {
    final controller = AppSessionController();
    addTearDown(controller.dispose);

    await pumpDesktopPage(
      tester,
      page: MailPage.withService(
        controller: controller,
        mailService: _VisualAuditMailService(),
        testCredentials: const MailAccessCredentials(
          userId: 'student01',
          emailAddress: 'student01@mail.bnbu.edu.cn',
          password: 'visual-audit-only',
        ),
      ),
    );

    expect(find.byType(MailPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mail-desktop-subject-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compose desktop workspace searches official recipients', (
    tester,
  ) async {
    final recipientDirectory = MailRecipientDirectory(
      directoryService: _VisualAuditDirectoryService(),
    );
    addTearDown(recipientDirectory.dispose);
    await pumpDesktopPage(
      tester,
      page: ComposeMailPage(
        mailService: _VisualAuditMailService(),
        credentials: const MailAccessCredentials(
          userId: 'student01',
          emailAddress: 'student01@mail.bnbu.edu.cn',
          password: 'visual-audit-only',
        ),
        recipientDirectory: recipientDirectory,
      ),
    );

    expect(
      find.byKey(const ValueKey('compose-desktop-workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('compose-preview')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-save-draft')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compose-editor-toolbar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compose-desktop-attachment')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compose-toolbar-insert')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('compose-desktop-editor')))
          .width,
      greaterThan(1100),
    );

    await tester.enterText(
      find.byKey(const ValueKey('compose-recipient-field')),
      '图书',
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump();
    expect(find.text('图书馆'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compose-recipient-options-surface')),
      findsOneWidget,
    );
    final optionsSurface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('compose-recipient-options-surface')),
    );
    expect((optionsSurface.decoration as BoxDecoration).boxShadow, isNotEmpty);
    expect(find.byType(MailSenderAvatar), findsWidgets);
    await tester.tap(find.text('图书馆'));
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is InputChip && widget.tooltip == 'library@bnbu.edu.cn',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('compose toolbar exposes rich-document commands', (tester) async {
    await pumpDesktopPage(
      tester,
      page: ComposeMailPage(
        mailService: _VisualAuditMailService(),
        credentials: const MailAccessCredentials(
          userId: 'student01',
          emailAddress: 'student01@mail.bnbu.edu.cn',
          password: 'visual-audit-only',
        ),
        recipientDirectory: MailRecipientDirectory(
          directoryService: _VisualAuditDirectoryService(),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('compose-rich-mail-editor')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('compose-toolbar-bold')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-toolbar-more')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compose-toolbar-insert')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('compose-toolbar-more')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-toolbar-emoji')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compose desktop uses the reference command hierarchy and popup surfaces',
    (tester) async {
      await pumpDesktopPage(
        tester,
        page: ComposeMailPage(
          mailService: _VisualAuditMailService(),
          credentials: const MailAccessCredentials(
            userId: 'student01',
            emailAddress: 'student01@mail.bnbu.edu.cn',
            password: 'visual-audit-only',
          ),
          recipientDirectory: MailRecipientDirectory(
            directoryService: _VisualAuditDirectoryService(),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('compose-send')), findsOneWidget);
      final send = tester.widget<BnbuCreationAction>(
        find.byKey(const ValueKey('compose-send')),
      );
      expect(send.label, '发送');
      expect(
        tester.getSize(find.byKey(const ValueKey('compose-send'))).height,
        greaterThanOrEqualTo(44),
      );
      expect(find.byKey(const ValueKey('compose-save-draft')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('compose-desktop-attachment')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compose-toolbar-clear-format')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compose-toolbar-font-size')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compose-toolbar-color')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('compose-toolbar-font-size')),
          matching: find.text('11'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compose-toolbar-signature')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('compose-toolbar-attachment')),
        findsNothing,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('compose-editor-toolbar')))
            .height,
        38,
      );

      await tester.tap(find.byKey(const ValueKey('compose-toolbar-font')));
      // Finish the popup route transition before focusing the collapsed
      // search; its hit-test position is still animated on the first frame.
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('compose-font-search')), findsOneWidget);
      expect(find.text('Helvetica Neue'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('compose-font-search')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('compose-font-search')),
        '楷',
      );
      await tester.pump();
      expect(find.text('楷体'), findsOneWidget);
      expect(find.text('Helvetica Neue'), findsNothing);
      await tester.tap(find.text('楷体'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('compose-toolbar-font-size')));
      await tester.pump();
      final sizeItems = tester
          .widgetList<PopupMenuItem<int>>(
            find.byWidgetPredicate((widget) => widget is PopupMenuItem<int>),
          )
          .map((item) => item.value)
          .whereType<int>()
          .toList();
      expect(sizeItems, <int>[8, 9, 10, 11, 12, 14, 16, 18, 20, 24]);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('compose-toolbar-color')));
      await tester.pump();
      expect(find.byKey(const ValueKey('compose-color-hex')), findsOneWidget);
      expect(find.text('文字高亮'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('compose-toolbar-more')));
      await tester.pump();
      expect(find.byTooltip('删除线'), findsWidgets);
      expect(find.byKey(const ValueKey('compose-more-table')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compose desktop uses compact controls and one field grid', (
    tester,
  ) async {
    final recipientDirectory = MailRecipientDirectory(
      directoryService: _VisualAuditDirectoryService(),
    );
    addTearDown(recipientDirectory.dispose);
    await pumpDesktopPage(
      tester,
      page: ComposeMailPage(
        mailService: _VisualAuditMailService(),
        credentials: const MailAccessCredentials(
          userId: 'student01',
          emailAddress: 'student01@mail.bnbu.edu.cn',
          password: 'visual-audit-only',
        ),
        recipientDirectory: recipientDirectory,
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('compose-preview'))).height,
      48,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('compose-editor-toolbar')))
          .height,
      38,
    );

    final recipientLabelRect = tester.getRect(find.text('收件人：'));
    final subjectLabelRect = tester.getRect(find.text('主题：'));
    final recipientFieldRect = tester.getRect(
      find.byKey(const ValueKey('compose-recipient-field')),
    );
    final subjectFieldRect = tester.getRect(
      find.byKey(const ValueKey('compose-subject-field')),
    );
    expect(subjectLabelRect.left, recipientLabelRect.left);
    expect(subjectFieldRect.left, recipientFieldRect.left);
    expect(
      (recipientLabelRect.center.dy - recipientFieldRect.center.dy).abs(),
      lessThan(1),
    );
    expect(
      (subjectLabelRect.center.dy - subjectFieldRect.center.dy).abs(),
      lessThan(1),
    );

    await tester.tap(find.byKey(const ValueKey('compose-toggle-cc-bcc')));
    await tester.pump();
    for (final label in <String>['抄送：', '密送：']) {
      expect(tester.getRect(find.text(label)).left, recipientLabelRect.left);
    }
    for (final key in <String>['compose-cc-field', 'compose-bcc-field']) {
      expect(
        tester.getRect(find.byKey(ValueKey(key))).left,
        recipientFieldRect.left,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('compose adapts at compact, medium and expanded widths', (
    tester,
  ) async {
    final recipientDirectory = MailRecipientDirectory(
      directoryService: _VisualAuditDirectoryService(),
    );
    addTearDown(recipientDirectory.dispose);
    for (final width in <double>[390, 768, 880, 1024, 1440]) {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: ComposeMailPage(
              mailService: _VisualAuditMailService(),
              credentials: const MailAccessCredentials(
                userId: 'student01',
                emailAddress: 'student01@mail.bnbu.edu.cn',
                password: 'visual-audit-only',
              ),
              recipientDirectory: recipientDirectory,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('compose-desktop-workspace')),
        findsNothing,
      );
      expect(tester.takeException(), isNull, reason: 'width=$width');
    }
  });

  testWidgets('compose desktop keeps controls legible in dark mode', (
    tester,
  ) async {
    final recipientDirectory = MailRecipientDirectory(
      directoryService: _VisualAuditDirectoryService(),
    );
    addTearDown(recipientDirectory.dispose);
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        home: ComposeMailPage(
          mailService: _VisualAuditMailService(),
          credentials: const MailAccessCredentials(
            userId: 'student01',
            emailAddress: 'student01@mail.bnbu.edu.cn',
            password: 'visual-audit-only',
          ),
          recipientDirectory: recipientDirectory,
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('compose-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iSpace desktop visual audit', (tester) async {
    final controller = _VisualAuditIspaceController();
    addTearDown(controller.dispose);

    await pumpDesktopPage(
      tester,
      page: IspacePage(controller: controller, onGoToUserTab: () {}),
    );

    expect(
      find.byKey(const ValueKey('ispace-desktop-navigation-pane')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('ispace-desktop-top-bar')))
          .height,
      48,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule desktop visual audit', (tester) async {
    final controller = AppSessionController();
    final taCourseController = TaCourseController(
      sessionController: controller,
    );
    addTearDown(controller.dispose);
    addTearDown(taCourseController.dispose);

    await pumpDesktopPage(
      tester,
      page: SchedulePage(
        controller: controller,
        taCourseController: taCourseController,
      ),
    );

    expect(find.byType(SchedulePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('user desktop visual audit', (tester) async {
    final controller = AppSessionController();
    final themeModeController = AppThemeModeController();
    addTearDown(controller.dispose);
    addTearDown(themeModeController.dispose);

    await pumpDesktopPage(
      tester,
      page: UserPage(
        controller: controller,
        themeModeController: themeModeController,
      ),
    );

    expect(find.byType(UserPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-desktop-split-layout')),
      findsOneWidget,
    );
    expect(find.text('我的'), findsNothing);
    expect(find.byKey(const ValueKey('user-profile-major')), findsOneWidget);
    expect(find.byKey(const ValueKey('user-profile-email')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-desktop-avatar-stage')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('user-desktop-background-overlay')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('student-avatar-vector-fallback')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

class _VisualAuditIspaceController extends AppSessionController {
  @override
  bool get isLoggedIn => true;
}

class _VisualAuditMailService extends MailService {
  static final _messages = <MailMessageSummary>[
    MailMessageSummary(
      uid: 1,
      subject: '课程项目里程碑确认',
      sender: '张老师 <teacher@bnbu.edu.cn>',
      preview: '请在本周五前确认项目选题，并在 iSpace 提交阶段成果。',
      hasHtmlBody: false,
      date: DateTime(2026, 7, 28, 10, 24),
      isSeen: false,
      hasAttachments: true,
      mailboxUidValidity: 101,
    ),
    MailMessageSummary(
      uid: 2,
      subject: '图书馆预约提醒',
      sender: 'BNBU Library <library@bnbu.edu.cn>',
      preview: '你预约的三楼研讨室将在今天 14:00 开始使用。',
      hasHtmlBody: true,
      date: DateTime(2026, 7, 28, 8, 40),
      isSeen: true,
      mailboxUidValidity: 101,
    ),
    MailMessageSummary(
      uid: 3,
      subject: '本周校园活动汇总',
      sender: '学生事务中心 <student-affairs@bnbu.edu.cn>',
      preview: '创新工作坊、电影放映和校队招新信息已更新。',
      hasHtmlBody: true,
      date: DateTime(2026, 7, 27, 17, 15),
      isSeen: true,
      mailboxUidValidity: 101,
    ),
  ];

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async {
    final messages = folder == MailFolder.inbox
        ? _messages
        : const <MailMessageSummary>[];
    return MailFolderSnapshot(
      emailAddress: credentials.emailAddress,
      incomingServer: 'imap.mail.bnbu.edu.cn',
      outgoingServer: 'smtp.mail.bnbu.edu.cn',
      messages: messages,
      fetchedAt: DateTime(2026, 7, 28, 10, 30),
      folder: folder,
      totalMessages: messages.length,
      currentPage: page,
      pageSize: pageSize,
      mailboxUidValidity: 101,
    );
  }

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) async {
    final summary = _messages.firstWhere((message) => message.uid == uid);
    return MailMessageDetail(
      uid: uid,
      subject: summary.subject,
      sender: summary.sender,
      recipients: credentials.emailAddress,
      cc: null,
      date: summary.date,
      body: summary.preview,
      htmlBody: null,
      isSeen: summary.isSeen,
      mailboxUidValidity: 101,
      folder: folder,
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
    return _messages
        .where((message) => message.subject.contains(query))
        .toList(growable: false);
  }

  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) async {}

  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  }) async => const [1, 2, 3];

  @override
  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  }) async {
    return const MailDraftIdentity(uid: 4, mailboxUidValidity: 101);
  }

  @override
  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async {}

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

class _VisualAuditDirectoryService implements CampusDirectoryService {
  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async {
    return const [
      CampusDirectoryOrganization(
        id: 'library',
        category: CampusDirectoryCategory.administration,
        nameCn: '图书馆',
        nameEn: 'Library',
        shortName: 'Library',
        websiteUrl: '',
        facultyUrl: '',
        teacherUnit: '',
        office: '',
        phones: [],
        emails: ['library@bnbu.edu.cn'],
        responsibilities: ['借阅服务'],
        contacts: [],
        embeddedStaff: [],
        sourceUrls: [],
      ),
    ];
  }

  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async {
    return OfficialTeacherPage(
      items: const [],
      total: 0,
      offset: offset,
      limit: limit,
      units: const [],
    );
  }

  @override
  void dispose() {}
}
