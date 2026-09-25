import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/mail_compose_signature_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'signature selection is account scoped and does not affect another mailbox',
    () async {
      final store = MailComposeSignatureStore();
      await store.save('one@mail.bnbu.edu.cn', MailComposeSignature.bnbuMe);

      expect(
        await store.load('one@mail.bnbu.edu.cn'),
        MailComposeSignature.bnbuMe,
      );
      expect(
        await store.load('two@mail.bnbu.edu.cn'),
        MailComposeSignature.none,
      );
    },
  );
}
