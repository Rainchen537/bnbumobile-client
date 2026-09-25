import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/pages/mail_page.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/services/mail_compose_signature_store.dart';
import 'package:bnbu_me/services/mail_recipient_directory.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/assistant_context_scope.dart';
import 'package:bnbu_me/widgets/bnbu_creation_form.dart';
import 'package:bnbu_me/widgets/mail_search_header.dart';

import '../tool/mobile_mail_preview.dart';

class _Directory extends ReferenceRecipientDirectory {
  final remote = <String, Completer<List<MailRecipientSuggestion>>>{};
  @override
  Future<List<MailRecipientSuggestion>> search(String query) =>
      (remote[query] ??= Completer()).future;
}

class _Mail extends ReferenceMailService {
  _Mail() : super(DateTime(2026, 9, 7));
  MailComposeData? sent;
  @override
  Future<void> sendEmail({
    required MailAccessCredentials credentials,
    required MailComposeData composeData,
  }) async {
    sent = composeData;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('desktop font size converts points to CSS pixels and back', () {
    expect(mailComposeFontPointToPixels(11), closeTo(44 / 3, 0.000001));
    expect(mailComposeFontPointToPixels(24), 32);
    expect(mailComposeFontPixelsToPointLabel(null), '11');
    expect(mailComposeFontPixelsToPointLabel('14.666666666666666px'), '11');
    expect(mailComposeFontPixelsToPointLabel('15px'), '11.3');
    expect(mailComposeFontPixelsToPointLabel('12pt'), '12');
  });

  Future<void> launch(
    WidgetTester tester,
    MailRecipientDirectory directory,
    _Mail mail, {
    double width = 390,
    ThemeData? theme,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: ComposeMailPage(
          mailService: mail,
          credentials: MailReferenceFixture.credentials,
          recipientDirectory: directory,
          senderAvatarService: ReferenceMailAvatar(),
          autoSaveDrafts: false,
        ),
      ),
    );
    await tester.pump();
  }

