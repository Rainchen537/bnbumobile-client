import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/mail_radar_analyzer.dart';
import 'package:bnbu_me/services/mail_radar_attachment_processor.dart';
import 'package:bnbu_me/services/mail_radar_store.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/state/mail_radar_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/mail_radar_view.dart';
import 'package:bnbu_me/widgets/mail_message_row.dart';
import 'package:bnbu_me/pages/mail_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final now = DateTime(2026, 8, 9, 12);
  const credentials = MailAccessCredentials(
    userId: 'student',
    emailAddress: 'student@mail.bnbu.edu.cn',
    password: 'test-only',
  );

  test('长邮件保留首尾且覆盖状态与实际请求一致', () async {
    final remote = _RadarAssistantService();
    final service = _RadarMailService([_summary(9, now)]);
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: remote,
      attachmentService: remote,
    );
    final item = await analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: service.messages.single,
      detail: MailMessageDetail(
        uid: 9,
        subject: 'Long message',
        sender: 'Teacher <t@bnbu.edu.cn>',
        recipients: '',
        cc: null,
        date: now,
        body: '开始${'x' * 15000}截止原文在末尾',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
      ),
      mailService: service,
    );
    expect(item.bodyCoverage, 'partial');
    expect(remote.lastRadarRequest!.bodyExcerpt, startsWith('开始'));
    expect(remote.lastRadarRequest!.bodyExcerpt, endsWith('截止原文在末尾'));
    expect(
      remote.lastRadarRequest!.bodyExcerpt.length,
      lessThanOrEqualTo(7800),
    );
  });

  test('附件预算耗尽后不宣称提供未发送内容且限制设备提取数量', () async {
    final remote = _RadarAssistantService();
    final processor = _BudgetAttachmentProcessor();
    final service = _RadarMailService([_summary(9, now)]);
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: remote,
      attachmentService: remote,
      attachmentProcessor: processor,
    );
    final item = await analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: service.messages.single,
      detail: MailMessageDetail(
        uid: 9,
        subject: 'Attachments',
        sender: 'Teacher <t@bnbu.edu.cn>',
        recipients: '',
        cc: null,
        date: now,
        body: '附件要求',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
        attachments: [
          for (var i = 0; i < 7; i++)
            MailAttachment(
              name: '$i.txt',
              mimeType: 'text/plain',
              size: 100,
              partId: '$i',
            ),
        ],
      ),
      mailService: service,
    );
    expect(processor.count, 6);
    expect(item.attachmentCoverage['0.txt'], 'complete');
    expect(item.attachmentCoverage['2.txt'], 'partial');
    expect(item.attachmentCoverage['3.txt'], 'unread');
    expect(item.attachmentCoverage['6.txt'], 'unread');
    expect(
      remote.lastRadarRequest!.attachmentContext,
      isNot(contains('内容已随本次请求提供')),
    );
    expect(item.attachmentNotes, contains('3.txt：本次未读取'));
  });

  test('分析刷新与独立状态字段合并不丢失完成和分类纠正', () {
    final base = _radarItem(uid: 9, category: MailRadarCategory.notice);
    final done = base.copyWith(
      completed: true,
      taskStatus: MailRadarTaskStatus.completed,
      updatedAt: now,
      userFieldTimes: {
        'status': now.toUtc().toIso8601String(),
        'category': '2020-01-01T00:00:00Z',
      },
    );
    final classified = base.copyWith(
      category: MailRadarCategory.action,
      userCorrectedCategory: true,
      updatedAt: now.add(const Duration(minutes: 1)),
      userFieldTimes: {
        'status': '2020-01-01T00:00:00Z',
        'category': now
            .add(const Duration(minutes: 1))
            .toUtc()
            .toIso8601String(),
      },
    );
    final merged = mergeMailRadarItem(done, classified);
    expect(merged.completed, isTrue);
    expect(merged.category, MailRadarCategory.action);
    expect(mergeMailRadarItem(classified, done).toJson(), merged.toJson());
    expect(
      MailRadarItem.fromJson(merged.toJson()).effectiveStatus,
      MailRadarTaskStatus.completed,
    );
  });

  test('雷达查询按八封分页并报告范围与未分析数量', () async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        for (var i = 1; i <= 10; i++)
          _radarItem(uid: i, category: MailRadarCategory.notice),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([]),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => DateTime(2026, 8, 10),
    );
    await controller.initialize();
    final result = await controller.queryTasks({
      'status': 'active',
      'offset': 0,
    });
    expect(result.kind, 'mail_radar');
    expect(result.radarItems.length, 8);
    expect(result.nextCursor, '8');
    expect(result.completeness, 'truncated');
    final rest = await controller.queryTasks({'status': 'active', 'offset': 8});
    expect(rest.radarItems.length, 2);
    await controller.revokeConsent();
    await expectLater(
      controller.queryTasks({}),
      throwsA(isA<AiAssistantException>()),
    );
    controller.dispose();
  });

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('事项状态菜单在${width.toInt()}宽度保持可用且不改变邮箱已读', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _RadarMailService([]);
      final controller = MailRadarController(
        username: 'student',
        credentials: credentials,
        mailService: service,
        analyzer: _RadarAnalyzer(),
        now: () => now,
        store: _MemoryRadarStore(consented: true)
          ..items = [_radarItem(uid: 88, category: MailRadarCategory.action)],
      );
      await controller.initialize();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MailRadarView.analysisPreview(
              controller: controller,
              onOpenOriginal: (_) async {},
              onScheduleReminder: (_, __, ___) async => null,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('邮件 88'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('设置提醒'), findsOneWidget);
      await tester.tap(find.text('处理状态').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('等待回复'));
      await tester.pumpAndSettle();
      expect(
        controller.items.single.effectiveStatus,
        MailRadarTaskStatus.waiting,
      );
      expect(service.seenUids, isEmpty);
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  }

  test('稍后时间到期恢复待处理语义而不改写用户版本', () {
    final original = _radarItem(uid: 3, category: MailRadarCategory.action);
    final item = original.copyWith(
      taskStatus: MailRadarTaskStatus.snoozed,
      snoozedUntil: now.add(const Duration(hours: 1)),
    );
    expect(item.taskStatusAt(now), MailRadarTaskStatus.snoozed);
    expect(
      item.taskStatusAt(now.add(const Duration(hours: 1))),
      MailRadarTaskStatus.pending,
    );
    expect(item.taskStatus, MailRadarTaskStatus.snoozed);
  });

  testWidgets('英文雷达详情翻译状态标签和操作而保留原始主题', (tester) async {
    final item = MailRadarItem.fromJson({
      ..._radarItem(uid: 55, category: MailRadarCategory.action).toJson(),
      'body_coverage': 'complete',
    });
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([_summary(55, now)]),
      analyzer: _RadarAnalyzer(),
      store: _MemoryRadarStore(consented: true)..items = [item],
      now: () => now,
    );
    await controller.initialize();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [BnbuLocalizations.delegate],
        theme: AppTheme.dark,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
            onScheduleReminder: (_, __, ___) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Act now  1'),
      findsNothing,
    ); // normal priority belongs to Recent Priority
    expect(find.byType(MailMessageRow), findsOneWidget);
    await tester.tap(find.text('邮件 55'));
    await tester.pumpAndSettle();
    expect(find.text('To do'), findsOneWidget);
    expect(find.text('Mark complete'), findsOneWidget);
    expect(find.textContaining('Message: Fully read'), findsOneWidget);
    expect(find.text('待处理'), findsNothing);
    controller.dispose();
  });

  test('首次默认只分析近30天收件箱，重复扫描只处理新增邮件', () async {
    final service = _RadarMailService([
      _summary(3, now.subtract(const Duration(days: 1))),
      _summary(2, now.subtract(const Duration(days: 29))),
      _summary(1, now.subtract(const Duration(days: 31))),
    ]);
    final analyzer = _RadarAnalyzer();
    final store = _MemoryRadarStore(consented: true);
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: analyzer,
      store: store,
      now: () => now,
    );

    await controller.initialize();
    await controller.scan();

    expect(controller.items.map((item) => item.uid), containsAll([2, 3]));
    expect(controller.items, hasLength(2));
    expect(analyzer.calls, 2);
    expect(service.readMarkAsSeen, everyElement(isFalse));

    await controller.scan();
    expect(analyzer.calls, 2);

    service.messages.insert(0, _summary(4, now));
    await controller.scan();
    expect(analyzer.calls, 3);
    expect(controller.items.map((item) => item.uid), contains(4));
    expect(
      controller.items.firstWhere((item) => item.uid == 4).isUnread,
      isTrue,
    );
    await controller.markOpened(
      controller.items.firstWhere((item) => item.uid == 4),
    );
    expect(
      controller.items.firstWhere((item) => item.uid == 4).isUnread,
      isFalse,
    );
    controller.dispose();
  });

  test('同账号第二台设备先合并远端终态，不重复调用邮件分析', () async {
    final remote = _MemoryRadarSyncService();
    final firstAnalyzer = _RadarAnalyzer();
    final messages = [_summary(88, now.subtract(const Duration(minutes: 2)))];
    final first = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(List.of(messages)),
      analyzer: firstAnalyzer,
      store: _MemoryRadarStore(consented: true),
      syncService: remote,
      now: () => now,
    );

    await first.initialize();
    await first.scan();
    expect(firstAnalyzer.calls, 1);
    expect(remote.items.single.analysisPending, isFalse);

    final secondAnalyzer = _RadarAnalyzer();
    final second = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(List.of(messages)),
      analyzer: secondAnalyzer,
      store: _MemoryRadarStore(consented: true),
      syncService: remote,
      now: () => now,
    );

    await second.initialize();
    await second.scan();

    expect(second.items.single.summaryZh, '摘要');
    expect(secondAnalyzer.calls, 0);
    first.dispose();
    second.dispose();
  });

  test('同账号设备为同一邮箱 UID 生成一致的 UUID v4 请求标识', () {
    final first = createStableMailRadarClientRequestId(
      username: 'Student',
      mailboxUidValidity: 77,
      uid: 88,
    );
    final second = createStableMailRadarClientRequestId(
      username: 'student@mail.bnbu.edu.cn',
      mailboxUidValidity: 77,
      uid: 88,
    );

    expect(first, second);
    expect(
      first,
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(
      createStableMailRadarClientRequestId(
        username: 'student',
        mailboxUidValidity: 77,
        uid: 89,
      ),
      isNot(first),
    );
    expect(
      createStableMailRadarClientRequestId(
        username: 'student',
        mailboxUidValidity: 77,
        uid: 88,
        targetLanguageTag: 'en',
      ),
      isNot(first),
    );
  });

  test('切换界面语言后按新目标语言重新分析已缓存邮件', () async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 92,
          category: MailRadarCategory.notice,
          receivedAt: now,
        ).copyWith(analysisLanguageTag: 'zh-Hans'),
      ];
    final analyzer = _RadarAnalyzer(analysisLanguageTagProvider: () => 'en');
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([_summary(92, now)]),
      analyzer: analyzer,
      store: store,
      now: () => now,
      targetLanguageTagProvider: () => 'en',
    );

    await controller.initialize();
    await controller.scan();

    expect(analyzer.calls, 1);
    expect(controller.items.single.analysisLanguageTag, 'en');
    expect(analyzer.requestIds[92], [
      createStableMailRadarClientRequestId(
        username: 'student',
        mailboxUidValidity: 77,
        uid: 92,
        targetLanguageTag: 'en',
      ),
    ]);
    controller.dispose();
  });

  test('打开旧版空翻译记录时只按当前契约补分析一次', () async {
    final legacyJson = _radarItem(
      uid: 93,
      category: MailRadarCategory.notice,
      translationZh: '',
      receivedAt: now,
    ).toJson()..remove('analysis_contract_version');
    final legacyItem = MailRadarItem.fromJson(legacyJson);
    final store = _MemoryRadarStore(consented: true)..items = [legacyItem];
    final analyzer = _RadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([_summary(93, now)]),
      analyzer: analyzer,
      store: store,
      now: () => now,
    );

    await controller.initialize();
    expect(controller.needsDetailTranslationRefresh(legacyItem), isTrue);

    final upgraded = await controller.prepareItemForDetail(legacyItem);
    expect(upgraded.translationZh, '翻译');
    expect(upgraded.analysisContractVersion, mailRadarAnalysisContractVersion);
    expect(analyzer.calls, 1);

    final reopened = await controller.prepareItemForDetail(upgraded);
    expect(reopened.translationZh, '翻译');
    expect(analyzer.calls, 1);
    controller.dispose();
  });

  test('远端版本冲突时合并另一设备已完成结果并停止重复分析', () async {
    final analyzer = _RadarAnalyzer();
    final remote = _MemoryRadarSyncService(
      conflictOnceWith: [
        _radarItem(
          uid: 90,
          category: MailRadarCategory.action,
          receivedAt: now,
        ),
      ],
    );
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([_summary(90, now)]),
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      syncService: remote,
      now: () => now,
    );

    await controller.initialize();
    await controller.scan();

    expect(analyzer.calls, 0);
    expect(controller.items.single.category, MailRadarCategory.action);
    expect(controller.items.single.analysisPending, isFalse);
    expect(remote.version, 2);
    controller.dispose();
  });

  testWidgets('邮箱页面在后台定时发现并立即保存新邮件分析结果', (tester) async {
    final service = _RadarMailService([
      _summary(101, now.subtract(const Duration(minutes: 2))),
    ]);
    final analyzer = _RadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MailPage.withService(
          controller: null,
          mailService: service,
          testCredentials: credentials,
          radarController: controller,
          radarPollInterval: const Duration(minutes: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.items.map((item) => item.uid), contains(101));

    service.messages.insert(0, _summary(102, now));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();

    expect(controller.items.map((item) => item.uid), containsAll([101, 102]));
    expect(
      controller.items.firstWhere((item) => item.uid == 102).isUnread,
      isTrue,
    );
  });

  testWidgets('雷达点按直接打开原信正文，并可从正文进入回复', (tester) async {
    final service = _RadarMailService([_summary(103, now)]);
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: _RadarAnalyzer(),
      store: _MemoryRadarStore(consented: true)
        ..items = [_radarItem(uid: 103, category: MailRadarCategory.direct)],
      now: () => now,
    );
    await controller.initialize();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MailPage.withService(
          controller: null,
          mailService: service,
          testCredentials: credentials,
          radarController: controller,
          radarPollInterval: Duration.zero,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('邮件雷达'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('邮件 103'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mail-desktop-reading-pane')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mail-detail-page')), findsNothing);
    expect(find.byKey(const ValueKey('mail-radar-detail-modal')), findsNothing);
    // Desktop commands may be icon-only when aligned to the reading pane.
    // Exercise the same reply action without depending on a visible label.
    final reply = find.byKey(const ValueKey('mail-desktop-reply'));
    expect(reply, findsOneWidget);
    final replyTooltip = find.ancestor(
      of: reply,
      matching: find.byType(Tooltip),
    );
    expect(tester.widget<Tooltip>(replyTooltip).message, '回复');
    await tester.tap(reply);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('compose-desktop-workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('compose-send')), findsOneWidget);
    final recipient = tester.widget<TextField>(
      find.byKey(const ValueKey('compose-recipient-field')),
    );
    final subject = tester.widget<TextField>(
      find.byKey(const ValueKey('compose-subject-field')),
    );
    expect(recipient.controller?.text, isEmpty);
    expect(
      find.widgetWithText(InputChip, 'sender103@bnbu.edu.cn'),
      findsOneWidget,
    );
    expect(subject.controller?.text, 'Re: 邮件 103');
    expect(service.readMarkAsSeen, [true]);
  });

  test('第一页混入旧日期邮件时仍继续读取后续页', () async {
    final messages = <MailMessageSummary>[
      for (var uid = 1; uid <= 49; uid++)
        _summary(uid, now.subtract(const Duration(days: 2))),
      _summary(50, now.subtract(const Duration(days: 120))),
      _summary(51, now.subtract(const Duration(days: 3))),
    ];
    final service = _RadarMailService(messages);
    final analyzer = _RadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
    );

    await controller.initialize();
    await controller.scan();

    expect(service.fetchedPages, [1, 2]);
    expect(controller.inboxTotal, 51);
    expect(controller.eligibleTotal, 50);
    expect(controller.items, hasLength(50));
    expect(controller.items.map((item) => item.uid), contains(51));
    expect(controller.items.map((item) => item.uid), isNot(contains(50)));
    controller.dispose();
  });

  test('整页邮件均早于范围时停止继续读取收件箱标题', () async {
    final messages = <MailMessageSummary>[
      for (var uid = 1; uid <= 50; uid++)
        _summary(uid, now.subtract(const Duration(days: 2))),
      for (var uid = 51; uid <= 120; uid++)
        _summary(uid, now.subtract(const Duration(days: 180))),
    ];
    final service = _RadarMailService(messages);
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: _RadarAnalyzer(),
      store: _MemoryRadarStore(consented: true),
      now: () => now,
    );

    await controller.initialize();
    await controller.scan();

    expect(service.fetchedPages, [1, 2]);
    expect(controller.items, hasLength(50));
    controller.dispose();
  });

  test('暂停后保留已完成和待分析记录，恢复时复用稳定请求标识', () async {
    final analyzer = _ControllableSlowRadarAnalyzer();
    final store = _MemoryRadarStore(consented: true);
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([
        _summary(42, now),
        _summary(41, now.subtract(const Duration(minutes: 1))),
      ]),
      analyzer: analyzer,
      store: store,
      now: () => now,
    );

    await controller.initialize();
    final scanning = controller.scan();
    await analyzer.fastMailCompleted.future.timeout(const Duration(seconds: 1));
    await controller.setEnabled(false);
    analyzer.releaseSlowMail.complete();
    await scanning;

    expect(controller.enabled, isFalse);
    expect(controller.items, hasLength(2));
    expect(controller.analyzedCount, 1);
    final stableId = controller.items
        .firstWhere((item) => item.uid == 42)
        .analysisRequestId;
    expect(stableId, isNotEmpty);

    await controller.setEnabled(true);

    expect(controller.analyzedCount, 2);
    expect(analyzer.requestIds[42], [stableId, stableId]);
    controller.dispose();
  });

  test('缩小分析范围不会删除已经保存的雷达记录', () async {
    final store = _MemoryRadarStore(consented: true)..lookbackDays = 60;
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([
        _summary(61, now.subtract(const Duration(days: 60))),
      ]),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );

    await controller.initialize();
    await controller.scan();
    expect(controller.items.single.uid, 61);

    await controller.setLookbackDays(30);

    expect(controller.lookbackDays, 30);
    expect(controller.items.single.uid, 61);
    expect(controller.visibleItems, isEmpty);

    await controller.setLookbackDays(60);

    expect(controller.items.single.uid, 61);
    expect(controller.visibleItems.single.uid, 61);
    controller.dispose();
  });

  test('服务端终止原请求时释放队列位并在下次扫描重试', () async {
    final analyzer = _NewRequestOnceRadarAnalyzer();
    final store = _MemoryRadarStore(consented: true);
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([_summary(62, now)]),
      analyzer: analyzer,
      store: store,
      now: () => now,
      retryDelay: (_) async {},
    );

    await controller.initialize();
    await controller.scan();

    expect(analyzer.requestIds[62], hasLength(1));
    expect(controller.pendingCount, 1);
    expect(controller.failed, 1);
    expect(controller.error, contains('稍后自动重试'));

    await controller.retryNow();

    expect(analyzer.requestIds[62], hasLength(2));
    expect(analyzer.requestIds[62]![0], isNot(analyzer.requestIds[62]![1]));
    expect(controller.pendingCount, 0);
    expect(controller.analyzedCount, 1);
    controller.dispose();
  });

  test('旧契约待处理项升级后保留服务端要求的新请求标识', () async {
    final analyzer = _NewRequestOnceRadarAnalyzer();
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 63,
          category: MailRadarCategory.notice,
          analysisPending: true,
          analysisRequestId: '123e4567-e89b-42d3-a456-426614174000',
          analysisContractVersion: 'legacy-contract',
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([_summary(63, now)]),
      analyzer: analyzer,
      store: store,
      now: () => now,
      retryDelay: (_) async {},
    );

    await controller.initialize();
    await controller.scan();

    expect(
      controller.items.single.analysisContractVersion,
      mailRadarAnalysisContractVersion,
    );
    final replacementId = controller.items.single.analysisRequestId;
    expect(replacementId, isNot(analyzer.requestIds[63]!.single));

    await controller.retryNow();

    expect(analyzer.requestIds[63], hasLength(2));
    expect(analyzer.requestIds[63]![1], replacementId);
    expect(controller.pendingCount, 0);
    controller.dispose();
  });

  test('上游故障会停止领取积压邮件并等待下一次自动重试', () async {
    final analyzer = _AlwaysNewRequestRadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([
        for (var uid = 70; uid >= 61; uid--)
          _summary(uid, now.subtract(Duration(minutes: 70 - uid))),
      ]),
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
    );

    await controller.initialize();
    await controller.scan();

    expect(
      analyzer.calls,
      lessThanOrEqualTo(MailRadarController.maxConcurrentAnalyses),
    );
    expect(controller.pendingCount, 10);
    expect(controller.isWaitingForProvider, isTrue);
    expect(
      controller.providerRetryAt,
      now.add(MailRadarController.providerRetryCooldown),
    );

    await controller.scan();
    expect(
      analyzer.calls,
      lessThanOrEqualTo(MailRadarController.maxConcurrentAnalyses),
    );

    await controller.retryNow();
    expect(
      analyzer.calls,
      lessThanOrEqualTo(MailRadarController.maxConcurrentAnalyses * 2),
    );
    controller.dispose();
  });

  test(
    'account preference stop cancels scanning without revoking administrator access',
    () async {
      var denials = 0;
      final controller = MailRadarController(
        username: 'student',
        credentials: credentials,
        mailService: _RadarMailService([_summary(72, now)]),
        analyzer: _UnavailableRadarAnalyzer(accountStopped: true),
        store: _MemoryRadarStore(consented: true),
        now: () => now,
        onRemoteAccessUnavailable: () => denials++,
      );
      await controller.initialize();
      await controller.scan();
      expect(controller.enabled, false);
      expect(denials, 0);
      expect(controller.isWaitingForProvider, false);
      controller.dispose();
    },
  );
  test('远端关闭权限时静默隐藏邮件雷达且不显示 HTTP 错误', () async {
    var unavailableSignals = 0;
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([_summary(72, now)]),
      analyzer: _UnavailableRadarAnalyzer(),
      store: _MemoryRadarStore(consented: true),
      now: () => now,
      onRemoteAccessUnavailable: () => unavailableSignals++,
    );

    await controller.initialize();
    await controller.scan();

    expect(unavailableSignals, 1);
    expect(controller.error, isNull);
    expect(controller.failed, 0);
    expect(controller.pendingCount, 1);
    expect(controller.isWaitingForProvider, isFalse);
    controller.dispose();
  });

  test('初始化同步发现远端权限已关闭时立即隐藏且不留下错误', () async {
    var unavailableSignals = 0;
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: _MemoryRadarStore(consented: true),
      syncService: _UnavailableRadarSyncService(),
      now: () => now,
      onRemoteAccessUnavailable: () => unavailableSignals++,
    );

    await controller.initialize();

    expect(unavailableSignals, 1);
    expect(controller.error, isNull);
    expect(controller.isLoading, isFalse);
    expect(controller.isWaitingForProvider, isFalse);
    controller.dispose();
  });

  testWidgets('上游故障结束扫描后明确显示等待重试', (tester) async {
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([_summary(71, now)]),
      analyzer: _AlwaysNewRequestRadarAnalyzer(),
      store: _MemoryRadarStore(consented: true),
      now: () => now,
    );
    await controller.initialize();
    await controller.scan();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
            onReply: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('小U上游暂时不可用'), findsOneWidget);
    expect(controller.pendingCount, 1);
    expect(find.text('等待分析'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('小U分析中'), findsNothing);
    controller.dispose();
  });

  test('标记完成设置服务器已读，撤销只改变雷达本地状态', () async {
    final service = _RadarMailService([
      _summary(7, now.subtract(const Duration(hours: 2))),
    ]);
    final store = _MemoryRadarStore(consented: true);
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();
    await controller.scan();
    final item = controller.items.single;

    await controller.setCompleted(item, true);
    expect(controller.items.single.completed, isTrue);
    expect(service.seenUids, [7]);

    await controller.setCompleted(controller.items.single, false);
    expect(controller.items.single.completed, isFalse);
    expect(service.seenUids, [7]);

    await controller.correctCategory(
      controller.items.single,
      MailRadarCategory.direct,
    );
    expect(controller.items.single.category, MailRadarCategory.direct);
    expect(controller.items.single.userCorrectedCategory, isTrue);
    controller.dispose();
  });

  test('单封小U分析超时后继续处理下一封并允许重试', () async {
    final service = _RadarMailService([
      _summary(42, now),
      _summary(41, now.subtract(const Duration(minutes: 1))),
    ]);
    final analyzer = _BlockingFirstRadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
      analysisTimeout: const Duration(milliseconds: 20),
    );

    await controller.initialize();
    await controller.scan();

    expect(controller.processed, 2);
    expect(controller.failed, 1);
    expect(controller.items.map((item) => item.uid), containsAll([41, 42]));
    expect(
      controller.items.firstWhere((item) => item.uid == 42).analysisPending,
      isTrue,
    );
    expect(controller.analyzedCount, 1);
    expect(controller.pendingCount, 1);
    expect(controller.error, contains('刷新后会自动重试'));
    expect(controller.error, isNot(contains('TimeoutException')));
    controller.dispose();
  });

  test('默认分析时限不会让单封慢邮件长期占用队列', () {
    expect(
      MailRadarController.defaultAnalysisTimeout,
      const Duration(seconds: 90),
    );
  });

  test('手动详情升级与后台共用两个分析位置', () async {
    final analyzer = _ConcurrencyRadarAnalyzer();
    final old = _radarItem(
      uid: 40,
      category: MailRadarCategory.notice,
      analysisContractVersion: 'old-contract',
      translationZh: '',
    );
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([
        _summary(42, now),
        _summary(41, now),
        _summary(40, now),
      ]),
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true)..items = [old],
      now: () => now,
    );
    await controller.initialize();
    final scanning = controller.scan();
    await analyzer.fourStarted.future.timeout(const Duration(seconds: 2));
    final upgrading = controller.prepareItemForDetail(old);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(analyzer.started, 2);
    analyzer.release.complete();
    await Future.wait([scanning, upgrading]);
    expect(analyzer.started, 3);
    expect(analyzer.maximumActive, 2);
    controller.dispose();
  });

  test('邮件雷达最多同时分析两封邮件', () async {
    final analyzer = _ConcurrencyRadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([
        for (var uid = 50; uid >= 46; uid--)
          _summary(uid, now.subtract(Duration(minutes: 50 - uid))),
      ]),
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
    );

    await controller.initialize();
    final scanning = controller.scan();
    await analyzer.fourStarted.future.timeout(const Duration(seconds: 1));

    expect(analyzer.active, MailRadarController.maxConcurrentAnalyses);
    expect(analyzer.started, MailRadarController.maxConcurrentAnalyses);
    expect(
      controller.activeAnalyses,
      MailRadarController.maxConcurrentAnalyses,
    );
    expect(controller.items, hasLength(5));
    expect(controller.items, everyElement(isA<MailRadarItem>()));
    expect(controller.pendingCount, 5);

    analyzer.release.complete();
    await scanning;
    expect(analyzer.maximumActive, MailRadarController.maxConcurrentAnalyses);
    expect(controller.items, hasLength(5));
    expect(controller.pendingCount, 0);
    controller.dispose();
  });

  test('最新邮件优先于较旧的无附件邮件进入分析队列', () async {
    final analyzer = _PriorityOrderRadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([
        _summary(60, now, hasAttachments: true),
        for (var uid = 59; uid >= 56; uid--)
          _summary(uid, now.subtract(Duration(minutes: 60 - uid))),
      ]),
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
    );

    await controller.initialize();
    final scanning = controller.scan();
    await analyzer.fourStarted.future.timeout(const Duration(seconds: 1));

    expect(analyzer.startedUids, unorderedEquals([60, 59]));
    expect(analyzer.startedUids, isNot(contains(58)));
    expect(analyzer.startedUids, isNot(contains(57)));
    expect(analyzer.startedUids, isNot(contains(56)));

    analyzer.release.complete();
    await scanning;
    expect(analyzer.startedUids, contains(56));
    controller.dispose();
  });

  test('耗时邮件不会阻塞后续邮件完成分析', () async {
    final service = _RadarMailService([
      _summary(42, now),
      _summary(41, now.subtract(const Duration(minutes: 1))),
    ]);
    final analyzer = _ControllableSlowRadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
    );

    await controller.initialize();
    final scanning = controller.scan();
    await analyzer.fastMailCompleted.future.timeout(const Duration(seconds: 1));
    await Future<void>.delayed(Duration.zero);

    expect(controller.isScanning, isTrue);
    expect(controller.items.map((item) => item.uid), containsAll([41, 42]));
    expect(
      controller.items.firstWhere((item) => item.uid == 42).analysisPending,
      isTrue,
    );
    expect(
      controller.items.firstWhere((item) => item.uid == 41).analysisPending,
      isFalse,
    );

    analyzer.releaseSlowMail.complete();
    await scanning;
    expect(controller.items.map((item) => item.uid), containsAll([41, 42]));
    controller.dispose();
  });

  test('分析进行中收到的新扫描请求会在当前批次后继续处理', () async {
    final service = _RadarMailService([
      _summary(42, now),
      _summary(41, now.subtract(const Duration(minutes: 1))),
    ]);
    final analyzer = _ControllableSlowRadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
    );
    await controller.initialize();

    final firstScan = controller.scan();
    await analyzer.fastMailCompleted.future.timeout(const Duration(seconds: 1));
    service.messages.insert(0, _summary(43, now));
    final queuedScan = controller.scan();
    analyzer.releaseSlowMail.complete();

    await Future.wait([firstScan, queuedScan]);
    expect(controller.items.map((item) => item.uid), containsAll([41, 42, 43]));
    controller.dispose();
  });

  test('积压分析中发现新邮件时停止领取旧任务并优先处理新邮件', () async {
    final service = _RadarMailService([
      for (var uid = 60; uid >= 55; uid--)
        _summary(uid, now.subtract(Duration(minutes: 60 - uid))),
    ]);
    final analyzer = _PriorityOrderRadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
    );
    await controller.initialize();

    final firstScan = controller.scan();
    await analyzer.fourStarted.future.timeout(const Duration(seconds: 1));
    service.messages.insert(
      0,
      _summary(61, now.add(const Duration(minutes: 1))),
    );
    final queuedScan = controller.scan();
    analyzer.release.complete();

    await Future.wait([firstScan, queuedScan]);
    expect(analyzer.startedUids.take(3), [60, 59, 61]);
    expect(controller.pendingCount, 0);
    controller.dispose();
  });

  test('普通临时失败会在同一次扫描中自动重试', () async {
    final analyzer = _FailOnceRadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([_summary(51, now)]),
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
      retryDelay: (_) async {},
    );

    await controller.initialize();
    await controller.scan();

    expect(analyzer.attempts, 2);
    expect(controller.failed, 0);
    expect(controller.items.map((item) => item.uid), [51]);
    controller.dispose();
  });

  test('单封超时邮件释放位置且不在同批次重复消耗模型请求', () async {
    final analyzer = _TimeoutOnceRadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([
        _summary(52, now),
        _summary(51, now.subtract(const Duration(minutes: 1))),
      ]),
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
      analysisTimeout: const Duration(milliseconds: 20),
      retryDelay: (_) async {},
    );

    await controller.initialize();
    await controller.scan();

    expect(analyzer.attempts[52], 1);
    expect(controller.failed, 1);
    expect(controller.processed, 2);
    expect(controller.checked, 2);
    expect(controller.isRetryPass, isFalse);
    expect(controller.items.map((item) => item.uid), containsAll([51, 52]));
    expect(controller.pendingCount, 1);
    controller.dispose();
  });

  test('补试阶段保留第一轮检查进度并明确标记状态', () async {
    final analyzer = _HeldRetryRadarAnalyzer();
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService([
        _summary(54, now),
        _summary(53, now.subtract(const Duration(minutes: 1))),
      ]),
      analyzer: analyzer,
      store: _MemoryRadarStore(consented: true),
      now: () => now,
      retryDelay: (_) async {},
    );

    await controller.initialize();
    final scanning = controller.scan();
    await analyzer.retryPassStarted.future.timeout(const Duration(seconds: 1));

    expect(controller.isRetryPass, isTrue);
    expect(controller.checked, 2);
    expect(controller.activeAnalyses, 2);

    analyzer.releaseRetryPass.complete();
    await scanning;
    expect(controller.isRetryPass, isFalse);
    expect(controller.processed, 2);
    controller.dispose();
  });

  test('小U分析识别直接来信并在上下文中剔除凭据行', () async {
    final acceptedRequestId = createAssistantClientRequestId();
    final assistant = _RadarAssistantService(
      acceptedClientRequestId: acceptedRequestId,
    );
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: assistant,
      attachmentService: assistant,
    );
    final service = _RadarMailService([
      _summary(9, now.subtract(const Duration(hours: 1))),
    ]);
    final item = await analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: service.messages.single,
      detail: MailMessageDetail(
        uid: 9,
        subject: 'Re: Office hour',
        sender: 'Dr Chen <chen@bnbu.edu.cn>',
        recipients: credentials.emailAddress,
        cc: null,
        date: now,
        body: 'Please visit at 3pm.\npassword: should-never-leave-device',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
      ),
      mailService: service,
    );

    expect(item.category, MailRadarCategory.direct);
    expect(item.senderRole, MailRadarSenderRole.teacher);
    expect(item.priority, MailRadarPriority.high);
    expect(item.analysisRequestId, acceptedRequestId);
    expect(item.translationZh, '请在下午三点前往办公室。');
    expect(item.deadlineText, '下午三点（北京时间 UTC+8）');
    expect(assistant.lastRadarRequest?.senderEmail, 'chen@bnbu.edu.cn');
    expect(assistant.lastRadarRequest?.subject, 'Re: Office hour');
    expect(assistant.lastRadarRequest?.targetLanguageTag, 'zh-Hans');
    expect(
      assistant.lastContext!.selectedMail!.bodyExcerpt,
      isNot(contains('should-never-leave-device')),
    );
  });

  test('邮件雷达按当前英文界面决定是否翻译并记录结果语言', () async {
    final englishAssistant = _RadarAssistantService(
      answer:
          '''{"summary_zh":"A class reminder.","content_language":"other","content_matches_target_language":true,"needs_translation":false,"translation_zh":"","priority":"normal","category":"notice","is_direct_correspondence":false,"sender_role":"department","action_zh":"","deadline_text":"","related_thread_key":"class"}''',
    );
    final englishAnalyzer = SmallUMailRadarAnalyzer(
      assistantService: englishAssistant,
      radarService: englishAssistant,
      targetLanguageTagProvider: () => 'en',
    );
    final englishItem = await englishAnalyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: _summary(90, now),
      detail: MailMessageDetail(
        uid: 90,
        subject: 'Class reminder',
        sender: 'AR <ar@bnbu.edu.cn>',
        recipients: credentials.emailAddress,
        cc: null,
        date: now,
        body: 'Please attend class on time.',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
      ),
      mailService: _RadarMailService(const []),
    );

    expect(englishAssistant.lastRadarRequest?.targetLanguageTag, 'en');
    expect(englishItem.translationZh, isEmpty);
    expect(englishItem.analysisLanguageTag, 'en');

    final chineseAssistant = _RadarAssistantService(
      answer:
          '''{"summary_zh":"A Chinese class notice.","content_language":"chinese","content_matches_target_language":false,"needs_translation":true,"translation_zh":"Please attend class on time.","priority":"normal","category":"notice","is_direct_correspondence":false,"sender_role":"department","action_zh":"","deadline_text":"","related_thread_key":"class-zh"}''',
    );
    final chineseAnalyzer = SmallUMailRadarAnalyzer(
      assistantService: chineseAssistant,
      radarService: chineseAssistant,
      targetLanguageTagProvider: () => 'en',
    );
    final chineseItem = await chineseAnalyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: _summary(91, now),
      detail: MailMessageDetail(
        uid: 91,
        subject: '课程通知',
        sender: '教务处 <ar@bnbu.edu.cn>',
        recipients: credentials.emailAddress,
        cc: null,
        date: now,
        body: '请同学们按时上课。',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
      ),
      mailService: _RadarMailService(const []),
    );

    expect(chineseItem.translationZh, 'Please attend class on time.');
    expect(chineseItem.analysisLanguageTag, 'en');
  });

  test('专用雷达响应保存真实工具记录和待确认记忆候选', () async {
    final assistant = _RadarAssistantService(
      toolUses: const [
        MailRadarToolUse(
          name: 'official_directory',
          status: 'used',
          query: 'chen@bnbu.edu.cn',
        ),
        MailRadarToolUse(
          name: 'approved_memory',
          status: 'used',
          query: '当前邮件',
        ),
      ],
      memorySuggestions: const [
        AssistantMemorySuggestion(content: '用户长期倾向在毕业后继续从事软件开发。'),
      ],
    );
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: assistant,
      radarService: assistant,
    );

    final item = await analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: _summary(10, now),
      detail: MailMessageDetail(
        uid: 10,
        subject: 'Career plan',
        sender: 'Dr Chen <chen@bnbu.edu.cn>',
        recipients: credentials.emailAddress,
        cc: null,
        date: now,
        body:
            'You mentioned your long-term plan to work in software development.',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
      ),
      mailService: _RadarMailService(const []),
    );

    expect(item.toolUses.map((tool) => tool.name), [
      'official_directory',
      'approved_memory',
    ]);
    expect(item.memorySuggestions.single.isPending, isTrue);
  });

  test('记忆候选只在用户决定后持久化保存或忽略状态', () async {
    const suggestion = AssistantMemorySuggestion(content: '用户长期计划从事软件开发。');
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 11,
          category: MailRadarCategory.notice,
        ).copyWith(memorySuggestions: const [suggestion]),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();

    await controller.resolveMemorySuggestion(
      controller.items.single,
      suggestion,
      status: AssistantMemorySuggestionStatus.saved,
      content: '用户长期目标是从事软件开发。',
    );

    final saved = store.items.single.memorySuggestions.single;
    expect(saved.status, AssistantMemorySuggestionStatus.saved);
    expect(saved.content, '用户长期目标是从事软件开发。');
    expect(controller.pendingMemorySuggestions, isEmpty);
    controller.dispose();
  });

  test('邮件明确标注其他时区时保留原时区', () async {
    final assistant = _RadarAssistantService(
      answer:
          '''{"summary_zh":"线上说明会。","content_language":"other","needs_translation":true,"translation_zh":"说明会于下午 3 点 PDT 开始。","priority":"normal","category":"event","is_direct_correspondence":false,"sender_role":"department","action_zh":"下午 3 点 PDT 参加说明会","deadline_text":"8月12日下午3点 PDT","related_thread_key":"briefing"}''',
    );
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: assistant,
      attachmentService: assistant,
    );
    final item = await analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: _summary(19, now),
      detail: MailMessageDetail(
        uid: 19,
        subject: 'Online briefing',
        sender: 'Office <office@example.edu>',
        recipients: credentials.emailAddress,
        cc: null,
        date: now,
        body: 'The briefing starts at 3 PM PDT on August 12.',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
      ),
      mailService: _RadarMailService(const []),
    );

    expect(item.deadlineText, '8月12日下午3点 PDT');
  });

  test('旧缓存中未标注时区的截止时间自动补为北京时间', () {
    final json = _radarItem(
      uid: 18,
      category: MailRadarCategory.deadline,
    ).toJson()..['deadline_text'] = '8月12日18点';

    final item = MailRadarItem.fromJson(json);

    expect(item.deadlineText, '8月12日18点（北京时间 UTC+8）');
  });

  test('简体中文界面下中文或双语邮件不重复翻译', () async {
    for (final language in ['chinese', 'bilingual']) {
      final assistant = _RadarAssistantService(
        answer:
            '''{"summary_zh":"课程安排。","content_language":"$language","needs_translation":false,"translation_zh":"不应显示的翻译","priority":"normal","category":"notice","is_direct_correspondence":false,"sender_role":"department","action_zh":"","deadline_text":"","related_thread_key":"course"}''',
      );
      final analyzer = SmallUMailRadarAnalyzer(
        assistantService: assistant,
        attachmentService: assistant,
      );
      final item = await analyzer.analyze(
        clientRequestId: createAssistantClientRequestId(),
        username: 'student',
        credentials: credentials,
        summary: _summary(20, now),
        detail: MailMessageDetail(
          uid: 20,
          subject: '课程安排',
          sender: '教务处 <ar@bnbu.edu.cn>',
          recipients: credentials.emailAddress,
          cc: null,
          date: now,
          body: language == 'chinese'
              ? '请同学们按时上课。'
              : '请同学们按时上课。 Please attend class on time.',
          htmlBody: null,
          isSeen: false,
          mailboxUidValidity: 77,
        ),
        mailService: _RadarMailService(const []),
      );

      expect(item.translationZh, isEmpty);
    }
  });

  test('下一步链接只能引用邮件中的真实链接并剔除敏感参数', () async {
    final assistant = _RadarAssistantService(
      answer:
          '''{"summary_zh":"请完成报名。","content_language":"chinese","needs_translation":false,"translation_zh":"","priority":"normal","category":"action","is_direct_correspondence":false,"sender_role":"department","is_recall_notice":false,"action_zh":"打开报名页面并提交。","action_links":[{"label":"前往报名","source_index":1},{"label":"伪造链接","source_index":99}],"deadline_text":"","related_thread_key":"registration"}''',
    );
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: assistant,
      attachmentService: assistant,
    );
    const exactUrl = 'https://forms.example.edu/register?token=secret-123';
    final item = await analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: _summary(24, now),
      detail: MailMessageDetail(
        uid: 24,
        subject: '活动报名',
        sender: 'SAO <sao@bnbu.edu.cn>',
        recipients: credentials.emailAddress,
        cc: null,
        date: now,
        body: '请在这里报名：$exactUrl',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
      ),
      mailService: _RadarMailService(const []),
    );

    expect(item.actionLinks, hasLength(1));
    expect(item.actionLinks.single.label, '前往报名');
    expect(item.actionLinks.single.sourceIndex, 1);
    expect(item.toJson().toString(), isNot(contains('secret-123')));
    expect(assistant.lastMessage, isNot(contains('secret-123')));
    expect(
      assistant.lastContext!.selectedMail!.bodyExcerpt,
      isNot(contains('secret-123')),
    );
  });

  test('邮件雷达提示在大量收件人与链接下仍满足小U请求长度边界', () async {
    final assistant = _RadarAssistantService();
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: assistant,
      attachmentService: assistant,
    );
    final links = [
      for (var index = 0; index < 16; index++)
        'https://forms.example.edu/${'path/' * 120}$index?campaign=${'x' * 600}',
    ].join('\n');
    await analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: _summary(25, now),
      detail: MailMessageDetail(
        uid: 25,
        subject: '活动链接汇总',
        sender: 'SAO <sao@bnbu.edu.cn>',
        recipients: List.filled(30, 'student@mail.bnbu.edu.cn').join(', '),
        cc: List.filled(30, 'teacher@bnbu.edu.cn').join(', '),
        date: now,
        body: links,
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
        listId: 'all-students-${'a' * 200}',
        precedence: 'bulk-${'b' * 100}',
        inReplyTo: '<${'c' * 200}@bnbu.edu.cn>',
        references: '<${'d' * 200}@bnbu.edu.cn>',
      ),
      mailService: _RadarMailService(const []),
    );

    expect(assistant.lastRadarRequest?.sourceLinks, hasLength(16));
    expect(
      assistant.lastRadarRequest!.sourceLinks.every((url) => url.length <= 500),
      isTrue,
    );
    expect(
      assistant.lastRadarRequest!.sourceLinks,
      everyElement('https://forms.example.edu'),
    );
  });

  test('撤回通知只保留撤回状态', () async {
    final assistant = _RadarAssistantService(
      answer:
          '''{"summary_zh":"不应保留的摘要","content_language":"chinese","needs_translation":false,"translation_zh":"","priority":"high","category":"action","is_direct_correspondence":false,"sender_role":"department","is_recall_notice":true,"action_zh":"不应保留的下一步","deadline_text":"明天","related_thread_key":"recall"}''',
    );
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: assistant,
      attachmentService: assistant,
    );
    final item = await analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: _summary(70, now),
      detail: MailMessageDetail(
        uid: 70,
        subject: '发件人已撤回邮件：【Job Opportunities】实习生招聘',
        sender: 'career@bnbu.edu.cn',
        recipients: credentials.emailAddress,
        cc: null,
        date: now,
        body: '发件人已撤回这封邮件。',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
      ),
      mailService: _RadarMailService(const []),
    );

    expect(item.isRecallNotice, isTrue);
    expect(item.summaryZh, '发件人已撤回');
    expect(item.priority, MailRadarPriority.normal);
    expect(item.actionZh, isEmpty);
    expect(item.deadlineText, isEmpty);
    expect(item.translationZh, isEmpty);
    expect(item.attachmentNotes, isEmpty);
    expect(assistant.lastMessage, isNull);
  });

  test('同一封邮件并行准备附件且只发起一次合并小U请求', () async {
    final assistant = _RadarAssistantService();
    final processor = _ParallelAttachmentProcessor();
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: assistant,
      attachmentService: assistant,
      attachmentProcessor: processor,
    );
    const attachments = [
      MailAttachment(
        name: '第一份.pdf',
        size: 100,
        mimeType: 'application/pdf',
        partId: '2',
      ),
      MailAttachment(
        name: '第二份.pdf',
        size: 100,
        mimeType: 'application/pdf',
        partId: '3',
      ),
      MailAttachment(
        name: '第三份.pdf',
        size: 100,
        mimeType: 'application/pdf',
        partId: '4',
      ),
    ];

    final analyzing = analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: _summary(71, now, hasAttachments: true),
      detail: MailMessageDetail(
        uid: 71,
        subject: '三份附件',
        sender: 'sao@bnbu.edu.cn',
        recipients: credentials.emailAddress,
        cc: null,
        date: now,
        body: '请查看附件。',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
        attachments: attachments,
      ),
      mailService: _RadarMailService(const []),
    );
    await processor.twoStarted.future.timeout(const Duration(seconds: 1));

    expect(processor.active, 2);
    expect(processor.maximumActive, 2);
    expect(processor.started, 2);

    processor.release.complete();
    final item = await analyzing;
    expect(processor.maximumActive, 2);
    expect(processor.started, 3);
    expect(assistant.chatCalls, 0);
    expect(assistant.attachmentChatCalls, 1);
    expect(assistant.lastAttachments, hasLength(1));
    expect(assistant.lastMessage!.length, lessThanOrEqualTo(4000));
    expect(item.attachmentNotes, [
      '第一份.pdf：附件摘要',
      '第二份.pdf：附件摘要',
      '第三份.pdf：附件摘要',
    ]);
  });

  test('二维码图片不发送给小U分析并标记为直接展示', () async {
    final assistant = _RadarAssistantService();
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: assistant,
      attachmentService: assistant,
    );
    final item = await analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: _summary(80, now),
      detail: MailMessageDetail(
        uid: 80,
        subject: '报名信息',
        sender: 'sao@bnbu.edu.cn',
        recipients: credentials.emailAddress,
        cc: null,
        date: now,
        body: 'Please scan the attached code.',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
        attachments: const [
          MailAttachment(
            name: 'QR Code.png',
            size: 68,
            mimeType: 'image/png',
            partId: '2',
          ),
        ],
      ),
      mailService: _RadarMailService(const []),
    );

    expect(item.hasInlineImages, isTrue);
    expect(item.attachmentNotes, isEmpty);
    expect(assistant.lastContext!.selectedMail!.attachments, isEmpty);
  });

  test('群发招聘即使有截止时间也归为普通通知', () async {
    final assistant = _RadarAssistantService(
      answer:
          '''{"summary_zh":"职业发展中心群发实习招聘。","content_language":"bilingual","needs_translation":false,"translation_zh":"","priority":"urgent","category":"deadline","is_direct_correspondence":false,"sender_role":"department","is_recall_notice":false,"action_zh":"有意者可投递简历","deadline_text":"8月2日18点","related_thread_key":"job-zhihui"}''',
    );
    final analyzer = SmallUMailRadarAnalyzer(
      assistantService: assistant,
      attachmentService: assistant,
    );
    final item = await analyzer.analyze(
      clientRequestId: createAssistantClientRequestId(),
      username: 'student',
      credentials: credentials,
      summary: _summary(90, now),
      detail: MailMessageDetail(
        uid: 90,
        subject: '【Job Opportunities】珠海智汇元启科技有限公司实习生招聘',
        sender: 'Career <career@bnbu.edu.cn>',
        recipients: 'all students',
        cc: null,
        date: now,
        body: '学生职业发展中心发布实习生招聘，有意者可在截止日期前投递。',
        htmlBody: null,
        isSeen: false,
        mailboxUidValidity: 77,
      ),
      mailService: _RadarMailService(const []),
    );

    expect(item.category, MailRadarCategory.notice);
    expect(item.priority, MailRadarPriority.normal);
    expect(item.deadlineText, '8月2日18点（北京时间 UTC+8）');
  });

  test('旧缓存中的群发招聘自动纠正为普通通知', () {
    final json =
        _radarItem(
            uid: 91,
            category: MailRadarCategory.deadline,
            priority: MailRadarPriority.urgent,
          ).toJson()
          ..['subject'] = '【Job Opportunities】实习生招聘'
          ..['sender'] = 'career@bnbu.edu.cn';

    final item = MailRadarItem.fromJson(json);

    expect(item.category, MailRadarCategory.notice);
    expect(item.priority, MailRadarPriority.normal);
  });

  test('旧缓存中的图片文字说明迁移为直接展示', () {
    final json =
        _radarItem(uid: 81, category: MailRadarCategory.notice).toJson()
          ..remove('has_inline_images')
          ..['attachment_notes'] = ['QR Code.png：附件仅包含一个黑白二维码，未见可读文字。'];

    final item = MailRadarItem.fromJson(json);

    expect(item.hasInlineImages, isTrue);
    expect(item.attachmentNotes, isEmpty);
  });

  testWidgets('邮件雷达沿用应用主题并展示约定分区和详情', (tester) async {
    final service = _RadarMailService([_summary(12, now)]);
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 12,
          category: MailRadarCategory.direct,
          role: MailRadarSenderRole.teacher,
        ),
        _radarItem(
          uid: 11,
          category: MailRadarCategory.deadline,
          priority: MailRadarPriority.urgent,
        ),
        _radarItem(
          uid: 10,
          category: MailRadarCategory.lowPriority,
          priority: MailRadarPriority.low,
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();
    MailMessageDetail? replyDetail;
    await tester.binding.setSurfaceSize(const Size(760, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
            onReply: (detail) async => replyDetail = detail,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MailMessageRow), findsNWidgets(3));
    expect(find.text('立即处理  1'), findsNothing);
    await tester.tap(find.text('邮件 12'));
    await tester.pumpAndSettle();
    expect(find.text('小U摘要'), findsOneWidget);
    expect(find.text('翻译'), findsOneWidget);
    expect(find.text('查看原始邮件'), findsOneWidget);
    expect(find.text('回复邮件'), findsOneWidget);
    await tester.tap(find.text('回复邮件'));
    await tester.pumpAndSettle();
    expect(replyDetail?.uid, 12);
    expect(replyDetail?.sender, contains('sender12@bnbu.edu.cn'));
    expect(service.readMarkAsSeen, [false]);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('邮件雷达详情在手机使用底部面板且宽屏使用中心弹窗', (tester) async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [_radarItem(uid: 121, category: MailRadarCategory.notice)];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final width in [390.0, 900.0, 1440.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MailRadarView.analysisPreview(
              controller: controller,
              onOpenOriginal: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('邮件 121'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mail-radar-detail-modal')),
        findsOneWidget,
      );
      if (width < 700) {
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
          findsNothing,
        );
      } else {
        expect(find.byType(BottomSheet), findsNothing);
        final dialogFinder = find.byKey(
          const ValueKey('bnbu-adaptive-modal-dialog'),
        );
        expect(dialogFinder, findsOneWidget);
        final dialog = tester.getRect(dialogFinder);
        expect(dialog.width, lessThanOrEqualTo(760));
        expect(dialog.height, lessThanOrEqualTo(760));
        expect(dialog.center.dx, closeTo(width / 2, 0.1));
        expect(dialog.center.dy, closeTo(450, 0.1));
      }
      expect(find.byTooltip('关闭'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
    }
    controller.dispose();
  });

  testWidgets('手机打开外语邮件雷达详情后首屏直接显示翻译', (tester) async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(uid: 122, category: MailRadarCategory.deadline).copyWith(
          toolUses: const [MailRadarToolUse(name: 'directory', status: 'used')],
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('邮件 122'));
    await tester.pumpAndSettle();

    expect(find.text('翻译').hitTestable(), findsOneWidget);
    expect(find.text('邮件中文翻译 122').hitTestable(), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('翻译')).dy,
      lessThan(tester.getTopLeft(find.text('小U摘要')).dy),
    );
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('邮件雷达列表不重复显示设置控件且记忆候选适配三档宽度', (tester) async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(uid: 120, category: MailRadarCategory.notice).copyWith(
          toolUses: const [
            MailRadarToolUse(name: 'approved_memory', status: 'used'),
          ],
          memorySuggestions: const [
            AssistantMemorySuggestion(content: '用户长期倾向软件开发方向。'),
          ],
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();
    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final width in [390.0, 900.0, 1440.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MailRadarView.analysisPreview(
              controller: controller,
              onOpenOriginal: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mail-radar-enabled-switch')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mail-radar-lookback-selector')),
        findsNothing,
      );
      expect(find.byType(MailMessageRow), findsOneWidget);
      await tester.tap(find.byType(MailMessageRow));
      await tester.pumpAndSettle();
      expect(
        find.text('忽略'),
        findsNothing,
      ); // candidate actions use accessible tooltips
      expect(find.byTooltip('忽略'), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('mail-radar-detail-modal'))),
      ).pop();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    controller.dispose();
  });

  testWidgets('尚未完成分析的邮件仍显示为带状态的普通邮件行', (tester) async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(uid: 17, category: MailRadarCategory.notice),
        _radarItem(
          uid: 16,
          category: MailRadarCategory.notice,
          analysisPending: true,
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
            onReply: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('等待分析'), findsOneWidget);
    expect(find.text('邮件 16'), findsOneWidget);
    expect(find.byType(MailMessageRow), findsNWidgets(2));
    controller.dispose();
  });

  test('等待分析状态可以保存并恢复', () {
    final pending = _radarItem(
      uid: 15,
      category: MailRadarCategory.notice,
      analysisPending: true,
    );

    final restored = MailRadarItem.fromJson(pending.toJson());

    expect(restored.analysisPending, isTrue);
  });

  testWidgets('邮件雷达收件时间固定按北京时间展示', (tester) async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 15,
          category: MailRadarCategory.notice,
          receivedAt: DateTime.utc(2026, 8, 9, 18),
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('8/10'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('雷达保留原邮件蓝点，打开分析详情不改变原邮件已读状态', (tester) async {
    final service = _RadarMailService(const []);
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(uid: 13, category: MailRadarCategory.notice, isUnread: true),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final indicator = find.byKey(const ValueKey('mail-unread-indicator-13'));
    expect(indicator, findsOneWidget);
    await tester.tap(find.text('邮件 13'));
    await tester.pumpAndSettle();
    expect(controller.items.single.originalIsSeen, isFalse);
    expect(controller.items.single.isUnread, isFalse);
    expect(service.seenUids, isEmpty);
    controller.dispose();
  });

  testWidgets('下一步外部链接经隐私确认后才打开', (tester) async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 14,
          category: MailRadarCategory.action,
          actionLinks: const [
            MailRadarActionLink(label: '前往报名', sourceIndex: 1),
          ],
        ),
      ];
    final service = _RadarMailService(
      [_summary(14, now)],
      bodies: const {14: '报名：https://forms.example.edu/register'},
    );
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();
    String? openedUrl;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
            onOpenExternalLink: (url) async => openedUrl = url,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('邮件 14'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('前往报名'));
    await tester.pumpAndSettle();

    expect(find.text('即将打开外部链接'), findsOneWidget);
    expect(find.textContaining('forms.example.edu'), findsOneWidget);
    expect(openedUrl, isNull);
    await tester.tap(find.text('确认打开'));
    await tester.pumpAndSettle();
    expect(openedUrl, 'https://forms.example.edu/register');
    controller.dispose();
  });

  testWidgets('中文及双语邮件详情不显示翻译区', (tester) async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 21,
          category: MailRadarCategory.notice,
          translationZh: '',
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('邮件 21'));
    await tester.pumpAndSettle();

    expect(find.text('小U摘要'), findsOneWidget);
    expect(find.text('翻译'), findsNothing);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('直接来信保留紧急程度并按时间展示', (tester) async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 61,
          category: MailRadarCategory.direct,
          priority: MailRadarPriority.low,
          role: MailRadarSenderRole.personal,
        ),
        _radarItem(
          uid: 62,
          category: MailRadarCategory.direct,
          priority: MailRadarPriority.urgent,
          role: MailRadarSenderRole.teacher,
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MailMessageRow), findsNWidgets(2));
    expect(find.text('低优先级'), findsNothing);
    expect(find.text('紧急'), findsOneWidget);
    final newer = tester.getTopLeft(find.text('邮件 62')).dy;
    final older = tester.getTopLeft(find.text('邮件 61')).dy;
    expect(newer, lessThan(older));
    controller.dispose();
  });

  testWidgets('撤回邮件详情不显示摘要和下一步', (tester) async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 71,
          category: MailRadarCategory.notice,
          isRecallNotice: true,
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
            onReply: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MailMessageRow), findsOneWidget);
    await tester.tap(find.text('邮件 71'));
    await tester.pumpAndSettle();

    expect(find.text('发件人已撤回'), findsWidgets);
    expect(find.text('小U摘要'), findsNothing);
    expect(find.text('下一步'), findsNothing);
    expect(find.text('截止时间'), findsNothing);
    expect(find.text('回复邮件'), findsNothing);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('二维码图片在邮件雷达详情中直接展示', (tester) async {
    final service = _ImageRadarMailService([_summary(82, now)]);
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 82,
          category: MailRadarCategory.notice,
          hasInlineImages: true,
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: service,
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();

    String? savedName;
    Uint8List? savedBytes;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
            onSaveAttachment: (name, bytes) async {
              savedName = name;
              savedBytes = bytes;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('邮件 82'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('QR Code.png'),
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('mail-radar-detail-modal')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('QR Code.png'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(service.downloadedPartIds, ['2']);
    expect(service.readMarkAsSeen, everyElement(isFalse));
    await tester.tap(find.text('保存图片'));
    await tester.pumpAndSettle();
    expect(savedName, 'QR Code.png');
    expect(savedBytes, isNotEmpty);
    await tester.scrollUntilVisible(
      find.text('报告.pdf'),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('mail-radar-detail-modal')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('报告.pdf'));
    await tester.pumpAndSettle();
    expect(savedName, '报告.pdf');
    expect(savedBytes, isNotEmpty);
    expect(service.downloadedPartIds, ['2', '3']);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('同一关联事项的每封邮件都在时间范围内的连续列表中展示', (tester) async {
    final store = _MemoryRadarStore(consented: true)
      ..items = [
        _radarItem(
          uid: 31,
          category: MailRadarCategory.notice,
          relatedThreadKey: 'same-event',
        ),
        _radarItem(
          uid: 30,
          category: MailRadarCategory.notice,
          relatedThreadKey: 'same-event',
        ),
      ];
    final controller = MailRadarController(
      username: 'student',
      credentials: credentials,
      mailService: _RadarMailService(const []),
      analyzer: _RadarAnalyzer(),
      store: store,
      now: () => now,
    );
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: MailRadarView.analysisPreview(
            controller: controller,
            onOpenOriginal: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MailMessageRow), findsNWidgets(2));
    expect(find.text('邮件 31'), findsOneWidget);
    expect(find.text('邮件 30'), findsOneWidget);
    controller.dispose();
  });
}

MailRadarItem _radarItem({
  required int uid,
  required MailRadarCategory category,
  MailRadarPriority priority = MailRadarPriority.normal,
  MailRadarSenderRole role = MailRadarSenderRole.department,
  String? translationZh,
  String? relatedThreadKey,
  bool isRecallNotice = false,
  bool hasInlineImages = false,
  bool isUnread = false,
  bool analysisPending = false,
  String analysisRequestId = '',
  String analysisContractVersion = mailRadarAnalysisContractVersion,
  DateTime? receivedAt,
  List<MailRadarActionLink> actionLinks = const [],
}) => MailRadarItem(
  key: '77_$uid',
  uid: uid,
  mailboxUidValidity: 77,
  subject: '邮件 $uid',
  sender: 'Sender $uid',
  receivedAt: receivedAt ?? DateTime(2026, 8, 9, uid),
  summaryZh: isRecallNotice ? '发件人已撤回' : '邮件摘要 $uid',
  translationZh: translationZh ?? '邮件中文翻译 $uid',
  priority: priority,
  category: category,
  senderRole: role,
  actionZh: '完成下一步',
  actionLinks: actionLinks,
  deadlineText: '8月10日 12:00',
  relatedThreadKey: relatedThreadKey ?? 'thread_$uid',
  attachmentNotes: const [],
  analyzedAt: DateTime(2026, 8, 9),
  isRecallNotice: isRecallNotice,
  hasInlineImages: hasInlineImages,
  isUnread: isUnread,
  analysisPending: analysisPending,
  analysisRequestId: analysisRequestId,
  analysisContractVersion: analysisContractVersion,
);

MailMessageSummary _summary(
  int uid,
  DateTime date, {
  bool hasAttachments = false,
}) => MailMessageSummary(
  uid: uid,
  subject: '邮件 $uid',
  sender: 'Sender <sender$uid@bnbu.edu.cn>',
  preview: 'preview',
  hasHtmlBody: false,
  date: date,
  isSeen: false,
  hasAttachments: hasAttachments,
  folder: MailFolder.inbox,
  mailboxUidValidity: 77,
);

class _RadarMailService extends MailService {
  _RadarMailService(this.messages, {this.bodies = const {}});
  final List<MailMessageSummary> messages;
  final Map<int, String> bodies;
  final List<bool> readMarkAsSeen = [];
  final List<int> seenUids = [];
  final List<int> fetchedPages = [];

  @override
  Future<MailFolderSnapshot> fetchFolder({
    required MailAccessCredentials credentials,
    MailFolder folder = MailFolder.inbox,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async {
    fetchedPages.add(page);
    final start = (page - 1) * pageSize;
    final end = (start + pageSize).clamp(0, messages.length);
    return MailFolderSnapshot(
      emailAddress: credentials.emailAddress,
      incomingServer: 'imap',
      outgoingServer: 'smtp',
      messages: start < messages.length
          ? messages.sublist(start, end)
          : const [],
      fetchedAt: DateTime.now(),
      folder: folder,
      totalMessages: messages.length,
      currentPage: page,
      pageSize: pageSize,
      mailboxUidValidity: 77,
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
    readMarkAsSeen.add(markAsSeen);
    final summary = messages.firstWhere((item) => item.uid == uid);
    return MailMessageDetail(
      uid: uid,
      subject: summary.subject,
      sender: summary.sender,
      recipients: credentials.emailAddress,
      cc: null,
      date: summary.date,
      body: bodies[uid] ?? 'body',
      htmlBody: null,
      isSeen: false,
      mailboxUidValidity: 77,
      folder: folder,
    );
  }

  @override
  Future<void> markMessagesSeen({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async => seenUids.addAll(uids);

  @override
  Future<void> close() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ImageRadarMailService extends _RadarMailService {
  _ImageRadarMailService(super.messages);

  final List<String> downloadedPartIds = [];

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) async {
    readMarkAsSeen.add(markAsSeen);
    final summary = messages.firstWhere((item) => item.uid == uid);
    return MailMessageDetail(
      uid: uid,
      subject: summary.subject,
      sender: summary.sender,
      recipients: credentials.emailAddress,
      cc: null,
      date: summary.date,
      body: 'body',
      htmlBody: null,
      isSeen: false,
      mailboxUidValidity: 77,
      folder: folder,
      attachments: const [
        MailAttachment(
          name: 'QR Code.png',
          size: 68,
          mimeType: 'image/png',
          partId: '2',
        ),
        MailAttachment(
          name: '报告.pdf',
          size: 68,
          mimeType: 'application/pdf',
          partId: '3',
        ),
      ],
    );
  }

  @override
  Future<List<int>> downloadAttachment({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    required String partId,
    int? expectedMailboxUidValidity,
  }) async {
    downloadedPartIds.add(partId);
    return base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
  }
}

class _RadarAnalyzer implements MailRadarAnalyzer {
  _RadarAnalyzer({String Function()? analysisLanguageTagProvider})
    : _analysisLanguageTagProvider =
          analysisLanguageTagProvider ?? _defaultAnalysisLanguageTag;

  int calls = 0;
  final Map<int, List<String>> requestIds = {};
  final String Function() _analysisLanguageTagProvider;

  static String _defaultAnalysisLanguageTag() => 'zh-Hans';

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    calls++;
    requestIds.putIfAbsent(summary.uid, () => []).add(clientRequestId);
    return MailRadarItem(
      key: '77_${summary.uid}',
      uid: summary.uid,
      mailboxUidValidity: 77,
      subject: summary.subject,
      sender: summary.sender,
      receivedAt: summary.date!,
      summaryZh: '摘要',
      translationZh: '翻译',
      priority: MailRadarPriority.normal,
      category: MailRadarCategory.notice,
      senderRole: MailRadarSenderRole.department,
      actionZh: '',
      deadlineText: '',
      relatedThreadKey: 'mail_${summary.uid}',
      attachmentNotes: const [],
      analyzedAt: DateTime(2026, 8, 9),
      analysisLanguageTag: _analysisLanguageTagProvider(),
    );
  }
}

class _NewRequestOnceRadarAnalyzer extends _RadarAnalyzer {
  var failed = false;

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) {
    if (!failed) {
      failed = true;
      calls++;
      requestIds.putIfAbsent(summary.uid, () => []).add(clientRequestId);
      throw const AiAssistantMailRadarNewRequestRequiredException();
    }
    return super.analyze(
      clientRequestId: clientRequestId,
      username: username,
      credentials: credentials,
      summary: summary,
      detail: detail,
      mailService: mailService,
      isOperationActive: isOperationActive,
    );
  }
}

class _AlwaysNewRequestRadarAnalyzer extends _RadarAnalyzer {
  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) {
    calls++;
    requestIds.putIfAbsent(summary.uid, () => []).add(clientRequestId);
    throw const AiAssistantMailRadarNewRequestRequiredException();
  }
}

class _UnavailableRadarAnalyzer extends _RadarAnalyzer {
  _UnavailableRadarAnalyzer({this.accountStopped = false});
  final bool accountStopped;
  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) {
    throw AiAssistantMailRadarUnavailableException(
      stoppedByPreference: accountStopped,
    );
  }
}

class _BlockingFirstRadarAnalyzer extends _RadarAnalyzer {
  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    if (summary.uid == 42) {
      await Completer<void>().future;
    }
    return super.analyze(
      clientRequestId: clientRequestId,
      username: username,
      credentials: credentials,
      summary: summary,
      detail: detail,
      mailService: mailService,
      isOperationActive: isOperationActive,
    );
  }
}

class _ControllableSlowRadarAnalyzer extends _RadarAnalyzer {
  final Completer<void> releaseSlowMail = Completer<void>();
  final Completer<void> fastMailCompleted = Completer<void>();

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    if (summary.uid == 42) {
      await releaseSlowMail.future;
    }
    final item = await super.analyze(
      clientRequestId: clientRequestId,
      username: username,
      credentials: credentials,
      summary: summary,
      detail: detail,
      mailService: mailService,
      isOperationActive: isOperationActive,
    );
    if (summary.uid == 41 && !fastMailCompleted.isCompleted) {
      fastMailCompleted.complete();
    }
    return item;
  }
}

class _ConcurrencyRadarAnalyzer extends _RadarAnalyzer {
  final Completer<void> fourStarted = Completer<void>();
  final Completer<void> release = Completer<void>();
  int active = 0;
  int started = 0;
  int maximumActive = 0;

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    started++;
    active++;
    if (active > maximumActive) maximumActive = active;
    if (started == MailRadarController.maxConcurrentAnalyses &&
        !fourStarted.isCompleted) {
      fourStarted.complete();
    }
    await release.future;
    final item = await super.analyze(
      clientRequestId: clientRequestId,
      username: username,
      credentials: credentials,
      summary: summary,
      detail: detail,
      mailService: mailService,
      isOperationActive: isOperationActive,
    );
    active--;
    return item;
  }
}

class _PriorityOrderRadarAnalyzer extends _RadarAnalyzer {
  final Completer<void> fourStarted = Completer<void>();
  final Completer<void> release = Completer<void>();
  final List<int> startedUids = [];

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    startedUids.add(summary.uid);
    if (startedUids.length == MailRadarController.maxConcurrentAnalyses &&
        !fourStarted.isCompleted) {
      fourStarted.complete();
    }
    await release.future;
    return super.analyze(
      clientRequestId: clientRequestId,
      username: username,
      credentials: credentials,
      summary: summary,
      detail: detail,
      mailService: mailService,
      isOperationActive: isOperationActive,
    );
  }
}

