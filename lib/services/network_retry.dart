import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

const appNetworkRetryDelays = <Duration>[
  Duration(milliseconds: 300),
  Duration(milliseconds: 900),
];
const appNetworkMaxConnectionsPerHost = 6;

HttpClient createAppDartHttpClient({
  SecurityContext? securityContext,
  int maxConnectionsPerHost = appNetworkMaxConnectionsPerHost,
}) {
  if (maxConnectionsPerHost < 1 || maxConnectionsPerHost > 80) {
    throw RangeError.range(
      maxConnectionsPerHost,
      1,
      80,
      'maxConnectionsPerHost',
    );
  }
  return HttpClient(context: securityContext)
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 15)
    ..maxConnectionsPerHost = maxConnectionsPerHost;
}

http.Client createAppHttpClient({
  SecurityContext? securityContext,
  int maxConnectionsPerHost = appNetworkMaxConnectionsPerHost,
}) {
  return IOClient(
    createAppDartHttpClient(
      securityContext: securityContext,
      maxConnectionsPerHost: maxConnectionsPerHost,
    ),
  );
}

bool isTransientHttpStatus(int statusCode) {
  return statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode >= 500;
}

bool isTransientNetworkError(Object error) {
  return error is TimeoutException ||
      error is SocketException ||
      error is HttpException ||
      error is http.ClientException;
}

Future<T> retryNetworkOperation<T>(
  Future<T> Function() operation, {
  bool Function(T result)? shouldRetryResult,
  bool Function(Object error)? shouldRetryError,
  List<Duration> retryDelays = appNetworkRetryDelays,
  Future<void> Function(Duration delay)? delay,
}) async {
  final wait = delay ?? Future<void>.delayed;
  for (var attempt = 0; ; attempt++) {
    try {
      final result = await operation();
      if (attempt >= retryDelays.length ||
          shouldRetryResult == null ||
          !shouldRetryResult(result)) {
        return result;
      }
    } catch (error) {
      final retryable =
          shouldRetryError?.call(error) ?? isTransientNetworkError(error);
      if (!retryable || attempt >= retryDelays.length) {
        rethrow;
      }
    }
    await wait(retryDelays[attempt]);
  }
}
