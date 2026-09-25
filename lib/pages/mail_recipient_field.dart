part of 'mail_page.dart';

class _RecipientField extends StatefulWidget {
  const _RecipientField({
    required this.controller,
    required this.directory,
    required this.label,
    required this.fieldKey,
    required this.avatarService,
    required this.desktop,
    this.autofocus = false,
    this.trailing,
  });
  final TextEditingController controller;
  final MailRecipientDirectory directory;
  final String label;
  final Key fieldKey;
  final MailSenderAvatarService avatarService;
  final bool desktop, autofocus;
  final Widget? trailing;
  @override
  State<_RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<_RecipientField> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  final List<({String email, String name})> _recipients = [];
  List<MailRecipientSuggestion> _options = const [];
  Timer? _debounce;
  int _generation = 0, _highlight = 0, _remoteResultGeneration = -1;
  bool _writing = false, _loading = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _restore();
    widget.controller.addListener(_externalChanged);
    _input.addListener(_changed);
    _focus.addListener(_focusChanged);
    _focus.onKeyEvent = (_, event) {
      if (event is KeyDownEvent &&
          _options.isNotEmpty &&
          (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowUp)) {
        setState(
          () => _highlight =
              (_highlight +
                      (event.logicalKey == LogicalKeyboardKey.arrowDown
                          ? 1
                          : -1))
                  .clamp(0, _options.length - 1),
        );
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  void _restore() {
    _recipients.clear();
    try {
      for (final address in parseMailRecipientAddresses(
        widget.controller.text.replaceAll('，', ','),
      )) {
        _recipients.add((
          email: address.email,
          name: address.personalName ?? address.email,
        ));
      }
      _input.clear();
    } on FormatException {
      _input.text = widget.controller.text;
    }
  }

  void _externalChanged() {
    if (_writing) return;
    _writing = true;
    _restore();
    _writing = false;
    if (mounted) setState(() {});
  }

  void _publish() {
    _writing = true;
    widget.controller.text = [
      ..._recipients.map((item) => item.email),
      if (_input.text.trim().isNotEmpty) _input.text.trim(),
    ].join(', ');
    _writing = false;
  }

  void _focusChanged() {
    if (!_focus.hasFocus) {
      _generation++;
      _debounce?.cancel();
      _overlay.hide();
      _commitTyped();
    } else {
      _changed();
    }
  }

  void _commitTyped() {
    try {
      final addresses = parseMailRecipientAddresses(
        _input.text.replaceAll('，', ',').replaceAll('；', ';'),
      );
      if (addresses.isEmpty) return;
      for (final address in addresses) {
        if (_recipients.any(
          (r) => r.email.toLowerCase() == address.email.toLowerCase(),
        )) {
          continue;
        }
        _recipients.add((
          email: address.email,
          name: address.personalName ?? address.email,
        ));
      }
      _writing = true;
      _input.clear();
      _writing = false;
      _publish();
      if (mounted) setState(() {});
    } on FormatException {
      /* Keep unfinished addresses editable. */
    }
  }

  void _commitPrefix() {
    final value = _input.value;
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    final separators = RegExp(r'[,;，；]').allMatches(value.text).toList();
    if (separators.isEmpty) return;
    final end = separators.last.end;
    if (value.selection.isValid && value.selection.baseOffset < end) return;
    try {
      final addresses = parseMailRecipientAddresses(
        value.text.substring(0, end),
      );
      if (addresses.isEmpty) return;
      for (final address in addresses) {
        if (_recipients.any(
          (r) => r.email.toLowerCase() == address.email.toLowerCase(),
        )) {
          continue;
        }
        _recipients.add((
          email: address.email,
          name: address.personalName ?? address.email,
        ));
      }
      final remaining = value.text.substring(end).trimLeft();
      _writing = true;
      _input.value = TextEditingValue(
        text: remaining,
        selection: TextSelection.collapsed(offset: remaining.length),
      );
      _writing = false;
    } on FormatException {
      /* An unfinished token stays in the editable field. */
    }
  }

  void _changed() {
    if (_writing) return;
    _commitPrefix();
    _publish();
    final generation = ++_generation;
    _debounce?.cancel();
    final query = _input.text.trim();
    _options = const [];
    _highlight = 0;
    _failed = false;
    _loading = false;
    if (!_focus.hasFocus ||
        query.isEmpty ||
        (_input.value.composing.isValid &&
            !_input.value.composing.isCollapsed)) {
      _overlay.hide();
      setState(() {});
      return;
    }
    if (RegExp(r'[,;，；]$').hasMatch(query)) {
      _commitTyped();
      _overlay.hide();
      return;
    }
    _loading = true;
    unawaited(_search(query, generation, local: true));
    _debounce = Timer(
      const Duration(milliseconds: 230),
      () => unawaited(_search(query, generation, local: false)),
    );
    setState(() {});
  }

  Future<void> _search(
    String query,
    int generation, {
    required bool local,
  }) async {
    try {
      final result = await (local
          ? widget.directory.searchLocal(query)
          : widget.directory.search(query));
      if (!mounted || generation != _generation || !_focus.hasFocus) return;
      if (local && _remoteResultGeneration == generation) return;
      if (!local) _remoteResultGeneration = generation;
      setState(() {
        _options = result
            .where(
              (r) => !_recipients.any(
                (selected) =>
                    selected.email.toLowerCase() == r.email.toLowerCase(),
              ),
            )
            .toList();
        _highlight = _highlight.clamp(
          0,
          _options.isEmpty ? 0 : _options.length - 1,
        );
        if (!local) _loading = false;
      });
      _overlay.show();
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
      _overlay.show();
    }
  }

  void _select(MailRecipientSuggestion option) {
    if (!_recipients.any(
      (r) => r.email.toLowerCase() == option.email.toLowerCase(),
    )) {
      _recipients.add((email: option.email, name: option.displayName));
    }
    _input.clear();
    _publish();
    _overlay.hide();
    _focus.requestFocus();
    setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    widget.controller.removeListener(_externalChanged);
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _decorateOptions(Widget child) => DecoratedBox(
    key: const ValueKey('compose-recipient-options-surface'),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(6),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .18),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: .10),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final colors = MailSurfaceColors(context);
    return LayoutBuilder(
      builder: (context, constraints) => OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: (context) => Positioned(
          width: constraints.maxWidth - 28,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(14, 0),
            showWhenUnlinked: false,
            child: TextFieldTapRegion(
              child: _decorateOptions(
                Material(
                  elevation: 0,
                  shadowColor: Colors.black38,
                  color: colors.background,
                  borderRadius: BorderRadius.circular(6),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight:
                          (MediaQuery.sizeOf(context).height -
                              MediaQuery.viewInsetsOf(context).bottom) *
                          .4,
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (var i = 0; i < _options.length; i++)
                          _MailRecipientOption(
                            suggestion: _options[i],
                            highlighted: i == _highlight,
                            senderAvatarService: widget.avatarService,
                            onTap: () => _select(_options[i]),
                          ),
                        BnbuUpdateProgress(active: _loading),
                        if (_failed)
                          TextButton(
                            key: const ValueKey('compose-recipient-retry'),
                            onPressed: _changed,
                            child: const BnbuText('重试'),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: CompositedTransformTarget(
          link: _link,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.desktop ? 16 : 15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_recipients.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final recipient in _recipients)
                          InputChip(
                            label: Text(
                              recipient.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                            tooltip: recipient.email,
                            onPressed: () {
                              _recipients.remove(recipient);
                              _input.text = recipient.email;
                              _focus.requestFocus();
                              setState(() {});
                            },
                            onDeleted: () {
                              _recipients.remove(recipient);
                              _publish();
                              setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: 52),
                  child: Row(
                    children: [
                      SizedBox(
                        width: widget.desktop ? 72 : null,
                        child: BnbuText(
                          '${widget.label}：',
                          style: TextStyle(
                            fontSize: 16,
                            color: context.bnbuTheme.textSecondary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          key: widget.fieldKey,
                          controller: _input,
                          focusNode: _focus,
                          autofocus: widget.autofocus,
                          onTapOutside: (_) => _focus.unfocus(),
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          style: TextStyle(
                            fontSize: 16,
                            color: colors.foreground,
                          ),
                          onSubmitted: (_) => _options.isNotEmpty
                              ? _select(_options[_highlight])
                              : _commitTyped(),
                          decoration: InputDecoration(
                            hintText: _recipients.isEmpty
                                ? context.l10n.text('输入联系人／部门')
                                : null,
                            hintStyle: TextStyle(
                              color: context.bnbuTheme.textMuted,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      ?widget.trailing,
                      if (!widget.desktop && widget.trailing != null)
                        IconButton(
                          key: const ValueKey('compose-search-contact'),
                          tooltip: context.l10n.text('搜索联系人'),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          onPressed: () {
                            _focus.requestFocus();
                            _changed();
                          },
                          icon: Icon(
                            LucideIcons.userRoundPlus300,
                            size: 24,
                            color: colors.foreground,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
