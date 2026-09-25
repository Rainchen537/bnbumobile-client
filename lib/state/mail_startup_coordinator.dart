import 'dart:async';
import '../models/mail_models.dart';

import '../services/campus_contact_index.dart';
import '../services/campus_directory_service.dart';
import '../services/mail_sender_avatar_service.dart';
import '../services/mail_service.dart';
import '../services/mail_service_factory.dart';
import 'app_session_controller.dart';
import 'mail_access_controller.dart';

/// Ordinary local mail caching is independent of radar permission and consent.
/// Owns the same IMAP service used by the visible mailbox, never a hidden page.
class MailStartupCoordinator {
  MailStartupCoordinator({
    required this.sessionController,
    MailService? mailService,
    this.pollInterval = const Duration(minutes: 2),
    Future<void> Function()? warmContacts,
  }) : mailService = mailService ?? createMailService(),
       _warmContactsOverride = warmContacts;

  final AppSessionController sessionController;
  final MailService mailService;
  final Duration pollInterval;
  final Future<void> Function()? _warmContactsOverride;
  Timer? _timer;
  StreamSubscription<void>? _subscription;
  Future<void>? _running;
  bool _started = false, _disposed = false, _foreground = true, _again = false;
  int _generation = 0;
  String? _account;
  int _mailRevision = -1;

  void start() {
    if (_started || _disposed) return;
    _started = true;
    sessionController.addListener(_sessionChanged);
    unawaited(
      (_warmContactsOverride?.call() ?? _warmContacts()).catchError(
        (Object _) {},
      ),
    );
    final monitor = mailService;
    if (monitor is MailInboxMonitor) {
      _subscription = (monitor as MailInboxMonitor).inboxChanges.listen(
        (_) => refresh(),
      );
    }
    if (pollInterval > Duration.zero) {
      _timer = Timer.periodic(pollInterval, (_) => refresh());
    }
    _sessionChanged();
  }

  void _sessionChanged() {
    final account = sessionController.isLoggedIn
        ? sessionController.username
        : null;
    final access = sessionController.mailAccess;
    if (_account == account) {
      if (_mailRevision != access.revision) {
        _mailRevision = access.revision;
        if (access.status == MailAccessStatus.pending ||
            access.status == MailAccessStatus.connected) {
          refresh();
        }
        if (access.status == MailAccessStatus.skipped ||
            access.status == MailAccessStatus.needsPassword) {
          _generation++;
          unawaited(mailService.close());
        }
      }
      return;
    }
    _mailRevision = access.revision;
    _account = account;
    _generation++;
    if (account == null) {
      unawaited(mailService.close());
    } else {
      refresh();
    }
  }

  void setForeground(bool foreground) {
    _foreground = foreground;
    if (foreground) refresh();
  }

  Future<void> refresh() {
    if (_disposed || !_foreground || _account == null) return Future.value();
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    final generation = _generation;
    return _running = _refresh(generation).whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        unawaited(refresh());
      }
    });
  }

  bool _current(int generation) =>
      !_disposed &&
      _foreground &&
      generation == _generation &&
      sessionController.isLoggedIn;

  Future<void> _refresh(int generation) async {
    MailAccessCredentials? credentials;
    try {
      credentials = await sessionController.loadMailAccessCredentials();
      if (!_current(generation) || credentials == null) return;
      final snapshot = await mailService.fetchFolder(credentials: credentials);
      if (!_current(generation)) return;
      final organization = mailService;
      if (organization is MailOrganizationService) {
        final messages = [...snapshot.messages]
          ..sort((a, b) {
            if (a.isSeen != b.isSeen) return a.isSeen ? 1 : -1;
            return b.uid.compareTo(a.uid);
          });
        for (final message in messages) {
          if (!_current(generation)) return;
          unawaited(
            IoMailSenderAvatarService.sharedPortraitCache
                .loadThumbnail(message.sender)
                .catchError((Object _) => null),
          );
          await (organization as MailOrganizationService).loadPreviews(
            credentials: credentials,
            messages: [message],
          );
        }
      }
      if (!_current(generation)) return;
      final monitor = mailService;
      if (monitor is MailInboxMonitor) {
        await (monitor as MailInboxMonitor).startInboxMonitoring(
          credentials: credentials,
        );
      }
    } on MailAuthenticationException {
      if (credentials != null && _current(generation)) {
        await sessionController.mailAccess.reportAuthenticationFailure(
          credentials,
        );
      }
    } on Object {
      /* Keep disk content; the next foreground/event refresh retries. */
    }
  }

  Future<void> _warmContacts() async {
    final index = CampusContactIndex.shared;
    await index.loadLocal();
    final directory = RemoteCampusDirectoryService();
    final refresh = Future.wait([
      index.refresh(force: true).catchError((Object _) {}),
      directory
          .loadOrganizations()
          .then<void>((_) {})
          .catchError((Object _) {}),
    ]).whenComplete(directory.dispose);
    await _warmPortraits();
    await refresh;
    await _warmPortraits();
  }

  Future<void> _warmPortraits() async {
    final index = CampusContactIndex.shared;
    final urls = {
      for (final teacher in [
        ...index.teachers,
        for (final organization in index.organizations)
          ...organization.embeddedStaff,
      ])
        if (teacher.photoUrl.isNotEmpty) teacher.photoUrl,
    }.iterator;
    Future<void> worker() async {
      while (!_disposed && urls.moveNext()) {
        final url = urls.current;
        while (!_disposed && !_foreground) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (_disposed) return;
        final portraits = IoMailSenderAvatarService.sharedPortraitCache;
        // The disk cache is the checkpoint across short app sessions. Cached
        // entries must not consume the network pacing delay on every launch.
        if (await portraits.hasCachedTeacherPortrait(url)) continue;
        await portraits.loadTeacherPortrait(url);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }

    await Future.wait([worker(), worker()]);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    sessionController.removeListener(_sessionChanged);
    unawaited(mailService.close());
  }
}
