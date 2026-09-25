import 'dart:convert';
import 'dart:io';

const String ispaceTrustedHost = 'ispace.bnbu.edu.cn';
const String bnbuSchoolIntermediateCertificateSha256 =
    '8BC47366C0E82A249EE1A8769813B7BFD6718D253DD69A6C4B4BE7693362F1E9';
const String bnbuSchoolIntermediateCertificateNotAfter = '2028-01-21T00:00:00Z';

const String bnbuSchoolIntermediateCertificatePem =
    r'''-----BEGIN CERTIFICATE-----
MIIEkDCCA3igAwIBAgIRAIUVBBljp/BI9bl8t9E8LsUwDQYJKoZIhvcNAQELBQAw
TDEgMB4GA1UECxMXR2xvYmFsU2lnbiBSb290IENBIC0gUjMxEzARBgNVBAoTCkds
b2JhbFNpZ24xEzARBgNVBAMTCkdsb2JhbFNpZ24wHhcNMjYwMTIxMDMwMDQ4WhcN
MjgwMTIxMDAwMDAwWjBYMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2ln
biBudi1zYTEuMCwGA1UEAxMlR2xvYmFsU2lnbiBBdGxhcyBSMyBPViBUTFMgQ0Eg
MjAyNiBRMjCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOOmc9ikdLTr
65qXkRqiNpsVm/ktJXtQIYbsos7HHaYviyZKtRLwSKEdUP5BFFCM34/FSDLutlxR
gqpE18MwtEuyeiYpNfhIlYe6T7Ni7lSnRDO5fFUElQ2JoasPFUGnoW2EyHPt0vDq
cLmLeneT2v/BL7EYYaGC5Ilq6oXqlqx6KCNaBbWb6zcgt3EdZi53zRI935UvSpGX
6E/cr+LQklVx+TH5oxGMgt/0chbJvTgMAaR9ZMNgb9C1ipGaWZ80tH5Fsb8TU6d4
Jf1Pvl6hnzJPlJeblVGxpHx0UaAIbGrSdNUZy4YkLHiOZPjKOV3NEWqOZ+r6cPBM
OinO2IuLjkMCAwEAAaOCAV8wggFbMA4GA1UdDwEB/wQEAwIBhjAdBgNVHSUEFjAU
BggrBgEFBQcDAQYIKwYBBQUHAwIwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4E
FgQUkRxtDetU9Y5Vbr0WUCRLgkCuMe8wHwYDVR0jBBgwFoAUj/BLf6guRSSuTVD6
Y5qL3uLdG7wwewYIKwYBBQUHAQEEbzBtMC4GCCsGAQUFBzABhiJodHRwOi8vb2Nz
cDIuZ2xvYmFsc2lnbi5jb20vcm9vdHIzMDsGCCsGAQUFBzAChi9odHRwOi8vc2Vj
dXJlLmdsb2JhbHNpZ24uY29tL2NhY2VydC9yb290LXIzLmNydDA2BgNVHR8ELzAt
MCugKaAnhiVodHRwOi8vY3JsLmdsb2JhbHNpZ24uY29tL3Jvb3QtcjMuY3JsMCEG
A1UdIAQaMBgwCAYGZ4EMAQICMAwGCisGAQQBoDIKAQIwDQYJKoZIhvcNAQELBQAD
ggEBABLrPscDXN3KE4zTGOXzAJthjXJLhuX96kj762BBQbzYLpSAfTrkl5OALccJ
o7IxxzB/aVM3obrfml8t8+zaBRFg4g8OxrRbBQpNBiJJPlYm+Pj4LZHMSvOGGinC
hEej2L0y2NwsNnH4m98xqYFDLc6T3PJspGQRJmfIVQJnlmEAHnBMPi3lP/EiqDJH
74P+5L3GG8eEc8jVo3oJZXgQQuNz+9TKEgH0EGQKPYi0x11ksZnVb/T4lUy7FJqq
FWMu4hCS1m5ges0Np8Z290/jZiGDsbnCTmHNutgwFSRwJCtKTiJ6hI4cw/jodUdy
YobQp2l8RrcOdsRwg9Aakk1OBDk=
-----END CERTIFICATE-----
''';

const String ispaceIntermediateCertificateSha256 =
    bnbuSchoolIntermediateCertificateSha256;
const String ispaceIntermediateCertificateNotAfter =
    bnbuSchoolIntermediateCertificateNotAfter;
const String ispaceIntermediateCertificatePem =
    bnbuSchoolIntermediateCertificatePem;

SecurityContext? createBnbuSchoolSecurityContext(
  Iterable<String> urls, {
  bool? platformIsAndroid,
}) {
  if (!(platformIsAndroid ?? Platform.isAndroid)) return null;
  final normalizedUrls = urls.map((value) => value.trim()).toList();
  if (normalizedUrls.isEmpty ||
      normalizedUrls.any((value) {
        final uri = Uri.tryParse(value);
        if (uri == null) return true;
        final host = uri.host.toLowerCase();
        return uri.scheme.toLowerCase() != 'https' ||
            (host != 'bnbu.edu.cn' && !host.endsWith('.bnbu.edu.cn')) ||
            uri.userInfo.isNotEmpty ||
            uri.hasQuery ||
            uri.hasFragment ||
            (uri.hasPort && uri.port != 443);
      })) {
    return null;
  }
  return SecurityContext(withTrustedRoots: true)..setTrustedCertificatesBytes(
    utf8.encode(bnbuSchoolIntermediateCertificatePem),
  );
}

SecurityContext? createIsSpaceSecurityContext(
  String baseUrl, {
  bool? platformIsAndroid,
}) {
  if (!(platformIsAndroid ?? Platform.isAndroid)) return null;
  final uri = Uri.tryParse(baseUrl.trim());
  if (uri == null || uri.host.toLowerCase() != ispaceTrustedHost) {
    return null;
  }
  return createBnbuSchoolSecurityContext(<String>[
    baseUrl,
  ], platformIsAndroid: platformIsAndroid);
}

/// A safe user-facing classification, independent of the TLS trust policy.
/// Never expose raw exception text or relax certificate verification here.
class SchoolTlsFailure {
  const SchoolTlsFailure({required this.message, required this.isRetryable});
  final String message;
  final bool isRetryable;
}

SchoolTlsFailure classifySchoolTlsFailure(TlsException error) {
  final detail = '${error.message} ${error.osError?.message ?? ''}'
      .toLowerCase();
  final certificateFailure =
      error is CertificateException ||
      const [
        'certificate_verify_failed',
        'certificate verify failed',
        'certificate verification failed',
        'certificate has expired',
        'certificate expired',
        'certificate revoked',
        'hostname mismatch',
        'missing issuer',
        'unable to get local issuer',
        'self signed certificate',
        'self-signed certificate',
        'unknown ca',
        'bad certificate',
      ].any(detail.contains);
  if (certificateFailure) {
    return const SchoolTlsFailure(
      message: '学校服务器证书校验失败，已停止连接，请稍后重试或联系学校。',
      isRetryable: false,
    );
  }
  final interrupted = const [
    'connection terminated during handshake',
    'connection reset',
    'unexpected_eof',
    'unexpected eof',
    'ssl_error_syscall',
    'broken pipe',
  ].any(detail.contains);
  return SchoolTlsFailure(
    message: interrupted ? '学校系统的安全连接暂时中断，请稍后重试。' : '无法与学校系统建立安全连接，请稍后重试。',
    isRetryable: interrupted,
  );
}
