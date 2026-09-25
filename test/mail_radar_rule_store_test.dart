import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/services/mail_radar_rule_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('规则按账号隔离，编辑停用和删除可持久恢复', () async {
    const store = MailRadarRuleStore();
    await store.save('student-a', [
      const MailRadarRule(
        sender: 'teacher@bnbu.edu.cn',
        category: MailRadarCategory.action,
      ),
    ]);
    expect(await store.load('student-b'), isEmpty);
    expect((await store.load('student-a')).single.enabled, isTrue);
    await store.save('student-a', [
      const MailRadarRule(
        sender: 'teacher@bnbu.edu.cn',
        category: MailRadarCategory.notice,
        enabled: false,
      ),
    ]);
    final edited = (await store.load('student-a')).single;
    expect(edited.enabled, isFalse);
    expect(edited.category, MailRadarCategory.notice);
    await store.save('student-a', []);
    expect(await store.load('student-a'), isEmpty);
  });
  test('发件人规则使用完整邮箱，拒绝相似地址作为相同身份', () {
    expect(
      MailRadarRule.senderAddress('Teacher <TEACHER@bnbu.edu.cn>'),
      'teacher@bnbu.edu.cn',
    );
    expect(
      MailRadarRule.senderAddress('teacher@bnbu.edu.cn.evil.example'),
      isNot('teacher@bnbu.edu.cn'),
    );
  });
}
