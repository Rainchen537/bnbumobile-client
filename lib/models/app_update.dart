enum AppUpdatePlatform { android, ios, macos, windows, unsupported }

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.platform,
    required this.version,
    required this.buildNumber,
    required this.downloadUri,
    this.releaseNotes = const [],
    this.artifactSha256,
    this.artifactSize,
    this.nativeVersion,
    this.mandatory = false,
    this.policyRevision = 0,
    this.mandatoryReason = '',
    this.mandatoryReasonEn = '',
    this.mandatoryAfter,
    this.validUntil,
    this.releaseNotesEn = const [],
  });

  final AppUpdatePlatform platform;
  final String version;
  final String? nativeVersion;
  final bool mandatory;
  final int policyRevision;
  final String mandatoryReason;
  final String mandatoryReasonEn;
  final DateTime? mandatoryAfter;
  final DateTime? validUntil;
  final List<String> releaseNotesEn;
  final int? buildNumber;
  final Uri downloadUri;
  final List<String> releaseNotes;
  final String? artifactSha256;
  final int? artifactSize;

  static const maxAndroidArtifactBytes = 512 * 1024 * 1024;

  bool get canInstallInApp =>
      platform == AppUpdatePlatform.android &&
      buildNumber != null &&
      buildNumber! > 0 &&
      artifactSha256 != null &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(artifactSha256!) &&
      artifactSize != null &&
      artifactSize! > 0 &&
      artifactSize! <= maxAndroidArtifactBytes;

  String get versionLabel {
    final build = buildNumber;
    return build == null ? version : '$version+$build';
  }
}

sealed class AppUpdateState {
  const AppUpdateState();

  AppUpdateRelease? get release => null;
}

final class AppUpdateIdle extends AppUpdateState {
  const AppUpdateIdle();
}

final class AppUpdateUnsupported extends AppUpdateState {
  const AppUpdateUnsupported();
}

final class AppUpdateChecking extends AppUpdateState {
  const AppUpdateChecking();
}

final class AppUpdateUpToDate extends AppUpdateState {
  const AppUpdateUpToDate();
}

final class AppUpdateAvailable extends AppUpdateState {
  const AppUpdateAvailable(this.value);

  final AppUpdateRelease value;

  @override
  AppUpdateRelease get release => value;
}

final class AppUpdateFailed extends AppUpdateState {
  const AppUpdateFailed(this.error, {this.value, required this.retryAction});

  final Object error;
  final AppUpdateRelease? value;
  final AppUpdateRetryAction retryAction;

  @override
  AppUpdateRelease? get release => value;
}

final class AppUpdateDownloading extends AppUpdateState {
  const AppUpdateDownloading(this.value, this.receivedBytes);

  final AppUpdateRelease value;
  final int receivedBytes;

  @override
  AppUpdateRelease get release => value;

  double get progress => (receivedBytes / value.artifactSize!).clamp(0.0, 1.0);
}

final class AppUpdateVerifying extends AppUpdateState {
  const AppUpdateVerifying(this.value);

  final AppUpdateRelease value;

  @override
  AppUpdateRelease get release => value;
}

final class AppUpdateInstalling extends AppUpdateState {
  const AppUpdateInstalling(this.value);

  final AppUpdateRelease value;

  @override
  AppUpdateRelease get release => value;
}

final class AppUpdateAwaitingInstall extends AppUpdateState {
  const AppUpdateAwaitingInstall(
    this.value, {
    required this.permissionRequired,
  });

  final AppUpdateRelease value;
  final bool permissionRequired;

  @override
  AppUpdateRelease get release => value;
}

enum AppUpdateRetryAction { check, openWebsite, download, install }

enum AppUpdateCheckOutcome { available, upToDate, failed, unsupported }
