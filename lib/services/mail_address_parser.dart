import 'package:enough_mail/enough_mail.dart';

List<MailAddress> parseMailRecipientAddresses(String input) {
  if (input.trim().isEmpty) return const [];
  if (input.contains('\r') || input.contains('\n')) {
    throw const FormatException('邮件地址格式无效');
  }
  // Validate every editable token before handing it to enough_mail. Its parser
  // otherwise drops unfinished tokens and prints their contents to stdout.
  final tokens = <String>[];
  var token = StringBuffer();
  var quoted = false, escaped = false, angle = false;
  for (final rune in input.runes) {
    final character = String.fromCharCode(rune);
    if (escaped) {
      token.write(character);
      escaped = false;
      continue;
    }
    if (character == r'\' && quoted) {
      token.write(character);
      escaped = true;
      continue;
    }
    if (character == '"') quoted = !quoted;
    if (!quoted && character == '<') {
      if (angle) throw const FormatException('邮件地址格式无效');
      angle = true;
    }
    if (!quoted && character == '>') {
      if (!angle) throw const FormatException('邮件地址格式无效');
      angle = false;
    }
    if (!quoted && !angle && ',;，；'.contains(character)) {
      if (token.toString().trim().isNotEmpty) {
        tokens.add(token.toString().trim());
      }
      token = StringBuffer();
    } else {
      token.write(character);
    }
  }
  if (quoted || angle || escaped) throw const FormatException('邮件地址格式无效');
  if (token.toString().trim().isNotEmpty) tokens.add(token.toString().trim());
  final emailPattern = RegExp(r'^[^\s<>@,;:]+@[^\s<>@,;:]+\.[^\s<>@,;:]+$');
  for (final value in tokens) {
    final start = value.indexOf('<');
    final email = start < 0
        ? value
        : value.endsWith('>')
        ? value.substring(start + 1, value.length - 1)
        : '';
    if (!emailPattern.hasMatch(email)) throw const FormatException('邮件地址格式无效');
  }
  final message = MimeMessage()..setHeader('To', tokens.join(', '));
  final addresses = message.decodeHeaderMailAddressValue('To') ?? const [];
  if (addresses.isEmpty ||
      addresses.any(
        (address) => !RegExp(
          r'^[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+$',
        ).hasMatch(address.email),
      )) {
    throw const FormatException('邮件地址格式无效');
  }
  final unique = <String, MailAddress>{};
  for (final address in addresses) {
    unique.putIfAbsent(address.email.toLowerCase(), () => address);
  }
  return unique.values.toList(growable: false);
}

String replyAllCarbonCopy(
  String recipients,
  String? cc,
  String sender,
  String self,
) {
  try {
    final excluded = {
      self.toLowerCase(),
      ...parseMailRecipientAddresses(sender).map((a) => a.email.toLowerCase()),
    };
    return parseMailRecipientAddresses(
          [
            recipients,
            if (cc?.trim().isNotEmpty == true) cc!,
          ].where((s) => s.trim().isNotEmpty).join(', '),
        )
        .where((a) => !excluded.contains(a.email.toLowerCase()))
        .map((a) => a.email)
        .join(', ');
  } on FormatException {
    return '';
  }
}
