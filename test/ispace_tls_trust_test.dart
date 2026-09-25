import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/config/ispace_tls_trust.dart';

void main() {
  test(
    'TLS classification prioritizes verified certificate errors over interruption text',
    () {
      for (final error in [
        const HandshakeException(
          'Handshake error',
          OSError('CERTIFICATE_VERIFY_FAILED: certificate has expired', 1),
        ),
        const HandshakeException('Connection reset: CERTIFICATE_VERIFY_FAILED'),
        const CertificateException('certificate unavailable'),
      ]) {
        final failure = classifySchoolTlsFailure(error);
        expect(failure.message, contains('证书校验失败'));
        expect(failure.isRetryable, isFalse);
      }
      final interrupted = classifySchoolTlsFailure(
        const HandshakeException('Connection terminated during handshake'),
      );
      expect(interrupted.message, contains('安全连接暂时中断'));
      expect(interrupted.isRetryable, isTrue);
      final unknown = classifySchoolTlsFailure(
        const HandshakeException('TLS protocol version mismatch'),
      );
      expect(unknown.message, isNot(contains('证书')));
      expect(unknown.isRetryable, isFalse);
    },
  );

  test(
    'Android adds the verified iSpace intermediate only for the exact host',
    () {
      expect(
        createIsSpaceSecurityContext(
          'https://ispace.bnbu.edu.cn',
          platformIsAndroid: true,
        ),
        isNotNull,
      );
      expect(
        createIsSpaceSecurityContext(
          'https://ispace.bnbu.edu.cn:443',
          platformIsAndroid: true,
        ),
        isNotNull,
      );
      for (final rejected in [
        'http://ispace.bnbu.edu.cn',
        'https://ispace.bnbu.edu.cn.evil.example',
        'https://user@ispace.bnbu.edu.cn',
        'https://ispace.bnbu.edu.cn:444',
        'https://ispace.bnbu.edu.cn?redirect=1',
      ]) {
        expect(
          createIsSpaceSecurityContext(rejected, platformIsAndroid: true),
          isNull,
          reason: rejected,
        );
      }
      expect(
        createIsSpaceSecurityContext(
          'https://ispace.bnbu.edu.cn',
          platformIsAndroid: false,
        ),
        isNull,
      );
    },
  );

  test('Android adds the verified intermediate only to BNBU HTTPS URLs', () {
    expect(
      createBnbuSchoolSecurityContext(const <String>[
        'https://sso.bnbu.edu.cn',
        'https://mis.bnbu.edu.cn',
        'https://portal.bnbu.edu.cn:443/wui/index.html',
        'https://ar.bnbu.edu.cn/attachment/file/calendar.pdf',
        'https://staff.bnbu.edu.cn',
        'https://gs.bnbu.edu.cn',
      ], platformIsAndroid: true),
      isNotNull,
    );
    for (final rejected in <List<String>>[
      const <String>[],
      const <String>['http://mis.bnbu.edu.cn'],
      const <String>['https://mis.bnbu.edu.cn.evil.example'],
      const <String>['https://user@mis.bnbu.edu.cn'],
      const <String>['https://mis.bnbu.edu.cn:444'],
      const <String>['https://mis.bnbu.edu.cn?next=1'],
      const <String>['https://mis.bnbu.edu.cn', 'https://attacker.example'],
    ]) {
      expect(
        createBnbuSchoolSecurityContext(rejected, platformIsAndroid: true),
        isNull,
        reason: rejected.join(', '),
      );
    }
    expect(
      createBnbuSchoolSecurityContext(const <String>[
        'https://mis.bnbu.edu.cn',
      ], platformIsAndroid: false),
      isNull,
    );
  });

  test('pinned public intermediate stays byte-stable and time-bounded', () {
    expect(
      sha256.convert(utf8.encode(ispaceIntermediateCertificatePem)).toString(),
      '258164ee031fda41596da62667e6418abc623feffce66101c54c2ec518bbd289',
    );
    expect(
      bnbuSchoolIntermediateCertificateSha256,
      '8BC47366C0E82A249EE1A8769813B7BFD6718D253DD69A6C4B4BE7693362F1E9',
    );
    expect(
      DateTime.parse(
        bnbuSchoolIntermediateCertificateNotAfter,
      ).isAfter(DateTime.utc(2026, 8, 26)),
      isTrue,
    );
    final androidCertificate = File(
      'android/app/src/main/res/raw/'
      'globalsign_atlas_r3_ov_tls_ca_2026_q2.pem',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    expect(
      androidCertificate.trim(),
      bnbuSchoolIntermediateCertificatePem.trim(),
    );
  });

  test('Android native trust remains scoped to the BNBU domain family', () {
    final config = File(
      'android/app/src/main/res/xml/network_security_config.xml',
    ).readAsStringSync();
    expect(config, contains('<domain includeSubdomains="true">bnbu.edu.cn'));
    expect(config, contains('<certificates src="system" />'));
    expect(
      config,
      contains(
        '<certificates '
        'src="@raw/globalsign_atlas_r3_ov_tls_ca_2026_q2" />',
      ),
    );
    expect(config, isNot(contains('certificates src="user"')));
  });
}
