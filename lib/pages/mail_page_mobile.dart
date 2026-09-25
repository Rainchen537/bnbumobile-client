part of 'mail_page.dart';

extension _MobileMailPage on _MailPageState {
  MailOrganizationService? get _organizationService =>
      _mailService is MailOrganizationService
      ? _mailService as MailOrganizationService
      : null;
  List<MailMessageSummary> get _selectedMessages => _visibleMessages
      .where((message) => _selectedUids.contains(message.identityKey))
      .toList();

  bool get _mailResultsPending =>
      !_showRadar &&
      (_isLoading ||
          _loadingCollection ||
          _isSearching ||
          (_collection != MailCollection.folder && _errorMessage != null) ||
          (_collection == MailCollection.folder &&
              (_searchDebounce?.isActive ?? false)));

  bool get _hasMoreMailPages =>
      !_showRadar &&
      _collection == MailCollection.folder &&
      _searchResults == null &&
      _snapshot != null &&
      _snapshot!.currentPage * _snapshot!.pageSize < _snapshot!.totalMessages;

  bool get _allMailSelected =>
      !_mailResultsPending &&
      !_hasMoreMailPages &&
      _visibleMessages.isNotEmpty &&
      _visibleMessages.every(
        (message) => _selectedUids.contains(message.identityKey),
      );

  Future<MailFolderSnapshot> _fetchMailboxPage(
    MailAccessCredentials credentials,
    MailFolder folder,
    int page,
    int? validity,
  ) {
    final sorted = _mailService is MailSortedFolderReader
        ? _mailService as MailSortedFolderReader
        : null;
    // The compact inbox has no date-order menu. Keep its usual newest-page
    // request bounded, so opening it cannot delay body reads behind a full
    // metadata index on servers without SORT. A chosen oldest order survives
    // a tablet/window resize and still needs a complete result index.
    final needsDateIndex =
        _sortOrder == MailSortOrder.oldestFirst ||
        MediaQuery.sizeOf(context).width >= BnbuBreakpoints.tabletWorkspace;
    if (sorted != null && needsDateIndex) {
      return sorted.fetchSortedFolder(
        credentials: credentials,
        folder: folder,
        sortOrder: _sortOrder,
        page: page,
        unreadOnly: _showUnreadOnly,
        expectedMailboxUidValidity: validity,
      );
    }
    final organization = _organizationService;
    if (organization != null) {
      return organization.fetchFilteredFolder(
        credentials: credentials,
        folder: folder,
        page: page,
        unreadOnly: _showUnreadOnly,
        expectedMailboxUidValidity: validity,
      );
    }
    return _mailService.fetchFolder(
      credentials: credentials,
      folder: folder,
      page: page,
      expectedMailboxUidValidity: validity,
    );
  }

  Future<void> _loadFolderInformation() async {
    final service = _organizationService;
    final credentials = _credentials;
    if (service == null || credentials == null) return;
    final generation = _folderRequestGeneration;
    try {
      final folders = await service.listFolders(credentials);
      if (!mounted || generation != _folderRequestGeneration) return;
      _updateMail(() {
        _folderInfos
          ..clear()
          ..addEntries(
            folders.map((folder) => MapEntry(folder.folder, folder)),
          );
      });
    } catch (_) {
      /* Unknown counts stay unknown; never fabricate zero. */
    }
  }

