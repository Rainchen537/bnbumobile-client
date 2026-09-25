import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/config/app_config.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/models/campus_landmark.dart';
import 'package:bnbu_me/services/campus_landmark_store.dart';
import 'package:bnbu_me/services/prepared_assistant_action.dart';
import 'package:bnbu_me/models/course_summary.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/models/moodle_module_access.dart';
import 'package:bnbu_me/models/quiz_attempt_data.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timeline_detail_data.dart';
import 'package:bnbu_me/models/timeline_item.dart';
import 'package:bnbu_me/models/upload_file_payload.dart';
import 'package:bnbu_me/pages/course_detail_page.dart';
import 'package:bnbu_me/pages/mail_page.dart';
import 'package:bnbu_me/pages/official_web_page.dart';
import 'package:bnbu_me/pages/leave_application_page.dart';
import 'package:bnbu_me/pages/ta_course_manager_page.dart';
import 'package:bnbu_me/pages/timeline_detail_page.dart';
import 'package:bnbu_me/services/ai_assistant_action_executor.dart';
import 'package:bnbu_me/services/assistant_action_runtime.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/mail_assistant_intent_controller.dart';
import 'package:bnbu_me/state/root_shell_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'ME Life navigation refreshes and rejects deleted or unavailable entries',
    (tester) async {
      final store = _MeLifeStore();
      addTearDown(store.dispose);
      final harness = await _pumpHarness(tester, meLifeStore: store);
      addTearDown(harness.dispose);
      final action = _action(
        AssistantActionType.openMeLifeEntry,
        targetId: 'library',
      );
      final prepared = await harness.executor.prepare(action);
      expect(prepared.handoffKind, AssistantActionHandoffKind.meLifeEntry);
      expect(store.reads, 1);
      store.present = false;
      await expectLater(
        harness.executor.prepare(action),
        throwsA(isA<AiAssistantActionException>()),
      );
      store.present = true;
      store.unavailable = true;
      await expectLater(
        harness.executor.prepare(action),
        throwsA(isA<AiAssistantActionException>()),
      );
      final count = store.reads;
      await expectLater(
        harness.executor.prepare(
          _action(
            AssistantActionType.openMeLifeEntry,
            targetId: 'library',
            url: 'https://source.example/api',
          ),
        ),
        throwsA(isA<AiAssistantActionException>()),
      );
      expect(store.reads, count);
    },
  );

  testWidgets(
    'rejects non-BNBU compose recipients before loading mail access',
    (tester) async {
      final harness = await _pumpHarness(tester);
      addTearDown(harness.dispose);

      for (final recipient in ['attacker@example.com', '@bnbu.edu.cn']) {
        await expectLater(
          harness.executor.execute(
            _action(
              AssistantActionType.composeEmail,
              recipient: recipient,
              subject: 'Subject',
              body: 'Body',
            ),
            userConfirmed: true,
          ),
          throwsA(
            isA<AiAssistantActionException>().having(
              (error) => error.message,
              'message',
              contains('BNBU 官方邮箱'),
            ),
          ),
        );
      }

      expect(harness.controller.mailCredentialLoads, 0);
    },
  );

  testWidgets('sets a confirmed Small U notification on the device', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);
    final scheduledAt = DateTime.now().add(const Duration(hours: 2));

    await harness.executor.execute(
      _action(
        AssistantActionType.scheduleNotification,
        notificationTitle: '带校园卡',
        notificationBody: '出门前记得带校园卡。',
        notificationAt: scheduledAt,
      ),
      userConfirmed: true,
    );
    await tester.pump();

    expect(harness.controller.reminderTitle, '带校园卡');
    expect(harness.controller.reminderBody, '出门前记得带校园卡。');
    expect(harness.controller.reminderAt, scheduledAt);
    expect(find.text('提醒已设置'), findsOneWidget);
  });

  testWidgets('rejects non-BNBU pages before invoking native actions', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);

    await expectLater(
      harness.executor.execute(
        _action(
          AssistantActionType.openPage,
          url: 'https://bnbu.edu.cn.evil.example/path',
        ),
      ),
      throwsA(
        isA<AiAssistantActionException>().having(
          (error) => error.message,
          'message',
          contains('BNBU 官方 HTTPS 页面'),
        ),
      ),
    );
  });

  testWidgets('opens valid BNBU pages inside the app', (tester) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);

    final execution = harness.executor.execute(
      _action(
        AssistantActionType.openPage,
        url: 'https://www.bnbu.edu.cn/campus_life/Campus_Map.htm',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(OfficialWebPage), findsOneWidget);
    expect(find.text('Test action'), findsOneWidget);

    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await execution;
  });

  testWidgets('Small U leave handoff uses the dedicated form route', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);
    harness.rootShellController.selectTab(AppTab.mail);
    final execution = harness.executor.execute(
      _action(AssistantActionType.openCampusPage, targetId: 'leave'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(LeaveApplicationPage), findsOneWidget);
    final page = tester.widget<LeaveApplicationPage>(
      find.byType(LeaveApplicationPage),
    );
    expect(page.controller, same(harness.controller));
    expect(page.onReturnHome, isNotNull);
    page.onReturnHome!();
    expect(harness.rootShellController.selectedTab, AppTab.home);
    expect(find.byType(OfficialWebPage), findsNothing);
    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await execution;
  });

  testWidgets('rejects assignment and course IDs absent from current session', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);

    await expectLater(
      harness.executor.execute(
        _action(AssistantActionType.openAssignment, targetId: '404'),
      ),
      throwsA(
        isA<AiAssistantActionException>().having(
          (error) => error.message,
          'message',
          contains('没有找到对应的 DDL 或作业'),
        ),
      ),
    );
    await expectLater(
      harness.executor.execute(
        _action(AssistantActionType.openCourse, targetId: '404'),
      ),
      throwsA(
        isA<AiAssistantActionException>().having(
          (error) => error.message,
          'message',
          contains('没有找到对应课程'),
        ),
      ),
    );
  });

  testWidgets('side-effect actions require explicit user confirmation', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);

    await expectLater(
      harness.executor.execute(
        _action(
          AssistantActionType.composeEmail,
          recipient: 'teacher@bnbu.edu.cn',
          subject: 'Subject',
          body: 'Body',
        ),
      ),
      throwsA(
        isA<AiAssistantActionException>().having(
          (error) => error.message,
          'message',
          contains('必须先由用户确认'),
        ),
      ),
    );
    await expectLater(
      harness.executor.execute(
        _action(
          AssistantActionType.submitAssignment,
          targetId: '7',
          body: 'Answer',
          requiresConfirmation: false,
        ),
        userConfirmed: true,
      ),
      throwsA(isA<AiAssistantActionException>()),
    );
    await expectLater(
      harness.executor.execute(
        _action(
          AssistantActionType.openMail,
          requiresConfirmation: true,
          mailUid: 17,
          mailFolder: 'inbox',
          mailboxUidValidity: 9001,
        ),
      ),
      throwsA(isA<AiAssistantActionException>()),
    );
    await expectLater(
      harness.executor.execute(
        _action(
          AssistantActionType.prepareCoursePack,
          targetId: '42',
          requiresConfirmation: false,
        ),
        userConfirmed: true,
      ),
      throwsA(isA<AiAssistantActionException>()),
    );

    expect(harness.controller.mailCredentialLoads, 0);
  });

  testWidgets('reply keeps the original thread and AI body without sending', (
    tester,
  ) async {
    const original = MailMessageDetail(
      uid: 17,
      folder: MailFolder.inbox,
      mailboxUidValidity: 9001,
      subject: 'Original question',
      sender: 'friend@example.test',
      recipients: 'student01@mail.bnbu.edu.cn',
      cc: null,
      date: null,
      body: 'Original body',
      htmlBody: null,
      isSeen: false,
      messageId: '<original@example.test>',
    );
    final harness = await _pumpHarness(
      tester,
      credentials: const MailAccessCredentials(
        userId: 'student01',
        emailAddress: 'student01@mail.bnbu.edu.cn',
        password: 'synthetic-password',
      ),
      mailDetail: original,
    );
    addTearDown(harness.dispose);
    final action = _action(
      AssistantActionType.composeEmail,
      recipient: 'friend@example.test',
      subject: 'Re: Original question',
      body: 'Prepared reply',
      mailUid: 17,
      mailFolder: 'inbox',
      mailboxUidValidity: 9001,
    );
    final execution = harness.executor.execute(action, userConfirmed: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final page = tester.widget<ComposeMailPage>(find.byType(ComposeMailPage));
    expect(page.replyTo!.messageId, '<original@example.test>');
    expect(find.widgetWithText(TextField, 'Prepared reply'), findsOneWidget);
    expect(harness.mailService.sendCalls, 0);
    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await execution;
  });

  testWidgets(
    'Small U forward preserves safe rich original content above its prepared text',
    (tester) async {
      final original = MailMessageDetail(
        uid: 17,
        folder: MailFolder.inbox,
        mailboxUidValidity: 9001,
        subject: '原始课程安排',
        sender: 'Teacher <teacher@bnbu.edu.cn>',
        recipients: 'student01@mail.bnbu.edu.cn',
        cc: null,
        date: DateTime.utc(2026, 9, 6, 9, 30),
        body: '原始纯文本',
        htmlBody:
            '<table><tbody><tr><th>课程</th><td>数据结构</td></tr></tbody></table>'
            '<script>ignored()</script>',
        isSeen: true,
      );
      final harness = await _pumpHarness(
        tester,
        credentials: const MailAccessCredentials(
          userId: 'student01',
          emailAddress: 'student01@mail.bnbu.edu.cn',
          password: 'synthetic-password',
        ),
        mailDetail: original,
      );
      addTearDown(harness.dispose);

      final execution = harness.executor.execute(
        _action(
          AssistantActionType.composeEmail,
          mailMode: 'forward',
          recipient: 'destination@bnbu.edu.cn',
          subject: 'Fwd: 原始课程安排',
          body: '请协助转发 <草稿>',
          mailUid: 17,
          mailFolder: 'inbox',
          mailboxUidValidity: 9001,
        ),
        userConfirmed: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final page = tester.widget<ComposeMailPage>(find.byType(ComposeMailPage));
      expect(page.initialBody, startsWith('请协助转发 <草稿>'));
      expect(page.initialBody, contains('---------- 转发的邮件 ----------'));
      expect(page.initialHtmlBody, contains('<table>'));
      expect(page.initialHtmlBody, contains('<th>课程</th>'));
      expect(page.initialHtmlBody, contains('&lt;草稿&gt;'));
      expect(page.initialHtmlBody, isNot(contains('<script')));
      expect(harness.mailService.sendCalls, 0);

      harness.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await execution;
    },
  );

  testWidgets(
    'confirmed compose action opens a prefilled native compose page',
    (tester) async {
      final harness = await _pumpHarness(
        tester,
        credentials: const MailAccessCredentials(
          userId: 'student01',
          emailAddress: 'student01@mail.bnbu.edu.cn',
          password: 'fake-test-password',
        ),
      );
      addTearDown(harness.dispose);

      final execution = harness.executor.execute(
        _action(
          AssistantActionType.composeEmail,
          recipient: 'Teacher@BNBU.EDU.CN',
          subject: 'Course question',
          body: 'Dear teacher,',
        ),
        userConfirmed: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(harness.mailService.sendCalls, 0);
      expect(find.byType(ComposeMailPage), findsOneWidget);
      expect(
        find.widgetWithText(InputChip, 'teacher@bnbu.edu.cn'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextField, 'Course question'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Dear teacher,'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('assistant-review-frame')),
        findsOneWidget,
      );
      expect(harness.mailService.closed, isFalse);

      harness.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await execution;
      expect(
        find.byKey(const ValueKey('assistant-review-frame')),
        findsNothing,
      );
      expect(harness.mailService.sendCalls, 0);
      expect(harness.mailService.saveDraftCalls, 0);
      expect(harness.mailService.closed, isTrue);
    },
  );

  testWidgets('open mail rejects incomplete stable identity', (tester) async {
    final harness = await _pumpHarness(
      tester,
      credentials: const MailAccessCredentials(
        userId: 'student01',
        emailAddress: 'student01@mail.bnbu.edu.cn',
        password: 'fake-test-password',
      ),
    );
    addTearDown(harness.dispose);

    await expectLater(
      harness.executor.execute(
        _action(AssistantActionType.openMail, mailUid: 17, mailFolder: 'inbox'),
      ),
      throwsA(
        isA<AiAssistantActionException>().having(
          (error) => error.message,
          'message',
          contains('邮件引用已失效'),
        ),
      ),
    );

    expect(harness.controller.mailCredentialLoads, 0);
    expect(harness.mailService.readCalls, 0);
  });

  testWidgets('open mail validates UIDVALIDITY and opens detail in app', (
    tester,
  ) async {
    final detail = MailMessageDetail(
      uid: 17,
      subject: 'Course update',
      sender: 'Teacher <teacher@bnbu.edu.cn>',
      recipients: 'student01@mail.bnbu.edu.cn',
      cc: null,
      date: DateTime.utc(2026, 7, 22),
      body: 'Please read the update.',
      htmlBody: null,
      isSeen: true,
      mailboxUidValidity: 9001,
      folder: MailFolder.inbox,
    );
    final harness = await _pumpHarness(
      tester,
      credentials: const MailAccessCredentials(
        userId: 'student01',
        emailAddress: 'student01@mail.bnbu.edu.cn',
        password: 'fake-test-password',
      ),
      mailDetail: detail,
    );
    addTearDown(harness.dispose);

    final execution = harness.executor.execute(
      _action(
        AssistantActionType.openMail,
        mailUid: 17,
        mailFolder: 'inbox',
        mailboxUidValidity: 9001,
      ),
    );
    await tester.pumpAndSettle();

    expect(harness.mailService.readCalls, 1);
    expect(harness.mailService.lastReadFolder, MailFolder.inbox);
    expect(harness.mailService.lastReadUid, 17);
    expect(harness.mailService.lastExpectedUidValidity, 9001);
    expect(find.byType(MailDetailPage), findsOneWidget);
    expect(find.text('Course update'), findsOneWidget);
    expect(harness.mailService.closed, isFalse);

    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await execution;
    expect(harness.mailService.closed, isTrue);
  });

  testWidgets('open mail stops when the login session changes during read', (
    tester,
  ) async {
    final readCompleter = Completer<MailMessageDetail>();
    final harness = await _pumpHarness(
      tester,
      credentials: const MailAccessCredentials(
        userId: 'student01',
        emailAddress: 'student01@mail.bnbu.edu.cn',
        password: 'fake-test-password',
      ),
      mailReadCompleter: readCompleter,
    );
    addTearDown(harness.dispose);

    final execution = harness.executor.execute(
      _action(
        AssistantActionType.openMail,
        mailUid: 17,
        mailFolder: 'inbox',
        mailboxUidValidity: 9001,
      ),
    );
    await tester.pump();
    expect(harness.mailService.readCalls, 1);

    harness.controller.sessionActive = false;
    readCompleter.complete(_mailDetail());
    await tester.pumpAndSettle();
    await execution;

    expect(find.byType(MailDetailPage), findsNothing);
    expect(harness.mailService.closed, isTrue);
  });

  testWidgets('open mail continues after root handoff starts', (tester) async {
    final readCompleter = Completer<MailMessageDetail>();
    var handoffs = 0;
    final harness = await _pumpHarness(
      tester,
      credentials: const MailAccessCredentials(
        userId: 'student01',
        emailAddress: 'student01@mail.bnbu.edu.cn',
        password: 'fake-test-password',
      ),
      mailReadCompleter: readCompleter,
      beforeNavigation: () async {
        handoffs++;
      },
    );
    addTearDown(harness.dispose);

    final execution = harness.executor.execute(
      _action(
        AssistantActionType.openMail,
        mailUid: 17,
        mailFolder: 'inbox',
        mailboxUidValidity: 9001,
      ),
    );
    await tester.pump();
    expect(handoffs, 1);
    expect(harness.mailService.readCalls, 1);

    readCompleter.complete(_mailDetail());
    await tester.pumpAndSettle();
    expect(find.byType(MailDetailPage), findsOneWidget);

    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await execution;
    expect(harness.mailService.closed, isTrue);
  });

  testWidgets(
    'confirmed assignment action opens prefilled native detail page',
    (tester) async {
      final item = _timelineItem();
      final detail = TimelineDetailData(
        item: item,
        type: TimelineDetailType.assignment,
        assignmentId: 70,
        canEditSubmission: true,
        supportsOnlineTextSubmission: true,
      );
      final harness = await _pumpHarness(
        tester,
        timelineItems: [item],
        timelineDetail: detail,
      );
      addTearDown(harness.dispose);

      final execution = harness.executor.execute(
        _action(
          AssistantActionType.submitAssignment,
          targetId: '7',
          targetIdentity: AssistantActionRuntime.timelineIdentity(item),
          body: 'Edited answer',
        ),
        userConfirmed: true,
      );
      await tester.pumpAndSettle();

      expect(harness.controller.detailLoads, 1);
      expect(harness.controller.submittedAssignmentId, isNull);
      expect(harness.controller.submittedText, isNull);
      expect(find.byType(TimelineDetailPage), findsOneWidget);
      expect(find.text('Lab assignment'), findsOneWidget);

      await tester.tap(find.text('在线文本提交'));
      await tester.pumpAndSettle();
      expect(find.text('Edited answer'), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(harness.controller.submittedAssignmentId, isNull);
      expect(harness.controller.submittedText, isNull);

      harness.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await execution;
    },
  );

  testWidgets('open app tab selects the existing root tab without pushing', (
    tester,
  ) async {
    var handoffs = 0;
    final harness = await _pumpHarness(
      tester,
      beforeNavigation: () async {
        handoffs++;
      },
    );
    addTearDown(harness.dispose);

    await harness.executor.execute(
      _action(AssistantActionType.openAppTab, targetId: 'schedule'),
    );

    expect(handoffs, 1);
    expect(harness.rootShellController.selectedTab, AppTab.schedule);
    expect(find.text('Home'), findsOneWidget);
    expect(find.byType(TimelineDetailPage), findsNothing);

    await expectLater(
      harness.executor.execute(
        _action(AssistantActionType.openAppTab, targetId: 'admin'),
      ),
      throwsA(
        isA<AiAssistantActionException>().having(
          (error) => error.message,
          'message',
          contains('无效的应用页面'),
        ),
      ),
    );
  });

  testWidgets(
    'official system actions ignore provider URLs and use fixed targets',
    (tester) async {
      final harness = await _pumpHarness(tester);
      addTearDown(harness.dispose);

      for (final testCase in [
        (
          targetId: 'portal',
          expectedTitle: 'BNBU Portal',
          expectedUrl: AppConfig.bnbuPortalBaseUrl,
        ),
        (
          targetId: 'mis',
          expectedTitle: 'BNBU MIS',
          expectedUrl: AppConfig.bnbuMisBaseUrl,
        ),
      ]) {
        final prepared = await harness.executor.prepare(
          _action(
            AssistantActionType.openOfficialSystem,
            targetId: testCase.targetId,
            url: 'https://attacker.example/',
          ),
        );

        expect(prepared.officialTitle, testCase.expectedTitle);
        expect(prepared.officialUri.toString(), testCase.expectedUrl);
      }
    },
  );

  testWidgets('mail delete and restore publish one-shot native intents', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);

    await harness.executor.execute(
      _action(
        AssistantActionType.deleteMail,
        mailUid: 17,
        mailFolder: 'inbox',
        mailboxUidValidity: 9001,
      ),
      userConfirmed: true,
    );
    expect(harness.rootShellController.selectedTab, AppTab.mail);
    final deleteIntent = harness.mailIntentController.takePendingIntent();
    expect(deleteIntent, isNotNull);
    expect(deleteIntent!.kind, AssistantMailIntentKind.delete);
    expect(deleteIntent.folder, MailFolder.inbox);
    expect(deleteIntent.uid, 17);
    expect(deleteIntent.mailboxUidValidity, 9001);
    expect(harness.mailIntentController.takePendingIntent(), isNull);

    await harness.executor.execute(
      _action(
        AssistantActionType.restoreMail,
        mailUid: 18,
        mailFolder: 'trash',
        mailboxUidValidity: 9002,
      ),
      userConfirmed: true,
    );
    final restoreIntent = harness.mailIntentController.takePendingIntent();
    expect(restoreIntent, isNotNull);
    expect(restoreIntent!.kind, AssistantMailIntentKind.restore);
    expect(restoreIntent.folder, MailFolder.trash);
    expect(restoreIntent.uid, 18);
    expect(restoreIntent.mailboxUidValidity, 9002);
  });

  testWidgets(
    'attachment handoff rejects stale identity and changed live name',
    (tester) async {
      final detail = MailMessageDetail(
        uid: 17,
        subject: 'Course update',
        sender: 'Teacher <teacher@bnbu.edu.cn>',
        recipients: 'student01@mail.bnbu.edu.cn',
        cc: null,
        date: DateTime.utc(2026, 7, 22),
        body: 'Please read the attachment.',
        htmlBody: null,
        isSeen: true,
        attachments: const [
          MailAttachment(
            name: 'renamed-report.pdf',
            size: 2048,
            mimeType: 'application/pdf',
            partId: '2.1',
          ),
        ],
        mailboxUidValidity: 9001,
        folder: MailFolder.inbox,
      );
      final harness = await _pumpHarness(
        tester,
        credentials: const MailAccessCredentials(
          userId: 'student01',
          emailAddress: 'student01@mail.bnbu.edu.cn',
          password: 'fake-test-password',
        ),
        mailDetail: detail,
      );
      addTearDown(harness.dispose);

      await expectLater(
        harness.executor.execute(
          _action(
            AssistantActionType.downloadAttachment,
            mailUid: 17,
            mailFolder: 'inbox',
            mailboxUidValidity: 9001,
            mailPartId: '2.1',
            attachmentName: 'report.pdf',
            targetIdentity: _mailAttachmentIdentity(
              mailFolder: 'inbox',
              mailUid: 17,
              mailboxUidValidity: 9001,
              mailPartId: '9.9',
            ),
          ),
          userConfirmed: true,
        ),
        throwsA(
          isA<AiAssistantActionException>().having(
            (error) => error.message,
            'message',
            contains('附件引用已失效'),
          ),
        ),
      );
      expect(harness.controller.mailCredentialLoads, 0);
      expect(harness.mailService.readCalls, 0);

      await expectLater(
        harness.executor.execute(
          _action(
            AssistantActionType.downloadAttachment,
            mailUid: 17,
            mailFolder: 'inbox',
            mailboxUidValidity: 9001,
            mailPartId: '2.1',
            attachmentName: 'report.pdf',
          ),
          userConfirmed: true,
        ),
        throwsA(
          isA<AiAssistantActionException>().having(
            (error) => error.message,
            'message',
            contains('附件已变化'),
          ),
        ),
      );
      expect(harness.controller.mailCredentialLoads, 1);
      expect(harness.mailService.readCalls, 1);
      expect(harness.mailService.closed, isTrue);
      expect(find.byType(MailDetailPage), findsNothing);
    },
  );

  testWidgets('assignment file handoff opens picker without submitting', (
    tester,
  ) async {
    final filePicker = _FakeFilePicker();
    FilePicker.platform = filePicker;

    final item = _timelineItem();
    final detail = TimelineDetailData(
      item: item,
      type: TimelineDetailType.assignment,
      assignmentId: 70,
      canEditSubmission: true,
      supportsFileSubmission: true,
      maxFileSubmissions: 3,
      maxSubmissionSizeBytes: 10 * 1024 * 1024,
    );
    final harness = await _pumpHarness(
      tester,
      timelineItems: [item],
      timelineDetail: detail,
    );
    addTearDown(harness.dispose);

    final execution = harness.executor.execute(
      _action(AssistantActionType.uploadAssignmentFile, targetId: '7'),
      userConfirmed: true,
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimelineDetailPage), findsOneWidget);
    expect(harness.controller.detailLoads, 2);
    expect(filePicker.pickCalls, 1);
    expect(harness.controller.submittedFileCalls, 0);

    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await execution;
    expect(harness.controller.submittedFileCalls, 0);
  });

  testWidgets('attached assignment file is prefilled without reopening picker', (
    tester,
  ) async {
    final filePicker = _FakeFilePicker();
    FilePicker.platform = filePicker;
    final item = _timelineItem();
    final detail = TimelineDetailData(
      item: item,
      type: TimelineDetailType.assignment,
      assignmentId: 70,
      canEditSubmission: true,
      supportsFileSubmission: true,
      maxFileSubmissions: 3,
      maxSubmissionSizeBytes: 10 * 1024 * 1024,
    );
    final harness = await _pumpHarness(
      tester,
      timelineItems: [item],
      timelineDetail: detail,
    );
    addTearDown(harness.dispose);
    final attachment = AssistantInputAttachment(
      name: 'finished-report.docx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      bytes: Uint8List(0),
      localFilePath: '/tmp/finished-report.docx',
      localByteCount: 1024,
    );

    final execution = harness.executor.execute(
      _action(
        AssistantActionType.uploadAssignmentFile,
        targetId: '7',
        localAttachments: [attachment],
      ),
      userConfirmed: true,
    );
    await tester.pumpAndSettle();

    expect(find.byType(TimelineDetailPage), findsOneWidget);
    expect(find.text('finished-report.docx'), findsOneWidget);
    expect(find.byTooltip('移除文件'), findsOneWidget);
    expect(filePicker.pickCalls, 0);
    expect(harness.controller.submittedFileCalls, 0);

    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await execution;
  });

  testWidgets(
    'course batch handoff reloads native course files before acting',
    (tester) async {
      final harness = await _pumpHarness(
        tester,
        courses: [_course()],
        courseContents: const [],
      );
      addTearDown(harness.dispose);

      final execution = harness.executor.execute(
        _action(AssistantActionType.batchDownloadCourseFiles, targetId: '42'),
        userConfirmed: true,
      );
      await tester.pumpAndSettle();

      expect(find.byType(CourseDetailPage), findsOneWidget);
      expect(harness.controller.courseContentLoads, 1);
      expect(find.text('当前课程没有可安全批量下载的文件。'), findsOneWidget);

      harness.navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      await execution;
    },
  );

  testWidgets('confirmed TA add opens native editor before mutating state', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);
    final revision = harness.taCourseController.revision;
    final execution = harness.executor.execute(
      _taAction(
        AssistantActionType.addTaCourse,
        targetIdentity: AssistantActionRuntime.taCourseCollectionIdentity(
          collectionRevision: revision,
        ),
        expectedCollectionRevision: revision,
        title: 'TA课',
        location: '',
        startMinutes: 8 * 60,
        endMinutes: 9 * 60,
      ),
      userConfirmed: true,
    );
    await tester.pumpAndSettle();

    expect(find.byType(TaCourseManagerPage), findsOneWidget);
    expect(find.text('新建固定日程'), findsAtLeastNWidgets(1));
    expect(harness.taCourseController.entries, isEmpty);

    await tester.tap(find.byKey(const ValueKey('ta-course-editor-save')));
    await tester.pumpAndSettle();
    final saved = harness.taCourseController.entries.single;
    expect(saved.title, 'TA课');
    expect(saved.location, isEmpty);
    expect(saved.weekday, DateTime.monday);
    expect(saved.startMinutes, 8 * 60);
    expect(saved.endMinutes, 9 * 60);

    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await execution;
  });

  testWidgets('TA editor refuses a stale revision after native confirmation', (
    tester,
  ) async {
    final harness = await _pumpHarness(
      tester,
      taEntries: const [
        TaCourseEntry(
          id: 'ta-existing',
          title: 'Original TA',
          location: 'B201',
          weekday: DateTime.monday,
          startMinutes: 9 * 60,
          endMinutes: 9 * 60 + 50,
          repeatType: TaCourseRepeatType.weekly,
        ),
      ],
    );
    addTearDown(harness.dispose);
    final liveEntry = harness.taCourseController.entries.single;
    final collectionRevision = harness.taCourseController.revision;
    final execution = harness.executor.execute(
      _taAction(
        AssistantActionType.updateTaCourse,
        targetId: liveEntry.id,
        targetIdentity: AssistantActionRuntime.taCourseEntryIdentity(
          entry: liveEntry,
          collectionRevision: collectionRevision,
        ),
        expectedCollectionRevision: collectionRevision,
        expectedEntryRevision: liveEntry.revision,
        title: 'Edited by Small U',
      ),
      userConfirmed: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('编辑固定日程'), findsOneWidget);

    final concurrentResult = await harness.taCourseController.addEntry(
      const TaCourseEntry(
        id: 'ta-concurrent',
        title: 'Concurrent TA',
        location: '',
        weekday: DateTime.friday,
        startMinutes: 14 * 60,
        endMinutes: 14 * 60 + 50,
        repeatType: TaCourseRepeatType.weekly,
      ),
      expectedRevision: collectionRevision,
    );
    expect(concurrentResult.isSuccess, isTrue);

    await tester.tap(find.byKey(const ValueKey('ta-course-editor-save')));
    await tester.pumpAndSettle();
    final unchanged = harness.taCourseController.entries.singleWhere(
      (entry) => entry.id == liveEntry.id,
    );
    expect(unchanged.title, 'Original TA');
    expect(find.textContaining('日程已变化'), findsOneWidget);

    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await execution;
  });

  testWidgets('confirmed iSpace completion is rechecked and executed in app', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);
    const moduleRef = 'm1:42:101:88:page';
    final action = _action(
      AssistantActionType.setIspaceCompletion,
      targetId: moduleRef,
      ispaceCompleted: true,
    );

    await expectLater(
      harness.executor.execute(action),
      throwsA(isA<AiAssistantActionException>()),
    );
    await harness.executor.execute(action, userConfirmed: true);
    await tester.pump();

    expect(harness.controller.completionStateReads, 1);
    expect(harness.controller.completedModuleRef, moduleRef);
    expect(harness.controller.completedValue, isTrue);
    expect(find.text('已标记为完成'), findsOneWidget);
  });

  testWidgets('v4 Assignment module opens the native confirmed draft flow', (
    tester,
  ) async {
    const moduleRef = 'm1:42:101:88:assign';
    final item = _moduleTimelineItem(moduleRef);
    final harness = await _pumpHarness(
      tester,
      timelineDetail: TimelineDetailData(
        item: item,
        type: TimelineDetailType.assignment,
        assignmentId: 88,
        canEditSubmission: true,
        supportsOnlineTextSubmission: true,
      ),
    );
    addTearDown(harness.dispose);

    final execution = harness.executor.execute(
      _action(
        AssistantActionType.submitAssignment,
        targetId: moduleRef,
        body: 'Module-bound answer',
      ),
      userConfirmed: true,
    );
    await tester.pumpAndSettle();

    expect(harness.controller.moduleTimelineResolutions, 2);
    expect(find.byType(TimelineDetailPage), findsOneWidget);
    harness.navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    await execution;
  });

  testWidgets('v4 Quiz module revalidates fields before saving answers', (
    tester,
  ) async {
    const moduleRef = 'm1:42:103:90:quiz';
    final harness = await _pumpHarness(
      tester,
      quizSnapshot: const QuizAttemptSnapshot(
        itemId: '103',
        quizId: 90,
        attemptId: 501,
        state: 'inprogress',
        canStart: false,
        canSave: true,
        canFinish: true,
        questions: [
          QuizQuestionData(
            slot: 1,
            number: '1',
            type: 'multichoice',
            prompt: 'Choose one',
            status: '',
            sequenceCheckName: 'q1_:sequencecheck',
            sequenceCheck: '1',
            fields: [
              QuizAnswerField(
                name: 'q1_answer',
                kind: QuizAnswerFieldKind.choice,
                label: '',
                currentValues: [],
                options: [QuizAnswerOption(value: '1', label: 'A')],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(harness.dispose);

    await harness.executor.execute(
      _action(
        AssistantActionType.saveQuizAnswers,
        targetId: moduleRef,
        quizAttemptId: 501,
        quizResponses: const [
          AssistantQuizResponse(slot: 1, fieldName: 'q1_answer', value: '1'),
        ],
      ),
      userConfirmed: true,
    );
    await tester.pump();

    expect(harness.controller.savedQuizAnswers.single.value, '1');
    expect(find.text('Quiz 答案已保存，尚未交卷'), findsOneWidget);

    await expectLater(
      harness.executor.execute(
        _action(
          AssistantActionType.saveQuizAnswers,
          targetId: moduleRef,
          quizAttemptId: 501,
          quizResponses: const [
            AssistantQuizResponse(
              slot: 1,
              fieldName: 'q1_answer',
              value: 'invented',
            ),
          ],
        ),
        userConfirmed: true,
      ),
      throwsA(isA<AiAssistantActionException>()),
    );
    expect(harness.controller.savedQuizCalls, 1);
  });

  testWidgets('confirmed Choice uses only freshly selectable option ids', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);
    const moduleRef = 'm1:42:102:89:choice';

    await harness.executor.execute(
      _action(
        AssistantActionType.submitIspaceChoice,
        targetId: moduleRef,
        choiceOptionIds: const ['11'],
      ),
      userConfirmed: true,
    );
    await tester.pump();

    expect(harness.controller.moduleAccessReads, 1);
    expect(harness.controller.choiceModuleRef, moduleRef);
    expect(harness.controller.submittedChoiceOptionIds, [11]);
    expect(find.text('Choice 已提交'), findsOneWidget);

    await expectLater(
      harness.executor.execute(
        _action(
          AssistantActionType.submitIspaceChoice,
          targetId: moduleRef,
          choiceOptionIds: const ['12'],
        ),
        userConfirmed: true,
      ),
      throwsA(isA<AiAssistantActionException>()),
    );
    expect(harness.controller.submittedChoiceOptionIds, [11]);
  });

  testWidgets('iSpace mutation rejects a stale module identity before read', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester);
    addTearDown(harness.dispose);

    await expectLater(
      harness.executor.execute(
        _action(
          AssistantActionType.setIspaceCompletion,
          targetId: 'm1:42:101:88:page',
          targetIdentity: 'moodle-module:stale',
          ispaceCompleted: true,
        ),
        userConfirmed: true,
      ),
      throwsA(isA<AiAssistantActionException>()),
    );
    expect(harness.controller.completionStateReads, 0);
  });
}

Future<_ActionHarness> _pumpHarness(
  WidgetTester tester, {
  MailAccessCredentials? credentials,
  List<TimelineItem> timelineItems = const [],
  TimelineDetailData? timelineDetail,
  MailMessageDetail? mailDetail,
  Completer<MailMessageDetail>? mailReadCompleter,
  Future<void> Function()? beforeNavigation,
  List<TaCourseEntry> taEntries = const [],
  List<CourseSummary>? courses,
  List<CourseContentSection> courseContents = const [],
  QuizAttemptSnapshot? quizSnapshot,
  CampusLandmarkStore? meLifeStore,
}) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  final controller = _ActionController(
    credentials: credentials,
    timelineItems: timelineItems,
    timelineDetail: timelineDetail,
    courses:
        courses ??
        (timelineItems.any((item) => item.courseId == 42)
            ? [_course()]
            : const []),
    courseContents: courseContents,
    quizSnapshot: quizSnapshot,
  );
  final taCourseController = TaCourseController(sessionController: controller);
  final rootShellController = RootShellController();
  final mailIntentController = MailAssistantIntentController();
  await taCourseController.reload();
  for (final entry in taEntries) {
    final result = await taCourseController.addEntry(
      entry,
      expectedRevision: taCourseController.revision,
    );
    if (!result.isSuccess) {
      throw StateError('Failed to seed TA course test data.');
    }
  }
  final mailService = _FakeMailService(
    mailDetail: mailDetail,
    readCompleter: mailReadCompleter,
  );
  final executor = AiAssistantActionExecutor(
    navigatorKey: navigatorKey,
    controller: controller,
    mailServiceFactory: () => mailService,
    beforeNavigation: beforeNavigation,
    taCourseController: taCourseController,
    rootShellController: rootShellController,
    mailIntentController: mailIntentController,
    meLifeStore: meLifeStore,
  );
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      home: const Scaffold(body: Text('Home')),
    ),
  );
  return _ActionHarness(
    navigatorKey: navigatorKey,
    controller: controller,
    taCourseController: taCourseController,
    rootShellController: rootShellController,
    mailIntentController: mailIntentController,
    mailService: mailService,
    executor: executor,
  );
}