class _ParallelAttachmentProcessor extends MailRadarAttachmentProcessor {
  final Completer<void> twoStarted = Completer<void>();
  final Completer<void> release = Completer<void>();
  int active = 0;
  int started = 0;
  int maximumActive = 0;

  @override
  Future<MailRadarPreparedAttachment> prepare({
    required MailAccessCredentials credentials,
    required MailMessageDetail message,
    required MailAttachment attachment,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    started++;
    active++;
    if (active > maximumActive) maximumActive = active;
    if (started == SmallUMailRadarAnalyzer.maxConcurrentAttachmentAnalyses &&
        !twoStarted.isCompleted) {
      twoStarted.complete();
    }
    await release.future;
    active--;
    return MailRadarPreparedAttachment(
      name: attachment.name,
      text: '${attachment.name} 的测试正文',
    );
  }
}

class _TimeoutOnceRadarAnalyzer extends _RadarAnalyzer {
  final Map<int, int> attempts = {};

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    final attempt = attempts.update(
      summary.uid,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    if (summary.uid == 52 && attempt == 1) {
      await Completer<void>().future;
    }
    return super.analyze(
      clientRequestId: clientRequestId,
      username: username,
      credentials: credentials,
      summary: summary,
      detail: detail,
      mailService: mailService,
      isOperationActive: isOperationActive,
    );
  }
}

class _HeldRetryRadarAnalyzer extends _RadarAnalyzer {
  final Map<int, int> attempts = {};
  final Completer<void> retryPassStarted = Completer<void>();
  final Completer<void> releaseRetryPass = Completer<void>();
  int retrying = 0;

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    final attempt = attempts.update(
      summary.uid,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    if (attempt == 1) {
      throw const AiAssistantChatNetworkException('临时失败');
    }
    retrying++;
    if (retrying == 2 && !retryPassStarted.isCompleted) {
      retryPassStarted.complete();
    }
    await releaseRetryPass.future;
    return super.analyze(
      clientRequestId: clientRequestId,
      username: username,
      credentials: credentials,
      summary: summary,
      detail: detail,
      mailService: mailService,
      isOperationActive: isOperationActive,
    );
  }
}

class _FailOnceRadarAnalyzer extends _RadarAnalyzer {
  int attempts = 0;

