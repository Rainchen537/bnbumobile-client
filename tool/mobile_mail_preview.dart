import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/pages/mail_page.dart';
import 'package:bnbu_me/pages/root_shell_page.dart';
import 'package:bnbu_me/services/mail_radar_analyzer.dart';
import 'package:bnbu_me/services/mail_radar_store.dart';
import 'package:bnbu_me/services/mail_sender_avatar_service.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/services/mail_recipient_directory.dart';
import 'package:bnbu_me/services/mail_attachment_store.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/mail_radar_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';

/// Synthetic, offline fixtures shared by widget QA and the native WebView host.
/// This entry point never restores a real school login or sends mail.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final fixture = MailReferenceFixture();
  await fixture.initialize();
  runApp(
    MailReferencePreviewApp(
      fixture: fixture,
      light: const bool.fromEnvironment('MAIL_PREVIEW_LIGHT'),
      detail: const bool.fromEnvironment('MAIL_PREVIEW_DETAIL'),
      compose: const bool.fromEnvironment('MAIL_PREVIEW_COMPOSE'),
    ),
  );
}

class MailReferenceFixture {
  MailReferenceFixture({
    DateTime? now,
    ReferenceMailService? mailService,
    this.includeDeadlinePrecisionPair = false,
  }) : service = mailService ?? ReferenceMailService(now ?? DateTime.now());
  static const credentials = MailAccessCredentials(
    userId: 'mail-reference-fixture',
    emailAddress: 'preview@example.test',
    password: 'synthetic-only',
  );
  final ReferenceMailService service;
  final bool includeDeadlinePrecisionPair;
  final avatar = ReferenceMailAvatar();
  late final store = ReferenceRadarStore(
    service.messages
        .where((message) => message.folder == MailFolder.inbox)
        .map(
          (message) => _radarItem(
            message,
            includeDeadlinePrecisionPair: includeDeadlinePrecisionPair,
          ),
        )
        .toList(),
  );
  late final radar = MailRadarController(
    username: credentials.userId,
    credentials: credentials,
    mailService: service,
    analyzer: ReferenceRadarAnalyzer(),
    store: store,
  );
  Future<void> initialize() => radar.initialize();
  Widget page() => MailPage.withService(
    controller: null,
    mailService: service,
    testCredentials: credentials,
    senderAvatarService: avatar,
    radarController: radar,
    radarPollInterval: Duration.zero,
  );
  MailDetailPage detailPage() => MailDetailPage(
    attachmentStore: const IoMailAttachmentStore(),
    detail: service.detail(2, MailFolder.inbox),
    timeFormat: DateFormat('yyyy年M月d日 HH:mm'),
    onReply: () {},
    mailService: service,
    credentials: credentials,
    senderAvatarService: avatar,
  );
  Widget composePage() => ComposeMailPage(
    senderDisplayName: '演示同学',
    mailService: service,
    credentials: credentials,
    senderAvatarService: avatar,
    recipientDirectory: ReferenceRecipientDirectory(),
    autoSaveDrafts: false,
  );
  void dispose() {
    radar.dispose();
  }
}

class MailReferencePreviewApp extends StatefulWidget {
  const MailReferencePreviewApp({
    super.key,
    required this.fixture,
    this.light = false,
    this.detail = false,
    this.compose = false,
    this.locale = const Locale('zh', 'CN'),
    this.textScale = 1,
  });
  final MailReferenceFixture fixture;
  final bool light;
  final bool detail;
  final bool compose;
  final Locale locale;
  final double textScale;
  @override
  State<MailReferencePreviewApp> createState() =>
      _MailReferencePreviewAppState();
}

