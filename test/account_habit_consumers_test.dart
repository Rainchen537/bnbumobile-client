import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/pages/ispace_page.dart';
import 'package:bnbu_me/services/mail_compose_signature_store.dart';
import 'package:bnbu_me/services/deadline_reminder_service.dart';
import 'package:bnbu_me/state/account_habits.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/state/app_language_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';

class _Session extends AppSessionController {
  @override
  String get username => 'fixture';
  @override
  bool get isLoggedIn => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  var values = <String, dynamic>{};
  void receive() => AccountHabits.shared.attachWindowSnapshot(
    'fixture',
    values,
    (key, value) async {
      values = {
        ...values,
        key: {'value': value, 'source': 'explicit'},
      };
      AccountHabits.shared.attachWindowSnapshot(
        'fixture',
        values,
        (k, v) async {},
      );
    },
  );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    values = {};
    receive();
  });
  tearDown(() => AccountHabits.shared.detachWindowSnapshot());

  testWidgets(
    'remote habit update reaches the real iSpace filter and sort controls',
    (tester) async {
      final session = _Session();
      addTearDown(session.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: IspacePage(controller: session, onGoToUserTab: () {}),
        ),
      );
      await tester.pumpAndSettle();
      values = {
        'ispace.dashboard.date_filter': {
          'value': 'next30Days',
          'source': 'explicit',
        },
        'ispace.dashboard.sort_mode': {
          'value': 'byCourses',
          'source': 'explicit',
        },
      };
      receive();
      await tester.pumpAndSettle();
      expect(find.text('未来 30 天'), findsOneWidget);
      expect(find.text('按课程排序'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'signature accepts the same account email and writes through the shared repository',
    () async {
      final signature = MailComposeSignatureStore();
      await signature.save(
        'fixture@mail.bnbu.edu.cn',
        MailComposeSignature.bnbuMe,
      );
      expect(values['mail.compose.signature']['value'], 'bnbu-me');
      expect(
        await signature.load('fixture@mail.bnbu.edu.cn'),
        MailComposeSignature.bnbuMe,
      );
      expect(
        await signature.load('other@mail.bnbu.edu.cn'),
        MailComposeSignature.none,
      );
    },
  );

  test(
    'appearance language and reminder policy read the same account preferences',
    () async {
      values = {
        'app.appearance.theme_mode': {'value': 'dark', 'source': 'explicit'},
        'app.appearance.language_mode': {
          'value': 'english',
          'source': 'explicit',
        },
        'course_reminders.lead_minutes': {'value': 30, 'source': 'explicit'},
        'deadline_reminders.policy': {
          'value': {
            'mode': 'fixed',
            'count': 1,
            'leads': [90],
            'quietStart': 0,
            'quietEnd': 360,
          },
          'source': 'explicit',
        },
      };
      receive();
      final theme = AppThemeModeController(
        liquidGlassSupportLoader: () async => false,
      );
      final language = AppLanguageController();
      await theme.restore();
      await language.restore(preferredLocales: [const Locale('zh', 'CN')]);
      expect(theme.themeMode, ThemeMode.dark);
      expect(language.mode, AppLanguageMode.english);
      final notifications = DeadlineReminderService();
      expect(await notifications.loadCourseLeadMinutes(), 30);
      expect(
        (await notifications.loadDeadlineReminderPreferences())
            .fixedLeadMinutes,
        [90],
      );
      theme.dispose();
      language.dispose();
    },
  );
}