  @override
  Future<MailRadarItem> analyze({
    required String clientRequestId,
    required String username,
    required MailAccessCredentials credentials,
    required MailMessageSummary summary,
    required MailMessageDetail detail,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    attempts++;
    if (attempts == 1) {
      throw const AiAssistantChatNetworkException('小U连接暂时中断。');
    }
    return super.analyze(
      clientRequestId: clientRequestId,
      username: username,
      credentials: credentials,
      summary: summary,
      detail: detail,
      mailService: mailService,
      isOperationActive: isOperationActive,
    );
  }
}

class _MemoryRadarStore implements MailRadarStore {
  _MemoryRadarStore({required this.consented});
  bool consented;
  bool enabled = true;
  int lookbackDays = mailRadarDefaultLookbackDays;
  List<MailRadarItem> items = [];

  @override
  Future<MailRadarPreferences> loadPreferences(String username) async =>
      MailRadarPreferences(
        hasConsent: consented,
        enabled: consented && enabled,
        lookbackDays: lookbackDays,
      );

  @override
  Future<void> grantConsent(String username) async {
    consented = true;
    enabled = true;
  }

  @override
  Future<bool> hasConsent(String username) async => consented;

  @override
  Future<void> setEnabled(String username, bool value) async => enabled = value;

  @override
  Future<void> setLookbackDays(String username, int days) async =>
      lookbackDays = days;

