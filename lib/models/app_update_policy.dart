import 'app_update.dart';

/// BNBU product versions have three shared components and an optional platform fix.
class ProductVersion implements Comparable<ProductVersion> {
  ProductVersion.parse(String value) {
    if (!RegExp(
      r'^(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})\.(0|[1-9]\d{0,3})(?:\.(0|[1-9]\d{0,3}))?$',
    ).hasMatch(value)) {
      throw const FormatException('Invalid product version');
    }
    parts = value.split('.').map(int.parse).toList();
    if (parts.length == 3) parts.add(0);
  }
  late final List<int> parts;
  @override
  int compareTo(ProductVersion other) {
    for (var i = 0; i < 4; i++) {
      final result = parts[i].compareTo(other.parts[i]);
      if (result != 0) return result;
    }
    return 0;
  }

  @override
  String toString() => parts.take(parts[3] == 0 ? 3 : 4).join('.');
}

enum UpdateTrigger { startup, resume, login, navigation, periodic, remoteEvent }

class UpdateCheckOptions {
  const UpdateCheckOptions({
    this.cacheSeconds = 21600,
    this.retrySeconds = 300,
    this.deferSeconds = 86400,
    this.repeatSeconds = 86400,
    this.validSeconds = 86400,
    this.eventDebounceSeconds = 5,
    this.triggers = const {
      'startup': true,
      'resume': true,
      'login': true,
      'navigation': false,
      'periodic': true,
      'remote_event': true,
    },
  });
  final int cacheSeconds,
      retrySeconds,
      deferSeconds,
      repeatSeconds,
      validSeconds,
      eventDebounceSeconds;
  final Map<String, bool> triggers;
  bool allows(UpdateTrigger trigger) =>
      triggers[trigger == UpdateTrigger.remoteEvent
          ? 'remote_event'
          : trigger.name] ??
      false;
  factory UpdateCheckOptions.fromJson(Map<String, dynamic> policy) {
    final t = policy['timing'] as Map<String, dynamic>;
    int number(String key, int min, int max) {
      final n = t[key];
      if (n is! int || n < min || n > max) {
        throw const FormatException('Invalid update timing');
      }
      return n;
    }

    final triggers = Map<String, bool>.from(policy['triggers'] as Map);
    final result = UpdateCheckOptions(
      cacheSeconds: number('cache_seconds', 60, 86400),
      retrySeconds: number('retry_seconds', 30, 3600),
      deferSeconds: number('defer_seconds', 300, 604800),
      repeatSeconds: number('repeat_seconds', 300, 604800),
      validSeconds: number('policy_valid_seconds', 300, 604800),
      eventDebounceSeconds: number('event_debounce_seconds', 1, 60),
      triggers: triggers,
    );
    if (result.validSeconds < result.cacheSeconds) {
      throw const FormatException('Invalid policy validity');
    }
    return result;
  }
}

class UpdateDecision {
  const UpdateDecision({
    this.release,
    this.options = const UpdateCheckOptions(),
    this.revision = 0,
  });
  final AppUpdateRelease? release;
  final UpdateCheckOptions options;
  final int revision;
}
