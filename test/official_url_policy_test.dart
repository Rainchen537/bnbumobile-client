import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/config/app_config.dart';
import 'package:bnbu_me/models/official_web_target.dart';
import 'package:bnbu_me/services/official_url_policy.dart';

void main() {
  group('OfficialUrlPolicy', () {
    test('school links route only to registered session owners', () {
      for (final base in [
        AppConfig.bnbuPortalBaseUrl,
        AppConfig.bnbuMisBaseUrl,
        AppConfig.ispaceBaseUrl,
      ]) {
        final url = '$base/path?item=1#section';
        expect(OfficialUrlPolicy.schoolDestinationFor(url), Uri.parse(url));
      }
      for (final suffix in [
        '/auth/sso/ssoLogin?service=${AppConfig.bnbuMisServiceId}',
        '/auth/sso/login/${AppConfig.bnbuMisServiceId}?accountName=synthetic',
      ]) {
        expect(
          OfficialUrlPolicy.schoolDestinationFor(
            '${AppConfig.bnbuSsoBaseUrl}$suffix',
          ),
          Uri.parse(AppConfig.bnbuMisBaseUrl),
        );
      }
      for (final url in [
        'http://mis.bnbu.edu.cn/',
        'https://mis.bnbu.edu.cn:444/',
        'https://mis.bnbu.edu.cn.evil.example/',
        'https://user@mis.bnbu.edu.cn/',
        'javascript:location="https://mis.bnbu.edu.cn"',
        'https://unknown.bnbu.edu.cn/',
        '${AppConfig.bnbuSsoBaseUrl}/auth/sso/ssoLogin?service=unknown',
        '${AppConfig.bnbuSsoBaseUrl}/auth/sso/ssoLogin?service=${AppConfig.bnbuMisServiceId}&service=${AppConfig.bnbuPortalServiceId}',
        '${AppConfig.bnbuSsoBaseUrl}/auth/sso/login/${AppConfig.bnbuMisServiceId}?service=${AppConfig.bnbuPortalServiceId}',
      ]) {
        expect(
          OfficialUrlPolicy.schoolDestinationFor(url),
          isNull,
          reason: url,
        );
      }
    });

    test(
      'external navigation is not a source-session authentication failure',
      () {
        expect(
          OfficialUrlPolicy.isAuthenticationRedirectFor(
            '${AppConfig.bnbuSsoBaseUrl}/',
            OfficialWebTarget.portal,
          ),
          isTrue,
        );
        expect(
          OfficialUrlPolicy.isAuthenticationRedirectFor(
            '${AppConfig.bnbuSsoBaseUrl}/auth/sso/ssoLogin?service=${AppConfig.bnbuMisServiceId}',
            OfficialWebTarget.portal,
          ),
          isFalse,
        );
        expect(
          OfficialUrlPolicy.isAuthenticationRedirectFor(
            AppConfig.ispaceBaseUrl,
            OfficialWebTarget.portal,
          ),
          isFalse,
        );
        expect(
          OfficialUrlPolicy.isAuthenticationRedirectFor(
            'https://evil.example/login',
            OfficialWebTarget.portal,
          ),
          isFalse,
        );
      },
    );
    test('allows BNBU HTTPS pages on the default port', () {
      expect(
        OfficialUrlPolicy.requireBnbuUrl(
          'https://www.bnbu.edu.cn/campus_life/Campus_Map.htm',
        ).host,
        'www.bnbu.edu.cn',
      );
      expect(
        OfficialUrlPolicy.requireBnbuUrl(
          'https://directory.bnbu.edu.cn:443/teachers',
        ).port,
        443,
      );
    });

    test(
      'rejects downgrade, userinfo, suffix attacks, and non-default ports',
      () {
        for (final value in <String>[
          'http://www.bnbu.edu.cn/',
          'https://user:password@www.bnbu.edu.cn/',
          'https://bnbu.edu.cn.evil.example/',
          'https://www.bnbu.edu.cn.:443/',
          'https://www.bnbu.edu.cn:444/',
          'https://evil.example/?next=https://bnbu.edu.cn/',
        ]) {
          expect(
            () => OfficialUrlPolicy.requireBnbuUrl(value),
            throwsFormatException,
            reason: value,
          );
        }
      },
    );

    test('rejects empty and oversized URLs', () {
      expect(
        () => OfficialUrlPolicy.requireBnbuUrl('  '),
        throwsFormatException,
      );
      final oversized = 'https://www.bnbu.edu.cn/${'a' * 4080}';
      expect(oversized.length, greaterThan(4096));
      expect(
        () => OfficialUrlPolicy.requireBnbuUrl(oversized),
        throwsFormatException,
      );
    });

    test('classifies only configured MIS and Portal origins', () {
      expect(
        OfficialUrlPolicy.targetFor(
          Uri.parse('${AppConfig.bnbuMisBaseUrl}/mis/usr/index.do'),
        ),
        OfficialWebTarget.mis,
      );
      expect(
        OfficialUrlPolicy.targetFor(
          Uri.parse('${AppConfig.bnbuPortalBaseUrl}/wui/index.html'),
        ),
        OfficialWebTarget.portal,
      );
      expect(
        OfficialUrlPolicy.targetFor(
          Uri.parse('https://www.bnbu.edu.cn/portal'),
        ),
        isNull,
      );
      expect(
        () => OfficialUrlPolicy.requireBnbuUrl(
          '${AppConfig.bnbuPortalBaseUrl}:444/wui/index.html',
        ),
        throwsFormatException,
      );
    });

    test(
      'authenticated root entries resolve to stable in-app landing pages',
      () {
        expect(
          OfficialUrlPolicy.authenticatedEntryFor(
            OfficialWebTarget.mis,
            Uri.parse(AppConfig.bnbuMisBaseUrl),
          ),
          Uri.parse('${AppConfig.bnbuMisBaseUrl}/mis/usr/index.do'),
        );
        expect(
          OfficialUrlPolicy.authenticatedEntryFor(
            OfficialWebTarget.portal,
            Uri.parse('${AppConfig.bnbuPortalBaseUrl}/'),
          ),
          Uri.parse('${AppConfig.bnbuPortalBaseUrl}/wui/index.html'),
        );

        final leaveApplication = Uri.parse(AppConfig.bnbuLeaveApplicationUrl);
        expect(
          OfficialUrlPolicy.targetFor(leaveApplication),
          OfficialWebTarget.portal,
        );
        expect(
          OfficialUrlPolicy.authenticatedEntryFor(
            OfficialWebTarget.portal,
            leaveApplication,
          ),
          leaveApplication,
        );

        final deepMisPage = Uri.parse(
          '${AppConfig.bnbuMisBaseUrl}/mis/student/tts/timetable.do',
        );
        expect(
          OfficialUrlPolicy.authenticatedEntryFor(
            OfficialWebTarget.mis,
            deepMisPage,
          ),
          deepMisPage,
        );
      },
    );

    test('allows only the configured privacy-policy origin outside BNBU', () {
      expect(
        AppConfig.privacyPolicyUrl,
        'https://bnbu.yunwai.cloud/app-privacy.html',
      );
      final privacy = Uri.parse(AppConfig.privacyPolicyUrl);
      final sameOriginPage = privacy.resolve('details.html');
      expect(
        OfficialUrlPolicy.requireTrustedPageUrl(sameOriginPage.toString()),
        sameOriginPage,
      );
      expect(
        () => OfficialUrlPolicy.requireTrustedPageUrl(
          'https://evil.example/privacy',
        ),
        throwsFormatException,
      );
    });

    test('public sessions inject no cookies and use an ephemeral store', () {
      final bnbuUri = Uri.parse(
        'https://www.bnbu.edu.cn/campus_life/Campus_Map.htm',
      );
      final bnbuSession = OfficialUrlPolicy.publicSessionFor(bnbuUri);
      expect(bnbuSession.cookies, isEmpty);
      expect(bnbuSession.allowedOrigins, <String>['https://www.bnbu.edu.cn']);
      expect(bnbuSession.allowedDomains, <String>['bnbu.edu.cn']);
      expect(bnbuSession.useEphemeralSession, isTrue);

      final privacyUri = Uri.parse(AppConfig.privacyPolicyUrl);
      final privacySession = OfficialUrlPolicy.publicSessionFor(privacyUri);
      expect(privacySession.cookies, isEmpty);
      expect(privacySession.allowedDomains, isEmpty);
      expect(privacySession.useEphemeralSession, isTrue);
    });
  });
}