class _MailReferencePreviewAppState extends State<MailReferencePreviewApp> {
  final session = AppSessionController();
  final shell = RootShellController()..selectTab(AppTab.mail);
  final intent = MailAssistantIntentController();
  late final ta = TaCourseController(sessionController: session);
  @override
  void dispose() {
    ta.dispose();
    intent.dispose();
    shell.dispose();
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: widget.light ? ThemeMode.light : ThemeMode.dark,
    locale: widget.locale,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(widget.textScale)),
      child: child!,
    ),
    supportedLocales: BnbuLocalizations.supportedLocales,
    localizationsDelegates: const [
      BnbuLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: widget.compose
        ? widget.fixture.composePage()
        : widget.detail
        ? widget.fixture.detailPage()
        : RootShellPage(
            controller: session,
            shellController: shell,
            taCourseController: ta,
            mailIntentController: intent,
            pageOverrideBuilder: (tab) => tab == AppTab.mail
                ? widget.fixture.page()
                : const SizedBox.expand(),
          ),
  );
}

class ReferenceMailService extends MailService
    implements MailOrganizationService, MailFlagReader {
  ReferenceMailService(this.now) {
    final senders = [
      'Alex CHEN (via iSpace) <alex.chen@example.test>',
      'Student Services <student.services@example.test>',
      'BNBU PGCC <pgcc@bnbu.edu.cn>',
      'SAO-SLCDT <sao@bnbu.edu.cn>',
      'Career <career@bnbu.edu.cn>',
      'GitHub <updates@github.com>',
      'Library <library@bnbu.edu.cn>',
      'Registrar <ar@bnbu.edu.cn>',
    ];
    final subjects = [
      '[Data Structures and Algorithm Analysis] Course update',
      '【提醒】你于2026-09-06 00:00:00有一条校园通知 / You have a campus notice received on 2026-09-06 00:00:00',
      'BMS | 手作集—校园创作工作坊',
      '关于公共区域个人物品领取的通知',
      '【Job Opportunities】职业发展活动邀请',
      'Your weekly repository activity',
      '图书馆预约开放通知',
      '新学期课程注册提醒',
    ];
    for (final folder in MailFolder.values) {
      for (
        var index = 0;
        index <
            (folder == MailFolder.inbox
                ? 8
                : folder == MailFolder.sent
                ? 3
                : 0);
        index++
      ) {
        messages.add(
          MailMessageSummary(
            uid: index + 1,
            folder: folder,
            mailboxUidValidity: 101,
            sender: folder == MailFolder.sent
                ? credentialsAddress
                : senders[index],
            recipients: folder == MailFolder.sent
                ? senders[index]
                : credentialsAddress,
            subject: const bool.fromEnvironment('UI_PREVIEW_CAPTURE')
                ? const [
                    'Week 2 · 课程讲义与实验安排',
                    '校园讲座 · 设计与人工智能',
                    '手作集 · 校园创作工作坊报名',
                    '遗失物品领取通知',
                    '秋季实习宣讲会报名',
                    '本周项目动态',
                    '图书馆研讨室预约',
                    '新学期课程注册提醒',
                  ][index]
                : subjects[index],
            preview: index.isEven
                ? 'Dear students, please read the updated course information and prepare for the next session.'
                : '各位同学，你们好！请查看本周安排，按照通知中的时间完成相关事项。',
            previewLoaded: true,
            hasHtmlBody: index == 1,
            date: now.subtract(Duration(days: index < 2 ? 1 : index + 1)),
            isSeen: folder == MailFolder.sent || index == 1,
            isFlagged: index == 3,
            hasAttachments: index == 5,
            messageId: '<${folder.name}-${index + 1}@example.test>',
            references: folder == MailFolder.sent && index == 0
                ? '<inbox-1@example.test>'
                : '',
          ),
        );
      }
    }
  }
  static const credentialsAddress = 'Preview Student <preview@example.test>';
  final DateTime now;
  final List<MailMessageSummary> messages = [];
  final List<String> mutations = [];
  MailFolderSnapshot snapshot(
    MailAccessCredentials credentials,
    MailFolder folder,
    List<MailMessageSummary> filtered,
    int page,
    int pageSize,
  ) => MailFolderSnapshot(
    emailAddress: credentials.emailAddress,
    incomingServer: 'offline',
    outgoingServer: 'offline',
    folder: folder,
    fetchedAt: now,
    totalMessages: filtered.length,
    currentPage: page,
    pageSize: pageSize,
    mailboxUidValidity: 101,
    mailboxUnreadCount: messages
        .where((message) => message.folder == folder && !message.isSeen)
        .length,
    messages: filtered.skip((page - 1) * pageSize).take(pageSize).toList(),
  );
  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async => snapshot(
    credentials,
    folder,
    messages.where((message) => message.folder == folder).toList(),
    page,
    pageSize,
  );
  @override
  Future<MailFolderSnapshot> fetchFilteredFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async => snapshot(
    credentials,
    folder,
    messages
        .where(
          (message) =>
              message.folder == folder &&
              (!unreadOnly || !message.isSeen) &&
              (!flaggedOnly || message.isFlagged),
        )
        .toList(),
    page,
    pageSize,
  );
  @override
  Future<List<MailFolderInfo>> listFolders(
    MailAccessCredentials credentials,
  ) async => [
    for (final folder in MailFolder.values)
      MailFolderInfo(
        folder: folder,
        total: messages.where((message) => message.folder == folder).length,
        unread: messages
            .where((message) => message.folder == folder && !message.isSeen)
            .length,
      ),
  ];
  MailMessageDetail detail(int uid, MailFolder folder) {
    final message = messages.firstWhere(
      (message) => message.uid == uid && message.folder == folder,
    );
    return MailMessageDetail(
      uid: uid,
      folder: folder,
      mailboxUidValidity: 101,
      subject: message.subject,
      sender: message.sender,
      recipients: message.recipients,
      cc: null,
      date: message.date,
      isSeen: message.isSeen,
      messageId: message.messageId,
      body: const bool.fromEnvironment('UI_PREVIEW_CAPTURE') && uid == 2
          ? '同学，你好！\n\n校园讲座「设计与人工智能」将于9月15日14:30–16:00举行，欢迎各专业同学参加。\n\n地点：T29-203\n内容：设计方法、交互原型与人工智能协作实践。\n请于9月14日23:59前完成报名，并提前10分钟到场。'
          : '同学，你好！\n\n请查看以下校园服务安排。\n\n开放时间规定如下：\n周一至周日：06:00 - 24:00\n请按时完成相关事项。',
      htmlBody: const bool.fromEnvironment('UI_PREVIEW_CAPTURE') && uid == 2
          ? null
          : message.hasHtmlBody
          ? '''<!DOCTYPE html><html><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
<style>p { margin: 14px 0 18px; } .section { margin-top: 58px; } strong { font-weight: 700; }</style>
</head><body><p>同学，你好！</p>
<p>我们注意到，校园服务系统中有一条新的通知。请你查看相关时间与要求，并在规定时间内完成。</p>
<p class="section"><strong>开放时间规定如下：</strong></p>
<p>周一至周日：06:00 - 24:00</p><p>请按时完成相关事项。</p>
<p class="section"><strong>办理条件及流程：</strong></p>
<p>如果你有以下特殊情况，可提出申请：</p>
<p>1、身体不适（需要提供相关证明）</p><p>2、交通工具晚点（需要提供车票凭据）</p>
<p>3、课程原因（需要提供课程安排）</p></body></html>'''
          : null,
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
    if (markAsSeen) {
      await markMessagesSeen(
        credentials: credentials,
        folder: folder,
        uids: [uid],
        expectedMailboxUidValidity: 101,
      );
    }
    return detail(uid, folder);
  }

  void update(
    List<MailMessageIdentity> identities,
    MailMessageSummary Function(MailMessageSummary) change,
  ) {
    final keys = identities
        .map((id) => '${id.folder.name}:${id.mailboxUidValidity}:${id.uid}')
        .toSet();
    for (var index = 0; index < messages.length; index++) {
      if (keys.contains(messages[index].identityKey)) {
        messages[index] = change(messages[index]);
      }
    }
  }

  @override
  Future<Map<MailMessageIdentity, bool>> readSeenFlags({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
  }) async => {
    for (final identity in messages)
      if (this.messages.any((message) => message.identity == identity))
        identity: this.messages
            .firstWhere((message) => message.identity == identity)
            .isSeen,
  };

  @override
  Future<void> setMessagesSeen({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    required bool seen,
  }) async {
    mutations.add('seen:$seen');
    update(messages, (message) => message.copyWith(isSeen: seen));
  }

  @override
  Future<void> setMessagesFlagged({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    required bool flagged,
  }) async {
    mutations.add('flag:$flagged');
    update(messages, (message) => message.copyWith(isFlagged: flagged));
  }

  @override
  Future<void> markMessagesSeen({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) => setMessagesSeen(
    credentials: credentials,
    messages: [
      for (final uid in uids)
        MailMessageIdentity(
          folder: folder,
          uid: uid,
          mailboxUidValidity: expectedMailboxUidValidity ?? 101,
        ),
    ],
    seen: true,
  );
  @override
  Future<void> moveMessages({
    required MailAccessCredentials credentials,
    required List<MailMessageIdentity> messages,
    required MailFolder target,
  }) async {
    mutations.add('move:${target.name}');
    update(
      messages,
      (message) => message.copyWith(folder: target, uid: message.uid + 100),
    );
  }

  @override
  Future<void> deleteMessages({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async {
    mutations.add('delete:${folder.name}');
    if (folder == MailFolder.trash) {
      messages.removeWhere(
        (message) => message.folder == folder && uids.contains(message.uid),
      );
    } else {
      await moveMessages(
        credentials: credentials,
        messages: [
          for (final uid in uids)
            MailMessageIdentity(
              folder: folder,
              uid: uid,
              mailboxUidValidity: 101,
            ),
        ],
        target: MailFolder.trash,
      );
    }
  }

  @override
  Future<void> restoreMessages({
    required MailAccessCredentials credentials,
    required List<int> uids,
    required String userEmailAddress,
    int? expectedMailboxUidValidity,
  }) => moveMessages(
    credentials: credentials,
    messages: [
      for (final uid in uids)
        MailMessageIdentity(
          folder: MailFolder.trash,
          uid: uid,
          mailboxUidValidity: 101,
        ),
    ],
    target: MailFolder.inbox,
  );
  @override
  Future<List<MailMessageSummary>> loadPreviews({
    required MailAccessCredentials credentials,
    required List<MailMessageSummary> messages,
  }) async => messages;
  @override
  Future<List<MailMessageSummary>> searchFolder({
    required MailAccessCredentials credentials,
    required String query,
    MailFolder folder = MailFolder.inbox,
    MailSearchScope searchScope = MailSearchScope.allText,
  }) async => messages
      .where(
        (message) =>
            message.folder == folder &&
            '${message.subject} ${message.sender} ${message.preview}'
                .toLowerCase()
                .contains(query.toLowerCase()),
      )
      .toList();
  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) async {}
  @override
  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  }) async => null;
  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  }) async => [];
  @override
  Future<void> close() async {}
}