  @override
  Future<void> revokeConsent(String username) async {
    consented = false;
    enabled = false;
  }

  @override
  Future<List<MailRadarItem>> load(String username) async => List.of(items);

  @override
  Future<void> save(String username, List<MailRadarItem> items) async {
    this.items = List.of(items);
  }
}

class _MemoryRadarSyncService implements AiAssistantMailRadarSyncService {
  _MemoryRadarSyncService({this.conflictOnceWith});

  final List<MailRadarItem>? conflictOnceWith;
  int version = 0;
  List<MailRadarItem> items = [];
  bool _didConflict = false;

  @override
  Future<MailRadarSnapshot> loadMailRadar(String username) async =>
      MailRadarSnapshot(version: version, items: List.of(items));

  @override
  Future<MailRadarSnapshot> saveMailRadar(
    String username, {
    required int expectedVersion,
    required List<MailRadarItem> items,
  }) async {
    if (!_didConflict && conflictOnceWith != null) {
      _didConflict = true;
      version++;
      this.items = List.of(conflictOnceWith!);
      throw AiAssistantMailRadarConflictException(currentVersion: version);
    }
    if (expectedVersion != version) {
      throw AiAssistantMailRadarConflictException(currentVersion: version);
    }
    version++;
    this.items = List.of(items);
    return MailRadarSnapshot(version: version, items: List.of(this.items));
  }
}

class _UnavailableRadarSyncService implements AiAssistantMailRadarSyncService {
  @override
  Future<MailRadarSnapshot> loadMailRadar(String username) {
    throw const AiAssistantMailRadarUnavailableException();
  }

