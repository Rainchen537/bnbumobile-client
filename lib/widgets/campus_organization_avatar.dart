import 'package:flutter/material.dart';

import '../models/campus_directory.dart';
import 'mail_sender_avatar.dart';

/// A local-only organization symbol; never loads a teacher portrait.
class CampusOrganizationAvatar extends StatelessWidget {
  const CampusOrganizationAvatar({
    super.key,
    required this.organization,
    this.diameter = 44,
  });

  final CampusDirectoryOrganization organization;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    // Match official mail identities, including legacy mailbox abbreviations.
    final local = organization.emails
        .where((email) => email.toLowerCase().endsWith('@bnbu.edu.cn'))
        .map((email) => email.split('@').first)
        .firstOrNull;
    final identity =
        local ??
        (organization.shortName.isNotEmpty
            ? organization.shortName
            : organization.id);
    return ExcludeSemantics(
      child: SenderAvatarSymbol(
        appearance: resolveOfficialOrganizationAppearance(identity),
        diameter: diameter,
      ),
    );
  }
}