class ReferenceMailAvatar implements MailSenderAvatarService {
  @override
  Future<Uint8List?> loadThumbnail(String sender) async => null;
  @override
  void dispose() {}
}

MailRadarItem _radarItem(
  MailMessageSummary message, {
  bool includeDeadlinePrecisionPair = false,
}) {
  final isDateOnly = message.uid == 1;
  final isExactTime = includeDeadlinePrecisionPair && message.uid == 2;
  return MailRadarItem(
    key: mailRadarMessageKey(
      message.folder,
      message.mailboxUidValidity!,
      message.uid,
    ),
    uid: message.uid,
    mailboxUidValidity: message.mailboxUidValidity!,
    sourceFolder: message.folder,
    subject: message.subject,
    sender: message.sender,
    recipients: message.recipients,
    receivedAt: message.date!,
    summaryZh: const bool.fromEnvironment('UI_PREVIEW_CAPTURE')
        ? const [
            '请在9月14日前完成实验并上传报告。',
            '9月15日14:30，T8报告厅举行设计与AI讲座。',
            '工作坊本周五开放报名，材料由主办方提供。',
            '遗失物品可于工作日到学生服务中心领取。',
            '线上登记意向岗位，提前准备个人简历。',
            '团队本周完成三个功能更新，查看发布说明。',
            '研讨室预约已确认，请按时签到。',
            '请核对选课结果与课程时间，避免冲突。',
          ][(message.uid - 1).clamp(0, 7)]
        : isDateOnly
        ? '课程材料需在本周内提交。'
        : isExactTime
        ? '校园服务将于指定时间开放。'
        : '请查看邮件中的事项并按要求处理。',
    translationZh: '',
    originalIsSeen: message.isSeen,
    priority: message.uid == 1
        ? MailRadarPriority.urgent
        : MailRadarPriority.normal,
    category: isDateOnly || isExactTime
        ? MailRadarCategory.deadline
        : MailRadarCategory.action,
    senderRole: MailRadarSenderRole.department,
    actionZh: isDateOnly
        ? '提交课程材料'
        : isExactTime
        ? '按时前往办理'
        : '查看邮件要求',
    deadlineText: isDateOnly
        ? '2026-09-12（北京时间 UTC+8）'
        : isExactTime
        ? '2026-09-11 14:30（北京时间 UTC+8）'
        : '',
    relatedThreadKey: '',
    attachmentNotes: const [],
    analyzedAt: DateTime.now(),
    bodyCoverage: 'complete',
    deadlineAt: isDateOnly
        ? DateTime.utc(
            2026,
            9,
            const bool.fromEnvironment('UI_PREVIEW_CAPTURE') ? 14 : 12,
          )
        : isExactTime
        ? DateTime.utc(
            2026,
            9,
            const bool.fromEnvironment('UI_PREVIEW_CAPTURE') ? 15 : 11,
            6,
            30,
          )
        : null,
    deadlineEvidence: isDateOnly
        ? '请于9月12日前提交。'
        : isExactTime
        ? '开放时间为9月11日14:30。'
        : '',
    deadlinePrecision: isDateOnly
        ? 'date'
        : isExactTime
        ? 'datetime'
        : '',
    analysisLanguageTag: 'zh-Hans',
    analysisContractVersion: mailRadarAnalysisContractVersion,
  );
}