  @override
  Future<MailRadarSnapshot> saveMailRadar(
    String username, {
    required int expectedVersion,
    required List<MailRadarItem> items,
  }) {
    throw const AiAssistantMailRadarUnavailableException();
  }
}

class _RadarAssistantService
    implements
        AiAssistantService,
        AiAssistantAttachmentService,
        AiAssistantMailRadarService {
  _RadarAssistantService({
    this.answer =
        '''{"summary_zh":"老师邀请面谈。","content_language":"other","needs_translation":true,"translation_zh":"请在下午三点前往办公室。","priority":"high","category":"action","is_direct_correspondence":true,"sender_role":"teacher","action_zh":"下午三点前往办公室","deadline_text":"下午三点","related_thread_key":"office-hour"}''',
    this.toolUses = const [],
    this.memorySuggestions = const [],
    this.acceptedClientRequestId,
  });

  final String answer;
  final List<MailRadarToolUse> toolUses;
  final List<AssistantMemorySuggestion> memorySuggestions;
  final String? acceptedClientRequestId;
  AssistantContextPayload? lastContext;
  String? lastMessage;
  List<AssistantInputAttachment> lastAttachments = const [];
  int chatCalls = 0;
  int attachmentChatCalls = 0;
  MailRadarRemoteRequest? lastRadarRequest;

  @override
  Future<bool> isEnabled(String username) async => true;

  @override
  Future<AssistantChatResult> chat({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required AssistantContextPayload context,
    String? clientRequestId,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    chatCalls++;
    lastMessage = message;
    lastContext = context;
    return _result();
  }

  @override
  Future<AssistantChatResult> chatWithAttachments({
    required String username,
    required String message,
    required List<AssistantConversationMessage> history,
    required AssistantContextPayload context,
    required List<AssistantInputAttachment> attachments,
    String? clientRequestId,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    attachmentChatCalls++;
    lastMessage = message;
    lastContext = context;
    lastAttachments = attachments;
    return _result();
  }

  @override
  Future<MailRadarRemoteAnalysis> analyzeMailRadar({
    required String username,
    required MailRadarRemoteRequest request,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    lastRadarRequest = request;
    lastMessage = jsonEncode({
      'body_excerpt': request.bodyExcerpt,
      'source_links': request.sourceLinks,
      'attachment_context': request.attachmentContext,
    });
    lastAttachments = request.attachments;
    attachmentChatCalls++;
    lastContext = AssistantContextPayload(
      sources: const {AssistantContextSource.selectedMail},
      selectedMail: AssistantSelectedMailContext(
        uid: request.uid,
        folder: 'inbox',
        mailboxUidValidity: request.mailboxUidValidity,
        senderName: request.senderName,
        senderEmail: request.senderEmail,
        subject: request.subject,
        receivedAt: request.receivedAt,
        bodyExcerpt: request.bodyExcerpt,
      ),
    );
    final result = jsonDecode(_resolvedAnswer()) as Map<String, dynamic>;
    return MailRadarRemoteAnalysis(
      clientRequestId: acceptedClientRequestId ?? request.clientRequestId,
      result: result,
      toolUses: toolUses,
      memorySuggestions: memorySuggestions,
    );
  }

  AssistantChatResult _result() {
    final resolvedAnswer = _resolvedAnswer();
    return AssistantChatResult(
      requestId: 'radar-test',
      answer: resolvedAnswer,
      actions: const [],
      usage: const AssistantTokenUsage(
        inputTokens: 1,
        outputTokens: 1,
        totalTokens: 2,
      ),
      quota: AssistantQuota(
        periodStart: DateTime(2026, 8, 1),
        periodEnd: DateTime(2026, 9, 1),
        monthlyQuotaTokens: 100,
        creditBalanceTokens: 0,
        usedTokens: 2,
        reservedTokens: 0,
        remainingTokens: 98,
      ),
    );
  }

  String _resolvedAnswer() => answer.contains('"attachment_notes"')
      ? answer
      : answer.replaceFirst(
          '"related_thread_key":"office-hour"',
          '"related_thread_key":"office-hour","attachment_notes":['
              '{"name":"第一份.pdf","summary_zh":"附件摘要"},'
              '{"name":"第二份.pdf","summary_zh":"附件摘要"},'
              '{"name":"第三份.pdf","summary_zh":"附件摘要"}]',
        );

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BudgetAttachmentProcessor extends MailRadarAttachmentProcessor {
  int count = 0;
  @override
  Future<MailRadarPreparedAttachment> prepare({
    required MailAccessCredentials credentials,
    required MailMessageDetail message,
    required MailAttachment attachment,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    count++;
    return MailRadarPreparedAttachment(
      name: attachment.name,
      text: 'x' * 12000,
    );
  }
}