  for (final width in [900.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'desktop compose send is readable without scaling the header at $width dark=$dark',
        (tester) async {
          final mail = _Mail();
          await launch(
            tester,
            ReferenceRecipientDirectory(),
            mail,
            width: width,
            theme: dark ? AppTheme.dark : AppTheme.light,
          );
          final send = find.byKey(const ValueKey('compose-send'));
          final label = find.descendant(
            of: send,
            matching: find.byType(RichText),
          );
          final paragraph = tester.renderObject<RenderParagraph>(label);
          final transform = paragraph.getTransformTo(null);
          final scale =
              (MatrixUtils.transformPoint(transform, const Offset(1, 0)) -
                      MatrixUtils.transformPoint(transform, Offset.zero))
                  .distance;
          final paintedFontSize = paragraph.text.style!.fontSize! * scale;
          expect(paintedFontSize, closeTo(15.6, .01));
          final titleParagraph = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.text('新建邮件'),
              matching: find.byType(RichText),
            ),
          );
          final titleTransform = titleParagraph.getTransformTo(null);
          final titleScale =
              (MatrixUtils.transformPoint(titleTransform, const Offset(1, 0)) -
                      MatrixUtils.transformPoint(titleTransform, Offset.zero))
                  .distance;
          expect(
            titleParagraph.text.style!.fontSize! * titleScale,
            closeTo(20, .01),
          );
          expect(tester.getCenter(find.text('新建邮件')).dx, closeTo(width / 2, 1));
          expect(tester.getSize(send).height, greaterThanOrEqualTo(44));
          final button = find.descendant(
            of: send,
            matching: find.byType(TextButton),
          );
          expect(tester.widget<TextButton>(button).onPressed, isNull);
          await tester.enterText(
            find.byKey(const ValueKey('compose-recipient-field')),
            'recipient@example.com',
          );
          await tester.pump();
          expect(tester.widget<TextButton>(button).onPressed, isNotNull);
          await tester.tap(button);
          await tester.pumpAndSettle();
          expect(mail.sent, isNotNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'phone compose keeps the continuous reference canvas and blue send button',
    (tester) async {
      await launch(tester, ReferenceRecipientDirectory(), _Mail());
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, Colors.white);
      expect(find.byType(BnbuCreationGroup), findsNothing);
      expect(find.byType(BnbuCreationSurface), findsNothing);
      expect(tester.widget<Text>(find.text('新建邮件')).style!.fontSize, 17);
      expect(tester.getCenter(find.text('新建邮件')).dx, closeTo(195, 1));
      final send = tester.widget<TextButton>(
        find.byKey(const ValueKey('compose-send')),
      );
      expect(send.style!.textStyle!.resolve({})!.fontSize, 16);
      expect(
        send.style!.backgroundColor!.resolve({WidgetState.disabled})!.a,
        greaterThan(0),
      );
      expect(
        send.style!.foregroundColor!.resolve({WidgetState.disabled}),
        Colors.white,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('compose-reference-header')))
            .height,
        44,
      );
      expect(
        find.byKey(const ValueKey('compose-mobile-tools')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone contact icon activates existing search and tools keep rich actions',
    (tester) async {
      await launch(tester, ReferenceRecipientDirectory(), _Mail());
      final to = find.byKey(const ValueKey('compose-recipient-field'));
      await tester.tap(find.byKey(const ValueKey('compose-search-contact')));
      await tester.pump();
      expect(tester.widget<TextField>(to).focusNode!.hasFocus, isTrue);
      await tester.enterText(to, 'Alice');
      await tester.pump(const Duration(milliseconds: 260));
      await tester.tap(find.text('Alice Li'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('compose-mobile-tools')));
      await tester.pumpAndSettle();
      for (final text in [
        '添加图片',
        '插入链接',
        '项目列表',
        '编号列表',
        '引用',
        '分隔线',
        '使用 BNBU.ME 签名',
        '询问小U',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      await tester.tap(find.text('插入链接'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('compose-link-field')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone tools stay above keyboard and scroll to the last action', (
    tester,
  ) async {
    await launch(tester, ReferenceRecipientDirectory(), _Mail());
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('compose-mobile-tools')));
    await tester.pumpAndSettle();
    final menu = find
        .ancestor(of: find.text('添加图片'), matching: find.byType(Material))
        .first;
    expect(tester.getBottomRight(menu).dy, lessThanOrEqualTo(844 - 336));
    await tester.ensureVisible(find.text('智能翻译'));
    await tester.pumpAndSettle();
    expect(
      tester.getBottomRight(find.text('智能翻译')).dy,
      lessThanOrEqualTo(844 - 336),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'To Cc and Bcc append independently, preserve other recipients and deduplicate on send',
    (tester) async {
      final mail = _Mail();
      await launch(tester, ReferenceRecipientDirectory(), mail);
      final to = find.byKey(const ValueKey('compose-recipient-field'));
      await tester.enterText(to, 'Alice');
      await tester.pump(const Duration(milliseconds: 260));
      await tester.tap(find.text('Alice Li'));
      await tester.pump();
      await tester.enterText(to, 'Bob');
      await tester.pump(const Duration(milliseconds: 260));
      await tester.tap(find.text('Bob Chen'));
      await tester.pump();
      expect(find.byType(InputChip), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('compose-toggle-cc-bcc')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('compose-cc-field')),
        'copy@example.test',
      );
      await tester.enterText(
        find.byKey(const ValueKey('compose-bcc-field')),
        'alice@example.test',
      );
      await tester.tap(find.byKey(const ValueKey('compose-send')));
      await tester.pump();
      await tester.pump();
      expect(mail.sent?.to, 'alice@example.test, bob@example.test');
      expect(mail.sent?.cc, 'copy@example.test');
      expect(mail.sent?.bcc, isNull);
    },
  );

  testWidgets(
    'pasted completed addresses survive selecting the unfinished last recipient',
    (tester) async {
      final mail = _Mail();
      await launch(tester, ReferenceRecipientDirectory(), mail);
      await tester.enterText(
        find.byKey(const ValueKey('compose-recipient-field')),
        'first@example.test, Bob',
      );
      await tester.pump(const Duration(milliseconds: 260));
      await tester.tap(find.text('Bob Chen'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('compose-send')));
      await tester.pump();
      await tester.pump();
      expect(mail.sent?.to, 'first@example.test, bob@example.test');
    },
  );

  testWidgets('forwarded rich HTML is retained for SMTP instead of flattened', (
    tester,
  ) async {
    final mail = _Mail();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ComposeMailPage(
          mailService: mail,
          credentials: MailReferenceFixture.credentials,
          recipientDirectory: ReferenceRecipientDirectory(),
          senderAvatarService: ReferenceMailAvatar(),
          autoSaveDrafts: false,
          initialRecipient: 'receiver@example.test',
          initialBody: '课程安排',
          initialHtmlBody:
              '<table><tbody><tr><th>课程</th><td>数据结构</td></tr></tbody></table>',
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await tester.pump();
    await tester.pump();

    expect(mail.sent?.body, contains('课程安排'));
    expect(mail.sent?.htmlBody, contains('<table'));
    expect(mail.sent?.htmlBody, contains('<th>课程</th>'));
  });

  testWidgets(
    'BNBU signature preview keeps the mobile inset, short divider and hierarchy',
    (tester) async {
      final store = MailComposeSignatureStore();
      await store.save(
        MailReferenceFixture.credentials.emailAddress,
        MailComposeSignature.bnbuMe,
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ComposeMailPage(
            mailService: _Mail(),
            credentials: MailReferenceFixture.credentials,
            recipientDirectory: ReferenceRecipientDirectory(),
            senderAvatarService: ReferenceMailAvatar(),
            signatureStore: store,
            senderDisplayName: '李星辰',
            autoSaveDrafts: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final preview = find.byKey(const ValueKey('compose-signature-preview'));
      expect(preview, findsOneWidget);
      expect(tester.getTopLeft(preview).dx, 16);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('compose-signature-divider')))
            .width,
        126,
      );
      final school = tester.widget<Text>(find.text('北师港浸大BNBU'));
      final name = tester.widget<Text>(find.text('李星辰'));
      final source = tester.widget<Text>(find.text('来自BNBU.ME'));
      expect(school.style?.fontSize, 13);
      expect(school.style?.fontWeight, FontWeight.w600);
      expect(name.style?.fontSize, 16);
      expect(name.style?.fontWeight, FontWeight.w600);
      expect(source.style?.fontSize, 12);
      expect(
        tester.getBottomRight(preview).dy -
            tester.getBottomRight(find.text('来自BNBU.ME')).dy,
        greaterThanOrEqualTo(50),
      );
    },
  );

  testWidgets(
    'BNBU signature preview compacts typography inside the desktop editor',
    (tester) async {
      final store = MailComposeSignatureStore();
      await store.save(
        MailReferenceFixture.credentials.emailAddress,
        MailComposeSignature.bnbuMe,
      );
      tester.view.physicalSize = const Size(1180, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: ComposeMailPage(
            mailService: _Mail(),
            credentials: MailReferenceFixture.credentials,
            recipientDirectory: ReferenceRecipientDirectory(),
            senderAvatarService: ReferenceMailAvatar(),
            signatureStore: store,
            senderDisplayName: '李星辰',
            autoSaveDrafts: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final preview = find.byKey(const ValueKey('compose-signature-preview'));
      expect(preview, findsOneWidget);
      expect(tester.getTopLeft(preview).dx, 32);
      expect(tester.widget<Text>(find.text('北师港浸大BNBU')).style?.fontSize, 12);
      expect(tester.widget<Text>(find.text('李星辰')).style?.fontSize, 13);
      expect(tester.widget<Text>(find.text('来自BNBU.ME')).style?.fontSize, 11);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('compose-signature-divider')))
            .width,
        126,
      );
    },
  );

  testWidgets(
    '小U智能 creates a fresh typed draft reference without sending mail',
    (tester) async {
      final mail = _Mail();
      AssistantMailReference? reference;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: AssistantContextScope(
            coordinator: AssistantContextCoordinator(),
            openAssistantWithMailReference: (value) async {
              reference = value;
            },
            child: ComposeMailPage(
              mailService: mail,
              credentials: MailReferenceFixture.credentials,
              recipientDirectory: ReferenceRecipientDirectory(),
              senderAvatarService: ReferenceMailAvatar(),
              autoSaveDrafts: false,
              initialRecipient: 'teacher@bnbu.edu.cn',
              initialSubject: '课程问题',
              initialBody: '请问作业截止时间？',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('compose-toggle-cc-bcc')));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('compose-cc-field')),
        'copy@bnbu.edu.cn',
      );
      await tester.enterText(
        find.byKey(const ValueKey('compose-bcc-field')),
        'private@bnbu.edu.cn',
      );
      await tester.tap(find.byKey(const ValueKey('compose-mobile-tools')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('询问小U'));
      await tester.pump();

      expect(reference, isNotNull);
      expect(reference!.kind, AssistantMailReferenceKind.draft);
      expect(
        reference!.recipients,
        '收件人：teacher@bnbu.edu.cn\n'
        '抄送：copy@bnbu.edu.cn\n'
        '密送：private@bnbu.edu.cn',
      );
      expect(reference!.subject, '课程问题');
      expect(reference!.body, contains('请问作业截止时间'));
      expect(mail.sent, isNull);
    },
  );

  testWidgets(
    'an unfinished additional recipient keeps send disabled without discarding it',
    (tester) async {
      await launch(tester, ReferenceRecipientDirectory(), _Mail());
      final to = find.byKey(const ValueKey('compose-recipient-field'));
      await tester.enterText(to, 'first@example.test, unfinished');
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('compose-send')))
            .onPressed,
        isNull,
      );
      await tester.enterText(to, 'first@example.test, second@example.test');
      await tester.pump();
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('compose-send')))
            .onPressed,
        isNotNull,
      );
    },
  );

  testWidgets(
    'local suggestions are immediate, IME composition waits and stale remote completion is ignored',
    (tester) async {
      final directory = _Directory();
      await launch(tester, directory, _Mail());
      final to = find.byKey(const ValueKey('compose-recipient-field'));
      await tester.enterText(to, 'Alice');
      await tester.pump();
      expect(find.text('Alice Li'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 240));
      expect(directory.remote.keys, contains('Alice'));
      await tester.enterText(to, 'Bob');
      await tester.pump(const Duration(milliseconds: 240));
      directory.remote['Alice']!.complete([
        ReferenceRecipientDirectory.entries.first,
      ]);
      await tester.pump();
      expect(find.text('Alice Li'), findsNothing);
      expect(find.text('Bob Chen'), findsOneWidget);
      directory.remote['Bob']!.completeError(
        StateError('temporary network error'),
      );
      await tester.pump();
      expect(find.text('Bob Chen'), findsOneWidget);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('compose-recipient-retry')),
        findsOneWidget,
      );
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'Chen',
          selection: TextSelection.collapsed(offset: 4),
          composing: TextRange(start: 0, end: 4),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(directory.remote.keys, isNot(contains('Chen')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'search is centered in the whole header and expands around its center while moving plus away',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MailSearchHeader(
              controller: controller,
              onChanged: (_) {},
              onCompose: () {},
            ),
          ),
        ),
      );
      final field = find.byKey(const ValueKey('mail-search-control'));
      final plus = find.byKey(const ValueKey('mail-compose-action'));
      final collapsed = tester.getRect(field);
      expect(collapsed.center.dx, closeTo(195, .01));
      expect(tester.getRect(plus).right, closeTo(380, .01));
      await tester.tap(field);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final middle = tester.getRect(field);
      expect(middle.width, greaterThan(collapsed.width));
      expect(middle.center.dx, closeTo(195, .01));
      await tester.pumpAndSettle();
      expect(tester.getRect(field).width, 370);
      expect(plus.hitTestable(), findsNothing);
      await tester.tap(find.byKey(const ValueKey('mail-search-close')));
      await tester.pumpAndSettle();
      expect(tester.getRect(field), collapsed);
      expect(plus.hitTestable(), findsOneWidget);
    },
  );
}
