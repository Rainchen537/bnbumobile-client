import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bnbu_me/services/network_retry.dart';

void main() {
  test('app transport keeps its normal cap and bounds acceptance bursts', () {
    final standard = createAppDartHttpClient();
    final acceptance = createAppDartHttpClient(maxConnectionsPerHost: 80);
    addTearDown(() {
      standard.close(force: true);
      acceptance.close(force: true);
    });

    expect(standard.maxConnectionsPerHost, appNetworkMaxConnectionsPerHost);
    expect(acceptance.maxConnectionsPerHost, 80);
    expect(
      () => createAppDartHttpClient(maxConnectionsPerHost: 0),
      throwsRangeError,
    );
    expect(
      () => createAppDartHttpClient(maxConnectionsPerHost: 81),
      throwsRangeError,
    );
  });

  test(
    'transient response is retried without replaying permanent failures',
    () async {
      var attempts = 0;
      final response = await retryNetworkOperation<http.Response>(
        () async {
          attempts++;
          return http.Response('', attempts == 1 ? 503 : 200);
        },
        shouldRetryResult: (value) => isTransientHttpStatus(value.statusCode),
        delay: (_) async {},
      );

      expect(response.statusCode, 200);
      expect(attempts, 2);

      attempts = 0;
      final permanent = await retryNetworkOperation<http.Response>(
        () async {
          attempts++;
          return http.Response('', 400);
        },
        shouldRetryResult: (value) => isTransientHttpStatus(value.statusCode),
        delay: (_) async {},
      );
      expect(permanent.statusCode, 400);
      expect(attempts, 1);
    },
  );

  test(
    'transient transport failure is retried with a bounded budget',
    () async {
      var attempts = 0;
      final result = await retryNetworkOperation<String>(() async {
        attempts++;
        if (attempts < 3) {
          throw http.ClientException('connection reset');
        }
        return 'ok';
      }, delay: (_) async {});

      expect(result, 'ok');
      expect(attempts, 3);
    },
  );
}
