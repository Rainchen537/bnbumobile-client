import 'dart:async';
import 'dart:convert';

import 'package:bnbu_me/config/app_config.dart';
import 'package:bnbu_me/widgets/leave_application_editor.dart';
import 'package:bnbu_me/models/official_web_target.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/pages/home_page.dart';
import 'package:bnbu_me/pages/leave_application_page.dart';
import 'package:bnbu_me/pages/official_web_page.dart';
import 'package:bnbu_me/services/leave_application_presentation.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/native_mirror_webview.dart';
import 'package:bnbu_me/widgets/leave_course_picker.dart';
import 'package:bnbu_me/widgets/leave_application_review.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/home_navigation_fixtures.dart';

class _Session extends HomeNavigationFixture {
  final pending = Completer<WebSessionSnapshot>();
  final targets = <OfficialWebTarget>[];
  final lease = _Lease();
  int resets = 0;

  @override
  Future<void> resetOfficialWebSession(OfficialWebTarget target) async {
    resets++;
  }

  @override
  AppSessionLease captureSessionLease() => lease;

  @override
  Future<WebSessionSnapshot> prepareOfficialWebSession(
    OfficialWebTarget target,
  ) {
    targets.add(target);
    return pending.future;
  }
}

class _Lease implements AppSessionLease {
  @override
  String get owner => 'synthetic-user';
  @override
  bool isActive = true;
}