  void _schedulePreviews() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 120), () async {
      final service = _organizationService;
      final credentials = _credentials;
      if (service == null || credentials == null || !mounted || _showRadar) {
        return;
      }
      final messages = _visibleMessages;
      final first = _scrollController.hasClients
          ? (_scrollController.offset / 92).floor().clamp(0, messages.length)
          : 0;
      final pending = messages
          .skip(first)
          .take(10)
          .where(
            (message) =>
                !message.previewLoaded &&
                _previewRequests.add(message.identityKey),
          )
          .toList();
      final generation = _folderRequestGeneration;
      for (final message in pending) {
        if (!mounted || generation != _folderRequestGeneration) break;
        final previews = await service.loadPreviews(
          credentials: credentials,
          messages: [message],
        );
        if (!mounted || generation != _folderRequestGeneration) break;
        if (previews.isEmpty) continue;
        final preview = previews.first;
        MailMessageSummary update(MailMessageSummary current) =>
            current.identityKey != preview.identityKey
            ? current
            : current.copyWith(
                preview: preview.preview,
                previewLoaded: true,
                hasHtmlBody: preview.hasHtmlBody,
                hasAttachments: preview.hasAttachments,
              );
        _updateMail(() {
          if (_snapshot != null) {
            _snapshot = _snapshot!.copyWith(
              messages: _snapshot!.messages.map(update).toList(),
            );
          }
          _collectionMessages = _collectionMessages.map(update).toList();
          _searchResults = _searchResults?.map(update).toList();
        });
      }
      _previewRequests.removeAll(pending.map((message) => message.identityKey));
    });
  }

  void _setSelectionMode(bool active) {
    if (active && _mailResultsPending) return;
    if (_isMultiSelectMode == active) return;
    _selectionRequestGeneration++;
    _openSwipe.value = null;
    _updateMail(() {
      _isMultiSelectMode = active;
      _isSelectingAll = false;
      if (!active) _selectedUids.clear();
    });
    MailSelectionNotification(
      active || _workspaceCompose != null,
    ).dispatch(context);
  }

  Future<void> _chooseCollection(String value) async {
    _setSelectionMode(false);
    _openSwipe.value = null;
    _updateMail(() {
      _folderMenuOpen = false;
      _showRadar = false;
      _showUnreadOnly = false;
      _searchQuery = '';
      _searchController.clear();
      _searchResults = null;
      _collection = switch (value) {
        'starred' => MailCollection.starred,
        _ => MailCollection.folder,
      };
      if (_collection == MailCollection.folder) {
        _currentFolder = MailFolder.values.byName(value);
      }
    });
    if (_collection == MailCollection.folder) {
      await _refreshFolder();
    } else {
      await _loadCollection();
    }
  }

  Future<void> _loadCollection() async {
    final organization = _organizationService;
    final credentials = await _getCredentials();
    if (credentials == null || !mounted) return;
    final generation = ++_folderRequestGeneration;
    final collection = _collection;
    _updateMail(() {
      _loadingCollection = true;
      _collectionMessages = [];
      _errorMessage = null;
    });
    try {
      final folders = [MailFolder.inbox, MailFolder.sent, MailFolder.drafts];
      for (final folder in folders) {
        int? validity;
        for (var page = 1; ; page++) {
          if (!mounted || generation != _folderRequestGeneration) return;
          final snapshot = organization == null
              ? await _mailService.fetchFolder(
                  credentials: credentials,
                  folder: folder,
                  page: page,
                  pageSize: 200,
                  expectedMailboxUidValidity: validity,
                )
              : await organization.fetchFilteredFolder(
                  credentials: credentials,
                  folder: folder,
                  page: page,
                  pageSize: 200,
                  flaggedOnly: collection == MailCollection.starred,
                  expectedMailboxUidValidity: validity,
                );
          validity ??= snapshot.mailboxUidValidity;
          if (!mounted || generation != _folderRequestGeneration) return;
          _updateMail(() {
            _collectionMessages.addAll(
              snapshot.messages.where(
                (message) =>
                    collection != MailCollection.starred || message.isFlagged,
              ),
            );
            _collectionMessages.sort(
              (a, b) => (b.date ?? DateTime(1970)).compareTo(
                a.date ?? DateTime(1970),
              ),
            );
          });
          if (snapshot.messages.isEmpty ||
              page * snapshot.pageSize >= snapshot.totalMessages) {
            break;
          }
        }
      }
    } catch (error) {
      if (mounted && generation == _folderRequestGeneration) {
        _updateMail(() => _errorMessage = error.toString());
        BnbuToast.show(context, error.toString(), kind: BnbuToastKind.warning);
      }
    } finally {
      if (mounted && generation == _folderRequestGeneration) {
        _updateMail(() => _loadingCollection = false);
        _schedulePreviews();
      }
    }
  }

  Future<void> _refreshCurrentMailbox() async {
    _openSwipe.value = null;
    if (_showRadar) {
      await _refreshRadarReadStates();
      await _radarController?.retryNow();
    } else if (_collection != MailCollection.folder) {
      await _loadCollection();
    } else {
      await _refreshFolder();
    }
  }

  Future<void> _refreshRadarReadStates() async {
    try {
      await _radarController?.refreshOriginalReadStates();
    } catch (error) {
      if (mounted) {
        BnbuToast.show(context, error.toString(), kind: BnbuToastKind.warning);
      }
    }
  }

  void _toggleUnread() {
    _setSelectionMode(false);
    _updateMail(() => _showUnreadOnly = !_showUnreadOnly);
    unawaited(
      AccountHabits.shared
          .set('mail.unread_only', _showUnreadOnly)
          .catchError((Object _) {}),
    );
    if (_collection == MailCollection.folder && !_showRadar) {
      unawaited(_refreshFolder());
    }
  }

  Future<void> _selectEveryMessage() async {
    if (!_isMultiSelectMode ||
        _isSelectingAll ||
        _mailResultsPending ||
        _isLoadingMore) {
      return;
    }
    if (_allMailSelected) {
      _updateMail(_selectedUids.clear);
      return;
    }
    final generation = _folderRequestGeneration;
    final selectionGeneration = ++_selectionRequestGeneration;
    _updateMail(() => _isSelectingAll = true);
    try {
      while (_hasMoreMailPages) {
        final before = _snapshot!.currentPage;
        await _loadMore();
        if (!mounted ||
            generation != _folderRequestGeneration ||
            selectionGeneration != _selectionRequestGeneration ||
            !_isMultiSelectMode) {
          return;
        }
        if (_snapshot?.currentPage == before) {
          BnbuToast.show(
            context,
            '暂时无法加载全部邮件，请刷新后重试。',
            kind: BnbuToastKind.warning,
          );
          return;
        }
      }
      if (mounted && selectionGeneration == _selectionRequestGeneration) {
        _updateMail(
          () => _selectedUids.addAll(
            _visibleMessages.map((message) => message.identityKey),
          ),
        );
      }
    } finally {
      if (mounted && selectionGeneration == _selectionRequestGeneration) {
        _updateMail(() => _isSelectingAll = false);
      }
    }
  }

  Future<void> _runMailMutation(Future<void> Function() operation) async {
    if (_isDeleting) return;
    _updateMail(() => _isDeleting = true);
    try {
      await operation();
      if (mounted) _setSelectionMode(false);
    } catch (error) {
      if (mounted) {
        BnbuToast.show(context, error.toString(), kind: BnbuToastKind.danger);
      }
    } finally {
      if (mounted) {
        _updateMail(() => _isDeleting = false);
        await _refreshCurrentMailbox();
      }
    }
  }

  List<MailMessageIdentity> _identities(List<MailMessageSummary> messages) {
    final identities = messages.map((message) => message.identity).toList();
    if (identities.any((identity) => identity == null)) {
      throw const MailServiceException('邮箱内容已变化，请刷新后重试。');
    }
    return identities.cast<MailMessageIdentity>();
  }

  Future<void> _setMailRead(List<MailMessageSummary> messages, bool seen) =>
      _runMailMutation(() async {
        final credentials = _credentials;
        if (credentials == null) return;
        final service = _organizationService;
        if (service != null) {
          await service.setMessagesSeen(
            credentials: credentials,
            messages: _identities(messages),
            seen: seen,
          );
        } else if (seen) {
          for (final message in messages) {
            await _mailService.markMessagesSeen(
              credentials: credentials,
              folder: message.folder,
              uids: [message.uid],
              expectedMailboxUidValidity: message.mailboxUidValidity,
            );
          }
        } else {
          throw const MailServiceException('当前邮箱连接不支持修改未读状态。');
        }
        await _radarController?.recordOriginalReadState(messages, seen);
      });

  Future<void> _setMailStarred(
    List<MailMessageSummary> messages,
    bool flagged,
  ) => _runMailMutation(() async {
    final service = _organizationService;
    final credentials = _credentials;
    if (service == null || credentials == null) {
      throw const MailServiceException('当前邮箱连接不支持星标。');
    }
    await service.setMessagesFlagged(
      credentials: credentials,
      messages: _identities(messages),
      flagged: flagged,
    );
  });

  Future<void> _deleteMailRows(List<MailMessageSummary> messages) async {
    if (messages.isEmpty) return;
    final permanent = messages.any(
      (message) => message.folder == MailFolder.trash,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: BnbuText(permanent ? '永久删除' : '删除邮件'),
        content: BnbuText(
          permanent
              ? '永久删除选中的 ${messages.length} 封邮件？'
              : '将选中的 ${messages.length} 封邮件移到已删除？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const BnbuText('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const BnbuText('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runMailMutation(() async {
      final credentials = _credentials;
      if (credentials == null) return;
      final groups = <(MailFolder, int?), List<MailMessageSummary>>{};
      for (final message in messages) {
        groups
            .putIfAbsent((message.folder, message.mailboxUidValidity), () => [])
            .add(message);
      }
      for (final group in groups.values) {
        final message = group.first;
        await _mailService.deleteMessages(
          credentials: credentials,
          folder: message.folder,
          uids: group.map((message) => message.uid).toList(),
          expectedMailboxUidValidity: message.mailboxUidValidity,
        );
        await _radarController?.setMessageMembership(
          group,
          MailRadarMembership.excluded,
        );
      }
    });
  }

  Future<void> _moveMailRows(List<MailMessageSummary> messages) async {
    final choice = await showBnbuAdaptiveModal<String>(
      context: context,
      dialogMaxWidth: 420,
      dialogMaxHeight: 430,
      builder: (context, presentation) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (messages.isNotEmpty &&
                messages.every((message) => message.folder == MailFolder.trash))
              ListTile(
                leading: const Icon(LucideIcons.undo2300),
                title: const BnbuText('恢复到原文件夹'),
                onTap: () => Navigator.pop(context, 'restore'),
              ),
            for (final folder in MailFolder.values)
              if (folder != MailFolder.junk || _folderInfos.containsKey(folder))
                ListTile(
                  leading: Icon(_MailPageState._folderIcon(folder)),
                  title: BnbuText(_MailPageState._folderLabel(folder)),
                  onTap: () => Navigator.pop(context, folder.name),
                ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'restore') {
      await _restoreSelected();
      return;
    }
    final target = MailFolder.values.byName(choice);
    await _runMailMutation(() async {
      final service = _organizationService;
      final credentials = _credentials;
      if (service == null || credentials == null) {
        throw const MailServiceException('当前邮箱连接不支持移动。');
      }
      await service.moveMessages(
        credentials: credentials,
        messages: _identities(messages),
        target: target,
      );
      await _radarController?.setMessageMembership(
        messages.where((message) => message.folder != target).toList(),
        MailRadarMembership.excluded,
      );
    });
  }

  Future<void> _toggleRadarMembership(
    List<MailMessageSummary> messages,
    bool include,
  ) async {
    final radar = await _ensureRadarController();
    if (radar == null || !_radarEffectivelyEnabled || !mounted) return;
    await _runMailMutation(() async {
      await radar.setMessageMembership(
        messages,
        include ? MailRadarMembership.included : MailRadarMembership.excluded,
      );
    });
  }

  List<MailSwipeAction> _mailRowActions(
    MailMessageSummary message, {
    bool radar = false,
  }) => [
    MailSwipeAction(
      label: message.isSeen ? '标为未读' : '标为已读',
      icon: message.isSeen ? LucideIcons.mail300 : LucideIcons.mailOpen300,
      color: const Color(0xFF3788E7),
      onPressed: () => _setMailRead([message], !message.isSeen),
    ),
    if (_radarEffectivelyEnabled)
      MailSwipeAction(
        label: radar ? '标记完成' : '加入雷达',
        icon: LucideIcons.radar300,
        color: const Color(0xFF6D727B),
        onPressed: () => _toggleRadarMembership([message], !radar),
      ),
    MailSwipeAction(
      label: '删除',
      icon: LucideIcons.trash2300,
      color: const Color(0xFFD85050),
      onPressed: () => _deleteMailRows([message]),
    ),
  ];

  Widget _buildMobileMailbox(BuildContext context) => AnimatedBuilder(
    animation: _radarController ?? _openSwipe,
    builder: (context, _) {
      final colors = MailSurfaceColors(context);
      return PopScope(
        canPop: !_isMultiSelectMode,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _setSelectionMode(false);
        },
        child: ColoredBox(
          color: colors.background,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (_isMultiSelectMode)
                  _mobileSelectionHeader(colors)
                else ...[
                  _mobileSearchHeader(colors),
                  _mobileFolderToolbar(colors),
                  if (_showScopeArea &&
                      !_showRadar &&
                      _collection == MailCollection.folder)
                    _buildScopeChips(),
                ],
                BnbuUpdateProgress(
                  active:
                      !_showRadar &&
                      _visibleMessages.isNotEmpty &&
                      (_isLoading ||
                          _isSearching ||
                          _loadingCollection ||
                          _isSelectingAll ||
                          _isDeleting),
                  color: colors.accent,
                ),
                Expanded(
                  child: _showRadar
                      ? _buildRadarBody()
                      : _mobileMessageList(colors),
                ),
                if (_isMultiSelectMode) _mobileSelectionFooter(colors),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _mobileSearchHeader(MailSurfaceColors colors) => MailSearchHeader(
    controller: _searchController,
    onChanged: _onSearchChanged,
    onCompose: _credentials == null ? null : _openComposePage,
  );

  Widget _mobileFolderToolbar(MailSurfaceColors colors) {
    final inboxUnread = _showRadar
        ? (_radarController?.visibleItems
                  .where((item) => !item.originalIsSeen)
                  .length ??
              0)
        : _collection == MailCollection.folder
        ? _folderInfos[_currentFolder]?.unread ?? _snapshot?.unreadCount
        : _collectionMessages.where((message) => !message.isSeen).length;
    final canReadFilter =
        _showUnreadOnly || (inboxUnread != null && inboxUnread > 0);
    return SizedBox(
      key: const ValueKey('mail-folder-toolbar'),
      height: 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(flex: 12, child: _mobileFolderMenu(colors)),
            _mobileToolDivider(colors),
            Expanded(
              flex: 9,
              child: _mobileTool(
                colors,
                '未读',
                LucideIcons.mailCheck300,
                selected: _showUnreadOnly,
                onPressed: canReadFilter ? _toggleUnread : null,
              ),
            ),
            _mobileToolDivider(colors),
            Expanded(
              flex: 9,
              child: _mobileTool(
                colors,
                '多选',
                LucideIcons.listChecks300,
                onPressed: _visibleMessages.isEmpty || _mailResultsPending
                    ? null
                    : () => _setSelectionMode(true),
              ),
            ),
            if (_radarEffectivelyEnabled) ...[
              _mobileToolDivider(colors),
              Expanded(
                flex: 12,
                child: _mobileTool(
                  colors,
                  '邮件雷达',
                  LucideIcons.radar300,
                  selected: _showRadar,
                  onPressed: () {
                    _setSelectionMode(false);
                    _updateMail(() {
                      _showRadar = !_showRadar;
                      _showUnreadOnly = false;
                    });
                    if (_showRadar) unawaited(_refreshRadarReadStates());
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mobileToolDivider(MailSurfaceColors colors) => SizedBox(
    height: 14,
    child: VerticalDivider(width: 1, thickness: 0.5, color: colors.divider),
  );

  Widget _mobileTool(
    MailSurfaceColors colors,
    String label,
    IconData icon, {
    VoidCallback? onPressed,
    bool selected = false,
  }) {
    final color = selected
        ? colors.accent
        : onPressed == null
        ? colors.secondary.withValues(alpha: 0.45)
        : colors.control;
    return TextButton(
      key: label == '邮件雷达' ? const ValueKey('mail-radar-mobile-tile') : null,
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        minimumSize: const Size(0, 48),
        foregroundColor: color,
        disabledForegroundColor: color,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: BnbuText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileFolderMenu(MailSurfaceColors colors) {
    final selected = _collection == MailCollection.folder
        ? _currentFolder.name
        : _collection.name;
    final label = switch (_collection) {
      MailCollection.starred => '星标邮件',
      MailCollection.folder => _MailPageState._folderLabel(_currentFolder),
      _ => _MailPageState._folderLabel(MailFolder.inbox),
    };
    final icon = switch (_collection) {
      MailCollection.starred => LucideIcons.star300,
      MailCollection.folder => _MailPageState._folderIcon(_currentFolder),
      _ => LucideIcons.inbox300,
    };
    final color =
        _folderMenuOpen ||
            _collection != MailCollection.folder ||
            _currentFolder != MailFolder.inbox
        ? colors.accent
        : colors.control;
    final entries = <(String, String, IconData)>[
      ('inbox', '收件箱', LucideIcons.inbox300),
      ('starred', '星标邮件', LucideIcons.star300),
      ('drafts', '草稿箱', LucideIcons.stickyNote300),
      ('sent', '已发送', LucideIcons.send300),
      ('trash', '已删除', LucideIcons.trash2300),
      ('junk', '垃圾邮件', LucideIcons.archiveX300),
    ];
    return PopupMenuButton<String>(
      key: const ValueKey('mail-folder-selector'),
      color: colors.menu,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      menuPadding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 224, maxWidth: 260),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onOpened: () => _updateMail(() => _folderMenuOpen = true),
      onCanceled: () => _updateMail(() => _folderMenuOpen = false),
      onSelected: _chooseCollection,
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          height: 34,
          child: Text(
            _credentials?.emailAddress ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colors.control,
            ),
          ),
        ),
        for (final entry in entries) ...[
          PopupMenuItem<String>(
            value: entry.$1,
            height: 48,
            padding: EdgeInsets.zero,
            child: Semantics(
              selected: selected == entry.$1,
              child: SizedBox(
                height:
                    48 +
                    (MediaQuery.textScalerOf(context).scale(17) - 17).clamp(
                          0,
                          40,
                        ) *
                        1.4,
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 4,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: selected == entry.$1 ? colors.selected : null,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              entry.$3,
                              size: 20,
                              color: selected == entry.$1
                                  ? colors.accent
                                  : colors.control,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: BnbuText(
                                entry.$2,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w400,
                                  color: selected == entry.$1
                                      ? colors.accent
                                      : colors.foreground,
                                ),
                              ),
                            ),
                            if (entry.$1 == 'inbox' &&
                                (_folderInfos[MailFolder.inbox]?.unread ??
                                        _snapshot?.unreadCount ??
                                        0) >
                                    0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.control.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_folderInfos[MailFolder.inbox]?.unread ?? _snapshot?.unreadCount}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: colors.control,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (entry.$1 != 'junk')
                      Divider(
                        height: 0.5,
                        thickness: 0.5,
                        indent: 16,
                        endIndent: 16,
                        color: colors.dark
                            ? const Color(0xFF35373A)
                            : const Color(0xFFE3E6EB),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: BnbuText(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: color),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              _folderMenuOpen
                  ? LucideIcons.chevronUp300
                  : LucideIcons.chevronDown300,
              size: 12,
              color: color,
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobileMessageList(MailSurfaceColors colors) {
    final visible = _visibleMessages;
    final hasMore =
        _collection == MailCollection.folder &&
        _searchResults == null &&
        _snapshot != null &&
        _snapshot!.currentPage * _snapshot!.pageSize < _snapshot!.totalMessages;
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.metrics.axis == Axis.vertical) _openSwipe.value = null;
        return false;
      },
      child: BnbuRefreshIndicator(
        onRefresh: _refreshCurrentMailbox,
        child: ListView.builder(
          key: const ValueKey('mail-compact-message-list'),
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: visible.isEmpty ? 1 : visible.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (visible.isEmpty) {
              return Padding(
                key: const ValueKey('mail-refreshable-state'),
                padding: const EdgeInsets.symmetric(
                  vertical: 80,
                  horizontal: 24,
                ),
                child:
                    _errorMessage == null &&
                        (_isLoading || _loadingCollection || _isSearching)
                    ? const BnbuInitialLoading()
                    : Center(
                        child: BnbuText(
                          _errorMessage ??
                              (_isLoading || _loadingCollection
                                  ? ''
                                  : '没有匹配的邮件'),
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.secondary,
                          ),
                        ),
                      ),
              );
            }
            if (index == visible.length) return _buildLoadMoreFooter();
            final message = visible[index];
            return MailMessageRow(
              key: ValueKey(message.identityKey),
              message: message,
              timeLabel: _formatMessageTime(message.date),
              avatarService: _senderAvatarService,
              selectionMode: _isMultiSelectMode,
              selected: _selectedUids.contains(message.identityKey),
              busy: _isDeleting || _isSelectingAll,
              openSwipe: _openSwipe,
              swipeActions: _mailRowActions(message),
              onTap: () {
                if (_isMultiSelectMode) {
                  _toggleSelectMessage(message.identityKey);
                } else {
                  _openMessage(message);
                }
              },
              onLongPress: () {
                _setSelectionMode(true);
                _toggleSelectMessage(message.identityKey);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _mobileSelectionHeader(MailSurfaceColors colors) => SizedBox(
    height:
        44 +
        (MediaQuery.textScalerOf(context).scale(17) - 17).clamp(0, 40) * 1.4,
    child: Row(
      children: [
        SizedBox(
          width: 74,
          child: TextButton(
            onPressed: _isSelectingAll || _isLoadingMore || _mailResultsPending
                ? null
                : _selectEveryMessage,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 16),
            ),
            child: BnbuText(
              _allMailSelected ? '取消全选' : '全选',
              style: TextStyle(
                color: colors.foreground,
                fontSize: 17,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: BnbuText(
              '选择邮件',
              style: TextStyle(color: colors.foreground, fontSize: 17),
            ),
          ),
        ),
        SizedBox(
          width: 74,
          child: TextButton(
            onPressed: () => _setSelectionMode(false),
            style: TextButton.styleFrom(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 16),
            ),
            child: BnbuText(
              '完成',
              style: TextStyle(
                color: colors.foreground,
                fontSize: 17,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _mobileSelectionFooter(MailSurfaceColors colors) {
    final selected = _selectedMessages;
    final enabled = selected.isNotEmpty && !_isDeleting && !_isSelectingAll;
    Widget action(
      String label,
      VoidCallback callback, {
      bool destructive = false,
    }) => Expanded(
      child: TextButton(
        onPressed: enabled ? callback : null,
        style: TextButton.styleFrom(minimumSize: const Size(0, 56)),
        child: BnbuText(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: (destructive ? const Color(0xFFD85050) : colors.accent)
                .withValues(alpha: enabled ? 1 : 0.4),
          ),
        ),
      ),
    );
    return ColoredBox(
      color: colors.dark ? const Color(0xFF0C0C0D) : const Color(0xFFF7F8FA),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Expanded(
                child: BnbuMenuButton<String>(
                  enabled: enabled,
                  onSelected: (value) {
                    switch (value) {
                      case 'seen':
                        _setMailRead(selected, true);
                      case 'unseen':
                        _setMailRead(selected, false);
                      case 'star':
                        _setMailStarred(selected, true);
                      case 'unstar':
                        _setMailStarred(selected, false);
                      case 'radar':
                        _toggleRadarMembership(selected, !_showRadar);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'seen', child: BnbuText('标为已读')),
                    const PopupMenuItem(
                      value: 'unseen',
                      child: BnbuText('标为未读'),
                    ),
                    const PopupMenuItem(value: 'star', child: BnbuText('添加星标')),
                    const PopupMenuItem(
                      value: 'unstar',
                      child: BnbuText('取消星标'),
                    ),
                    if (_radarEffectivelyEnabled)
                      PopupMenuItem(
                        value: 'radar',
                        child: BnbuText(_showRadar ? '标记完成' : '加入雷达'),
                      ),
                  ],
                  child: Center(
                    child: BnbuText(
                      '标记',
                      style: TextStyle(
                        fontSize: 16,
                        color: colors.accent.withValues(
                          alpha: enabled ? 1 : 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              action('删除', () => _deleteMailRows(selected), destructive: true),
              action('移动', () => _moveMailRows(selected)),
            ],
          ),
        ),
      ),
    );
  }
}