class ReferenceRadarAnalyzer implements MailRadarAnalyzer {
  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async => _radarItem(summary);
}

class ReferenceRadarStore implements MailRadarStore {
  ReferenceRadarStore(this.items);
  List<MailRadarItem> items;
  bool consent = true;
  bool enabled = false;
  int days = 30;
  @override
  Future<MailRadarPreferences> loadPreferences(String username) async =>
      MailRadarPreferences(
        hasConsent: consent,
        enabled: enabled,
        lookbackDays: days,
      );
  @override
  Future<bool> hasConsent(String username) async => consent;
  @override
  Future<void> grantConsent(String username) async {
    consent = true;
    enabled = true;
  }

  @override
  Future<void> revokeConsent(String username) async {
    consent = false;
    enabled = false;
  }

  @override
  Future<void> setEnabled(String username, bool value) async {
    enabled = value;
  }

  @override
  Future<void> setLookbackDays(String username, int value) async {
    days = value;
  }

  @override
  Future<List<MailRadarItem>> load(String username) async => items;
  @override
  Future<void> save(String username, List<MailRadarItem> value) async {
    items = value;
  }
}

class ReferenceRecipientDirectory extends MailRecipientDirectory {
  static const entries = [
    MailRecipientSuggestion(
      email: 'alice@example.test',
      displayName: 'Alice Li',
      contextLabel: '理工科技学院',
      kind: MailRecipientKind.person,
      searchValues: ['Alice Li'],
      personNames: ['Alice Li'],
    ),
    MailRecipientSuggestion(
      email: 'bob@example.test',
      displayName: 'Bob Chen',
      contextLabel: '商学院',
      kind: MailRecipientKind.person,
      searchValues: ['Bob Chen'],
      personNames: ['Bob Chen'],
    ),
  ];
  @override
  Future<List<MailRecipientSuggestion>> searchLocal(String query) async =>
      query.trim().isEmpty
      ? []
      : entries
            .where(
              (item) =>
                  item.displayName.toLowerCase().contains(
                    query.toLowerCase(),
                  ) ||
                  item.email.startsWith(query),
            )
            .toList();
  @override
  Future<List<MailRecipientSuggestion>> search(String query) =>
      searchLocal(query);
}
