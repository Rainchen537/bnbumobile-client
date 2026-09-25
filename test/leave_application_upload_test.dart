import 'dart:async';
import 'dart:convert';

import 'package:bnbu_me/models/leave_application_form.dart';
import 'package:bnbu_me/models/official_web_target.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/pages/leave_application_page.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/leave_application_review.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/home_navigation_fixtures.dart';

class _Lease implements AppSessionLease {
  @override
  String get owner => 'synthetic';
  @override
  bool isActive = true;
}

class _Session extends HomeNavigationFixture {
  final lease = _Lease();
  @override
  AppSessionLease captureSessionLease() => lease;
  @override
  Future<WebSessionSnapshot> prepareOfficialWebSession(
    OfficialWebTarget target,
  ) async => WebSessionSnapshot(
    baseUrl: 'https://portal.bnbu.edu.cn',
    cookies: const [],
  );
}

class _Picker extends FilePicker {
  final picked = Completer<FilePickerResult?>();
  int calls = 0;
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
  }) {
    expect(allowMultiple, false);
    expect(withData, false);
    expect(withReadStream, true);
    calls++;
    return picked.future;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rootBundle.evict('assets/leave_application/bridge.js');
  });

  test(
    'required validation uses draft values and school attachment/course metadata',
    () {
      final form = LeaveApplicationForm(
        fields: const {
          'familyPhone': LeaveApplicationField(required: true, editable: true),
          'details': LeaveApplicationField(required: true, editable: true),
        },
        completion: const LeaveFormCompletion(
          attachmentRequired: true,
          missingCourses: true,
        ),
      );
      expect(form.missingRequired({'details': 'Synthetic reason'}), [
        '家人联系电话',
        '涉及课程与教师',
        '证明材料',
      ]);
      final optional = LeaveApplicationForm(fields: const {});
      expect(optional.missingRequired(), isEmpty);
      final confirmed = LeaveApplicationForm(
        fields: const {},
        completion: const LeaveFormCompletion(
          attachmentRequired: true,
          filesKnown: true,
          files: [LeaveSchoolAttachment('file-handle', 'proof.pdf')],
        ),
      );
      expect(confirmed.missingRequired(), isEmpty);
    },
  );

  for (final outcome in [
    'confirmed',
    'cancel',
    'stream-failed',
    'oversize',
    'unconfirmed',
    'late-confirmed',
    'uploader-changed',
    'logout',
  ]) {
    testWidgets(
      'native attachment refreshes handles and preserves drafts ($outcome)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final session = _Session(), picker = _Picker();
        FilePicker.platform = picker;
        String? channel;
        var revision = 0, uploaded = false, schoolConfirmed = false;
        final operations = <String>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          if (call.method != 'create') return null;
          channel = 'ispace/native_webview/${(call.arguments as Map)['id']}';
          messenger.setMockMethodCallHandler(MethodChannel(channel!), (
            call,
          ) async {
            if (call.method != 'evaluateJavascript') return null;
            final match = RegExp(
              r'\((\{"origin":.*\})\);$',
            ).firstMatch(call.arguments as String)!;
            final r = jsonDecode(match.group(1)!) as Map;
            final op = r['operation'] as String;
            operations.add(op);
            if (op == 'upload_begin') {
              expect(r['token'], 'fresh-$revision');
              expect(revision, greaterThanOrEqualTo(3));
              return jsonEncode({'status': 'upload_buffering'});
            }
            if (op == 'upload_chunk') {
              return jsonEncode({'status': 'upload_buffering'});
            }
            if (op == 'upload_abort') {
              return jsonEncode({'status': 'cancelled'});
            }
            if (op == 'upload_dispatch') {
              return jsonEncode({'status': 'upload_unconfirmed'});
            }
            if (op == 'upload_status') {
              uploaded = outcome == 'confirmed' || schoolConfirmed;
              return jsonEncode({
                'status': uploaded ? 'uploaded' : 'upload_unconfirmed',
              });
            }
            expect(['read', 'attach'].contains(op), true);
            revision++;
            return jsonEncode({
              'status': 'ready',
              'fields': {
                'details': {'value': '', 'editable': true},
              },
              'reasons': [],
              'courses': [],
              'completion': {
                'token': 'fresh-$revision',
                'canUpload':
                    revision > 1 &&
                    !(outcome == 'uploader-changed' && revision >= 3),
                'canSubmit': true,
                'attachmentRequired': true,
                'filesKnown': true,
                'maxBytes': 20 * 1024 * 1024,
                'files': [
                  if (uploaded)
                    {'key': 'attachment-handle', 'name': 'proof.pdf'},
                ],
              },
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
          if (channel != null) {
            messenger.setMockMethodCallHandler(MethodChannel(channel!), null);
          }
          session.dispose();
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: LeaveApplicationPage(controller: session),
          ),
        );
        await tester.pump();
        await messenger.handlePlatformMessage(
          channel!,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('pageFinished'),
          ),
          (_) {},
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('leave-details')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(
          find.byKey(const ValueKey('leave-details')),
          'Keep this synthetic draft',
        );
        tester.testTextInput.hide();
        await tester.scrollUntilVisible(
          find.text('选择附件并上传至学校'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('选择附件并上传至学校'));
        await tester.pumpAndSettle();
        expect(picker.calls, 1); // Initial unmounted uploader is refreshed.
        await tester.pump(
          const Duration(minutes: 6),
        ); // Old completion handle has expired.
        if (outcome == 'logout') {
          session.lease.isActive = false;
          session.notifyListeners();
        }
        picker.picked.complete(
          outcome == 'cancel'
              ? null
              : FilePickerResult([
                  PlatformFile(
                    name: 'proof.pdf',
                    size: outcome == 'oversize' ? 21 * 1024 * 1024 : 3,
                    readStream: outcome == 'stream-failed'
                        ? Stream.error(const FormatException())
                        : Stream.value([1, 2, 3]),
                  ),
                ]),
        );
        await tester.pumpAndSettle();
        // Platform file streams may resume outside the frame scheduler.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        for (var i = 0; i < 55; i++) {
          await tester.pump(const Duration(milliseconds: 400));
        }
        await tester.pumpAndSettle();
        expect(operations, isNot(contains('validate')));
        expect(operations, isNot(contains('write')));
        expect(operations, isNot(contains('acknowledge')));
        expect(operations, isNot(contains('submit_confirmed')));
        expect(
          operations.where((o) => o == 'upload_dispatch'),
          hasLength(
            ['confirmed', 'unconfirmed', 'late-confirmed'].contains(outcome)
                ? 1
                : 0,
          ),
          reason: operations.join(', '),
        );
        if (outcome == 'confirmed') {
          expect(find.text('已上传至学校'), findsOneWidget);
          expect(find.text('proof.pdf'), findsOneWidget);
        } else {
          expect(find.text('已上传至学校'), findsNothing);
        }
        expect(find.text('正在上传附件'), findsNothing);
        expect(find.text('正在同步学校表单'), findsNothing);
        if (outcome == 'uploader-changed') {
          expect(operations, isNot(contains('upload_begin')));
          expect(find.text('暂时无法确认学校附件控件，请重新读取。'), findsOneWidget);
        }
        if (['unconfirmed', 'late-confirmed'].contains(outcome)) {
          await tester.scrollUntilVisible(
            find.text('重新读取附件状态'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('重新读取附件状态'));
          await tester.pumpAndSettle();
          // Even if the read form claims canUpload, uncertain status cannot
          // clear the error and permit a duplicate upload.
          expect(find.text('重新读取附件状态'), findsOneWidget);
          await tester.tap(find.text('选择附件并上传至学校'));
          await tester.pumpAndSettle();
          expect(picker.calls, 1);
          if (outcome == 'late-confirmed') {
            schoolConfirmed = true;
            await tester.tap(find.text('重新读取附件状态'));
            await tester.pumpAndSettle();
            expect(find.text('proof.pdf'), findsOneWidget);
            expect(find.text('已上传至学校'), findsOneWidget);
            expect(find.text('重新读取附件状态'), findsNothing);
          }
          expect(operations.where((o) => o == 'upload_dispatch'), hasLength(1));
        }
        if (outcome != 'logout') {
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
            'Keep this synthetic draft',
          );
        }
        if (outcome == 'cancel') {
          await tester.scrollUntilVisible(
            find.text('核对并提交'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('核对并提交'));
          await tester.pumpAndSettle();
          expect(find.byType(LeaveApplicationReview), findsNothing);
          expect(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('证明材料'),
            ),
            findsOneWidget,
          );
          await tester.tap(find.text('返回修改'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
