part of 'mail_page.dart';

class _MailDetailHeader extends StatefulWidget {
  const _MailDetailHeader({
    super.key,
    required this.detail,
    required this.senderAvatarService,
    required this.external,
    required this.weekday,
    required this.time,
    this.originalStyle = false,
    this.onToggleStyle,
  });
  final MailMessageDetail detail;
  final MailSenderAvatarService? senderAvatarService;
  final bool external;
  final String weekday;
  final String time;
  final bool originalStyle;
  final VoidCallback? onToggleStyle;
  @override
  State<_MailDetailHeader> createState() => _MailDetailHeaderState();
}

class _MailDetailHeaderState extends State<_MailDetailHeader> {
  bool _expanded = false;

  Widget _address(String value, Color color, {double fontSize = 14}) => Text(
    value,
    style: TextStyle(fontSize: fontSize, height: 1.45, color: color),
  );

  List<({String name, String email})> _recipientParts(String raw) {
    try {
      return parseMailRecipientAddresses(raw)
          .map(
            (address) => (
              name: address.personalName?.trim().isNotEmpty == true
                  ? address.personalName!.trim()
                  : address.email.split('@').first,
              email: address.email,
            ),
          )
          .toList();
    } on FormatException {
      return raw.trim().isEmpty ? [] : [(name: raw.trim(), email: raw.trim())];
    }
  }

  String _recipientNames(String raw) =>
      _recipientParts(raw).map((part) => part.name).join('、');

  Future<void> _showAddress(String value) => showBnbuAdaptiveModal<void>(
    context: context,
    dialogMaxWidth: 460,
    dialogMaxHeight: 280,
    builder: (context, presentation) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(value, style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(LucideIcons.copy300, size: 18),
              label: const BnbuText('复制'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = MailSurfaceColors(context);
    final detail = widget.detail;
    final sender = _assistantSenderParts(detail.sender);
    final senderName = mailDisplayName(detail.sender);
    final recipientNames = _recipientNames(detail.recipients);
    final secondary = colors.dark
        ? const Color(0xFF54575B)
        : const Color(0xFF8B9098);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.subject.trim().isEmpty
                    ? context.l10n.text('无主题邮件')
                    : detail.subject,
                key: const ValueKey('mail-detail-expanded-subject'),
                style: TextStyle(
                  fontSize: _mailDetailTitleFontSize,
                  height: 1.42,
                  fontWeight: FontWeight.w600,
                  color: colors.foreground,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.zero,
                    child: MailSenderAvatar(
                      sender: detail.sender,
                      diameter: _mailDetailAvatarDiameter,
                      senderAvatarService: widget.senderAvatarService,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: _expanded
                                    ? () => _showAddress(detail.sender)
                                    : null,
                                child: Text(
                                  senderName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: _mailDetailSenderFontSize,
                                    height: 1.45,
                                    fontWeight: FontWeight.w400,
                                    color: _expanded
                                        ? colors.accent
                                        : colors.foreground,
                                  ),
                                ),
                              ),
                            ),
                            if (!_expanded && widget.weekday.isNotEmpty)
                              Text(
                                widget.weekday,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: secondary,
                                ),
                              ),
                          ],
                        ),
                        if (_expanded) ...[
                          const SizedBox(height: 2),
                          _address(
                            sender.$2.isNotEmpty ? sender.$2 : detail.sender,
                            secondary,
                          ),
                        ] else
                          InkWell(
                            key: const ValueKey('mail-recipient-expand'),
                            onTap: () => setState(() => _expanded = true),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2, bottom: 2),
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      '${context.l10n.text('发给')} $recipientNames',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        height: 1.45,
                                        color: secondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  _disclosure(colors, false),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_expanded) ...[
                if (widget.onToggleStyle != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: widget.onToggleStyle,
                      child: BnbuText(
                        widget.originalStyle ? '适应当前主题' : '查看原始样式',
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                _expandedAddresses(
                  context.l10n.text('收件人'),
                  detail.recipients,
                  colors,
                  secondary,
                ),
                if (detail.cc?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  _expandedAddresses(
                    context.l10n.text('抄送'),
                    detail.cc!,
                    colors,
                    secondary,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        '${context.l10n.text('时间')}: ',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: secondary,
                        ),
                      ),
                    ),
                    Expanded(child: _address(widget.time, secondary)),
                    const SizedBox(width: 28),
                  ],
                ),
                if (detail.messageSizeBytes != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${context.l10n.text('大小')}: ',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: secondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: _address(
                          _formatMailSize(detail.messageSizeBytes!),
                          secondary,
                        ),
                      ),
                      const SizedBox(width: 28),
                    ],
                  ),
                ],
              ],
            ],
          ),
          if (_expanded)
            Positioned(
              right: 0,
              bottom: 0,
              width: 44,
              height: 44,
              child: InkWell(
                key: const ValueKey('mail-recipient-collapse'),
                onTap: () => setState(() => _expanded = false),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _disclosure(colors, true),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _expandedAddresses(
    String label,
    String raw,
    MailSurfaceColors colors,
    Color secondary,
  ) {
    final addresses = _recipientParts(raw);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: TextStyle(fontSize: 14, height: 1.45, color: secondary),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final address in addresses)
                GestureDetector(
                  onTap: () => _showAddress(address.email),
                  child: _address(address.name, colors.accent),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _disclosure(MailSurfaceColors colors, bool up) => Container(
    width: 14,
    height: 14,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: colors.dark ? const Color(0xFF2B2D30) : const Color(0xFFE8EAED),
    ),
    child: Icon(
      up ? LucideIcons.chevronUp300 : LucideIcons.chevronDown300,
      size: 11,
      color: colors.control,
    ),
  );
}
