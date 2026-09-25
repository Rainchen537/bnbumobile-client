import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_update_policy_service.dart';

/// Foreground-only event transport; policy payloads are always fetched separately.
class AppUpdateEvents {
  AppUpdateEvents(this.onRevision);
  final void Function(int revision) onRevision;
  http.Client? _client;
  Timer? _retry;
  bool _enabled = false;
  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (enabled) {
      unawaited(_connect());
    } else {
      _retry?.cancel();
      _client?.close();
      _client = null;
    }
  }

  Future<void> _connect() async {
    if (!_enabled) return;
    final client = http.Client();
    _client = client;
    try {
      final uri = Uri.parse('${AppUpdatePolicyService.policyUri}/events');
      final response = await client
          .send(http.Request('GET', uri)..followRedirects = false)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || (response.request?.url ?? uri) != uri) {
        await response.stream.listen(null).cancel();
        throw StateError('Event connection unavailable');
      }
      // Bound each frame before decoding; a malformed stream cannot grow memory.
      var frame = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 45),
      )) {
        if (!_enabled || !identical(client, _client)) break;
        for (final byte in chunk) {
          if (byte == 10) {
            final line = utf8.decode(frame);
            frame = [];
            if (line.startsWith('data: ')) {
              final value = jsonDecode(line.substring(6));
              if (value is Map &&
                  value['revision'] is int &&
                  value['revision'] >= 0) {
                onRevision(value['revision'] as int);
              }
            }
          } else {
            frame.add(byte);
            if (frame.length > 1024) {
              throw const FormatException('Event too large');
            }
          }
        }
      }
    } catch (_) {
      /* Startup/resume/periodic checks remain independent. */
    } finally {
      client.close();
      if (identical(_client, client)) {
        _client = null;
        if (_enabled) {
          _retry = Timer(
            const Duration(seconds: 30),
            () => unawaited(_connect()),
          );
        }
      }
    }
  }

  void dispose() {
    setEnabled(false);
  }
}
