import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/landmark_review.dart';
import 'network_retry.dart';

Future<CommunityPolicy> readCommunityPolicy(String topic) async {
  final client = createAppHttpClient();
  try {
    final uri = Uri.parse(
      '${AppConfig.syncServiceBaseUrl}/v2/public/community/policy',
    ).replace(queryParameters: {'topic': topic});
    final request = http.Request('GET', uri)..followRedirects = false;
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return const CommunityPolicy();
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 10),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 8192) return const CommunityPolicy();
    }
    return CommunityPolicy.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );
  } catch (_) {
    return const CommunityPolicy();
  } finally {
    client.close();
  }
}
