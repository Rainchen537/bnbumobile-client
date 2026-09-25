import 'mail_service.dart';
import '../models/mail_models.dart';
import 'mail_service_stub.dart'
    if (dart.library.io) 'mail_service_io.dart'
    as platform;

MailService createMailService() => platform.createPlatformMailService();

/// A short-lived authentication-only consumer; no mailbox bodies or AI calls.
Future<void> verifyMailCredentials(MailAccessCredentials credentials) async {
  final service = createMailService();
  try {
    if (service is! MailAuthenticationVerifier) {
      throw const MailServiceException('此平台暂时无法验证邮箱。');
    }
    await (service as MailAuthenticationVerifier).verifyCredentials(
      credentials,
    );
  } finally {
    await service.close();
  }
}
