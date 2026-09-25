/// Stored only inside the account's atomic secure credential record.
class MailLoginSettings {
  const MailLoginSettings({
    this.password,
    this.skipped = false,
    this.needsPassword = false,
  });

  final String? password;
  final bool skipped;
  final bool needsPassword;

  Map<String, Object> toJson() => {
    if (password != null) 'password': password!,
    'skipped': skipped,
    'needs_password': needsPassword,
  };

  factory MailLoginSettings.fromJson(Object? json) {
    if (json == null) return const MailLoginSettings();
    if (json is! Map ||
        (json['password'] != null && json['password'] is! String) ||
        json['skipped'] is! bool ||
        json['needs_password'] is! bool) {
      // Isolate malformed optional mail metadata from the valid school login.
      return const MailLoginSettings(needsPassword: true);
    }
    return MailLoginSettings(
      password: json['password'] as String?,
      skipped: json['skipped'] as bool,
      needsPassword: json['needs_password'] as bool,
    );
  }
}
