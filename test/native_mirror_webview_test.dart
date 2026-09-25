import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:bnbu_me/models/web_session_snapshot.dart';
import 'package:bnbu_me/widgets/bnbu_loading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:bnbu_me/widgets/native_mirror_webview.dart';

void main() {
  test(
    'passive HTML preserves content and pins resource policy before markup',
    () {
      const source = NativeWebContent.html('''<html><head>
      <base href="https://evil.example/"><meta http-equiv="Refresh" content="0;url=https://evil.example/">
      <style>body {color: red}</style></head><body><p>中文 &amp; body</p>
      <img src="/pluginfile.php/42/image.png"><a href="https://teacher.example/">Link</a>
      <table><tr><td>42</td></tr></table></body></html>''');
      final html = source.documentFor('https://ispace.example.edu');
      expect(html, contains('中文 &amp; body'));
      expect(html, contains('<td>42</td>'));
      expect(html, contains('src="/pluginfile.php/42/image.png"'));
      expect(html, contains('href="https://teacher.example/"'));
      expect(html, isNot(contains('<base')));
      expect(html, isNot(contains('http-equiv="Refresh"')));
      expect(html, contains("script-src 'none'"));
      expect(html, contains('img-src data: https://ispace.example.edu'));
      expect(
        html.indexOf('Content-Security-Policy'),
        lessThan(html.indexOf('<style>')),
      );
      expect(
        source.documentFor('https://user@evil.example'),
        isNot(contains('img-src data: https://evil')),
      );
    },
  );

  test('noscript, script and link payloads cannot survive the mirror', () {
    const source = NativeWebContent.html(
      '<html><head>'
      '<noscript><meta http-equiv="refresh" content="0;url=https://evil.example/"></noscript>'
      '<link rel="preconnect" href="https://evil.example">'
      '<script>location="https://evil.example"</script>'
      '</head><body><p>正文</p></body></html>',
    );
    final html = source.documentFor('https://ispace.example.edu');
    expect(html, isNot(contains('evil.example')));
    expect(html.toLowerCase(), isNot(contains('http-equiv="refresh"')));
    expect(html, isNot(contains('<noscript')));
    expect(html, isNot(contains('<link')));
    expect(html, isNot(contains('<script')));
    expect(html, contains('正文'));
  });

  test(
    'URL mode never grants local document protocols external navigation',
    () {
      for (final url in [
        'data:text/html,<h1>body</h1>',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'blob:https://ispace.example.edu/id',
        'about:blank',
      ]) {
        expect(
          NativeMirrorWebView.allowsMainFrameUrl(
            url: url,
            allowedOrigins: ['https://ispace.example.edu'],
            allowExternalHttpsNavigation: true,
          ),
          isFalse,
          reason: url,
        );
        expect(
          NativeWebContent.url(url).isValidFor(
            WebSessionSnapshot(
              baseUrl: 'https://ispace.example.edu',
              cookies: const [],
            ),
          ),
          isFalse,
        );
      }
      expect(
        const NativeWebContent.html('<p>body</p>').isValidFor(
          WebSessionSnapshot(
            baseUrl: 'http://ispace.example.edu',
            cookies: const [],
          ),
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'HTML links are validated and native rejection is not a successful page',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messenger = tester.binding.defaultBinaryMessenger;
      int? viewId;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          viewId = (call.arguments as Map)['id'] as int;
        }
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      });
      final links = <String>[];
      var finished = 0;
      var failed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeMirrorWebView(
              content: const NativeWebContent.html('<p>body</p>'),
              session: WebSessionSnapshot(
                baseUrl: 'https://ispace.example.edu',
                cookies: [],
              ),
              observeLoginCodes: true,
              observeLeaveSubmission: true,
              onLeaveSubmission: (_) {},
              allowExternalHttpsNavigation: true,
              onHtmlLinkTapped: links.add,
              onPageFinished: () => finished++,
              onPageFailed: () => failed++,
            ),
          ),
        ),
      );
      await tester.pump();
      final params =
          tester.widget<UiKitView>(find.byType(UiKitView)).creationParams!
              as Map;
      expect(params['observeLoginCodes'], isFalse);
      expect(params['observeLeaveSubmission'], isFalse);
      expect(params['allowExternalHttpsNavigation'], isFalse);
      Future<void> event(String method, Object? value) async {
        await messenger.handlePlatformMessage(
          'ispace/native_webview/$viewId',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, value),
          ),
          (_) {},
        );
        await tester.pump();
      }

      await event('htmlLinkActivated', 'https://teacher.example/slides');
      await event('htmlLinkActivated', 'javascript:alert(1)');
      await event('htmlLinkActivated', 'https://user@evil.example/');
      expect(links, ['https://teacher.example/slides']);
      await event('loadRejected', 'cookie_setup');
      await event('pageFinished', null);
      expect(failed, 1);
      expect(finished, 0);
      expect(find.text('网页登录会话准备失败，请重试。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'initial rejection is recovered after the Dart channel attaches',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messenger = tester.binding.defaultBinaryMessenger;
      MethodChannel? channel;
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
        call,
      ) async {
        if (call.method == 'create') {
          channel = MethodChannel(
            'ispace/native_webview/${(call.arguments as Map)['id']}',
          );
          messenger.setMockMethodCallHandler(
            channel!,
            (call) async =>
                call.method == 'getLoadFailure' ? 'content_rules' : null,
          );
        }
        return null;
      });
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
        if (channel != null) messenger.setMockMethodCallHandler(channel!, null);
      });
      var failures = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeMirrorWebView(
              content: const NativeWebContent.url(
                'https://ispace.example.edu/page',
              ),
              session: WebSessionSnapshot(
                baseUrl: 'https://ispace.example.edu',
                cookies: const [],
              ),
              onPageFailed: () => failures++,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(failures, 1);
      expect(find.text('网页内容规则初始化失败，请重试。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final enabled in [false, true]) {
    testWidgets(
      'leave receipts require opt-in and exact narrow payload ($enabled)',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        int? viewId;
        final received = <Map<String, dynamic>>[];
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
          call,
        ) async {
          if (call.method == 'create') {
            viewId = (call.arguments as Map)['id'] as int;
          }
          return null;
        });
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          messenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NativeMirrorWebView(
                content: NativeWebContent.url(
                  'https://portal.bnbu.edu.cn/spa/workflow/static4form/index.html#/main/workflow/req?workflowid=57&iscreate=1',
                ),
                session: WebSessionSnapshot(
                  baseUrl: 'https://portal.bnbu.edu.cn',
                  cookies: const [],
                ),
                observeLeaveSubmission: enabled,
                onLeaveSubmission: received.add,
              ),
            ),
          ),
        );
        await tester.pump();
        final nonce = List.filled(48, 'a').join();
        for (final event in [
          {'nonce': nonce, 'status': 'submission_succeeded', 'requestid': 1},
          {'nonce': 'wrong', 'status': 'submission_succeeded'},
          {'nonce': '$nonce\n', 'status': 'submission_succeeded'},
          {'nonce': nonce, 'status': 'saved'},
          {'nonce': nonce, 'status': 'submission_succeeded'},
        ]) {
          await messenger.handlePlatformMessage(
            'ispace/native_webview/$viewId',
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('leaveSubmission', event),
            ),
            (_) {},
          );
          await tester.pump();
        }
        expect(received, hasLength(enabled ? 1 : 0));
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  test(
    'desktop response detects text attachments but preserves inline preview',
    () {
      NavigationResponse response({
        bool main = true,
        bool canShow = true,
        int status = 200,
        String? disposition,
      }) => NavigationResponse(
        isForMainFrame: main,
        canShowMIMEType: canShow,
        response: URLResponse(
          expectedContentLength: 12,
          statusCode: status,
          mimeType: 'text/plain',
          headers: {
            if (disposition != null) 'Content-Disposition': disposition,
          },
        ),
      );
      expect(
        NativeMirrorWebView.isDesktopAttachmentResponse(
          response(disposition: 'attachment; filename="notes.txt"'),
        ),
        isTrue,
      );
      expect(
        NativeMirrorWebView.isDesktopAttachmentResponse(
          response(disposition: 'INLINE; filename="slides.pdf"'),
        ),
        isFalse,
      );
      expect(
        NativeMirrorWebView.isDesktopAttachmentResponse(
          response(canShow: false),
        ),
        isTrue,
      );
      expect(
        NativeMirrorWebView.isDesktopAttachmentResponse(
          response(main: false, disposition: 'attachment'),
        ),
        isFalse,
      );
      expect(
        NativeMirrorWebView.isDesktopAttachmentResponse(
          response(status: 403, disposition: 'attachment'),
        ),
        isFalse,
      );
    },
  );
  testWidgets(
    'first web load uses the empty canvas and later reload uses a thin bar',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      int? viewId;
      var finishedCallbacks = 0;
      var failedCallbacks = 0;
      var reloads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async {
          if (call.method == 'create') {
            viewId = (call.arguments as Map)['id'] as int;
          }
          return null;
        },
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform_views,
          null,
        );
        if (viewId != null) {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel('ispace/native_webview/$viewId'),
            null,
          );
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeMirrorWebView(
              onPageFinished: () => finishedCallbacks++,
              onPageFailed: () => failedCallbacks++,
              content: NativeWebContent.url('https://example.test'),
              session: WebSessionSnapshot(
                baseUrl: 'https://example.test',
                cookies: const [],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(viewId, isNotNull);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel('ispace/native_webview/$viewId'),
        (call) async {
          if (call.method == 'reload') reloads++;
          return null;
        },
      );
      Future<void> event(String method) async {
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'ispace/native_webview/$viewId',
          const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
          (_) {},
        );
        await tester.pump();
      }

      expect(find.byType(BnbuActivityIndicator), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await event('pageFinished');
      expect(finishedCallbacks, 1);
      expect(find.byType(BnbuActivityIndicator), findsNothing);
      await event('pageStarted');
      expect(find.byType(BnbuActivityIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await event('pageFinished');
      expect(finishedCallbacks, 2);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await event('pageStarted');
      await event('pageError');
      await event('pageFinished');
      expect(
        finishedCallbacks,
        2,
        reason: 'failed loads do not run presentation',
      );
      await tester.pump(const Duration(milliseconds: 350));
      expect(reloads, 1);
      expect(failedCallbacks, 0);
      await event('pageStarted');
      await event('pageError');
      await tester.pump(const Duration(milliseconds: 900));
      expect(reloads, 2);
      expect(failedCallbacks, 0);
      await event('pageStarted');
      await event('pageError');
      await tester.pump(const Duration(milliseconds: 500));
      expect(failedCallbacks, 1);
      await event('pageError');
      await event('pageFinished');
      expect(failedCallbacks, 1);
      expect(finishedCallbacks, 2);
      await event('pageStarted');
      await event('pageError');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(failedCallbacks, 1, reason: 'disposed documents cannot notify');
      debugDefaultTargetPlatformOverride = null;
    },
  );

  const origins = <String>['https://ispace.example.edu'];

  test('login-code action result parses native save and WeChat status', () {
    final result = NativeLoginCodeActionResult.tryParse(<String, Object?>{
      'saved': true,
      'openedWechat': false,
    });

    expect(result.saved, isTrue);
    expect(result.openedWechat, isFalse);
  });

  test('login-code action result fails closed for malformed payloads', () {
    final result = NativeLoginCodeActionResult.tryParse('unexpected');

    expect(result.saved, isFalse);
    expect(result.openedWechat, isFalse);
  });

  test('external navigation stays blocked unless explicitly enabled', () {
    expect(
      NativeMirrorWebView.allowsMainFrameUrl(
        url: 'https://teacher.example.org/slides',
        allowedOrigins: origins,
      ),
      isFalse,
    );
    expect(
      NativeMirrorWebView.allowsMainFrameUrl(
        url: 'https://ispace.example.edu/course',
        allowedOrigins: origins,
      ),
      isTrue,
    );
  });

  test('relaxed iSpace policy accepts teacher HTTP and HTTPS addresses', () {
    bool allows(String url) => NativeMirrorWebView.allowsMainFrameUrl(
      url: url,
      allowedOrigins: origins,
      allowExternalHttpsNavigation: true,
    );

    expect(allows('https://teacher.example.org/slides'), isTrue);
    expect(allows('http://teacher.example.org/slides'), isTrue);
    expect(allows('https://user@teacher.example.org/slides'), isFalse);
    expect(allows('https://teacher.example.org:8443/slides'), isTrue);
  });
}
