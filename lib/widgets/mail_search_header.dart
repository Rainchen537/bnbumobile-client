import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import 'bnbu_reveal_search.dart';
import 'mail_message_row.dart';

class MailSearchHeader extends StatefulWidget {
  const MailSearchHeader({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onCompose,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCompose;
  @override
  State<MailSearchHeader> createState() => _MailSearchHeaderState();
}

class _MailSearchHeaderState extends State<MailSearchHeader> {
  @override
  Widget build(BuildContext context) {
    final colors = MailSurfaceColors(context);
    return Padding(
      key: const ValueKey('mail-compact-top-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: BnbuRevealSearch(
        controller: widget.controller,
        onChanged: widget.onChanged,
        softMode: true,
        collapseOnFocusLoss: false,
        surfaceColor: colors.search,
        foregroundColor: colors.foreground,
        secondaryColor: colors.secondary,
        borderColor: colors.divider,
        controlKey: const ValueKey('mail-search-control'),
        closeKey: const ValueKey('mail-search-close'),
        trailingKey: const ValueKey('mail-compose-action-slot'),
        trailingAction: IconButton(
          key: const ValueKey('mail-compose-action'),
          style: IconButton.styleFrom(
            minimumSize: const Size.square(44),
            maximumSize: const Size.square(44),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          tooltip: context.l10n.text('写邮件'),
          onPressed: widget.onCompose,
          icon: Icon(LucideIcons.plus300, size: 28, color: colors.foreground),
        ),
      ),
    );
  }
}