void main() {
  test('success dialog copy is available in all app languages', () {
    const english = BnbuLocalizations(Locale('en'));
    const traditional = BnbuLocalizations(Locale('zh', 'TW'));
    expect(english.text('申请提交成功'), 'Application submitted successfully');
    expect(english.text('请等待审批。'), 'Please wait for approval.');
    expect(english.text('返回'), 'Back');
    expect(traditional.text('申请提交成功'), '申請提交成功');
    expect(traditional.text('请等待审批。'), '請等待審批。');
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // A cached Future from a prior fake-async test cannot complete in this
    // test's zone. Each document must load its fixture in its own zone.
    rootBundle.evict('assets/leave_application/bridge.js');
  });

  for (final outcome in [
    'cancel',
    'submit',
    'submit-failed',
    'submit-timeout',
    'submit-timeout-confirm',
    'submit-query-confirm',
    'submit-late-receipt',
    'submit-school-confirm',
    'submit-school-confirm-logout',
    'submit-school-confirm-dispose',
    'submit-school-custom-phone',
    'submit-school-custom-tablet',
    'submit-school-custom-desktop',
    'submit-school-custom-chain',
    'submit-school-cancel',
    'submit-school-cancel-read-failed',
    'submit-receipt-failed',
    'logout',
    'required',
    'load-failed',
  ]) {
    testWidgets('native final review keeps confirmation bound ($outcome)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final submitting = outcome.startsWith('submit');
      final custom = outcome.startsWith('submit-school-custom');
      final schoolTitle = custom
          ? 'Submit Confirmation'
          : 'Synthetic school confirmation';
      final schoolMessage = custom
          ? 'The leave period you applied for is:\n2030-04-02 09:00 to 2030-04-02 11:00\n'
                'The courses you have chosen are:\n${List.filled(40, 'DEMO1001').join(', ')}\n'
                'Each person can only apply once a day. Are you sure you want to submit?\n\n'
                '你申请的请假时间是：\n2030-04-02 09:00 至 2030-04-02 11:00\n'
                '你选择的课程是：\n${List.filled(40, 'DEMO1001').join(', ')}\n'
                '每人每天只能申请一次。你确定要提交吗？'
          : 'Confirm this synthetic request?';
      if (custom) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = outcome.endsWith('tablet')
            ? const Size(768, 1024)
            : outcome.endsWith('desktop')
            ? const Size(1280, 800)
            : const Size(320, 740);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      final session = _Session();
      String? channelName;
      final operations = <String>[];
      var queryingAfterWait = false;
      String? submissionNonce;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method != 'create') return null;
        channelName = 'ispace/native_webview/${(call.arguments as Map)['id']}';
        messenger.setMockMethodCallHandler(MethodChannel(channelName!), (
          call,
        ) async {
          if (call.method != 'evaluateJavascript') return null;
          final match = RegExp(
            r'\((\{"origin":.*\})\);$',
          ).firstMatch(call.arguments as String)!;
          final request = jsonDecode(match.group(1)!) as Map<String, dynamic>;
          final op = request['operation'] as String;
          operations.add(op);
          if (op == 'acknowledge') {
            return jsonEncode({'status': 'acknowledged'});
          }
          if (op == 'submit_confirmed') {
            submissionNonce = request['nonce'] as String;
            if (outcome.startsWith('submit-timeout')) {
              return Completer<String>().future;
            }
            if (outcome.startsWith('submit-school')) {
              return jsonEncode({
                'status': 'submission_confirmation',
                'confirmation': {
                  'token': 'school-decision',
                  'title': schoolTitle,
                  'message': schoolMessage,
                  'cancel': custom ? 'Back' : 'School cancel',
                  'confirm': custom ? 'Confirm' : 'School confirm',
                },
              });
            }
            if (outcome == 'submit-receipt-failed') {
              return jsonEncode({'status': 'submission_failed'});
            }
            return jsonEncode({
              'status': outcome == 'submit-failed'
                  ? 'write_failed'
                  : 'submission_unconfirmed',
            });
          }
          if (op == 'submit_status' &&
              (outcome == 'submit-timeout-confirm' ||
                  (outcome == 'submit-query-confirm' && queryingAfterWait)) &&
              !operations.contains('submit_decision')) {
            return jsonEncode({
              'status': 'submission_confirmation',
              'confirmation': {
                'token': 'late-school-decision',
                'title': 'Synthetic school confirmation',
                'message': 'Confirm this synthetic request?',
                'cancel': 'School cancel',
                'confirm': 'School confirm',
              },
            });
          }
          if (op == 'submit_status' &&
              outcome == 'submit-late-receipt' &&
              queryingAfterWait) {
            return jsonEncode({
              'status': 'submission_succeeded',
              'schoolMessage': 'Synthetic late school receipt',
            });
          }
          if (op == 'submit_status' && outcome == 'submit-receipt-failed') {
            return jsonEncode({
              'status': 'submission_failed',
              'schoolMessage': 'Synthetic school attachment validation',
            });
          }
          if (op == 'submit_decision') {
            if (outcome == 'submit-school-custom-chain' &&
                operations.where((op) => op == 'submit_decision').length == 1) {
              return jsonEncode({
                'status': 'submission_confirmation',
                'confirmation': {
                  'token': 'standard-decision',
                  'title': 'School confirmation',
                  'message': 'Confirm submission?',
                  'cancel': 'Cancel',
                  'confirm': 'Confirm',
                },
              });
            }
            return jsonEncode({
              'status': request['confirmed'] == true
                  ? 'submission_succeeded'
                  : 'submission_cancelled',
            });
          }
          if (op == 'read' &&
              outcome == 'submit-school-cancel-read-failed' &&
              operations.contains('submit_decision')) {
            return jsonEncode({'status': 'unsupported'});
          }
          return jsonEncode({
            'status': 'ready',
            'fields': {
              'englishName': {'display': 'Synthetic A'},
              if (outcome == 'required')
                'familyPhone': {'required': true, 'value': ''},
            },
            'reasons': [],
            'courses': [],
            'completion': {
              'token': 'review-1',
              'canSubmit': true,
              'notices': ['Synthetic school note'],
              'declaration': 'Synthetic declaration',
              'acknowledgement': 'Synthetic acknowledgement',
            },
          });
        });
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (channelName != null) {
          messenger.setMockMethodCallHandler(MethodChannel(channelName!), null);
        }
        session.dispose();
      });
      session.pending.complete(
        WebSessionSnapshot(
          baseUrl: 'https://portal.bnbu.edu.cn',
          cookies: const [],
        ),
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      var returnedHome = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: outcome.endsWith('desktop') ? AppTheme.dark : AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(
                outcome.endsWith('phone') ? 1.6 : 1,
              ),
            ),
            child: child!,
          ),
          home: const Scaffold(body: Text('Synthetic app home')),
        ),
      );
      unawaited(
        navigatorKey.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => LeaveApplicationPage(
              controller: session,
              onReturnHome: () => returnedHome++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await messenger.handlePlatformMessage(
        channelName!,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('pageFinished'),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('核对并提交'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('核对并提交'));
      await tester.pumpAndSettle();
      if (outcome == 'required') {
        expect(find.byType(LeaveApplicationReview), findsNothing);
        expect(find.text('请先填写学校要求的必填内容。'), findsOneWidget);
      } else {
        expect(find.byType(LeaveApplicationReview), findsOneWidget);
        if (outcome == 'cancel') {
          await tester.tap(find.text('返回修改'));
        } else if (outcome == 'logout') {
          session.lease.isActive = false;
          session.notifyListeners();
        } else if (outcome == 'load-failed') {
          tester
              .widget<NativeMirrorWebView>(find.byType(NativeMirrorWebView))
              .onPageFailed!();
        } else {
          final ack = find.byKey(const ValueKey('leave-acknowledgement'));
          await tester.ensureVisible(ack);
          await tester.tap(ack);
          await tester.pumpAndSettle();
          await tester.tap(find.text('确认提交给学校'));
          if (outcome == 'submit-timeout-confirm') {
            await tester.pumpAndSettle();
            await tester.pump(const Duration(seconds: 16));
          }
          if (outcome.startsWith('submit-school') ||
              outcome == 'submit-timeout-confirm') {
            await tester.pumpAndSettle();
            expect(find.text(schoolTitle), findsOneWidget);
            if (custom) {
              expect(find.text(schoolMessage), findsOneWidget);
              expect(tester.takeException(), isNull);
              final content = find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Scrollable),
              );
              await tester.drag(content.first, const Offset(0, -800));
              await tester.pumpAndSettle();
              expect(find.text('Back').hitTestable(), findsOneWidget);
              expect(find.text('Confirm').hitTestable(), findsOneWidget);
            }
            expect(operations, isNot(contains('submit_decision')));
            await tester.tap(
              find.text(
                custom
                    ? 'Confirm'
                    : outcome.contains('cancel')
                    ? 'School cancel'
                    : 'School confirm',
              ),
            );
            if (outcome == 'submit-school-custom-chain') {
              await tester.pumpAndSettle();
              expect(find.text('School confirmation'), findsOneWidget);
              expect(
                operations.where((op) => op == 'submit_decision'),
                hasLength(1),
              );
              await tester.tap(find.text('Confirm'));
              await tester.pumpAndSettle();
              expect(
                operations.where((op) => op == 'submit_decision'),
                hasLength(2),
              );
            }
          }
          if (outcome == 'submit-timeout') {
            await tester.pumpAndSettle();
            expect(find.text('正在提交至学校'), findsOneWidget);
            expect(find.text('正在同步学校表单'), findsNothing);
            await tester.pump(const Duration(seconds: 16));
          }
        }
        await tester.pumpAndSettle();
        expect(find.byType(LeaveApplicationReview), findsNothing);
      }
      expect(
        operations.where((op) => op == 'acknowledge'),
        hasLength(submitting ? 1 : 0),
      );
      expect(
        operations.where((op) => op == 'submit_confirmed'),
        hasLength(submitting ? 1 : 0),
      );
      expect(operations, isNot(contains('focus')));
      expect(find.text('学校原表'), findsNothing);
      if (outcome == 'submit-query-confirm') {
        expect(find.text('查询学校提交结果'), findsOneWidget);
        queryingAfterWait = true;
        await tester.tap(find.text('查询学校提交结果'));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic school confirmation'), findsOneWidget);
        expect(operations, isNot(contains('submit_decision')));
        await tester.tap(find.text('School confirm'));
        await tester.pumpAndSettle();
        expect(
          operations.where((op) => op == 'submit_confirmed'),
          hasLength(1),
        );
        expect(operations.where((op) => op == 'submit_decision'), hasLength(1));
      }
      if (outcome == 'submit-late-receipt') {
        expect(find.text('查询学校提交结果'), findsOneWidget);
        queryingAfterWait = true;
        tester
            .widget<NativeMirrorWebView>(find.byType(NativeMirrorWebView))
            .onLeaveSubmission!({
          'nonce': submissionNonce,
          'status': 'submission_succeeded',
        });
        await tester.pumpAndSettle();
        expect(find.text('Synthetic late school receipt'), findsOneWidget);
        expect(find.text('查询学校提交结果'), findsNothing);
        expect(
          operations.where((op) => op == 'submit_confirmed'),
          hasLength(1),
        );
      }
      if (custom ||
          outcome.startsWith('submit-school-confirm') ||
          outcome == 'submit-timeout-confirm' ||
          outcome == 'submit-query-confirm' ||
          outcome == 'submit-late-receipt') {
        expect(find.text('申请提交成功'), findsOneWidget);
        expect(find.text('请等待审批。'), findsOneWidget);
        final dialog = tester.widget<AlertDialog>(find.byType(AlertDialog));
        expect(dialog.actions, hasLength(1));
        expect(find.widgetWithText(FilledButton, '返回'), findsOneWidget);
        tester
            .widget<NativeMirrorWebView>(find.byType(NativeMirrorWebView))
            .onPageFailed!();
        await tester.pumpAndSettle();
        expect(find.text('申请提交成功'), findsOneWidget);
        await tester.tapAt(const Offset(2, 2));
        await tester.pumpAndSettle();
        await navigatorKey.currentState!.maybePop();
        await tester.pumpAndSettle();
        expect(find.text('申请提交成功'), findsOneWidget);
        expect(find.text('学校已确认申请提交成功，请等待审批。'), findsOneWidget);
        expect(find.text('提交结果待确认'), findsNothing);
        if (outcome.endsWith('-logout')) {
          session.lease.isActive = false;
          session.notifyListeners();
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(returnedHome, 0);
          expect(find.text('登录状态已变化，请重新打开请假申请。'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          debugDefaultTargetPlatformOverride = null;
          return;
        }
        if (outcome.endsWith('-dispose')) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(returnedHome, 0);
          debugDefaultTargetPlatformOverride = null;
          return;
        }
        await tester.tap(find.widgetWithText(FilledButton, '返回'));
        await tester.pumpAndSettle();
        expect(returnedHome, 1);
        expect(find.text('Synthetic app home'), findsOneWidget);
        expect(find.byType(LeaveApplicationPage), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
      } else if (outcome == 'submit-school-cancel-read-failed') {
        expect(find.text('暂时无法读取申请资料，请检查网络后重新读取。'), findsOneWidget);
        expect(find.text('已取消学校提交确认，可以继续修改。'), findsNothing);
        expect(find.text('请先核对学校表单'), findsOneWidget);
      } else if (outcome == 'submit-school-cancel') {
        expect(find.text('已取消学校提交确认，可以继续修改。'), findsOneWidget);
        expect(find.text('核对并提交'), findsOneWidget);
        expect(find.text('提交结果待确认'), findsNothing);
      } else if (submitting) {
        expect(find.text('申请提交成功'), findsNothing);
        expect(find.text('重新读取表单'), findsNothing);
        expect(find.text('正在同步学校表单'), findsNothing);
        expect(find.text('查询学校提交结果'), findsOneWidget);
        if (outcome == 'submit-receipt-failed') {
          await tester.tap(find.text('查询学校提交结果'));
          await tester.pumpAndSettle();
          expect(
            operations.where((op) => op == 'submit_confirmed'),
            hasLength(1),
          );
          expect(operations.where((op) => op == 'acknowledge'), hasLength(1));
          expect(
            find.text('Synthetic school attachment validation'),
            findsOneWidget,
          );
        }
        await tester.scrollUntilVisible(
          find.text('提交结果待确认'),
          220,
          scrollable: find
              .descendant(
                of: find.byType(LeaveApplicationEditor),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('提交结果待确认'), findsOneWidget);
        final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, '提交结果待确认'),
        );
        expect(button.onPressed, isNull);
        await tester.ensureVisible(find.text('提交结果待确认'));
        await tester.tap(find.text('提交结果待确认'));
        await tester.pumpAndSettle();
        expect(
          operations.where((op) => op == 'submit_confirmed'),
          hasLength(1),
        );
        tester
            .widget<NativeMirrorWebView>(find.byType(NativeMirrorWebView))
            .onPageFailed!();
        await tester.pump();
        expect(find.text('重新读取表单'), findsNothing);
      }
      expect(session.targets, [OfficialWebTarget.portal]);
      if (outcome == 'submit') {
        expect(
          find.text('学校未确认提交结果。为避免重复申请，已停止重试；当前不能确认申请成功。'),
          findsOneWidget,
        );
      } else if (outcome == 'submit-failed' || outcome == 'submit-timeout') {
        expect(
          find.text('学校未确认提交结果。为避免重复申请，已停止重试；当前不能确认申请成功。'),
          findsOneWidget,
        );
      } else if (outcome == 'submit-receipt-failed') {
        expect(find.text('学校返回提交失败，申请未确认成功。请核对填写内容；不会自动重复提交。'), findsOneWidget);
        expect(
          find.text('Synthetic school attachment validation'),
          findsOneWidget,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  for (final outcome in [
    'choose',
    'slow-choose',
    'late-reconcile',
    'draft-choose',
    'draft-cancel',
    'selected-filter',
    'cancel',
    'logout',
    'conflict',
    'unavailable',
    'retry-conflict',
    'reload',
    'remove',
    'load-failed',
  ]) {
    testWidgets(
      'native course handoff preserves the school session ($outcome)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final session = _Session();
        String? channelName;
        final operations = <String>[];
        var selected = false;
        var settlementReads = 0;
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          if (call.method != 'create') return null;
          final id = (call.arguments as Map)['id'];
          channelName = 'ispace/native_webview/$id';
          messenger.setMockMethodCallHandler(MethodChannel(channelName!), (
            call,
          ) async {
            if (call.method != 'evaluateJavascript') return null;
            final source = call.arguments as String;
            final match = RegExp(
              r'\((\{"origin":.*\})\);$',
            ).firstMatch(source)!;
            final request = jsonDecode(match.group(1)!) as Map<String, dynamic>;
            final op = request['operation'] as String;
            operations.add(op);
            if (op == 'course_open') {
              return jsonEncode({
                'status':
                    [
                      'unavailable',
                      'retry-conflict',
                      'reload',
                    ].contains(outcome)
                    ? 'unsupported'
                    : 'loading',
              });
            }
            if (op == 'course_remove') {
              expect(request['token'], 'synthetic-row-token');
              selected = false;
              return jsonEncode({'status': 'loading'});
            }
            if (op == 'course_settle') return jsonEncode({'status': 'removed'});
            if (op == 'course_read') {
              return jsonEncode({
                'status': 'course_ready',
                'picker': {
                  'token': 'synthetic:1',
                  'rowIndex': '4',
                  'page': 'Page 1 / 1',
                  'hasPrevious': false,
                  'hasNext': false,
                  'candidates': [
                    {
                      'key': '0',
                      'code': 'DEMO1000',
                      'teacher': 'Example Teacher',
                      'units': '3',
                      'type': 'Lecture',
                      'time': 'Mon 09:00-09:50',
                    },
                  ],
                },
              });
            }
            if (op == 'course_cancel') {
              return jsonEncode({
                'status': outcome == 'retry-conflict'
                    ? 'conflict'
                    : 'cancelled',
              });
            }
            if (op == 'course_choose') {
              expect(request['token'], 'synthetic:1');
              expect(request['key'], '0');
              selected = outcome != 'conflict';
              return jsonEncode({'status': selected ? 'written' : 'conflict'});
            }
            if (op == 'focus') return jsonEncode({'status': 'focused'});
            if (op == 'read' &&
                selected &&
                ['slow-choose', 'late-reconcile'].contains(outcome) &&
                ++settlementReads <= (outcome == 'late-reconcile' ? 80 : 30)) {
              return jsonEncode({'status': 'busy'});
            }
            return jsonEncode({
              'status': 'ready',
              'fields': {
                'englishName': {'display': 'Synthetic A'},
                if (outcome.startsWith('draft-')) ...{
                  'details': {'value': '', 'editable': true},
                  'familyPhone': {
                    'value': '',
                    'editable': true,
                    'required': true,
                  },
                },
              },
              'reasons': [],
              'courses': [
                if (selected)
                  {
                    'index': '4',
                    'token': 'synthetic-row-token',
                    'code': 'DEMO1000',
                    'teacher': 'Example Teacher',
                    'type': 'Lecture',
                    'time': 'Mon 09:00-09:50',
                  },
              ],
            });
          });
          return null;
        });
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
          if (channelName != null) {
            messenger.setMockMethodCallHandler(
              MethodChannel(channelName!),
              null,
            );
          }
          session.dispose();
        });
        session.pending.complete(
          WebSessionSnapshot(
            baseUrl: 'https://portal.bnbu.edu.cn',
            cookies: const [],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: LeaveApplicationPage(controller: session),
          ),
        );
        await tester.pump();
        await messenger.handlePlatformMessage(
          channelName!,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('pageFinished'),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
        if (outcome.startsWith('draft-')) {
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('leave-details')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.enterText(
            find.byKey(const ValueKey('leave-details')),
            'Synthetic unsaved reason',
          );
          tester.testTextInput.hide();
          await tester.pumpAndSettle();
        }
        await tester.scrollUntilVisible(
          find.text('选择课程与教师'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('选择课程与教师'));
        await tester.pumpAndSettle();
        expect(
          find.byType(LeaveCoursePicker),
          ['unavailable', 'retry-conflict', 'reload'].contains(outcome)
              ? findsNothing
              : findsOneWidget,
        );
        if (['unavailable', 'retry-conflict'].contains(outcome)) {
          await tester.tap(find.text('重新读取课程'));
        } else if (outcome == 'reload') {
          await tester.tap(find.text('重新读取表单'));
        } else if (outcome == 'logout') {
          session.lease.isActive = false;
          session.notifyListeners();
        } else if (outcome == 'cancel' || outcome == 'draft-cancel') {
          await tester.tap(find.byTooltip('取消'));
        } else if (outcome == 'load-failed') {
          final picker = tester.widget<LeaveCoursePicker>(
            find.byType(LeaveCoursePicker),
          );
          tester
              .widget<NativeMirrorWebView>(find.byType(NativeMirrorWebView))
              .onPageFailed!();
          expect((await picker.onPage(picker.initial, true)).status, 'stale');
          expect((await picker.onRetry!()).status, 'stale');
          expect(operations, isNot(contains('course_page')));
        } else {
          await tester.tap(find.text('DEMO1000'));
          await tester.pumpAndSettle();
          expect(find.byType(LeaveCoursePicker), findsOneWidget);
          if (outcome == 'late-reconcile') {
            expect(find.text('已选'), findsNothing);
            expect(find.text('选课尚未确认，请重新读取。'), findsOneWidget);
            expect(find.text('DEMO1000'), findsOneWidget);
            expect(
              operations.where((op) => op == 'course_choose'),
              hasLength(1),
            );
            await tester.tap(
              find.descendant(
                of: find.byType(LeaveCoursePicker),
                matching: find.text('重新读取课程'),
              ),
            );
            await tester.pumpAndSettle();
            expect(settlementReads, greaterThan(75));
          }
          if (outcome != 'conflict') {
            expect(find.text('已选'), findsOneWidget);
            // A second tap cannot dispatch the same school row again.
            await tester.tap(find.text('DEMO1000').last);
            await tester.pumpAndSettle();
            expect(
              operations.where((op) => op == 'course_choose'),
              hasLength(1),
            );
          } else {
            expect(find.text('已选'), findsNothing);
            expect(
              find.descendant(
                of: find.byType(LeaveCoursePicker),
                matching: find.text('重新读取课程'),
              ),
              findsOneWidget,
            );
            expect(find.text('返回表单'), findsNothing);
          }
          await tester.tap(find.byTooltip('取消'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(LeaveCoursePicker), findsNothing);
        expect(
          operations.where((op) => op == 'course_open'),
          hasLength(
            [
                  'choose',
                  'slow-choose',
                  'late-reconcile',
                  'draft-choose',
                  'selected-filter',
                  'remove',
                ].contains(outcome)
                ? 2
                : 1,
          ),
        );
        expect(
          operations.where((op) => op == 'course_choose'),
          hasLength(
            [
                  'choose',
                  'slow-choose',
                  'late-reconcile',
                  'draft-choose',
                  'selected-filter',
                  'conflict',
                  'remove',
                ].contains(outcome)
                ? 1
                : 0,
          ),
        );
        expect(
          operations.where((op) => op == 'course_cancel'),
          hasLength(
            [
                  'cancel',
                  'draft-cancel',
                  'unavailable',
                  'retry-conflict',
                  'reload',
                  'choose',
                  'slow-choose',
                  'late-reconcile',
                  'draft-choose',
                  'selected-filter',
                  'remove',
                  'conflict',
                ].contains(outcome)
                ? 1
                : 0,
          ),
        );
        expect(session.targets, [OfficialWebTarget.portal]);
        if (outcome == 'choose') {
          expect(
            find.text('Example Teacher · Lecture · Mon 09:00-09:50'),
            findsOneWidget,
          );
        }
        if (outcome == 'selected-filter') {
          Future<void> reopen({required bool hidden}) async {
            await tester.ensureVisible(find.text('选择课程与教师'));
            await tester.tap(find.text('选择课程与教师'));
            await tester.pumpAndSettle();
            expect(
              find.descendant(
                of: find.byType(LeaveCoursePicker),
                matching: find.text('DEMO1000'),
              ),
              findsOneWidget,
            );
            if (hidden) {
              expect(find.text('已选'), findsOneWidget);
            }
            await tester.tap(find.byTooltip('取消'));
            await tester.pumpAndSettle();
          }

          await reopen(hidden: true);
          await tester.ensureVisible(find.byTooltip('更换课程'));
          await tester.tap(find.byTooltip('更换课程'));
          await tester.pumpAndSettle();
          expect(find.text('已选'), findsOneWidget);
          await tester.tap(find.byTooltip('取消'));
          await tester.pumpAndSettle();
          // Cancelling removal leaves the school-confirmed selection intact.
          await tester.ensureVisible(find.byTooltip('移除课程'));
          await tester.tap(find.byTooltip('移除课程'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(operations, isNot(contains('course_remove')));
          await reopen(hidden: true);
          await tester.ensureVisible(find.byTooltip('移除课程'));
          await tester.tap(find.byTooltip('移除课程'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('移除'));
          await tester.pumpAndSettle();
          await reopen(hidden: false);
          expect(operations.where((op) => op == 'course_choose'), hasLength(1));
          expect(operations.where((op) => op == 'course_remove'), hasLength(1));
          expect(session.targets, [OfficialWebTarget.portal]);
        }
        if (outcome == 'conflict') {
          expect(find.text('重新读取课程'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('核对并提交'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('核对并提交'));
          await tester.pumpAndSettle();
          expect(find.text('请先重新读取课程，核对学校状态后再提交。'), findsOneWidget);
          expect(operations, isNot(contains('acknowledge')));
          expect(operations, isNot(contains('submit_confirmed')));
        }
        if (outcome == 'retry-conflict') {
          expect(find.text('课程操作仍待学校确认，请稍后重新读取；不会重复操作。'), findsOneWidget);
          expect(find.text('正在同步学校表单'), findsNothing);
          await tester.scrollUntilVisible(
            find.text('核对并提交'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('核对并提交'));
          await tester.pumpAndSettle();
          expect(find.text('请先重新读取课程，核对学校状态后再提交。'), findsOneWidget);
          expect(operations, isNot(contains('acknowledge')));
          expect(operations, isNot(contains('submit_confirmed')));
        }
        if (outcome == 'reload') {
          expect(find.text('暂时无法读取学校课程，请重试。'), findsNothing);
          expect(session.resets, 0);
        }
        expect(find.text('返回表单'), findsNothing);
        expect(find.text('学校原表'), findsNothing);
        if (outcome != 'logout') {
          final web = find.byType(NativeMirrorWebView);
          expect(
            find.ancestor(
              of: web,
              matching: find.byWidgetPredicate(
                (widget) => widget is IgnorePointer && widget.ignoring,
              ),
            ),
            findsWidgets,
          );
          expect(
            find.ancestor(
              of: web,
              matching: find.byWidgetPredicate(
                (widget) => widget is ExcludeSemantics && widget.excluding,
              ),
            ),
            findsWidgets,
          );
        }
        expect(operations, isNot(contains('focus')));
        if (outcome == 'remove') {
          await tester.tap(find.byTooltip('移除课程'));
          await tester.pumpAndSettle();
          expect(find.text('移除此课程？'), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
          expect(operations, isNot(contains('course_remove')));
          await tester.tap(find.byTooltip('移除课程'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('移除'));
          await tester.pumpAndSettle();
          expect(operations.where((op) => op == 'course_remove'), hasLength(1));
          expect(
            find.text('Example Teacher · Lecture · Mon 09:00-09:50'),
            findsNothing,
          );
        }
        if (outcome == 'logout') expect(find.text('Synthetic A'), findsNothing);
        expect(operations, isNot(contains('write')));
        if (outcome.startsWith('draft-')) {
          expect(operations, isNot(contains('validate')));
          await tester.scrollUntilVisible(
            find.byKey(const ValueKey('leave-details')),
            -250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('leave-details')))
                .controller!
                .text,
            'Synthetic unsaved reason',
          );
          await tester.tap(find.text('重新读取表单'));
          await tester.pumpAndSettle();
          // Native draft dirtiness survives course selection/cancellation.
          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(find.text('取消'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets(
    'home leave entry uses dedicated layout and the same Portal owner',
    (tester) async {
      final session = _Session();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: HomePage(
            controller: session,
            onGoToIspace: () {},
            onGoToSchedule: () {},
            onGoToUser: () {},
          ),
        ),
      );
      await tester.pump();
      final entry = find.text('请假申请');
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(LeaveApplicationPage), findsOneWidget);
      final page = tester.widget<LeaveApplicationPage>(
        find.byType(LeaveApplicationPage),
      );
      expect(page.controller, same(session));
      expect(find.byType(OfficialWebPage), findsNothing);
      expect(session.targets, [OfficialWebTarget.portal]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'native-only layout does not recreate the Portal session across widths/themes',
    (tester) async {
      final session = _Session();
      addTearDown(() {
        session.dispose();
        tester.view.reset();
      });
      tester.view.devicePixelRatio = 1;
      for (final width in [320.0, 390.0, 900.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 844);
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: LeaveApplicationPage(controller: session),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('学校原表'), findsNothing);
          expect(find.text('返回表单'), findsNothing);
        }
      }
      expect(session.targets, [OfficialWebTarget.portal]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'native reread preserves drafts until confirmation; account invalidation destroys them',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final session = _Session();
      int? viewId;
      String? channelName;
      var schoolReady = false;
      final channelNames = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      final operations = <String>[];
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          viewId = (call.arguments as Map)['id'] as int;
          channelName = 'ispace/native_webview/$viewId';
          channelNames.add(channelName!);
          messenger.setMockMethodCallHandler(MethodChannel(channelName!), (
            call,
          ) async {
            if (call.method != 'evaluateJavascript') return null;
            final match = RegExp(
              r'\((\{"origin":.*\})\);$',
            ).firstMatch(call.arguments as String)!;
            final op =
                (jsonDecode(match.group(1)!) as Map)['operation'] as String;
            operations.add(op);
            if (op == 'course_cancel') {
              return jsonEncode({'status': 'cancelled'});
            }
            if (!schoolReady) return jsonEncode({'status': 'unsupported'});
            return jsonEncode({
              'status': 'ready',
              'fields': {
                'englishName': {
                  'value': 'Synthetic A',
                  'display': 'Synthetic A',
                },
                'mobile': {'value': '', 'editable': true},
              },
              'reasons': [],
              'courses': [],
            });
          });
        }
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        for (final channel in channelNames) {
          messenger.setMockMethodCallHandler(MethodChannel(channel), null);
        }
        session.dispose();
      });
      session.pending.complete(
        WebSessionSnapshot(
          baseUrl: 'https://portal.bnbu.edu.cn',
          cookies: const [],
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LeaveApplicationPage(controller: session),
        ),
      );
      await tester.pump();
      expect(viewId, isNotNull);
      final failedWeb = tester.widget<NativeMirrorWebView>(
        find.byType(NativeMirrorWebView),
      );
      failedWeb.onPageFailed!();
      await tester.pump();
      expect(find.text('重新读取申请资料'), findsOneWidget);
      await tester.tap(find.text('重新读取申请资料'));
      await tester.pump();
      await tester.pump();
      expect(session.resets, 0);
      expect(session.targets, [OfficialWebTarget.portal]);
      expect(channelNames, hasLength(2));
      failedWeb.onPageFailed!();
      await tester.pump();
      expect(find.text('重新读取申请资料'), findsNothing);
      await messenger.handlePlatformMessage(
        channelName!,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('pageFinished'),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(find.text('学校原表'), findsNothing);
      expect(find.text('重新读取申请资料'), findsOneWidget);
      schoolReady = true;
      await tester.tap(find.text('重新读取申请资料'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic A'), findsOneWidget);
      final oldWeb = tester.widget<NativeMirrorWebView>(
        find.byType(NativeMirrorWebView),
      );
      final field = find.byKey(const ValueKey('leave-mobile'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '11111');
      final countBeforeReload = operations.length;
      await tester.tap(find.text('重新读取表单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('11111'), findsOneWidget);
      expect(operations.length, countBeforeReload);
      await tester.tap(find.text('重新读取表单'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('放弃'));
      await tester.pumpAndSettle();
      expect(find.text('11111'), findsNothing);
      expect(operations.skip(countBeforeReload), ['course_cancel', 'read']);
      expect(session.targets, [OfficialWebTarget.portal]);
      expect(session.resets, 0);
      await tester.ensureVisible(field);
      await tester.enterText(field, '11111');
      oldWeb.onPageFailed!();
      await tester.pumpAndSettle();
      final operationsBeforeFailureRetry = operations.length;
      await tester.tap(find.text('重新读取表单'));
      await tester.pumpAndSettle();
      expect(find.text('11111'), findsOneWidget);
      expect(operations.length, operationsBeforeFailureRetry);
      expect(session.resets, 0);
      expect(find.text('连接已中断，当前填写已保留。请重新打开请假申请后核对学校状态。'), findsOneWidget);
      session.lease.isActive = false;
      session.notifyListeners();
      await tester.pump();
      expect(find.text('Synthetic A'), findsNothing);
      expect(find.text('11111'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('登录状态已变化，请重新打开请假申请。'), findsOneWidget);
      // A queued callback from the removed platform view cannot reset the
      // new controller's Portal target after switching accounts/documents.
      final nextSession = _Session();
      addTearDown(nextSession.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LeaveApplicationPage(controller: nextSession),
        ),
      );
      await tester.pump();
      oldWeb.onAuthenticationRequired!();
      oldWeb.onRetry!();
      oldWeb.onPageFailed!();
      await tester.pump();
      expect(session.resets, 0);
      expect(nextSession.resets, 0);
      expect(nextSession.targets, [OfficialWebTarget.portal]);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'ordinary school pages keep the original shell without layout control',
    (tester) async {
      final session = _Session();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: OfficialWebPage(
            title: 'Portal',
            url: AppConfig.bnbuLeaveApplicationUrl,
            controller: session,
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('查看原版'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'bundled presentation includes only layout and explicit destination config',
    (tester) async {
      final adapter = await tester.runAsync(LeaveApplicationPresentation.load);
      final script = adapter!.script(
        portal: Uri.parse('https://portal.example.edu/path'),
        enabled: false,
        dark: true,
      );
      expect(script, contains('"origin":"https://portal.example.edu"'));
      expect(script, contains('"enabled":false'));
      expect(script, contains('"dark":true'));
      expect(
        adapter.script(
          portal: Uri.parse('https://portal.example.edu'),
          enabled: true,
          dark: false,
          localizations: const BnbuLocalizations(
            Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
          ),
        ),
        contains('申請人資料'),
      );
      for (final forbidden in [
        'document.cookie',
        'localStorage',
        'sessionStorage',
        'fetch(',
        'XMLHttpRequest',
        '.submit(',
        'requestSubmit(',
        'innerHTML =',
      ]) {
        expect(script, isNot(contains(forbidden)));
      }
      expect(
        const BnbuLocalizations(Locale('en')).text('手机排版'),
        'Mobile layout',
      );
      expect(
        const BnbuLocalizations(
          Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        ).text('查看原版'),
        '查看原版',
      );
    },
  );
}
