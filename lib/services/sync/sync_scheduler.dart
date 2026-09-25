import 'dart:async';

/// Shared lifecycle-aware scheduling. Domain state machines retain their own
/// authorization and conflict policies; no UI page owns a network poll loop.
class SyncScheduler {
  SyncScheduler();
  static final shared = SyncScheduler();
  final Map<Object, _SyncJob> _jobs = {};
  Timer? _timer;
  bool _foreground = true;

  void Function() register({
    required Object key,
    required Duration interval,
    required Future<void> Function() run,
    bool background = false,
  }) {
    final job = _SyncJob(interval, run, background);
    _jobs[key] = job;
    _restartTimer();
    return () {
      if (identical(_jobs[key], job)) _jobs.remove(key);
      _restartTimer();
    };
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (_jobs.isEmpty) return;
    final interval = _jobs.values.fold(
      const Duration(seconds: 1),
      (Duration a, b) => b.interval < a ? b.interval : a,
    );
    _timer = Timer.periodic(interval, (_) => tick());
  }

  void setForeground(bool value) {
    _foreground = value;
    if (value) {
      for (final job in _jobs.values) {
        job.next = DateTime.fromMillisecondsSinceEpoch(0);
      }
      tick();
    }
  }

  void tick() {
    final now = DateTime.now();
    for (final job in _jobs.values.toList()) {
      if (job.running ||
          (!_foreground && !job.background) ||
          now.isBefore(job.next)) {
        continue;
      }
      job.running = true;
      job.next = now.add(job.interval);
      unawaited(
        job
            .run()
            .then(
              (_) {
                job.failures = 0;
              },
              onError: (Object _, StackTrace __) {
                job.failures = (job.failures + 1).clamp(0, 6);
                job.next = DateTime.now().add(
                  Duration(seconds: 1 << job.failures),
                );
              },
            )
            .whenComplete(() => job.running = false),
      );
    }
  }
}

class _SyncJob {
  _SyncJob(this.interval, this.run, this.background)
    : next = DateTime.now().add(interval);
  final Duration interval;
  final Future<void> Function() run;
  final bool background;
  DateTime next;
  bool running = false;
  int failures = 0;
}