class _ActionHarness {
  const _ActionHarness({
    required this.navigatorKey,
    required this.controller,
    required this.taCourseController,
    required this.rootShellController,
    required this.mailIntentController,
    required this.mailService,
    required this.executor,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final _ActionController controller;
  final TaCourseController taCourseController;
  final RootShellController rootShellController;
  final MailAssistantIntentController mailIntentController;
  final _FakeMailService mailService;
  final AiAssistantActionExecutor executor;

  void dispose() {
    mailIntentController.dispose();
    rootShellController.dispose();
    taCourseController.dispose();
    controller.dispose();
  }
}

class _MeLifeStore extends CampusLandmarkStore {
  int reads = 0;
  bool present = true, unavailable = false;
  @override
  Future<void> refresh() async {
    reads++;
    failed = unavailable;
    catalog = LandmarkCatalog.fromJson({
      'version': 7,
      'schema_version': 1,
      'catalog': {
        'title': {'zh-Hans': 'ME生活'},
        'default_language': 'zh-Hans',
        'categories': [
          {
            'id': 'life',
            'names': {'zh-Hans': 'ME生活'},
          },
        ],
        'landmarks': [
          if (present)
            {
              'id': 'library',
              'category_id': 'life',
              'names': {'zh-Hans': '图书馆'},
              'descriptions': {},
              'locations': {},
              'photos': [],
            },
        ],
      },
    });
  }
}

class _ActionController extends AppSessionController {
  _ActionController({
    required this.credentials,
    required this.timelineItems,
    required this.timelineDetail,
    required this.courses,
    required this.courseContents,
    this.quizSnapshot,
  });

  final MailAccessCredentials? credentials;
  @override
  final List<TimelineItem> timelineItems;
  @override
  final List<CourseSummary> courses;
  final List<CourseContentSection> courseContents;
  final TimelineDetailData? timelineDetail;
  final QuizAttemptSnapshot? quizSnapshot;
  int mailCredentialLoads = 0;
  int detailLoads = 0;
  int courseContentLoads = 0;
  int submittedFileCalls = 0;
  int? submittedAssignmentId;
  String? submittedText;
  String? reminderTitle;
  String? reminderBody;
  DateTime? reminderAt;
  bool sessionActive = true;
  int completionStateReads = 0;
  int moduleAccessReads = 0;
  String? completedModuleRef;
  bool? completedValue;
  String? choiceModuleRef;
  List<int>? submittedChoiceOptionIds;
  int moduleTimelineResolutions = 0;
  int savedQuizCalls = 0;
  List<QuizAnswerDraft> savedQuizAnswers = const [];

  @override
  bool get isLoggedIn => true;

  @override
  String? get username => 'student01';

  @override
  AppSessionLease? captureSessionLease() => _TestSessionLease(this);

  @override
  Future<MailAccessCredentials?> loadMailAccessCredentials() async {
    mailCredentialLoads++;
    return credentials;
  }

  @override
  Future<List<CourseContentSection>> loadCourseContents(int courseId) async {
    courseContentLoads++;
    return courseContents;
  }

  @override
  Future<TimelineDetailData> loadTimelineDetail(TimelineItem item) async {
    detailLoads++;
    return timelineDetail!;
  }

  @override
  Future<TimelineItem> resolveAssistantModuleTimelineItem(
    String moduleRef,
  ) async {
    moduleTimelineResolutions++;
    return _moduleTimelineItem(moduleRef);
  }

  @override
  Future<QuizAttemptSnapshot> loadQuizAttempt(TimelineItem item) async {
    return quizSnapshot!;
  }

  @override
  Future<void> saveQuizAttempt({
    required QuizAttemptSnapshot snapshot,
    required List<QuizAnswerDraft> answers,
  }) async {
    savedQuizCalls++;
    savedQuizAnswers = List.of(answers);
  }

  @override
  Future<AssignmentSubmissionOutcome> submitAssignmentFiles({
    required int assignmentId,
    required List<UploadFilePayload> files,
  }) async {
    submittedFileCalls++;
    return const AssignmentSubmissionOutcome(
      status: 'draft',
      draftSaved: true,
      finalSubmitted: false,
    );
  }

  @override
  Future<AssignmentSubmissionOutcome> submitAssignmentOnlineText({
    required int assignmentId,
    required String text,
  }) async {
    submittedAssignmentId = assignmentId;
    submittedText = text;
    return const AssignmentSubmissionOutcome(
      status: 'draft',
      draftSaved: true,
      finalSubmitted: false,
    );
  }

  @override
  Future<String?> scheduleAssistantReminder({
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) async {
    reminderTitle = title;
    reminderBody = body;
    reminderAt = scheduledAt;
    return null;
  }

  @override
  Future<bool> assistantModuleCompletionState(String moduleRef) async {
    completionStateReads++;
    return false;
  }

  @override
  Future<void> setAssistantModuleCompletion({
    required String moduleRef,
    required bool completed,
  }) async {
    completedModuleRef = moduleRef;
    completedValue = completed;
  }

  @override
  Future<MoodleModuleAccessSnapshot> loadAssistantModuleAccess(
    String moduleRef,
  ) async {
    moduleAccessReads++;
    return _choiceAccess;
  }

  MoodleModuleAccessSnapshot get _choiceAccess =>
      const MoodleModuleAccessSnapshot(
        moduleType: 'choice',
        canRead: true,
        canWrite: true,
        statusMessage: '',
        choiceOptions: [
          MoodleChoiceOption(
            id: 11,
            label: 'Option A',
            selected: false,
            disabled: false,
            maxAnswers: 10,
          ),
          MoodleChoiceOption(
            id: 12,
            label: 'Option B',
            selected: false,
            disabled: true,
            maxAnswers: 10,
          ),
        ],
      );

  @override
  Future<MoodleModuleAccessSnapshot> submitAssistantChoice({
    required String moduleRef,
    required List<int> optionIds,
  }) async {
    choiceModuleRef = moduleRef;
    submittedChoiceOptionIds = List.of(optionIds);
    return _choiceAccess;
  }
}

class _TestSessionLease implements AppSessionLease {
  const _TestSessionLease(this.controller);

  final _ActionController controller;

  @override
  String get owner => 'student01';

  @override
  bool get isActive => controller.sessionActive;
}

class _FakeFilePicker extends FilePicker {
  int pickCalls = 0;

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
    pickCalls++;
    return null;
  }
}

class _FakeMailService extends MailService {
  _FakeMailService({this.mailDetail, this.readCompleter});

  final MailMessageDetail? mailDetail;
  final Completer<MailMessageDetail>? readCompleter;
  bool closed = false;
  int sendCalls = 0;
  int readCalls = 0;
  int saveDraftCalls = 0;
  MailComposeData? lastComposeData;
  MailFolder? lastReadFolder;
  int? lastReadUid;
  int? lastExpectedUidValidity;

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<MailMessageDetail> readMessage({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required int uid,
    int? expectedMailboxUidValidity,
    bool markAsSeen = true,
  }) async {
    readCalls++;
    lastReadFolder = folder;
    lastReadUid = uid;
    lastExpectedUidValidity = expectedMailboxUidValidity;
    final pending = readCompleter;
    if (pending != null) {
      return pending.future;
    }
    return mailDetail!;
  }

  @override
  Future<void> markMessagesSeen({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required List<int> uids,
    int? expectedMailboxUidValidity,
  }) async {}

  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) async {
    sendCalls++;
    lastComposeData = composeData;
  }

  @override
  Future<MailDraftIdentity?> saveDraft({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
    int? existingDraftUid,
    int? expectedMailboxUidValidity,
  }) async {
    saveDraftCalls++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AssistantAction _action(
  AssistantActionType type, {
  String targetId = '',
  String url = '',
  String recipient = '',
  String mailMode = '',
  String subject = '',
  String body = '',
  String placeQuery = '',
  bool? requiresConfirmation,
  String sessionOwner = 'student01',
  String targetIdentity = '',
  int? mailUid,
  String mailFolder = '',
  int? mailboxUidValidity,
  String mailPartId = '',
  String attachmentName = '',
  String notificationTitle = '',
  String notificationBody = '',
  DateTime? notificationAt,
  int? quizAttemptId,
  List<AssistantQuizResponse> quizResponses = const [],
  bool? ispaceCompleted,
  List<String> choiceOptionIds = const [],
  List<AssistantInputAttachment> localAttachments = const [],
}) {
  var resolvedTargetIdentity = targetIdentity;
  if (resolvedTargetIdentity.isEmpty &&
      type == AssistantActionType.downloadAttachment &&
      mailUid != null &&
      mailboxUidValidity != null &&
      mailPartId.trim().isNotEmpty) {
    resolvedTargetIdentity = _mailAttachmentIdentity(
      mailFolder: mailFolder,
      mailUid: mailUid,
      mailboxUidValidity: mailboxUidValidity,
      mailPartId: mailPartId,
    );
  }
  if (resolvedTargetIdentity.isEmpty &&
      mailUid != null &&
      mailboxUidValidity != null) {
    resolvedTargetIdentity = _mailIdentity(
      mailFolder: mailFolder,
      mailUid: mailUid,
      mailboxUidValidity: mailboxUidValidity,
    );
  }
  if (resolvedTargetIdentity.isEmpty) {
    if ((type == AssistantActionType.openAssignment ||
            type == AssistantActionType.submitAssignment ||
            type == AssistantActionType.uploadAssignmentFile) &&
        targetId == '7') {
      resolvedTargetIdentity = AssistantActionRuntime.timelineIdentity(
        _timelineItem(),
      );
    } else if ((type == AssistantActionType.openCourse ||
            type == AssistantActionType.prepareCoursePack ||
            type == AssistantActionType.batchDownloadCourseFiles) &&
        targetId == '42') {
      resolvedTargetIdentity = AssistantActionRuntime.courseIdentity(_course());
    } else if (RegExp(
      r'^m1:[1-9][0-9]*:[1-9][0-9]*:[1-9][0-9]*:[a-z][a-z0-9_]*$',
    ).hasMatch(targetId)) {
      resolvedTargetIdentity = AssistantActionRuntime.moodleModuleIdentity(
        targetId,
      );
    }
  }
  return AssistantAction(
    type: type,
    title: 'Test action',
    requiresConfirmation:
        requiresConfirmation ??
        (type == AssistantActionType.composeEmail ||
            type == AssistantActionType.submitAssignment ||
            type == AssistantActionType.prepareCoursePack ||
            type == AssistantActionType.downloadAttachment ||
            type == AssistantActionType.batchDownloadCourseFiles ||
            type == AssistantActionType.uploadAssignmentFile ||
            type == AssistantActionType.startQuizAttempt ||
            type == AssistantActionType.saveQuizAnswers ||
            type == AssistantActionType.submitQuizAttempt ||
            type == AssistantActionType.setIspaceCompletion ||
            type == AssistantActionType.submitIspaceChoice ||
            type == AssistantActionType.deleteMail ||
            type == AssistantActionType.restoreMail ||
            type == AssistantActionType.scheduleNotification),
    targetId: targetId,
    url: url,
    recipient: recipient,
    mailMode: mailMode,
    subject: subject,
    body: body,
    placeQuery: placeQuery,
    sessionOwner: sessionOwner,
    targetIdentity: resolvedTargetIdentity,
    mailUid: mailUid,
    mailFolder: mailFolder,
    mailboxUidValidity: mailboxUidValidity,
    mailPartId: mailPartId,
    attachmentName: attachmentName,
    notificationTitle: notificationTitle,
    notificationBody: notificationBody,
    notificationAt: notificationAt,
    quizAttemptId: quizAttemptId,
    quizResponses: quizResponses,
    ispaceCompleted: ispaceCompleted,
    choiceOptionIds: choiceOptionIds,
    localAttachments: localAttachments,
  );
}

TimelineItem _moduleTimelineItem(String moduleRef) {
  final parts = moduleRef.split(':');
  final moduleId = int.parse(parts[2]);
  final instanceId = int.parse(parts[3]);
  final moduleType = parts[4];
  return TimelineItem(
    id: moduleId,
    title: moduleType == 'quiz' ? 'Module Quiz' : 'Module Assignment',
    activityState: '',
    activityType: moduleType,
    moduleName: moduleType,
    description: '',
    courseName: 'Module Course',
    courseId: int.parse(parts[1]),
    instanceId: instanceId,
    url: 'https://ispace.example.edu/mod/$moduleType/view.php?id=$moduleId',
    sortTime: null,
    formattedTime: '',
    isOverdue: false,
  );
}

AssistantAction _taAction(
  AssistantActionType type, {
  String targetId = '',
  required String targetIdentity,
  required int expectedCollectionRevision,
  int? expectedEntryRevision,
  required String title,
  String location = 'B201',
  int startMinutes = 9 * 60,
  int endMinutes = 9 * 60 + 50,
}) {
  return AssistantAction(
    type: type,
    title: title,
    requiresConfirmation: type != AssistantActionType.openTaCourseManager,
    targetId: targetId,
    url: '',
    recipient: '',
    subject: '',
    body: '',
    placeQuery: '',
    sessionOwner: 'student01',
    targetIdentity: targetIdentity,
    taTitle: title,
    taLocation: location,
    taWeekday: DateTime.monday,
    taStartMinutes: startMinutes,
    taEndMinutes: endMinutes,
    taRepeatType: 'weekly',
    taExpectedEntryRevision: expectedEntryRevision,
    taExpectedCollectionRevision: expectedCollectionRevision,
  );
}

String _mailAttachmentIdentity({
  required String mailFolder,
  required int mailUid,
  required int mailboxUidValidity,
  required String mailPartId,
}) {
  final folders = MailFolder.values.where(
    (folder) => folder.name == mailFolder,
  );
  if (folders.length != 1) {
    return '';
  }
  return AssistantActionRuntime.mailAttachmentIdentity(
    folder: folders.single,
    uid: mailUid,
    mailboxUidValidity: mailboxUidValidity,
    partId: mailPartId,
  );
}

String _mailIdentity({
  required String mailFolder,
  required int mailUid,
  required int mailboxUidValidity,
}) {
  final folders = MailFolder.values.where(
    (folder) => folder.name == mailFolder,
  );
  if (folders.length != 1) {
    return '';
  }
  return AssistantActionRuntime.mailIdentity(
    folder: folders.single,
    uid: mailUid,
    mailboxUidValidity: mailboxUidValidity,
  );
}

MailMessageDetail _mailDetail() {
  return MailMessageDetail(
    uid: 17,
    subject: 'Course update',
    sender: 'Teacher <teacher@bnbu.edu.cn>',
    recipients: 'student01@mail.bnbu.edu.cn',
    cc: null,
    date: DateTime.utc(2026, 7, 22),
    body: 'Please read the update.',
    htmlBody: null,
    isSeen: true,
    mailboxUidValidity: 9001,
    folder: MailFolder.inbox,
  );
}

CourseSummary _course() {
  return CourseSummary(
    id: 42,
    fullName: 'C Language',
    shortName: 'C',
    categoryName: 'CS',
    progress: 50,
  );
}

TimelineItem _timelineItem() {
  return TimelineItem(
    id: 7,
    title: 'Lab assignment',
    activityState: 'Assignment is due',
    activityType: 'assign',
    moduleName: 'assign',
    description: '',
    courseName: 'C Language',
    courseId: 42,
    instanceId: 70,
    url: '',
    sortTime: DateTime.utc(2026, 7, 23),
    formattedTime: '',
    isOverdue: false,
  );
}
