import '../state/account_habits.dart';
import '../pages/file_preview_page.dart';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/bnbu_loading.dart';
import '../widgets/home_navigation_stack.dart';
import '../widgets/mail_connection_panel.dart';
import '../state/mail_access_controller.dart';
import '../config/app_config.dart';
import '../models/assistant_models.dart';
import '../models/mail_models.dart';
import '../models/mail_radar_models.dart';
import '../services/assistant_action_runtime.dart';
import '../services/ai_assistant_service.dart';
import '../services/assistant_context_coordinator.dart';
import '../services/mail_attachment_store.dart';
import '../services/mail_compose_attachment_loader.dart';
import '../services/mail_compose_html_sanitizer.dart';
import '../services/mail_forward_content.dart';
import '../services/mail_compose_signature_store.dart';
import '../services/mail_recipient_directory.dart';
import '../services/mail_sender_avatar_service.dart';
import '../services/mail_sender_identity.dart';
import '../services/mail_service.dart';
import '../services/mail_presentation.dart';
import '../services/mail_address_parser.dart';
import '../services/mail_service_factory.dart';
import '../services/mail_radar_analyzer.dart';
import '../services/native_actions.dart';
import '../state/app_session_controller.dart';
import '../state/mail_assistant_intent_controller.dart';
import '../state/mail_radar_background_coordinator.dart';
import '../state/mail_radar_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/assistant_context_scope.dart';
import '../widgets/assistant_review_frame.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_adaptive_modal.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/bnbu_creation_form.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/bnbu_component_library.dart';
import '../widgets/mail_sender_avatar.dart';
import '../widgets/mail_radar_view.dart';
import '../widgets/mail_message_row.dart';
import '../widgets/mail_search_header.dart';
import '../widgets/native_html_mail_view.dart';
import '../widgets/rich_mail_editor.dart';
import '../widgets/small_u_logo.dart';

part 'mail_page_mobile.dart';
part 'mail_detail_header.dart';
part 'mail_recipient_field.dart';
part 'mail_compose_page.dart';

(String, String) _assistantSenderParts(String value) {
  final normalized = value.trim();
  final bracketMatch = RegExp(
    r'^(.*?)\s*<([^<>]+@[^<>]+)>$',
  ).firstMatch(normalized);
  if (bracketMatch != null) {
    return (
      bracketMatch.group(1)?.trim() ?? '',
      bracketMatch.group(2)?.trim().toLowerCase() ?? '',
    );
  }
  final emailMatch = RegExp(
    r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+',
  ).firstMatch(normalized);
  if (emailMatch == null) {
    return (normalized, '');
  }
  final email = emailMatch.group(0)!.toLowerCase();
  final name = normalized.replaceFirst(emailMatch.group(0)!, '').trim();
  return (name, email);
}

String _limitAssistantText(String value, int maxLength) {
  final normalized = value.trim().split(RegExp(r'\s+')).join(' ');
  return normalized.length <= maxLength
      ? normalized
      : normalized.substring(0, maxLength);
}

const double _mailDetailBodyFontSize = 14;
const double _mailDetailTitleFontSize = 18.7;
const double _mailDetailSenderFontSize = 14;
const double _mailDetailAvatarDiameter = 20;

// ─── MailPage ─────────────────────────────────────────────────────────────────

class MailPage extends StatefulWidget {
  const MailPage({
    super.key,
    required this.controller,
    this.assistantIntentController,
    this.senderAvatarService,
    this.radarAssistantService,
    this.radarCoordinator,
    this.radarPollInterval = const Duration(minutes: 2),
    MailService? mailService,
  }) : _mailService = mailService,
       _testCredentials = null,
       _attachmentStore = null,
       _testRadarController = null;

  /// Dependency-injected constructor for deterministic tests and offline
  /// visual previews. Production navigation uses the default constructor.
  const MailPage.withService({
    super.key,
    required this.controller,
    required MailService mailService,
    required MailAccessCredentials? testCredentials,
    MailAttachmentStore? attachmentStore,
    this.assistantIntentController,
    this.senderAvatarService,
    this.radarAssistantService,
    this.radarCoordinator,
    this.radarPollInterval = const Duration(minutes: 2),
    MailRadarController? radarController,
  }) : _mailService = mailService,
       _testCredentials = testCredentials,
       _attachmentStore = attachmentStore,
       _testRadarController = radarController;

  final AppSessionController? controller;
  final MailAssistantIntentController? assistantIntentController;
  final MailSenderAvatarService? senderAvatarService;
  final AiAssistantService? radarAssistantService;
  final MailRadarBackgroundCoordinator? radarCoordinator;
  final Duration radarPollInterval;
  final MailService? _mailService;
  final MailAccessCredentials? _testCredentials;
  final MailAttachmentStore? _attachmentStore;
  final MailRadarController? _testRadarController;

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> with WidgetsBindingObserver {
  void _updateMail(VoidCallback action) {
    if (mounted) setState(action);
  }

  late final MailService _mailService =
      widget._mailService ?? createMailService();
  late final MailAttachmentStore _attachmentStore =
      widget._attachmentStore ?? const IoMailAttachmentStore();
  late final MailSenderAvatarService _senderAvatarService =
      widget.senderAvatarService ??
      IoMailSenderAvatarService.sharedPortraitCache;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _senderController = TextEditingController();
  final TextEditingController _recipientController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<String?> _openSwipe = ValueNotifier(null);
  final Map<MailFolder, MailFolderInfo> _folderInfos = {};
  final Set<String> _previewRequests = {};
  Timer? _previewDebounce;
  MailCollection _collection = MailCollection.folder;
  List<MailMessageSummary> _collectionMessages = [];
  bool _loadingCollection = false;
  bool _folderMenuOpen = false;
  AssistantContextCoordinator? _contextCoordinator;
  AssistantContextRegistration? _contextRegistration;

  MailAccessCredentials? _credentials;
  int _mailAccessRevision = -1;
  MailFolderSnapshot? _snapshot;
  String? _errorMessage;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _showUnreadOnly = false;
  MailSortOrder _sortOrder = MailSortOrder.newestFirst;
  int? _openingMessageUid;
  String _searchQuery = '';
  MailFolder _currentFolder = MailFolder.inbox;
  MailSearchScope _searchScope = MailSearchScope.allText;
  bool _isSearching = false;
  List<MailMessageSummary>? _searchResults;
  Timer? _searchDebounce;
  Timer? _radarPollTimer;
  bool _isMultiSelectMode = false;
  bool _isSelectingAll = false;
  int _selectionRequestGeneration = 0;
  final Set<String> _selectedUids = {};
  bool _isDeleting = false;
  int _folderRequestGeneration = 0;
  int _searchRequestGeneration = 0;
  bool _handlingAssistantIntent = false;
  bool _showRadar = false;
  bool _localRadarFeatureAvailable = false;
  MailRadarController? _radarController;
  MailRadarController? _listenedRadarController;
  Future<MailRadarController?>? _radarInitialization;
  MailMessageSummary? _desktopSelectedMessage;
  MailMessageDetail? _desktopSelectedDetail;
  String? _desktopDetailError;
  bool _desktopDetailLoading = false;
  final LayerLink _desktopSearchLink = LayerLink();
  static const double _desktopSearchWidth = 260;

  bool get _showScopeArea =>
      _searchQuery.isNotEmpty ||
      _searchScope == MailSearchScope.from ||
      _searchScope == MailSearchScope.to;

  @override
  void initState() {
    super.initState();
    AccountHabits.shared.addListener(_mailHabitsChanged);
    _restoreMailHabits();
    // Inject test credentials if provided
    _credentials = widget._testCredentials;
    widget.controller?.mailAccess.addListener(_handleMailAccessChanged);
    _radarController =
        widget._testRadarController ?? widget.radarCoordinator?.controller;
    _listenToRadarController(_radarController);
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    widget.assistantIntentController?.addListener(_handleAssistantIntent);
    widget.radarCoordinator?.addListener(_handleRadarCoordinatorChanged);
    _refreshFolder();
    unawaited(_ensureRadarController());
    _scheduleAssistantIntent();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startRadarPolling();
      unawaited(_scanRadarInBackground());
      return;
    }
    _radarPollTimer?.cancel();
    _radarPollTimer = null;
  }

  @override
  void didUpdateWidget(covariant MailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.mailAccess.removeListener(_handleMailAccessChanged);
      widget.controller?.mailAccess.addListener(_handleMailAccessChanged);
      _mailAccessRevision = -1;
      _handleMailAccessChanged();
    }
    if (!identical(
      oldWidget.assistantIntentController,
      widget.assistantIntentController,
    )) {
      oldWidget.assistantIntentController?.removeListener(
        _handleAssistantIntent,
      );
      widget.assistantIntentController?.addListener(_handleAssistantIntent);
      _scheduleAssistantIntent();
    }
    if (!identical(oldWidget.radarCoordinator, widget.radarCoordinator)) {
      oldWidget.radarCoordinator?.removeListener(
        _handleRadarCoordinatorChanged,
      );
      widget.radarCoordinator?.addListener(_handleRadarCoordinatorChanged);
      _handleRadarCoordinatorChanged();
    }
  }

  /// Visibility is intentionally narrower than server capability.  A user who
  /// selected “不使用”, or whose consent was revoked, must return to the normal
  /// three-control mailbox immediately.
  bool get _radarEffectivelyEnabled {
    final controller = _radarController;
    if (widget._testRadarController != null) {
      return controller?.hasConsent == true && controller?.enabled == true;
    }
    final coordinator = widget.radarCoordinator;
    if (coordinator != null) return coordinator.isEffectivelyEnabled;
    return _localRadarFeatureAvailable &&
        controller?.hasConsent == true &&
        controller?.enabled == true;
  }

  void _handleRadarCoordinatorChanged() {
    final controller = widget.radarCoordinator?.controller;
    if (controller != null) {
      _radarController = controller;
      _listenToRadarController(controller);
    }
    if (!mounted) return;
    setState(() {
      if (!_radarEffectivelyEnabled) _showRadar = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = AssistantContextScope.maybeOf(context);
    if (coordinator == null || identical(coordinator, _contextCoordinator)) {
      return;
    }
    _contextRegistration?.dispose();
    _contextCoordinator = coordinator;
    _contextRegistration = coordinator.register(
      AssistantContextContribution(
        mailSummaries: _assistantMailSummaries,
        loadMailSummaries: _loadAssistantMailSummaries,
      ),
    );
  }

  @override
  void dispose() {
    AccountHabits.shared.removeListener(_mailHabitsChanged);
    final closed = _workspaceComposeClosed;
    if (closed != null && !closed.isCompleted) closed.complete();
    widget.controller?.mailAccess.removeListener(_handleMailAccessChanged);
    WidgetsBinding.instance.removeObserver(this);
    widget.assistantIntentController?.removeListener(_handleAssistantIntent);
    widget.radarCoordinator?.removeListener(_handleRadarCoordinatorChanged);
    _listenedRadarController?.removeListener(_handleRadarControllerChanged);
    _contextRegistration?.dispose();
    _searchController.dispose();
    _senderController.dispose();
    _recipientController.dispose();
    _scrollController.dispose();
    _openSwipe.dispose();
    _previewDebounce?.cancel();
    _searchDebounce?.cancel();
    _radarPollTimer?.cancel();
    if (widget.radarCoordinator == null &&
        widget._testRadarController == null) {
      _radarController?.dispose();
    }
    if (widget._mailService == null) unawaited(_mailService.close());
    super.dispose();
  }

  void _listenToRadarController(MailRadarController? controller) {
    if (identical(_listenedRadarController, controller)) return;
    _listenedRadarController?.removeListener(_handleRadarControllerChanged);
    _listenedRadarController = controller;
    controller?.addListener(_handleRadarControllerChanged);
  }

  void _handleRadarControllerChanged() {
    if (!mounted) return;
    setState(() {
      if (!_radarEffectivelyEnabled) _showRadar = false;
    });
  }

  void _handleAssistantIntent() {
    _scheduleAssistantIntent();
  }

  void _scheduleAssistantIntent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_consumeAssistantIntent());
      }
    });
  }

  Future<void> _consumeAssistantIntent() async {
    if (_handlingAssistantIntent) return;
    final intent = widget.assistantIntentController?.takePendingIntent();
    if (intent == null) return;
    _handlingAssistantIntent = true;
    try {
      final expectedIdentity = AssistantActionRuntime.mailIdentity(
        folder: intent.folder,
        uid: intent.uid,
        mailboxUidValidity: intent.mailboxUidValidity,
      );
      if (intent.targetIdentity != expectedIdentity ||
          (intent.kind == AssistantMailIntentKind.restore &&
              intent.folder != MailFolder.trash) ||
          (intent.kind == AssistantMailIntentKind.delete &&
              intent.folder == MailFolder.trash)) {
        throw const MailServiceException('邮件操作引用无效，请重新询问小U。');
      }

      if (_currentFolder != intent.folder) {
        setState(() => _currentFolder = intent.folder);
      }
      await _refreshFolder();
      if (!mounted) return;
      final snapshot = _snapshot;
      if (snapshot == null ||
          snapshot.folder != intent.folder ||
          snapshot.mailboxUidValidity != intent.mailboxUidValidity) {
        throw const MailServiceException('邮箱内容已更新，请重新询问小U。');
      }
      final credentials = await _getCredentials();
      if (credentials == null || !mounted) {
        throw const MailServiceException('请先登录后再操作邮箱。');
      }
      final detail = await _mailService.readMessage(
        credentials: credentials,
        folder: intent.folder,
        uid: intent.uid,
        expectedMailboxUidValidity: intent.mailboxUidValidity,
      );
      if (!mounted ||
          detail.uid != intent.uid ||
          detail.folder != intent.folder ||
          detail.mailboxUidValidity != intent.mailboxUidValidity) {
        throw const MailServiceException('邮件引用已失效，请刷新邮箱后重试。');
      }

      final isRestore = intent.kind == AssistantMailIntentKind.restore;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: BnbuText(isRestore ? '确认恢复邮件' : '确认删除邮件'),
          content: BnbuText(
            '${isRestore ? '恢复' : '删除'}“${detail.subject.trim().isEmpty ? '无主题邮件' : detail.subject.trim()}”？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const BnbuText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: BnbuText(isRestore ? '恢复' : '删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      if (isRestore) {
        await _mailService.restoreMessages(
          credentials: credentials,
          uids: [intent.uid],
          userEmailAddress: credentials.emailAddress,
          expectedMailboxUidValidity: intent.mailboxUidValidity,
        );
      } else {
        await _mailService.deleteMessages(
          credentials: credentials,
          folder: intent.folder,
          uids: [intent.uid],
          expectedMailboxUidValidity: intent.mailboxUidValidity,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: BnbuText(isRestore ? '邮件已恢复。' : '邮件已删除。')),
      );
      await _refreshFolder();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: BnbuText(error.toString())));
    } finally {
      _handlingAssistantIntent = false;
      if (mounted) _scheduleAssistantIntent();
    }
  }

  void _onScroll() {
    _schedulePreviews();
    if (_collection != MailCollection.folder || _showRadar) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<MailAccessCredentials?> _getCredentials() async {
    if (widget._testCredentials != null) return widget._testCredentials;
    final creds = await widget.controller?.loadMailAccessCredentials();
    _credentials = creds;
    return creds;
  }

  void _handleMailAccessChanged() {
    final access = widget.controller?.mailAccess;
    if (!mounted || access == null || access.revision == _mailAccessRevision) {
      return;
    }
    if (_workspaceCompose != null &&
        (access.credentials == null ||
            access.credentials!.userId != _credentials?.userId ||
            access.credentials!.emailAddress != _credentials?.emailAddress ||
            access.credentials!.password != _credentials?.password)) {
      _workspaceComposeKey.currentState?._draftTimer?.cancel();
      _workspaceCompose?.onClosed?.call();
    }
    _mailAccessRevision = access.revision;
    _folderRequestGeneration++;
    _searchRequestGeneration++;
    setState(() {
      _credentials = access.credentials;
      if (access.credentials == null) {
        _snapshot = null;
        _searchResults = null;
        _isLoading = false;
      }
    });
    if (access.status == MailAccessStatus.connected ||
        (access.status == MailAccessStatus.unavailable &&
            access.credentials != null)) {
      unawaited(_refreshFolder());
    }
  }

  Future<void> _refreshFolder() async {
    _setSelectionMode(false);
    final folder = _currentFolder;
    final requestGeneration = ++_folderRequestGeneration;
    _searchRequestGeneration++;
    _searchDebounce?.cancel();
    _senderController.clear();
    _recipientController.clear();
    setState(() {
      _isLoading = true;
      _isLoadingMore = false;
      _errorMessage = null;
      if (_snapshot?.folder != folder) {
        _snapshot = null;
      }
      _searchResults = null;
      _isSearching = false;
      _searchScope = MailSearchScope.allText;
      _isMultiSelectMode = false;
      _selectedUids.clear();
    });

    try {
      final credentials = await _getCredentials();
      if (credentials == null) {
        throw const MailServiceException('请先登录后再读取邮箱。');
      }
      final cache = _mailService;
      if (_snapshot == null &&
          (cache is MailSortedFolderReader || cache is MailCacheReader)) {
        final cached = cache is MailSortedFolderReader
            ? await (cache as MailSortedFolderReader).readCachedSortedFolder(
                credentials: credentials,
                folder: folder,
                unreadOnly: _showUnreadOnly,
                sortOrder: _sortOrder,
              )
            : await (cache as MailCacheReader).readCachedFolder(
                credentials: credentials,
                folder: folder,
                unreadOnly: _showUnreadOnly,
              );
        if (!mounted ||
            requestGeneration != _folderRequestGeneration ||
            folder != _currentFolder) {
          return;
        }
        if (cached != null) setState(() => _snapshot = cached);
      }
      final snapshot = await _withMailReadRetry(
        () => _fetchMailboxPage(credentials, folder, 1, null),
      );
      if (!mounted ||
          requestGeneration != _folderRequestGeneration ||
          folder != _currentFolder) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
      });
      _schedulePreviews();
      unawaited(_loadFolderInformation());
      if (folder == MailFolder.inbox) {
        unawaited(_scanRadarInBackground());
      }
    } catch (error) {
      if (!mounted ||
          requestGeneration != _folderRequestGeneration ||
          folder != _currentFolder) {
        return;
      }
      if (error is MailAuthenticationException && _credentials != null) {
        await widget.controller?.mailAccess.reportAuthenticationFailure(
          _credentials!,
        );
        return;
      }
      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted && requestGeneration == _folderRequestGeneration) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final snapshot = _snapshot;
    if (snapshot == null || _isLoadingMore || _isLoading) return;
    if (snapshot.folder != _currentFolder ||
        snapshot.currentPage * snapshot.pageSize >= snapshot.totalMessages) {
      return;
    }

    final folder = snapshot.folder;
    final requestGeneration = _folderRequestGeneration;
    setState(() => _isLoadingMore = true);

    try {
      final credentials = await _getCredentials();
      if (credentials == null) return;
      final nextPage = snapshot.currentPage + 1;
      final cache = _mailService;
      final cached = cache is MailSortedFolderReader
          ? await (cache as MailSortedFolderReader).readCachedSortedFolder(
              credentials: credentials,
              folder: folder,
              page: nextPage,
              unreadOnly: _showUnreadOnly,
              sortOrder: _sortOrder,
            )
          : cache is MailCacheReader
          ? await (cache as MailCacheReader).readCachedFolder(
              credentials: credentials,
              folder: folder,
              page: nextPage,
              unreadOnly: _showUnreadOnly,
            )
          : null;
      final nextSnapshot =
          cached != null &&
              cached.mailboxUidValidity == snapshot.mailboxUidValidity
          ? cached
          : await _withMailReadRetry(
              () => _fetchMailboxPage(
                credentials,
                folder,
                nextPage,
                snapshot.mailboxUidValidity,
              ),
            );
      if (!mounted ||
          requestGeneration != _folderRequestGeneration ||
          folder != _currentFolder) {
        return;
      }
      if (nextSnapshot.folder != folder ||
          nextSnapshot.mailboxUidValidity != snapshot.mailboxUidValidity) {
        throw const MailServiceException('邮箱内容已更新，请刷新后重试。');
      }
      setState(() {
        _snapshot = snapshot.copyWith(
          messages: [...snapshot.messages, ...nextSnapshot.messages],
          currentPage: nextPage,
        );
      });
      _schedulePreviews();
    } catch (error) {
      if (mounted &&
          requestGeneration == _folderRequestGeneration &&
          folder == _currentFolder) {
        setState(() => _errorMessage = error.toString());
      }
    } finally {
      if (mounted && requestGeneration == _folderRequestGeneration) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchRequestGeneration++;
    setState(() {
      _searchQuery = value;
      _isSearching = false;
      // Only clear results if we're not in from/to mode (those have their own inputs)
      if (value.isEmpty &&
          _searchScope != MailSearchScope.from &&
          _searchScope != MailSearchScope.to) {
        _searchResults = null;
        _isSearching = false;
      }
    });
    // from/to scopes use the secondary input, not the main bar
    if (_searchScope == MailSearchScope.from ||
        _searchScope == MailSearchScope.to) {
      return;
    }
    if (value.trim().isEmpty) return;
    _searchDebounce = Timer(const Duration(milliseconds: 500), _runSearch);
  }

  Future<T> _withMailReadRetry<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on MailServiceException catch (error) {
      if (!error.isRetryable) {
        rethrow;
      }
      await _mailService.close();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      return operation();
    }
  }

  void _onSenderChanged(String value) {
    _searchDebounce?.cancel();
    _searchRequestGeneration++;
    setState(() => _isSearching = false);
    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), _runSearch);
  }

  void _onRecipientChanged(String value) {
    _searchDebounce?.cancel();
    _searchRequestGeneration++;
    setState(() => _isSearching = false);
    if (value.trim().isEmpty) {
      setState(() {
        _searchResults = null;
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), _runSearch);
  }

  Future<void> _runSearch() async {
    if (_showRadar || _collection != MailCollection.folder) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchResults = null;
        });
      }
      return;
    }
    final scope = _searchScope;
    final folder = _currentFolder;
    final String query;
    switch (scope) {
      case MailSearchScope.from:
        query = _senderController.text.trim();
        break;
      case MailSearchScope.to:
        query = _recipientController.text.trim();
        break;
      default:
        query = _searchQuery.trim();
    }
    final requestGeneration = ++_searchRequestGeneration;
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _searchResults = null;
          _isSearching = false;
        });
      }
      return;
    }
    final credentials = await _getCredentials();
    if (credentials == null ||
        !mounted ||
        requestGeneration != _searchRequestGeneration) {
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await _mailService.searchFolder(
        credentials: credentials,
        query: query,
        folder: folder,
        searchScope: scope,
      );
      if (!mounted ||
          requestGeneration != _searchRequestGeneration ||
          folder != _currentFolder ||
          scope != _searchScope) {
        return;
      }
      setState(() => _searchResults = results);
    } catch (error) {
      if (!mounted ||
          requestGeneration != _searchRequestGeneration ||
          folder != _currentFolder ||
          scope != _searchScope) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: BnbuText('搜索失败：$error')));
    } finally {
      if (mounted && requestGeneration == _searchRequestGeneration) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _onScopeChanged(MailSearchScope scope) {
    _searchDebounce?.cancel();
    _searchRequestGeneration++;
    // Tapping an already-selected chip toggles it off (back to allText)
    if (_searchScope == scope) {
      setState(() {
        _searchScope = MailSearchScope.allText;
        _searchResults = null;
        _isSearching = false;
      });
      // Re-run text search if main bar has content
      if (_searchQuery.trim().isNotEmpty) _runSearch();
      return;
    }
    setState(() {
      _searchScope = scope;
      _searchResults = null;
      _isSearching = false;
    });
    // For from/to, wait for user to type in secondary input
    if (scope == MailSearchScope.from || scope == MailSearchScope.to) return;
    // For subject, re-run if main bar has content
    if (_searchQuery.trim().isNotEmpty) {
      _searchDebounce?.cancel();
      _runSearch();
    }
  }

  var _workspaceComposeKey = GlobalKey<_ComposeMailPageState>();
  ComposeMailPage? _workspaceCompose;
  Completer<void>? _workspaceComposeClosed;
  bool _openingCompose = false;

  Future<void> _presentCompose(
    ComposeMailPage Function(Key? key, VoidCallback? onClosed, bool embedded)
    builder,
  ) async {
    if (_openingCompose) return;
    _openingCompose = true;
    try {
      if (_workspaceCompose != null) {
        await _workspaceComposeKey.currentState?._onCancel();
        if (!mounted || _workspaceCompose != null) return;
      }
      if (!mounted) return;
      final width = (context.findRenderObject() as RenderBox?)?.size.width ?? 0;
      if (width < BnbuBreakpoints.tabletWorkspace) {
        _openingCompose = false;
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(builder: (_) => builder(null, null, false)),
        );
        return;
      }
      final closed = Completer<void>();
      setState(() {
        _workspaceComposeClosed = closed;
        _workspaceComposeKey = GlobalKey<_ComposeMailPageState>();
        _workspaceCompose = builder(_workspaceComposeKey, () {
          if (!mounted) return;
          setState(() {
            _workspaceCompose = null;
            _workspaceComposeClosed = null;
          });
          MailSelectionNotification(_isMultiSelectMode).dispatch(context);
          if (!closed.isCompleted) closed.complete();
        }, true);
      });
      MailSelectionNotification(true).dispatch(context);
      _openingCompose = false;
      await closed.future;
    } finally {
      _openingCompose = false;
    }
  }

  Future<void> _openMessage(MailMessageSummary message) async {
    if (_openingMessageUid != null) return;

    final credentials = _credentials;
    if (credentials == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('请先登录后再读取邮箱。')));
      return;
    }

    if (message.folder != MailFolder.drafts) {
      await _pushMessageDetail(message, credentials: credentials);
      return;
    }

    setState(() => _openingMessageUid = message.uid);

    try {
      final detail = await _mailService.readMessage(
        credentials: credentials,
        folder: message.folder,
        uid: message.uid,
        expectedMailboxUidValidity: message.mailboxUidValidity,
      );
      if (!mounted) return;

      await _presentCompose(
        (key, onClosed, embedded) => ComposeMailPage(
          key: key,
          onClosed: onClosed,
          embeddedInWorkspace: embedded,
          senderDisplayName: mailSenderDisplayName(widget.controller),
          mailService: _mailService,
          credentials: credentials,
          draftDetail: detail,
          senderAvatarService: _senderAvatarService,
        ),
      );
      if (mounted && _currentFolder == message.folder) {
        _refreshFolder();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: BnbuText(error.toString())));
    } finally {
      if (mounted) setState(() => _openingMessageUid = null);
    }
  }

  Future<void> _pushMessageDetail(
    MailMessageSummary message, {
    required MailAccessCredentials credentials,
    bool replace = false,
  }) async {
    final visible = List<MailMessageSummary>.of(_visibleMessages);
    late Route<void> Function(MailMessageSummary target) routeFor;
    routeFor = (target) {
      final targetIndex = visible.indexWhere(
        (candidate) =>
            candidate.uid == target.uid &&
            candidate.folder == target.folder &&
            candidate.mailboxUidValidity == target.mailboxUidValidity,
      );
      final previous = targetIndex > 0 ? visible[targetIndex - 1] : null;
      final next = targetIndex >= 0 && targetIndex + 1 < visible.length
          ? visible[targetIndex + 1]
          : null;
      void openAdjacent(
        BuildContext routeContext,
        MailMessageSummary adjacent,
      ) {
        Navigator.of(routeContext).pushReplacement(routeFor(adjacent));
      }

      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'MailDetailPage'),
        builder: (routeContext) => MailDetailPage.loading(
          senderDisplayName: mailSenderDisplayName(widget.controller),
          summary: target,
          timeFormat: routeContext.l10n.dateTimeFormatter(fullMonth: true),
          loadDetail: () async {
            final detail = await _mailService.readMessage(
              credentials: credentials,
              folder: target.folder,
              uid: target.uid,
              expectedMailboxUidValidity: target.mailboxUidValidity,
            );
            _markMessageAsSeen(target);
            return detail;
          },
          onReplyTo: (detail) => _openComposePage(replyTo: detail),
          onOpenPrevious: previous == null
              ? null
              : () => openAdjacent(routeContext, previous),
          onOpenNext: next == null
              ? null
              : () => openAdjacent(routeContext, next),
          onMailboxChanged: _refreshFolder,
          mailService: _mailService,
          credentials: credentials,
          attachmentStore: _attachmentStore,
          senderAvatarService: _senderAvatarService,
        ),
      );
    };

    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (replace) {
      await navigator.pushReplacement(routeFor(message));
    } else {
      await navigator.push(routeFor(message));
    }
  }

  void _openComposePage({
    MailMessageDetail? replyTo,
    bool replyAll = false,
    MailMessageDetail? forwardFrom,
  }) {
    final credentials = _credentials;
    if (credentials == null) return;
    assert(replyTo == null || forwardFrom == null);
    final forwardedTime = forwardFrom?.date == null
        ? '未知时间'
        : context.l10n
              .dateTimeFormatter(fullMonth: true)
              .format(mailDisplayDate(forwardFrom!.date!));
    unawaited(
      _presentCompose(
        (key, onClosed, embedded) => ComposeMailPage(
          key: key,
          onClosed: onClosed,
          embeddedInWorkspace: embedded,
          senderDisplayName: mailSenderDisplayName(widget.controller),
          mailService: _mailService,
          credentials: credentials,
          replyTo: replyTo,
          replyAll: replyAll,
          initialSubject: forwardFrom == null
              ? ''
              : forwardFrom.subject.startsWith('Fwd:')
              ? forwardFrom.subject
              : 'Fwd: ${forwardFrom.subject}',
          initialBody: forwardFrom == null
              ? ''
              : MailForwardContent.plainText(forwardFrom, forwardedTime),
          initialHtmlBody: forwardFrom == null
              ? null
              : MailForwardContent.html(forwardFrom, forwardedTime),
          senderAvatarService: _senderAvatarService,
        ),
      ),
    );
  }

  void _markMessageAsSeen(MailMessageSummary message) {
    MailMessageSummary update(MailMessageSummary candidate) =>
        candidate.identityKey == message.identityKey
        ? candidate.copyWith(isSeen: true)
        : candidate;
    if (!mounted) return;
    setState(() {
      final snapshot = _snapshot;
      if (snapshot != null) {
        final wasUnread = snapshot.messages.any(
          (candidate) =>
              candidate.identityKey == message.identityKey && !candidate.isSeen,
        );
        _snapshot = snapshot.copyWith(
          messages: snapshot.messages.map(update).toList(),
          mailboxUnreadCount: snapshot.mailboxUnreadCount == null
              ? null
              : (snapshot.mailboxUnreadCount! - (wasUnread ? 1 : 0)).clamp(
                  0,
                  snapshot.totalMessages,
                ),
        );
      }
      _searchResults = _searchResults?.map(update).toList();
      _collectionMessages = _collectionMessages.map(update).toList();
    });
    unawaited(_radarController?.recordOriginalReadState([message], true));
  }

  void _toggleSelectMessage(String uid) {
    if (!_isMultiSelectMode || _isSelectingAll || _isDeleting) return;
    setState(() {
      if (_selectedUids.contains(uid)) {
        _selectedUids.remove(uid);
      } else {
        _selectedUids.add(uid);
      }
    });
  }

  List<MailMessageSummary> get _visibleMessages {
    final base = _showRadar
        ? (_radarController?.visibleItems
                  .map((item) => item.toSummary())
                  .toList() ??
              <MailMessageSummary>[])
        : _collection != MailCollection.folder
        ? _collectionMessages
        : _searchResults ?? _snapshot?.messages ?? const <MailMessageSummary>[];
    final filtered =
        (_collection != MailCollection.folder || _showRadar) &&
            _searchQuery.isNotEmpty
        ? base
              .where(
                (message) =>
                    '${message.sender} ${message.subject} ${message.preview}'
                        .toLowerCase()
                        .contains(_searchQuery.toLowerCase()),
              )
              .toList()
        : base;
    final visible = !_showUnreadOnly
        ? List<MailMessageSummary>.of(filtered)
        : filtered.where((m) => !m.isSeen).toList(growable: true);
    if (_showRadar ||
        _collection != MailCollection.folder ||
        _searchResults != null) {
      visible.sort(_compareMessagesBySelectedDateOrder);
    }
    return visible;
  }

  int _compareMessagesBySelectedDateOrder(
    MailMessageSummary left,
    MailMessageSummary right,
  ) {
    final leftDate = left.date;
    final rightDate = right.date;
    int result;
    if (leftDate != null && rightDate != null) {
      result = leftDate.compareTo(rightDate);
      if (result == 0) result = left.uid.compareTo(right.uid);
    } else if (leftDate != null) {
      result = 1;
    } else if (rightDate != null) {
      result = -1;
    } else {
      result = left.uid.compareTo(right.uid);
    }
    return _sortOrder == MailSortOrder.oldestFirst ? result : -result;
  }

  List<AssistantMailSummaryContext> _assistantMailSummaries() {
    return _assistantSummariesFrom(
      _visibleMessages.take(24),
      fallbackDate: _snapshot?.fetchedAt ?? DateTime.now(),
    );
  }

  Future<List<AssistantMailSummaryContext>>
  _loadAssistantMailSummaries() async {
    final current = _assistantMailSummaries();
    if (_currentFolder == MailFolder.drafts && _snapshot != null) {
      return current;
    }
    final credentials = await _getCredentials();
    if (credentials == null) return current;
    try {
      final draftSnapshot = await _withMailReadRetry(
        () => _mailService.fetchFolder(
          credentials: credentials,
          folder: MailFolder.drafts,
          page: 1,
          pageSize: 12,
        ),
      );
      final drafts = _assistantSummariesFrom(
        draftSnapshot.messages.take(12),
        fallbackDate: draftSnapshot.fetchedAt,
      );
      return [...drafts, ...current].take(24).toList(growable: false);
    } on Object {
      return current;
    }
  }

  List<AssistantMailSummaryContext> _assistantSummariesFrom(
    Iterable<MailMessageSummary> messages, {
    required DateTime fallbackDate,
  }) {
    return messages
        .map((message) {
          final sender = _assistantSenderParts(message.sender);
          return AssistantMailSummaryContext(
            uid: message.uid,
            folder: message.folder.name,
            mailboxUidValidity: message.mailboxUidValidity,
            senderName: _limitAssistantText(sender.$1, 160),
            senderEmail: _limitAssistantText(sender.$2, 254),
            subject: _limitAssistantText(message.subject, 300),
            receivedAt: message.date ?? fallbackDate,
            preview: _limitAssistantText(message.preview, 320),
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final access = widget.controller?.mailAccess;
    if (widget._testCredentials == null &&
        access?.owner != null &&
        access!.credentials == null) {
      return MailConnectionPanel(
        key: ValueKey(access.owner),
        controller: access,
      );
    }
    final tokens = context.bnbuTheme;
    final visible = _visibleMessages;
    final snapshot = _snapshot;
    final hasMore =
        !_showRadar &&
        _collection == MailCollection.folder &&
        !_isSearching &&
        _searchResults == null &&
        snapshot != null &&
        snapshot.currentPage * snapshot.pageSize < snapshot.totalMessages;

    return PopScope(
      canPop:
          _workspaceCompose == null || !NavigationTabScope.isActiveOf(context),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop &&
            _workspaceCompose != null &&
            NavigationTabScope.isActiveOf(context)) {
          unawaited(_workspaceComposeKey.currentState?._onCancel());
        }
      },
      child: BnbuLoadingRegion(
        child: Scaffold(
          backgroundColor: tokens.canvas,
          bottomNavigationBar: null,
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= BnbuBreakpoints.tabletWorkspace) {
                return _buildDesktopWorkspace(
                  context,
                  visible: visible,
                  hasMore: hasMore,
                );
              }
              return _workspaceCompose ?? _buildMobileMailbox(context);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopWorkspace(
    BuildContext context, {
    required List<MailMessageSummary> visible,
    required bool hasMore,
  }) {
    final tokens = context.bnbuTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // A 3-pane mailbox only starts when the reading canvas has enough room.
        // At the tablet breakpoint the folder pane is removed first, never the
        // current list or the reading pane.
        final showFolders = constraints.maxWidth >= 1100;
        final listWidth = (constraints.maxWidth * .24).clamp(280.0, 330.0);
        final readingPaneLeft =
            (showFolders ? _DesktopMailFolderTile.paneWidth : 0) +
            listWidth +
            1;
        return SafeArea(
          child: Stack(
            children: [
              Column(
                key: const ValueKey('mail-desktop-workspace'),
                children: [
                  _buildDesktopCommandBar(
                    context,
                    readingPaneLeft: readingPaneLeft,
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        if (showFolders)
                          SizedBox(
                            key: const ValueKey('mail-desktop-folder-pane'),
                            width: _DesktopMailFolderTile.paneWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: tokens.surface.withValues(alpha: 0.72),
                                border: Border(
                                  right: BorderSide(color: tokens.border),
                                ),
                              ),
                              child: _buildDesktopFolderPane(context),
                            ),
                          ),
                        Expanded(
                          child: Row(
                            children: [
                              SizedBox(
                                width: listWidth,
                                child: Column(
                                  children: [
                                    _buildDesktopMailboxStatus(
                                      context,
                                      visible,
                                    ),
                                    Expanded(
                                      child: _buildDesktopBody(
                                        context,
                                        visible: visible,
                                        hasMore: hasMore,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: tokens.border,
                              ),
                              Expanded(
                                child:
                                    _workspaceCompose ??
                                    _buildDesktopReadingPane(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_showScopeArea &&
                  !_showRadar &&
                  _collection == MailCollection.folder)
                Positioned(
                  top: 0,
                  left: 0,
                  child: CompositedTransformFollower(
                    link: _desktopSearchLink,
                    showWhenUnlinked: false,
                    targetAnchor: Alignment.bottomLeft,
                    offset: const Offset(0, 4),
                    child: SizedBox(
                      width: _desktopSearchWidth,
                      child: Material(
                        elevation: 6,
                        borderRadius: BorderRadius.circular(tokens.radius12),
                        clipBehavior: Clip.antiAlias,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: constraints.maxHeight - 56,
                          ),
                          child: SingleChildScrollView(
                            child: _buildScopeChips(desktop: true),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopFolderPane(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Tooltip(
          message: _credentials?.emailAddress ?? _snapshot?.emailAddress ?? '',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
            child: BnbuText(
              _credentials?.emailAddress ?? _snapshot?.emailAddress ?? '邮箱',
              key: const ValueKey('mail-desktop-account'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        _DesktopMailFolderTile(
          icon: LucideIcons.inbox300,
          label: '收件箱',
          count:
              _folderInfos[MailFolder.inbox]?.total ??
              (_currentFolder == MailFolder.inbox
                  ? _snapshot?.totalMessages
                  : null),
          selected:
              !_showRadar &&
              _collection == MailCollection.folder &&
              _currentFolder == MailFolder.inbox,
          onTap: () => _selectFolder(MailFolder.inbox),
        ),
        _DesktopMailFolderTile(
          icon: LucideIcons.star300,
          label: '星标邮件',
          selected: !_showRadar && _collection == MailCollection.starred,
          onTap: () => _chooseCollection('starred'),
        ),
        for (final folder in const [
          MailFolder.drafts,
          MailFolder.sent,
          MailFolder.trash,
          MailFolder.junk,
        ])
          _DesktopMailFolderTile(
            icon: _desktopFolderIcon(folder),
            label: _folderLabel(folder),
            count:
                _folderInfos[folder]?.total ??
                (_currentFolder == folder ? _snapshot?.totalMessages : null),
            selected:
                !_showRadar &&
                _collection == MailCollection.folder &&
                folder == _currentFolder,
            onTap: () => _selectFolder(folder),
          ),
        if (_radarEffectivelyEnabled)
          _DesktopMailFolderTile(
            icon: LucideIcons.radar300,
            label: '邮件雷达',
            selected: _showRadar,
            onTap: _selectRadar,
          ),
        const Spacer(),
      ],
    );
  }

  Widget _buildDesktopCommandBar(
    BuildContext context, {
    required double readingPaneLeft,
  }) {
    final tokens = context.bnbuTheme;
    final selectedDesktop = _desktopSelectedMessage;
    final isTrash =
        _currentFolder == MailFolder.trash ||
        selectedDesktop?.folder == MailFolder.trash;
    return LayoutBuilder(
      builder: (context, constraints) {
        final commandWidth = readingPaneLeft - tokens.space8;
        final labels = [
          '收取',
          '新建邮件',
          isTrash ? '恢复' : '删除',
          '回复',
          '回复全部',
          '转发',
        ];
        var labelCommandsWidth = tokens.space4;
        for (final label in labels) {
          final painter = TextPainter(
            text: TextSpan(
              text: context.l10n.text(label),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout();
          labelCommandsWidth += (painter.width + 40).clamp(
            48.0,
            double.infinity,
          );
          painter.dispose();
        }
        final compact =
            constraints.maxWidth < 1180 || labelCommandsWidth > commandWidth;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: tokens.surface.withValues(alpha: 0.82),
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.space8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: commandWidth,
                  height: 44,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DesktopMailCommand(
                        icon: LucideIcons.refreshCw300,
                        label: '收取',
                        compact: compact,
                        onPressed: _isLoading ? null : _refreshFolder,
                      ),
                      _DesktopMailCommand(
                        buttonKey: const ValueKey('mail-desktop-compose'),
                        icon: LucideIcons.squarePen300,
                        label: '新建邮件',
                        compact: compact,
                        onPressed: _credentials == null
                            ? null
                            : _openComposePage,
                      ),
                      _DesktopMailCommand(
                        buttonKey: const ValueKey(
                          'mail-desktop-delete-or-restore',
                        ),
                        icon: isTrash
                            ? LucideIcons.archiveRestore300
                            : LucideIcons.trash2300,
                        label: isTrash ? '恢复' : '删除',
                        compact: compact,
                        onPressed: selectedDesktop == null
                            ? null
                            : _performDesktopDeleteOrRestore,
                      ),
                      _DesktopMailCommand(
                        buttonKey: const ValueKey('mail-desktop-reply'),
                        icon: LucideIcons.reply300,
                        label: '回复',
                        compact: compact,
                        onPressed: _desktopSelectedDetail == null
                            ? null
                            : () => _openComposePage(
                                replyTo: _desktopSelectedDetail,
                              ),
                      ),
                      _DesktopMailCommand(
                        buttonKey: const ValueKey('mail-desktop-reply-all'),
                        icon: LucideIcons.replyAll300,
                        label: '回复全部',
                        compact: compact,
                        onPressed: _desktopSelectedDetail == null
                            ? null
                            : () => _openComposePage(
                                replyTo: _desktopSelectedDetail,
                                replyAll: true,
                              ),
                      ),
                      _DesktopMailCommand(
                        buttonKey: const ValueKey('mail-desktop-forward'),
                        icon: LucideIcons.forward300,
                        label: '转发',
                        compact: compact,
                        onPressed: _desktopSelectedDetail == null
                            ? null
                            : () => _openComposePage(
                                forwardFrom: _desktopSelectedDetail,
                              ),
                      ),
                      const Spacer(),
                      SizedBox(width: tokens.space4),
                    ],
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: CompositedTransformTarget(
                      link: _desktopSearchLink,
                      child: SizedBox(
                        width: _desktopSearchWidth,
                        height: 44,
                        child: BnbuRevealSearch.hidden(
                          mode: BnbuRevealSearchMode.local,
                          controlKey: const ValueKey('mail-search-control'),
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          isLoading: _isSearching,
                          hintText: context.l10n.text('搜索邮件'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _performDesktopDeleteOrRestore() async {
    final selected = _desktopSelectedMessage;
    if (selected == null) return;
    if (selected.folder == MailFolder.trash) {
      await _restoreDesktopMessage(selected);
      return;
    }
    await _deleteMailRows([selected]);
  }

  Future<void> _restoreDesktopMessage(MailMessageSummary message) async {
    final snapshot = _snapshot;
    if (snapshot == null || snapshot.folder != MailFolder.trash) return;
    final credentials = await _getCredentials();
    if (credentials == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const BnbuText('确认恢复'),
        content: BnbuText(
          '将“${message.subject.trim().isEmpty ? '无主题邮件' : message.subject.trim()}”恢复到原文件夹？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const BnbuText('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        _currentFolder != MailFolder.trash ||
        _snapshot?.mailboxUidValidity != snapshot.mailboxUidValidity) {
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await _mailService.restoreMessages(
        credentials: credentials,
        uids: [message.uid],
        userEmailAddress: credentials.emailAddress,
        expectedMailboxUidValidity: snapshot.mailboxUidValidity,
      );
      if (!mounted ||
          _currentFolder != MailFolder.trash ||
          _snapshot?.mailboxUidValidity != snapshot.mailboxUidValidity) {
        return;
      }
      setState(() {
        _snapshot = snapshot.copyWith(
          messages: snapshot.messages
              .where(
                (candidate) => candidate.identityKey != message.identityKey,
              )
              .toList(),
        );
        if (_desktopSelectedMessage?.identityKey == message.identityKey) {
          _desktopSelectedMessage = null;
          _desktopSelectedDetail = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: BnbuText('恢复失败：$error')));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Widget _buildDesktopMailboxStatus(
    BuildContext context,
    List<MailMessageSummary> visible,
  ) {
    final tokens = context.bnbuTheme;
    final isFolder = _collection == MailCollection.folder && !_showRadar;
    final total = _showRadar || !isFolder || _searchResults != null
        ? visible.length
        : (_snapshot?.totalMessages ?? visible.length);
    final label = _showRadar
        ? '邮件雷达'
        : isFolder
        ? _folderLabel(_currentFolder)
        : '星标邮件';
    return Container(
      key: const ValueKey('mail-desktop-status'),
      height: 34,
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: tokens.space12),
      decoration: BoxDecoration(
        color: tokens.canvas,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          BnbuText(
            '${context.l10n.text(label)}($total)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          BnbuMenuButton<String>(
            key: const ValueKey('mail-desktop-result-menu'),
            tooltip: context.l10n.text('筛选与排序'),
            onSelected: _handleDesktopResultMenu,
            itemBuilder: (context) => [
              _desktopResultMenuItem('all', '全部', !_showUnreadOnly),
              _desktopResultMenuItem('unread', '未读', _showUnreadOnly),
              const PopupMenuDivider(),
              _desktopResultMenuItem(
                'newest',
                '由新到旧',
                _sortOrder == MailSortOrder.newestFirst,
              ),
              _desktopResultMenuItem(
                'oldest',
                '由旧到新',
                _sortOrder == MailSortOrder.oldestFirst,
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BnbuText(
                    _showUnreadOnly ? '未读' : '全部',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.brandBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    LucideIcons.chevronDown300,
                    size: 14,
                    color: tokens.brandBlue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _desktopResultMenuItem(
    String value,
    String label,
    bool selected,
  ) => BnbuMenuItem<String>(
    value: value,
    selected: selected,
    child: BnbuText(label),
  );

  void _restoreMailHabits() {
    if (!AccountHabits.shared.managed) return;
    _showUnreadOnly = AccountHabits.shared.read('mail.unread_only', false);
    _sortOrder =
        AccountHabits.shared.read('mail.sort_order', 'newestFirst') ==
            'oldestFirst'
        ? MailSortOrder.oldestFirst
        : MailSortOrder.newestFirst;
  }

  void _mailHabitsChanged() {
    if (!mounted) return;
    final before = '$_showUnreadOnly:$_sortOrder';
    setState(_restoreMailHabits);
    if (before != '$_showUnreadOnly:$_sortOrder' &&
        _desktopSelectedMessage == null) {
      unawaited(_refreshFolder());
    }
  }

  void _handleDesktopResultMenu(String value) {
    if (value == 'all' || value == 'unread') {
      final unread = value == 'unread';
      if (unread != _showUnreadOnly) _toggleUnread();
      return;
    }
    final order = value == 'oldest'
        ? MailSortOrder.oldestFirst
        : MailSortOrder.newestFirst;
    if (order == _sortOrder) return;
    setState(() => _sortOrder = order);
    unawaited(
      AccountHabits.shared
          .set('mail.sort_order', order.name)
          .catchError((Object _) {}),
    );
    if (!_showRadar &&
        _collection == MailCollection.folder &&
        _searchResults == null) {
      unawaited(_refreshFolder());
    }
  }

  Widget _buildDesktopBody(
    BuildContext context, {
    required List<MailMessageSummary> visible,
    required bool hasMore,
  }) {
    if (!_showRadar &&
        (_isLoading && _snapshot == null ||
            _errorMessage != null && _snapshot == null ||
            _snapshot == null)) {
      return _buildBody(context, visible, hasMore);
    }
    final tokens = context.bnbuTheme;
    final radarError = _showRadar ? _radarController?.error : null;
    return Column(
      children: [
        BnbuUpdateProgress(
          active:
              visible.isNotEmpty &&
              (_showRadar
                  ? _radarController?.isScanning == true
                  : _isLoading || _isSearching || _loadingCollection),
          height: 1,
        ),
        if ((_showRadar ? radarError : _errorMessage) != null)
          Padding(
            padding: EdgeInsets.all(tokens.space12),
            child: BnbuNotice(
              message: (_showRadar ? radarError : _errorMessage)!,
              kind: BnbuStatusKind.warning,
            ),
          ),
        Expanded(
          child: BnbuRefreshIndicator(
            onRefresh: _refreshCurrentMailbox,
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(height: tokens.space32),
                      if (_showRadar
                          ? _radarController?.isScanning == true
                          : _isLoading || _isSearching || _loadingCollection)
                        const BnbuInitialLoading()
                      else
                        BnbuEmptyState(
                          title: _showRadar ? '暂无雷达邮件' : '没有匹配的邮件',
                          message: _searchQuery.isNotEmpty
                              ? '换个关键词试试。'
                              : _showRadar
                              ? ''
                              : _showUnreadOnly
                              ? '当前没有未读邮件。'
                              : '该文件夹没有邮件。',
                        ),
                    ],
                  )
                : ListView.builder(
                    key: const ValueKey('mail-desktop-message-list'),
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: visible.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == visible.length) {
                        return _buildLoadMoreFooter();
                      }
                      final message = visible[index];
                      final radarItem = _showRadar
                          ? _radarItemFor(message)
                          : null;
                      return _DesktopMailRow(
                        message: message,
                        radarItem: radarItem,
                        senderAvatarService: _senderAvatarService,
                        timeLabel: _formatMessageTime(message.date),
                        active:
                            _desktopSelectedMessage?.identityKey ==
                            message.identityKey,
                        opening: _openingMessageUid == message.uid,
                        onTap: () => _selectDesktopMessage(message),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  MailRadarItem? _radarItemFor(MailMessageSummary message) {
    for (final item
        in _radarController?.visibleItems ?? const <MailRadarItem>[]) {
      if (item.toSummary().identityKey == message.identityKey) return item;
    }
    return null;
  }

  Widget _buildDesktopReadingPane() {
    final tokens = context.bnbuTheme;
    final detail = _desktopSelectedDetail;
    if (_desktopSelectedMessage == null) {
      return ColoredBox(
        color: tokens.surface,
        child: Center(
          child: BnbuText(
            '选择一封邮件',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
          ),
        ),
      );
    }
    if (_desktopDetailLoading) {
      return ColoredBox(
        color: tokens.surface,
        child: const Center(child: BnbuActivityIndicator()),
      );
    }
    if (_desktopDetailError != null || detail == null) {
      return ColoredBox(
        color: tokens.surface,
        child: Center(
          child: BnbuEmptyState(
            title: '邮件暂时无法读取',
            message: _desktopDetailError ?? '请稍后重试。',
            action: TextButton(
              onPressed: () => _selectDesktopMessage(_desktopSelectedMessage!),
              child: const BnbuText('重试'),
            ),
          ),
        ),
      );
    }
    return _DesktopMailReadingPane(
      detail: detail,
      senderAvatarService: _senderAvatarService,
      time: detail.date == null
          ? ''
          : context.l10n
                .dateTimeFormatter(fullMonth: true)
                .format(mailDisplayDate(detail.date!)),
      onReply: () => _openComposePage(replyTo: detail),
      onReplyAll: () => _openComposePage(replyTo: detail, replyAll: true),
      onForward: () => _openComposePage(forwardFrom: detail),
      onAskAssistant: () => _askDesktopAssistant(detail),
      onTranslate: _showDesktopTranslationUnavailable,
    );
  }

  Future<void> _askDesktopAssistant(MailMessageDetail detail) async {
    final launcher =
        AssistantContextScope.maybeOpenAssistantWithMailReferenceOf(context);
    final validity = detail.mailboxUidValidity;
    if (launcher == null || validity == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('小U当前不可用。')));
      return;
    }
    await launcher(
      AssistantMailReference.message(
        folder: detail.folder.name,
        uid: detail.uid,
        mailboxUidValidity: validity,
        sender: detail.sender,
        subject: detail.subject,
        receivedAt: detail.date ?? DateTime.now(),
      ),
    );
  }

  void _showDesktopTranslationUnavailable() => ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: BnbuText('智能翻译暂未开放。')));

  Future<void> _selectDesktopMessage(MailMessageSummary message) async {
    if (_openingMessageUid != null || _desktopDetailLoading) return;
    if (message.folder == MailFolder.drafts) {
      await _openMessage(message);
      return;
    }
    final credentials = _credentials;
    if (credentials == null) return;
    setState(() {
      _desktopSelectedMessage = message;
      _desktopSelectedDetail = null;
      _desktopDetailError = null;
      _desktopDetailLoading = true;
    });
    try {
      final detail = await _mailService.readMessage(
        credentials: credentials,
        folder: message.folder,
        uid: message.uid,
        expectedMailboxUidValidity: message.mailboxUidValidity,
      );
      if (!mounted ||
          _desktopSelectedMessage?.identityKey != message.identityKey) {
        return;
      }
      _markMessageAsSeen(message);
      setState(() => _desktopSelectedDetail = detail);
    } catch (error) {
      if (!mounted ||
          _desktopSelectedMessage?.identityKey != message.identityKey) {
        return;
      }
      setState(() => _desktopDetailError = error.toString());
    } finally {
      if (mounted &&
          _desktopSelectedMessage?.identityKey == message.identityKey) {
        setState(() => _desktopDetailLoading = false);
      }
    }
  }

  void _selectFolder(MailFolder folder) {
    if (!_showRadar &&
        _collection == MailCollection.folder &&
        folder == _currentFolder) {
      return;
    }
    setState(() {
      _showRadar = false;
      _collection = MailCollection.folder;
      _currentFolder = folder;
      _searchResults = null;
      _searchController.clear();
      _searchQuery = '';
      _selectedUids.clear();
      _isMultiSelectMode = false;
      _desktopSelectedMessage = null;
      _desktopSelectedDetail = null;
      _desktopDetailError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
    _refreshFolder();
  }

  Future<void> _selectRadar() async {
    if (_showRadar || !_radarEffectivelyEnabled) return;
    final controller = await _ensureRadarController();
    if (controller == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('当前版本无法连接小U邮件分析服务。')));
      return;
    }
    if (!mounted || !_radarEffectivelyEnabled) return;
    setState(() {
      _showRadar = true;
      _isMultiSelectMode = false;
      _selectedUids.clear();
      _desktopSelectedMessage = null;
      _desktopSelectedDetail = null;
      _desktopDetailError = null;
    });
    if (controller.hasConsent) {
      unawaited(controller.scan());
    }
  }

  Future<MailRadarController?> _ensureRadarController() async {
    final coordinator = widget.radarCoordinator;
    if (coordinator != null) {
      if (!await coordinator.refreshFeatureAvailability()) return null;
      final controller = await coordinator.ensureReady();
      if (controller != null && !identical(_radarController, controller)) {
        _radarController = controller;
        if (mounted) setState(() {});
      }
      return controller;
    }
    final existing = _radarInitialization;
    if (existing != null) return existing;

    final initialization = _initializeRadarController();
    _radarInitialization = initialization;
    try {
      final controller = await initialization;
      if (controller == null &&
          identical(_radarInitialization, initialization)) {
        _radarInitialization = null;
      }
      return controller;
    } catch (_) {
      if (identical(_radarInitialization, initialization)) {
        _radarInitialization = null;
      }
      rethrow;
    }
  }

  Future<MailRadarController?> _initializeRadarController() async {
    var controller = _radarController;
    if (controller == null) {
      final credentials = await _getCredentials();
      final service = widget.radarAssistantService;
      final AiAssistantMailRadarService? radarService =
          service is AiAssistantMailRadarService
          ? service as AiAssistantMailRadarService
          : null;
      if (credentials == null || service == null || radarService == null) {
        return null;
      }
      try {
        final capabilities = await service.loadCapabilities(
          widget.controller?.username ?? credentials.userId,
        );
        if (!capabilities.mailRadarEnabled) {
          _handleLocalRadarAccessUnavailable();
          return null;
        }
      } catch (_) {
        _handleLocalRadarAccessUnavailable();
        return null;
      }
      if (mounted && !_localRadarFeatureAvailable) {
        setState(() => _localRadarFeatureAvailable = true);
      }
      controller = MailRadarController(
        username: widget.controller?.username ?? credentials.userId,
        credentials: credentials,
        mailService: _mailService,
        analyzer: LightMailRadarAnalyzer(
          assistantService: service,
          radarService: radarService,
        ),
        syncService: service is AiAssistantMailRadarSyncService
            ? service as AiAssistantMailRadarSyncService
            : null,
        onRemoteAccessUnavailable: _handleLocalRadarAccessUnavailable,
      );
      _radarController = controller;
      _listenToRadarController(controller);
    }
    await controller.initialize();
    if (!mounted) return controller;
    _startRadarPolling();
    return controller;
  }

  void _handleLocalRadarAccessUnavailable() {
    if (!mounted) return;
    setState(() {
      _localRadarFeatureAvailable = false;
      _showRadar = false;
    });
  }

  void _startRadarPolling() {
    if (widget.radarCoordinator != null) return;
    _radarPollTimer?.cancel();
    if (widget.radarPollInterval <= Duration.zero) return;
    _radarPollTimer = Timer.periodic(widget.radarPollInterval, (_) {
      unawaited(_scanRadarInBackground());
    });
  }

  Future<void> _scanRadarInBackground() async {
    final controller = await _ensureRadarController();
    if (controller?.hasConsent != true || !_radarEffectivelyEnabled) return;
    await widget.radarCoordinator?.activateAfterConsent();
    if (widget._testRadarController == null) {
      final assistant = widget.radarAssistantService;
      final username = controller!.username.trim();
      if (assistant == null || username.isEmpty) return;
      try {
        if (!await assistant.isEnabled(username)) return;
      } catch (_) {
        return;
      }
    }
    await controller!.scan();
  }

  Widget _buildRadarBody({bool desktop = false}) {
    final controller = _radarController;
    if (controller == null) {
      return const Center(child: BnbuActivityIndicator());
    }
    return MailRadarView(
      // The only range picker lives in 我的 → 通用设置.  The mailbox is a
      // reading surface and never changes consent or the analysis range.
      showRangeSelector: false,
      rowBuilder: (context, item, open) {
        final message = item.toSummary().copyWith(
          preview: item.category == MailRadarCategory.deadline
              ? _DesktopMailRow._deadlineLabel(item)
              : item.summaryZh,
        );
        final colors = MailSurfaceColors(context);
        return TextFieldTapRegion(
          child: MailMessageRow(
            key: ValueKey(message.identityKey),
            message: message,
            timeLabel: _formatMessageTime(message.date),
            avatarService: _senderAvatarService,
            selectionMode: !desktop && _isMultiSelectMode,
            selected: !desktop && _selectedUids.contains(message.identityKey),
            busy: _isDeleting || _isSelectingAll,
            openSwipe: _openSwipe,
            tags: [
              MailRowTag(
                item.priority.label,
                item.priority == MailRadarPriority.urgent ||
                        item.priority == MailRadarPriority.high
                    ? const Color(0xFFEC6868)
                    : colors.secondary,
              ),
              MailRowTag(
                item.analysisPending ? '等待分析' : item.category.label,
                colors.accent,
              ),
            ],
            subjectColor: item.priority == MailRadarPriority.urgent
                ? const Color(0xFFEC6868)
                : null,
            swipeActions: _mailRowActions(message, radar: true),
            onTap: () {
              if (!desktop && _isMultiSelectMode) {
                _toggleSelectMessage(message.identityKey);
              } else {
                open();
              }
            },
            onLongPress: desktop
                ? null
                : () {
                    _setSelectionMode(true);
                    _toggleSelectMessage(message.identityKey);
                  },
          ),
        );
      },
      itemFilter: (item) =>
          (!_showUnreadOnly || !item.originalIsSeen) &&
          (_searchQuery.isEmpty ||
              '${item.subject} ${item.sender} ${item.summaryZh}'
                  .toLowerCase()
                  .contains(_searchQuery.toLowerCase())),
      controller: controller,
      assistantController: AssistantContextScope.maybeAssistantControllerOf(
        context,
      ),
      onScheduleReminder: widget.controller == null
          ? null
          : (title, body, at) async {
              if (widget.controller!.username != controller.username) {
                return '登录状态已变化。';
              }
              return widget.controller!.scheduleAssistantReminder(
                title: title,
                body: body,
                scheduledAt: at,
              );
            },
      onOpenOriginal: (item) async {
        final credentials = await _getCredentials();
        if (credentials == null || !mounted) return;
        await _pushMessageDetail(item.toSummary(), credentials: credentials);
      },
      onReply: (detail) async {
        if (!mounted) return;
        _openComposePage(replyTo: detail);
      },
    );
  }

  static IconData _desktopFolderIcon(MailFolder folder) {
    return switch (folder) {
      MailFolder.inbox => LucideIcons.inbox300,
      MailFolder.drafts => LucideIcons.filePenLine300,
      MailFolder.sent => LucideIcons.send300,
      MailFolder.trash => LucideIcons.trash2300,
      MailFolder.junk => LucideIcons.archiveX300,
    };
  }

  Widget _buildScopeChips({bool desktop = false}) {
    final tokens = context.bnbuTheme;
    return TextFieldTapRegion(
      child: BnbuSurfaceCard(
        key: desktop ? const ValueKey('mail-desktop-search-scopes') : null,
        padding: desktop ? EdgeInsets.zero : EdgeInsets.all(tokens.space12),
        borderRadius: desktop ? BorderRadius.circular(tokens.radius12) : null,
        backgroundColor: tokens.surfaceMuted,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: tokens.space8,
              runSpacing: tokens.space8,
              children: [
                _ScopeChip(
                  compact: desktop,
                  label: '仅主题',
                  selected: _searchScope == MailSearchScope.subject,
                  onTap: () => _onScopeChanged(MailSearchScope.subject),
                ),
                _ScopeChip(
                  compact: desktop,
                  label: '按发件人',
                  selected: _searchScope == MailSearchScope.from,
                  onTap: () => _onScopeChanged(MailSearchScope.from),
                ),
                _ScopeChip(
                  compact: desktop,
                  label: '按收件人',
                  selected: _searchScope == MailSearchScope.to,
                  onTap: () => _onScopeChanged(MailSearchScope.to),
                ),
              ],
            ),
            if (_searchScope == MailSearchScope.from)
              _buildSecondaryEmailInput(
                label: '发件人邮箱：',
                controller: _senderController,
                onChanged: _onSenderChanged,
              ),
            if (_searchScope == MailSearchScope.to)
              _buildSecondaryEmailInput(
                label: '收件人邮箱：',
                controller: _recipientController,
                onChanged: _onRecipientChanged,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryEmailInput({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.only(top: tokens.space8),
      child: BnbuSurfaceCard(
        padding: EdgeInsets.symmetric(horizontal: tokens.space12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: tokens.minInteractiveDimension,
          ),
          child: Row(
            children: [
              BnbuText(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: tokens.textSecondary),
              ),
              SizedBox(width: tokens.space8),
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  autofocus: true,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: false,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: tokens.space12,
                    ),
                    hintText: context.l10n.text('输入邮箱地址...'),
                    hintStyle: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: tokens.textMuted),
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: tokens.textPrimary),
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              if (controller.text.isNotEmpty)
                IconButton(
                  tooltip: context.l10n.text('清除邮箱地址'),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: Icon(LucideIcons.x300, color: tokens.textMuted),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Equal-width 3-section toolbar: [folder▼] | [未读] | [多选]
  Future<void> _restoreSelected() async {
    final snapshot = _snapshot;
    if (_selectedUids.isEmpty ||
        snapshot == null ||
        snapshot.folder != MailFolder.trash) {
      return;
    }
    final credentials = await _getCredentials();
    if (credentials == null || !mounted) return;

    final mailboxUidValidity = snapshot.mailboxUidValidity;
    final uids = _selectedMessages
        .map((message) => message.uid)
        .toList(growable: false);
    final tokens = context.bnbuTheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const BnbuText('确认恢复'),
        content: BnbuText('将已选 ${uids.length} 封邮件恢复到原文件夹？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const BnbuText('取消'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: tokens.brandBlue),
            onPressed: () => Navigator.pop(context, true),
            child: const BnbuText('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        _currentFolder != MailFolder.trash ||
        _snapshot?.mailboxUidValidity != mailboxUidValidity) {
      return;
    }

    setState(() => _isDeleting = true);
    try {
      await _mailService.restoreMessages(
        credentials: credentials,
        uids: uids,
        userEmailAddress: credentials.emailAddress,
        expectedMailboxUidValidity: mailboxUidValidity,
      );
      if (!mounted ||
          _currentFolder != MailFolder.trash ||
          _snapshot?.mailboxUidValidity != mailboxUidValidity) {
        return;
      }
      final currentSnapshot = _snapshot;
      if (currentSnapshot != null) {
        setState(() {
          _snapshot = currentSnapshot.copyWith(
            messages: currentSnapshot.messages
                .where((message) => !uids.contains(message.uid))
                .toList(),
          );
        });
        _setSelectionMode(false);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: BnbuText('恢复失败：$error')));
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Widget _buildBody(
    BuildContext context,
    List<MailMessageSummary> visible,
    bool hasMore,
  ) {
    final tokens = context.bnbuTheme;
    final topPadding = tokens.space12;
    if (_isLoading && _snapshot == null) {
      return _buildRefreshableMailboxState(
        context,
        const BnbuLoadingState(title: '正在加载邮件'),
      );
    }

    if (_errorMessage != null && _snapshot == null) {
      return _buildRefreshableMailboxState(
        context,
        BnbuErrorState(
          title: '加载失败',
          message: '${_errorMessage!}\n下拉即可重新读取邮箱。',
        ),
      );
    }

    if (_snapshot == null) {
      return _buildRefreshableMailboxState(
        context,
        const BnbuEmptyState(title: '暂无邮件', message: '下拉即可重新读取邮箱。'),
      );
    }

    return Column(
      children: [
        BnbuUpdateProgress(active: _isLoading && visible.isNotEmpty),
        if (_errorMessage != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.space16,
              tokens.space12,
              tokens.space16,
              0,
            ),
            child: BnbuNotice(
              message: _errorMessage!,
              kind: BnbuStatusKind.warning,
            ),
          ),
        Expanded(
          child: BnbuRefreshIndicator(
            onRefresh: _refreshFolder,
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(tokens.space16),
                    children: [
                      SizedBox(height: topPadding),
                      BnbuEmptyState(
                        title: '没有匹配的邮件',
                        message: _searchQuery.isNotEmpty
                            ? '换个关键词试试。'
                            : _showUnreadOnly
                            ? '当前没有未读邮件。'
                            : '该文件夹没有邮件。',
                      ),
                    ],
                  )
                : ListView.separated(
                    key: const ValueKey('mail-compact-message-list'),
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      tokens.space16,
                      tokens.space12,
                      tokens.space16,
                      tokens.space24,
                    ),
                    itemCount: visible.length + (hasMore ? 1 : 0),
                    separatorBuilder: (_, __) =>
                        SizedBox(height: tokens.space4),
                    itemBuilder: (context, index) {
                      if (index == visible.length) {
                        return _buildLoadMoreFooter();
                      }
                      final message = visible[index];
                      return TextFieldTapRegion(
                        child: _MailListTile(
                          message: message,
                          senderAvatarService: _senderAvatarService,
                          timeLabel: _formatMessageTime(message.date),
                          isOpening: _openingMessageUid == message.uid,
                          isMultiSelect: _isMultiSelectMode,
                          isSelected: _selectedUids.contains(
                            message.identityKey,
                          ),
                          onTap: _isMultiSelectMode
                              ? () => _toggleSelectMessage(message.identityKey)
                              : () => _openMessage(message),
                          onLongPress: _isMultiSelectMode
                              ? null
                              : () {
                                  setState(() {
                                    _isMultiSelectMode = true;
                                    _selectedUids.add(message.identityKey);
                                  });
                                },
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildRefreshableMailboxState(BuildContext context, Widget state) {
    final tokens = context.bnbuTheme;
    return BnbuRefreshIndicator(
      onRefresh: _refreshFolder,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.hasBoundedHeight
              ? (constraints.maxHeight - tokens.space32)
                    .clamp(0.0, double.infinity)
                    .toDouble()
              : 240.0;
          return ListView(
            key: const ValueKey('mail-refreshable-state'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(tokens.space16),
            children: [
              SizedBox(
                height: availableHeight,
                child: Center(child: state),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoadMoreFooter() {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.space12),
      child: Center(
        child: _isLoadingMore
            ? SizedBox.square(
                dimension: tokens.minInteractiveDimension,
                child: const Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: BnbuActivityIndicator(),
                  ),
                ),
              )
            : TextButton(onPressed: _loadMore, child: const BnbuText('加载更多')),
      ),
    );
  }

  String _formatMessageTime(DateTime? dateTime) {
    return formatMailListDate(
      dateTime,
      now: DateTime.now(),
      locale: Localizations.localeOf(context).toString(),
    );
  }

  static String _folderLabel(MailFolder folder) {
    switch (folder) {
      case MailFolder.inbox:
        return '收件箱';
      case MailFolder.drafts:
        return '草稿箱';
      case MailFolder.sent:
        return '已发送';
      case MailFolder.trash:
        return '已删除';
      case MailFolder.junk:
        return '垃圾邮件';
    }
  }

  static IconData _folderIcon(MailFolder folder) {
    switch (folder) {
      case MailFolder.inbox:
        return LucideIcons.inbox300;
      case MailFolder.drafts:
        return LucideIcons.filePenLine300;
      case MailFolder.sent:
        return LucideIcons.send300;
      case MailFolder.trash:
        return LucideIcons.trash2300;
      case MailFolder.junk:
        return LucideIcons.archiveX300;
    }
  }
}

// ─── ComposeMailPage (public) ─────────────────────────────────────────────────

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    this.compact = false,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? tokens.brandBlue : tokens.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            compact ? tokens.radius12 : tokens.radius24,
          ),
          side: BorderSide(color: selected ? tokens.brandBlue : tokens.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: tokens.minInteractiveDimension,
              minHeight: compact ? 44 : tokens.minInteractiveDimension,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.space12),
              child: Center(
                widthFactor: compact ? 1 : null,
                child: BnbuText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimary
                        : tokens.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopMailFolderTile extends StatelessWidget {
  static const scale = 1.1;
  static const paneWidth = 156 * scale;

  const _DesktopMailFolderTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final platform = Theme.of(context).platform;
    final pointerPlatform =
        platform == TargetPlatform.macOS ||
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 5 * scale,
        vertical: scale,
      ),
      child: Material(
        color: selected ? tokens.infoContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(4 * scale),
        child: InkWell(
          borderRadius: BorderRadius.circular(4 * scale),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (pointerPlatform ? 28 : 44) * scale,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.space12 * scale),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 16 * scale,
                    color: selected ? tokens.brandBlue : tokens.textSecondary,
                  ),
                  SizedBox(width: tokens.space12 * scale),
                  Expanded(
                    child: BnbuText(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected ? tokens.brandBlue : tokens.textPrimary,
                        fontSize: 13 * scale,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (count != null)
                    BnbuText(
                      '$count',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected ? tokens.brandBlue : tokens.textMuted,
                        fontSize:
                            (Theme.of(context).textTheme.labelSmall?.fontSize ??
                                11) *
                            scale,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopMailCommand extends StatelessWidget {
  const _DesktopMailCommand({
    this.buttonKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  final Key? buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return SizedBox(
      width: compact ? 44 : null,
      child: Tooltip(
        message: context.l10n.text(label),
        child: TextButton.icon(
          key: buttonKey,
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: tokens.textSecondary,
            minimumSize: Size(compact ? 38 : 40, 38),
            padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radius12),
            ),
          ),
          icon: Icon(icon, size: 16),
          label: compact ? const SizedBox.shrink() : BnbuText(label),
        ),
      ),
    );
  }
}

class _DesktopMailReadingPane extends StatefulWidget {
  const _DesktopMailReadingPane({
    required this.detail,
    required this.senderAvatarService,
    required this.time,
    required this.onReply,
    required this.onReplyAll,
    required this.onForward,
    required this.onAskAssistant,
    required this.onTranslate,
  });

  final MailMessageDetail detail;
  final MailSenderAvatarService senderAvatarService;
  final String time;
  final VoidCallback onReply;
  final VoidCallback onReplyAll;
  final VoidCallback onForward;
  final VoidCallback onAskAssistant;
  final VoidCallback onTranslate;

  @override
  State<_DesktopMailReadingPane> createState() =>
      _DesktopMailReadingPaneState();
}

class _DesktopMailReadingPaneState extends State<_DesktopMailReadingPane> {
  bool _originalMailStyle = false;
  bool _detailsExpanded = false;

  String _compactDate(BuildContext context) {
    final date = widget.detail.date;
    if (date == null) return '';
    final displayed = mailDisplayDate(date);
    final weekday = context.l10n.isEnglish
        ? DateFormat('EEE', 'en_US').format(displayed)
        : context.l10n.formatWeekday(displayed);
    return '${DateFormat('M/d').format(displayed)} $weekday '
        '${DateFormat('HH:mm').format(displayed)}';
  }

  @override
  void didUpdateWidget(covariant _DesktopMailReadingPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.folder != widget.detail.folder ||
        oldWidget.detail.mailboxUidValidity !=
            widget.detail.mailboxUidValidity ||
        oldWidget.detail.uid != widget.detail.uid) {
      _detailsExpanded = false;
      _originalMailStyle = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final detail = widget.detail;
    final html = detail.htmlBody?.trim() ?? '';
    final sender = mailDisplayName(detail.sender);
    return ColoredBox(
      key: const ValueKey('mail-desktop-reading-pane'),
      color: tokens.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 12, 12, 10),
            color: tokens.surfaceMuted,
            child: Row(
              children: [
                Expanded(
                  child: BnbuText(
                    detail.subject.trim().isEmpty ? '无主题邮件' : detail.subject,
                    key: const ValueKey('mail-desktop-reading-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(LucideIcons.star300, size: 16, color: tokens.textMuted),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MailSenderAvatar(
                  sender: detail.sender,
                  diameter: 28,
                  senderAvatarService: widget.senderAvatarService,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BnbuText(
                        sender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (_detailsExpanded) ...[
                        TextButton(
                          onPressed: () => setState(
                            () => _originalMailStyle = !_originalMailStyle,
                          ),
                          child: BnbuText(
                            _originalMailStyle ? '适应当前主题' : '查看原始样式',
                          ),
                        ),
                        _DesktopMailMetadataLine(
                          label: '发件人',
                          value: detail.sender,
                        ),
                        _DesktopMailMetadataLine(
                          label: '收件人',
                          value: detail.recipients,
                        ),
                        if (detail.cc?.trim().isNotEmpty == true)
                          _DesktopMailMetadataLine(
                            label: '抄送',
                            value: detail.cc!,
                          ),
                        if (widget.time.isNotEmpty)
                          _DesktopMailMetadataLine(
                            label: '时间',
                            value: widget.time,
                          ),
                        if (detail.messageSizeBytes != null)
                          _DesktopMailMetadataLine(
                            label: '大小',
                            value: _formatMailSize(detail.messageSizeBytes!),
                          ),
                      ] else
                        BnbuText(
                          '发给 ${detail.recipients}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: tokens.textSecondary),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _DesktopReaderActions(
                      onReply: widget.onReply,
                      onReplyAll: widget.onReplyAll,
                      onForward: widget.onForward,
                      onAskAssistant: widget.onAskAssistant,
                      onTranslate: widget.onTranslate,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_detailsExpanded && detail.date != null) ...[
                          BnbuText(
                            _compactDate(context),
                            key: const ValueKey('mail-desktop-compact-date'),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: tokens.textSecondary),
                          ),
                          const SizedBox(width: 6),
                        ],
                        TextButton(
                          key: ValueKey(
                            _detailsExpanded
                                ? 'mail-desktop-hide-details'
                                : 'mail-desktop-show-details',
                          ),
                          onPressed: () => setState(
                            () => _detailsExpanded = !_detailsExpanded,
                          ),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(0, 24),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.standard,
                          ),
                          child: BnbuText(
                            _detailsExpanded ? '隐藏' : '详情',
                            maxLines: 1,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: tokens.brandBlue,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: tokens.border),
          Expanded(
            child: html.isNotEmpty
                ? NativeHtmlMailView(
                    originalStyle: _originalMailStyle,
                    htmlContent: html,
                    fallbackText: detail.body,
                    baseUrl: AppConfig.normalizedHttpsBaseUrl(
                      AppConfig.mailWebBaseUrl,
                      settingName: 'BNBU_MAIL_WEB_BASE_URL',
                    ),
                  )
                : SelectionArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
                      child: BnbuText(
                        detail.body.isEmpty ? '这封邮件没有可解析的正文内容。' : detail.body,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DesktopMailMetadataLine extends StatelessWidget {
  const _DesktopMailMetadataLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 42,
            child: BnbuText(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
            ),
          ),
          Expanded(
            child: SelectionArea(
              child: BnbuText(
                value,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: tokens.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMailSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _DesktopReaderActions extends StatelessWidget {
  const _DesktopReaderActions({
    required this.onReply,
    required this.onReplyAll,
    required this.onForward,
    required this.onAskAssistant,
    required this.onTranslate,
  });

  final VoidCallback onReply;
  final VoidCallback onReplyAll;
  final VoidCallback onForward;
  final VoidCallback onAskAssistant;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _readerIcon(LucideIcons.reply300, '回复', onReply),
      _readerIcon(LucideIcons.replyAll300, '回复全部', onReplyAll),
      _readerIcon(LucideIcons.forward300, '转发', onForward),
      BnbuMenuButton<String>(
        tooltip: context.l10n.text('小U'),
        padding: EdgeInsets.zero,
        child: const SizedBox.square(
          dimension: 30,
          child: Center(child: SmallULogo(size: 17, monochrome: true)),
        ),
        onSelected: (value) {
          if (value == 'ask') {
            onAskAssistant();
          } else {
            onTranslate();
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'ask', child: BnbuText('询问小U')),
          PopupMenuItem(value: 'translate', child: BnbuText('智能翻译')),
        ],
      ),
    ],
  );

  Widget _readerIcon(IconData icon, String label, VoidCallback onPressed) =>
      Builder(
        builder: (context) => IconButton(
          tooltip: label,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          padding: EdgeInsets.zero,
          icon: Icon(icon, size: 16),
        ),
      );
}

class _DesktopMailRow extends StatelessWidget {
  const _DesktopMailRow({
    required this.message,
    this.radarItem,
    required this.senderAvatarService,
    required this.timeLabel,
    required this.active,
    required this.opening,
    required this.onTap,
  });

  final MailMessageSummary message;
  final MailRadarItem? radarItem;
  final MailSenderAvatarService senderAvatarService;
  final String timeLabel;
  final bool active;
  final bool opening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final unread = !message.isSeen;
    final primary = active ? Colors.white : tokens.textPrimary;
    final secondary = active
        ? Colors.white.withValues(alpha: .78)
        : tokens.textMuted;
    return Material(
      key: ValueKey('mail-desktop-row-${message.uid}'),
      color: active
          ? const Color(0xFF3187F4)
          : unread
          ? tokens.surface
          : tokens.canvas,
      child: InkWell(
        onTap: opening ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active
                    ? Colors.white.withValues(alpha: .18)
                    : tokens.border,
              ),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            tokens.space8,
            tokens.space8,
            tokens.space12,
            tokens.space8,
          ),
          child: Row(
            children: [
              _Avatar(
                message: message,
                senderAvatarService: senderAvatarService,
                compact: true,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: BnbuText(
                            mailDisplayName(message.correspondent),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: primary,
                                  fontWeight: unread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                          ),
                        ),
                        SizedBox(width: tokens.space8),
                        if (opening)
                          const SizedBox.square(
                            dimension: 14,
                            child: BnbuActivityIndicator(),
                          )
                        else
                          BnbuText(
                            timeLabel,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: active
                                      ? secondary
                                      : unread
                                      ? tokens.textSecondary
                                      : tokens.textMuted,
                                ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: BnbuText(
                            message.subject.trim().isEmpty
                                ? context.l10n.text('无主题邮件')
                                : message.subject,
                            key: ValueKey(
                              'mail-desktop-subject-${message.uid}',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: primary,
                                  fontWeight: unread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                          ),
                        ),
                        if (message.hasAttachments) ...[
                          const SizedBox(width: 5),
                          Icon(
                            LucideIcons.paperclip300,
                            size: 14,
                            color: secondary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    radarItem == null
                        ? BnbuText(
                            message.readablePreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: secondary,
                                  fontWeight: FontWeight.w400,
                                ),
                          )
                        : _buildRadarLine(context, secondary),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadarLine(BuildContext context, Color secondary) {
    final item = radarItem!;
    final tokens = context.bnbuTheme;
    final priorityColor = switch (item.priority) {
      MailRadarPriority.urgent ||
      MailRadarPriority.high => const Color(0xFFEC6868),
      MailRadarPriority.normal || MailRadarPriority.low => secondary,
    };
    final trailing = item.category == MailRadarCategory.deadline
        ? _deadlineLabel(item)
        : item.summaryZh.trim();
    return Row(
      children: [
        _DesktopRadarTag(
          label: item.priority.label,
          color: priorityColor,
          active: active,
        ),
        const SizedBox(width: 4),
        _DesktopRadarTag(
          label: item.analysisPending ? '等待分析' : item.category.label,
          color: active ? Colors.white : tokens.brandBlue,
          active: active,
        ),
        if (trailing.isNotEmpty) ...[
          const SizedBox(width: 6),
          Expanded(
            child: BnbuText(
              trailing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: secondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ],
    );
  }

  static String _deadlineLabel(MailRadarItem item) {
    final deadline = item.deadlineAt;
    if (deadline == null) return item.deadlineText.trim();
    final displayed = mailDisplayDate(deadline);
    switch (item.deadlinePrecision) {
      case 'date':
        return DateFormat('M/d').format(displayed);
      case 'datetime':
        return DateFormat('M/d HH:mm').format(displayed);
      default:
        final hasExplicitTime = RegExp(
          r'(?<!\d)(?:[01]?\d|2[0-3]):[0-5]\d(?!\d)',
        ).hasMatch(item.deadlineText);
        return DateFormat(
          hasExplicitTime ? 'M/d HH:mm' : 'M/d',
        ).format(displayed);
    }
  }
}

class _DesktopRadarTag extends StatelessWidget {
  const _DesktopRadarTag({
    required this.label,
    required this.color,
    required this.active,
  });

  final String label;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) => BnbuText(
    label,
    maxLines: 1,
    style: TextStyle(
      color: active ? Colors.white : color,
      fontSize: 11,
      height: 1.4,
      fontWeight: FontWeight.w400,
    ),
  );
}

class _MailListTile extends StatelessWidget {
  const _MailListTile({
    required this.message,
    required this.senderAvatarService,
    required this.timeLabel,
    required this.isOpening,
    required this.isMultiSelect,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  final MailMessageSummary message;
  final MailSenderAvatarService senderAvatarService;
  final String timeLabel;
  final bool isOpening;
  final bool isMultiSelect;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return BnbuSurfaceCard(
      padding: EdgeInsets.zero,
      backgroundColor: tokens.surface,
      child: InkWell(
        onTap: isOpening ? null : onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.all(tokens.space8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMultiSelect)
                SizedBox.square(
                  dimension: tokens.minInteractiveDimension,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: tokens.space4),
                      child: Icon(
                        isSelected
                            ? LucideIcons.circleCheck300
                            : LucideIcons.circle300,
                        size: 28,
                        color: isSelected ? tokens.brandBlue : tokens.border,
                      ),
                    ),
                  ),
                )
              else
                Padding(
                  padding: EdgeInsets.only(right: tokens.space12),
                  child: _Avatar(
                    message: message,
                    senderAvatarService: senderAvatarService,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: BnbuText(
                            message.sender,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textPrimary,
                                  height: 1.25,
                                ),
                          ),
                        ),
                        SizedBox(width: tokens.space8),
                        BnbuText(
                          timeLabel,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: tokens.textMuted),
                        ),
                      ],
                    ),
                    SizedBox(height: tokens.space4),
                    BnbuText(
                      message.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 13,
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                      ),
                    ),
                    if (message.preview.isNotEmpty || message.hasHtmlBody) ...[
                      SizedBox(height: tokens.space4),
                      Row(
                        children: [
                          Expanded(
                            child: BnbuText(
                              message.preview.isNotEmpty
                                  ? message.preview
                                  : 'HTML 邮件，点开查看完整内容',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w400,
                                    height: 1.3,
                                  ),
                            ),
                          ),
                          if (isOpening) ...[
                            SizedBox(width: tokens.space8),
                            const SizedBox.square(
                              dimension: 16,
                              child: BnbuActivityIndicator(),
                            ),
                          ],
                        ],
                      ),
                    ] else if (isOpening) ...[
                      SizedBox(height: tokens.space8),
                      const SizedBox.square(
                        dimension: 16,
                        child: BnbuActivityIndicator(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.message,
    required this.senderAvatarService,
    this.compact = false,
  });

  final MailMessageSummary message;
  final MailSenderAvatarService senderAvatarService;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final outerSize = compact ? 36.0 : 44.0;
    final portraitSize = compact ? 32.0 : 40.0;
    final indicatorSize = compact ? 9.0 : 11.0;
    return SizedBox(
      key: ValueKey('mail-avatar-${message.uid}'),
      width: outerSize,
      height: outerSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: MailSenderAvatar(
              sender: message.sender,
              senderAvatarService: senderAvatarService,
              diameter: portraitSize,
            ),
          ),
          if (!message.isSeen)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                key: ValueKey('mail-unread-indicator-${message.uid}'),
                width: indicatorSize,
                height: indicatorSize,
                decoration: BoxDecoration(
                  color: tokens.brandBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Mail Detail Page ─────────────────────────────────────────────────────────

class MailDetailPage extends StatefulWidget {
  const MailDetailPage({
    super.key,
    required this.detail,
    required this.timeFormat,
    this.onReply,
    required this.mailService,
    required this.credentials,
    required this.attachmentStore,
    this.senderAvatarService,
    this.senderDisplayName,
    this.initialAttachmentPartId = '',
    this.initialAttachmentName = '',
    this.onAttachmentSaved,
  }) : summary = null,
       loadDetail = null,
       onReplyTo = null,
       onOpenPrevious = null,
       onOpenNext = null,
       onMailboxChanged = null;

  const MailDetailPage.loading({
    super.key,
    required MailMessageSummary this.summary,
    required Future<MailMessageDetail> Function() this.loadDetail,
    required this.timeFormat,
    required this.mailService,
    required this.credentials,
    required this.attachmentStore,
    this.senderAvatarService,
    this.senderDisplayName,
    this.onReplyTo,
    this.onOpenPrevious,
    this.onOpenNext,
    this.onMailboxChanged,
  }) : onAttachmentSaved = null,
       detail = null,
       onReply = null,
       initialAttachmentPartId = '',
       initialAttachmentName = '';

  final ValueChanged<String>? onAttachmentSaved;
  final MailMessageDetail? detail;
  final MailMessageSummary? summary;
  final Future<MailMessageDetail> Function()? loadDetail;
  final DateFormat timeFormat;
  final VoidCallback? onReply;
  final ValueChanged<MailMessageDetail>? onReplyTo;
  final VoidCallback? onOpenPrevious;
  final VoidCallback? onOpenNext;
  final VoidCallback? onMailboxChanged;
  final MailService mailService;
  final MailAccessCredentials credentials;
  final MailAttachmentStore attachmentStore;
  final MailSenderAvatarService? senderAvatarService;
  final String? senderDisplayName;
  final String initialAttachmentPartId;
  final String initialAttachmentName;

  @override
  State<MailDetailPage> createState() => MailDetailPageState();
}

class MailDetailPageState extends State<MailDetailPage> {
  bool _originalMailStyle = false;
  final Set<String> _downloadingPartIds = {};
  final ScrollController _plainBodyScrollController = ScrollController();
  static const _nativeActions = NativeActions();
  AssistantContextCoordinator? _contextCoordinator;
  AssistantContextRegistration? _contextRegistration;
  MailMessageDetail? _detail;
  String? _loadError;
  bool _isLoading = false;
  bool _isMutating = false;
  bool _handledInitialAttachment = false;
  bool _contentCollapsed = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _plainBodyScrollController.addListener(_handlePlainBodyScroll);
    _detail = widget.detail;
    if (_detail == null) {
      unawaited(_loadDetail());
    } else {
      unawaited(_loadInlineImages(_detail!, _loadGeneration));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_handleInitialAttachment());
    });
  }

  Future<void> _loadDetail() async {
    final loader = widget.loadDetail;
    final summary = widget.summary;
    if (loader == null || summary == null) return;
    final generation = ++_loadGeneration;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final cache = widget.mailService;
      final identity = summary.identity;
      if (cache is MailCacheReader && identity != null) {
        final cached = await (cache as MailCacheReader).readCachedMessage(
          credentials: widget.credentials,
          identity: identity,
        );
        if (!mounted || generation != _loadGeneration) return;
        if (cached != null &&
            cached.uid == summary.uid &&
            cached.folder == summary.folder &&
            cached.mailboxUidValidity == summary.mailboxUidValidity) {
          setState(() => _detail = cached);
        }
      }
      final detail = await loader();
      if (!mounted || generation != _loadGeneration) return;
      if (detail.uid != summary.uid ||
          detail.folder != summary.folder ||
          (summary.mailboxUidValidity != null &&
              detail.mailboxUidValidity != summary.mailboxUidValidity)) {
        throw const MailServiceException('邮件引用已失效，请返回邮箱刷新后重试。');
      }
      setState(() => _detail = detail);
      unawaited(_loadInlineImages(detail, generation));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_handleInitialAttachment());
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      if (_detail == null) setState(() => _loadError = error.toString());
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadInlineImages(
    MailMessageDetail detail,
    int generation,
  ) async {
    final service = widget.mailService;
    if (detail.inlineImagesLoaded || service is! MailInlineImageLoader) return;
    try {
      final enriched = await (service as MailInlineImageLoader)
          .loadInlineImages(credentials: widget.credentials, detail: detail);
      if (mounted && generation == _loadGeneration) {
        setState(() => _detail = enriched);
      }
    } on Object {
      /* Text remains readable if an inline picture is unavailable. */
    }
  }

  Future<void> _handleInitialAttachment() async {
    if (_handledInitialAttachment) return;
    final detail = _detail;
    if (detail == null) return;
    _handledInitialAttachment = true;
    final partId = widget.initialAttachmentPartId.trim();
    final name = widget.initialAttachmentName.trim();
    if (partId.isEmpty) return;
    final matches = detail.attachments.where(
      (attachment) =>
          attachment.partId?.trim() == partId &&
          (name.isEmpty || attachment.name.trim() == name),
    );
    if (matches.length != 1) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: BnbuText('附件已变化，请重新打开邮件后再试。')));
      }
      return;
    }
    await _downloadAndOpen(matches.single);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final coordinator = AssistantContextScope.maybeOf(context);
    if (coordinator == null || identical(coordinator, _contextCoordinator)) {
      return;
    }
    _contextRegistration?.dispose();
    _contextCoordinator = coordinator;
    _contextRegistration = coordinator.register(
      AssistantContextContribution(
        currentPage: _currentPageContext,
        selectedMail: _selectedMailContext,
      ),
    );
  }

  @override
  void dispose() {
    _plainBodyScrollController
      ..removeListener(_handlePlainBodyScroll)
      ..dispose();
    _contextRegistration?.dispose();
    super.dispose();
  }

  void _handlePlainBodyScroll() {
    _setContentCollapsed(_plainBodyScrollController.offset > 18);
  }

  void _setContentCollapsed(bool value) {
    if (!mounted || value == _contentCollapsed) return;
    setState(() => _contentCollapsed = value);
  }

  AssistantCurrentPageContext? _currentPageContext() {
    final detail = _detail;
    if (detail == null) return null;
    return AssistantCurrentPageContext(
      pageType: 'mail_detail',
      title: _limitAssistantText(detail.subject, 240),
      selectedItemId: detail.uid.toString(),
      summary: _limitAssistantText(detail.sender, 1200),
    );
  }

  AssistantSelectedMailContext? _selectedMailContext() {
    final detail = _detail;
    if (detail == null) return null;
    final body = detail.body.trim();
    final attachments = detail.attachments
        .where(
          (attachment) =>
              attachment.partId?.trim().isNotEmpty == true &&
              attachment.name.trim().isNotEmpty,
        )
        .take(16)
        .map(
          (attachment) => AssistantMailAttachmentContext(
            partId: attachment.partId!.trim(),
            name: _limitAssistantText(attachment.name, 255),
            size: attachment.size.clamp(0, 1000 * 1000 * 1000).toInt(),
            mimeType: _limitAssistantText(attachment.mimeType, 160),
          ),
        )
        .toList(growable: false);
    if (body.isEmpty && attachments.isEmpty) {
      return null;
    }
    final sender = _assistantSenderParts(detail.sender);
    return AssistantSelectedMailContext(
      uid: detail.uid,
      folder: detail.folder.name,
      mailboxUidValidity: detail.mailboxUidValidity,
      senderName: _limitAssistantText(sender.$1, 160),
      senderEmail: _limitAssistantText(sender.$2, 254),
      subject: _limitAssistantText(detail.subject, 300),
      receivedAt: detail.date ?? DateTime.now(),
      bodyExcerpt: body.length <= 8000 ? body : body.substring(0, 8000),
      attachments: attachments,
    );
  }

  bool get _isCurrentRoute =>
      mounted && (ModalRoute.of(context)?.isCurrent ?? false);

  Future<void> _downloadAndOpen(MailAttachment attachment) async {
    final detail = _detail;
    if (detail == null) return;
    final partId = attachment.partId;
    if (partId == null || _downloadingPartIds.contains(partId)) return;
    setState(() => _downloadingPartIds.add(partId));
    var downloaded = false;
    try {
      final cacheDirPath = await _nativeActions
          .getMailAttachmentCacheDirectory();
      final fileName = mailAttachmentCacheFileName(
        accountId: widget.credentials.emailAddress,
        mailbox: detail.folder.name,
        messageId: detail.messageId,
        mailboxUidValidity: detail.mailboxUidValidity,
        messageUid: detail.uid,
        partId: partId,
        originalName: attachment.name,
      );
      final filePath = '$cacheDirPath/$fileName';
      if (!await widget.attachmentStore.exists(filePath)) {
        if (!_isCurrentRoute) return;
        final bytes = await widget.mailService.downloadAttachment(
          credentials: widget.credentials,
          folder: detail.folder,
          uid: detail.uid,
          partId: partId,
          expectedMailboxUidValidity: detail.mailboxUidValidity,
        );
        await widget.attachmentStore.publish(path: filePath, bytes: bytes);
      }
      downloaded = true;
      if (!mounted || !_isCurrentRoute) return;
      widget.onAttachmentSaved?.call(partId);
      final mimeType = attachment.mimeType.split(';').first.trim();
      await showFilePreview(
        context,
        title: attachment.name,
        path: filePath,
        mimeType: mimeType.isEmpty ? '*/*' : mimeType,
      );
    } catch (error) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        final message = downloaded
            ? switch (error) {
                PlatformException(code: 'no_app') => '附件已下载，设备没有可打开此类型文件的应用。',
                PlatformException(code: 'presentation_in_progress') =>
                  '附件已下载，请先关闭当前文件或分享菜单后重试。',
                _ => '附件已下载，暂时无法打开。请回到邮件页面后重试。',
              }
            : '附件下载失败，请稍后重试。';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: BnbuText(message)));
      }
    } finally {
      if (mounted) setState(() => _downloadingPartIds.remove(partId));
    }
  }

  void _reply() {
    final detail = _detail;
    if (detail == null || _isMutating) return;
    final callback = widget.onReplyTo;
    if (callback != null) {
      callback(detail);
    } else {
      widget.onReply?.call();
    }
  }

  void _forward() {
    final detail = _detail;
    if (detail == null || _isMutating) return;
    final forwardedTime = detail.date == null
        ? '未知时间'
        : widget.timeFormat.format(mailDisplayDate(detail.date!));
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ComposeMailPage(
          senderDisplayName: widget.senderDisplayName,
          mailService: widget.mailService,
          credentials: widget.credentials,
          senderAvatarService: widget.senderAvatarService,
          initialSubject: detail.subject.startsWith('Fwd:')
              ? detail.subject
              : 'Fwd: ${detail.subject}',
          initialBody: MailForwardContent.plainText(detail, forwardedTime),
          initialHtmlBody: MailForwardContent.html(detail, forwardedTime),
        ),
      ),
    );
  }

  Future<void> _askAssistant() async {
    final detail = _detail;
    final launcher =
        AssistantContextScope.maybeOpenAssistantWithMailReferenceOf(context);
    if (detail == null || launcher == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('小U当前不可用。')));
      return;
    }
    final validity = detail.mailboxUidValidity;
    if (validity == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: BnbuText('这封邮件缺少稳定引用，请返回邮箱刷新后重试。')),
      );
      return;
    }
    await launcher(
      AssistantMailReference.message(
        folder: detail.folder.name,
        uid: detail.uid,
        mailboxUidValidity: validity,
        sender: detail.sender,
        subject: detail.subject,
        receivedAt: detail.date ?? DateTime.now(),
      ),
    );
  }

  void _showTranslationUnavailable() => ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: BnbuText('智能翻译暂未开放。')));

  Future<void> _deleteOrRestore() async {
    final detail = _detail;
    if (detail == null || _isMutating) return;
    final restoring = detail.folder == MailFolder.trash;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: BnbuText(restoring ? '恢复邮件' : '删除邮件'),
        content: BnbuText(
          '${restoring ? '恢复' : '删除'}“${detail.subject.trim().isEmpty ? '无主题邮件' : detail.subject.trim()}”？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const BnbuText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: BnbuText(restoring ? '恢复' : '删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_isCurrentRoute) return;
    setState(() => _isMutating = true);
    try {
      if (restoring) {
        await widget.mailService.restoreMessages(
          credentials: widget.credentials,
          uids: [detail.uid],
          userEmailAddress: widget.credentials.emailAddress,
          expectedMailboxUidValidity: detail.mailboxUidValidity,
        );
      } else {
        await widget.mailService.deleteMessages(
          credentials: widget.credentials,
          folder: detail.folder,
          uids: [detail.uid],
          expectedMailboxUidValidity: detail.mailboxUidValidity,
        );
      }
      if (!mounted || !_isCurrentRoute) return;
      widget.onMailboxChanged?.call();
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted || !_isCurrentRoute) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: BnbuText('${restoring ? '恢复' : '删除'}失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  String _weekdayLabel(DateTime? value) {
    if (value == null) return '';
    return formatMailListDate(
      value,
      now: DateTime.now(),
      locale: context.l10n.locale.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final summary = widget.summary;
    final subject = detail?.subject ?? summary?.subject ?? '邮件';
    final htmlBody = detail?.htmlBody?.trim() ?? '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mailBackground = isDark ? const Color(0xFF18191B) : Colors.white;
    return Scaffold(
      key: const ValueKey('mail-detail-page'),
      backgroundColor: mailBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _MailDetailTopBar(
              subject: subject,
              collapsed: _contentCollapsed,
              onBack: () => Navigator.maybePop(context),
              onPrevious: widget.onOpenPrevious,
              onNext: widget.onOpenNext,
            ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: SizedBox(
                    width: double.infinity,
                    child: detail == null
                        ? _MailDetailLoadingState(
                            subject: subject,
                            sender: summary?.sender ?? '',
                            error: _loadError,
                            isLoading: _isLoading,
                            onRetry: _loadDetail,
                          )
                        : _buildLoadedContent(context, detail, htmlBody),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _MailDetailBottomBar(
        backgroundColor: isDark
            ? const Color(0xFF0C0C0D)
            : const Color(0xFFF5F6F7),
        restoring: detail?.folder == MailFolder.trash,
        enabled: detail != null && !_isMutating,
        isMutating: _isMutating,
        onDeleteOrRestore: _deleteOrRestore,
        onForward: _forward,
        onReply: _reply,
        onAskAssistant: _askAssistant,
        onTranslate: _showTranslationUnavailable,
      ),
    );
  }

  Widget _buildLoadedContent(
    BuildContext context,
    MailMessageDetail detail,
    String htmlBody,
  ) {
    final tokens = context.bnbuTheme;
    final body = htmlBody.isNotEmpty
        ? NativeHtmlMailView(
            originalStyle: _originalMailStyle,
            htmlContent: htmlBody,
            fallbackText: detail.body,
            baseUrl: AppConfig.normalizedHttpsBaseUrl(
              AppConfig.mailWebBaseUrl,
              settingName: 'BNBU_MAIL_WEB_BASE_URL',
            ),
            onCollapsedChanged: _setContentCollapsed,
          )
        : SelectionArea(
            child: SingleChildScrollView(
              key: const ValueKey('mail-detail-plain-scroll'),
              controller: _plainBodyScrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                tokens.space16,
                20,
                tokens.space16,
                tokens.space32,
              ),
              child: BnbuText(
                detail.body.isEmpty ? '这封邮件没有可解析的正文内容。' : detail.body,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontSize: _mailDetailBodyFontSize,
                  fontWeight: FontWeight.w400,
                  height: 1.58,
                ),
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _contentCollapsed
                ? const SizedBox.shrink(
                    key: ValueKey('mail-detail-header-collapsed'),
                  )
                : _MailDetailHeader(
                    key: const ValueKey('mail-detail-expanded-header'),
                    originalStyle: _originalMailStyle,
                    onToggleStyle: () => setState(
                      () => _originalMailStyle = !_originalMailStyle,
                    ),
                    detail: detail,
                    senderAvatarService: widget.senderAvatarService,
                    external: false,
                    weekday: _weekdayLabel(detail.date),
                    time: detail.date == null
                        ? '未知时间'
                        : widget.timeFormat.format(
                            mailDisplayDate(detail.date!),
                          ),
                  ),
          ),
        ),
        if (detail.attachments.isNotEmpty)
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: tokens.space16),
              itemCount: detail.attachments.length,
              separatorBuilder: (_, __) => SizedBox(width: tokens.space8),
              itemBuilder: (_, index) {
                final attachment = detail.attachments[index];
                final isLoading = _downloadingPartIds.contains(
                  attachment.partId,
                );
                return _AttachmentChip(
                  attachment: attachment,
                  isLoading: isLoading,
                  onTap: isLoading ? null : () => _downloadAndOpen(attachment),
                );
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Divider(
            height: 0.5,
            thickness: 0.5,
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF2C2E30)
                : const Color(0xFFE3E6EB),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _MailDetailTopBar extends StatelessWidget {
  const _MailDetailTopBar({
    required this.subject,
    required this.collapsed,
    required this.onBack,
    required this.onPrevious,
    required this.onNext,
  });

  final String subject;
  final bool collapsed;
  final VoidCallback onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return BnbuSecondaryHeader(
      referenceScale: 0.65,
      child: AnimatedContainer(
        key: const ValueKey('mail-detail-top-bar'),
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: collapsed
                  ? tokens.border.withValues(alpha: 0.42)
                  : Colors.transparent,
            ),
          ),
        ),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(
              children: [
                IconButton(
                  tooltip: context.l10n.text('返回邮箱'),
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                  constraints: const BoxConstraints.tightFor(
                    width: 44,
                    height: 44,
                  ),
                  icon: const Icon(LucideIcons.chevronLeft300, size: 24),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    key: const ValueKey('mail-detail-collapsed-title'),
                    duration: const Duration(milliseconds: 150),
                    // A reversed scroll can reintroduce a title while its old
                    // copy is still fading out. Let the switcher key each
                    // transition separately instead of reusing the child key.
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: collapsed
                        ? BnbuText(
                            subject.trim().isEmpty ? '无主题邮件' : subject,
                            key: const ValueKey(
                              'mail-detail-collapsed-subject-text',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: tokens.textPrimary,
                                  fontSize: _mailDetailTitleFontSize,
                                  fontWeight: FontWeight.w600,
                                ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('mail-detail-collapsed-title-hidden'),
                          ),
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: 44,
                  child: IconButton(
                    tooltip: context.l10n.text('上一封'),
                    onPressed: onPrevious,
                    padding: EdgeInsets.zero,
                    icon: const Icon(LucideIcons.chevronUp300, size: 24),
                  ),
                ),
                SizedBox(
                  width: 40,
                  height: 44,
                  child: IconButton(
                    tooltip: context.l10n.text('下一封'),
                    onPressed: onNext,
                    padding: EdgeInsets.zero,
                    icon: const Icon(LucideIcons.chevronDown300, size: 24),
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

class _MailDetailLoadingState extends StatelessWidget {
  const _MailDetailLoadingState({
    required this.subject,
    required this.sender,
    required this.error,
    required this.isLoading,
    required this.onRetry,
  });

  final String subject;
  final String sender;
  final String? error;
  final bool isLoading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    if (error != null && !isLoading) {
      return Padding(
        padding: EdgeInsets.all(tokens.space24),
        child: Center(
          child: BnbuEmptyState(
            title: '邮件暂时无法读取',
            message: error!,
            action: FilledButton(
              onPressed: onRetry,
              child: const BnbuText('重试'),
            ),
          ),
        ),
      );
    }
    return Padding(
      key: const ValueKey('mail-detail-loading'),
      padding: EdgeInsets.symmetric(horizontal: tokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BnbuText(
            subject,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: tokens.textPrimary,
              fontSize: _mailDetailTitleFontSize,
              fontWeight: FontWeight.w600,
              height: 1.22,
            ),
          ),
          SizedBox(height: tokens.space24),
          Row(
            children: [
              Container(
                width: _mailDetailAvatarDiameter,
                height: _mailDetailAvatarDiameter,
                decoration: BoxDecoration(
                  color: tokens.surfaceMuted,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: tokens.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BnbuText(
                      sender,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontSize: _mailDetailSenderFontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: tokens.space8),
                    Container(
                      width: 128,
                      height: 10,
                      color: tokens.surfaceMuted,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space24),
          Divider(color: tokens.border),
          SizedBox(height: tokens.space24),
          ...List.generate(
            5,
            (index) => Padding(
              padding: EdgeInsets.only(bottom: tokens.space12),
              child: FractionallySizedBox(
                widthFactor: index == 4 ? 0.58 : (index.isEven ? 0.94 : 0.82),
                child: Container(
                  height: 13,
                  decoration: BoxDecoration(
                    color: tokens.surfaceMuted,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MailDetailBottomBar extends StatelessWidget {
  const _MailDetailBottomBar({
    required this.backgroundColor,
    required this.restoring,
    required this.enabled,
    required this.isMutating,
    required this.onDeleteOrRestore,
    required this.onForward,
    required this.onReply,
    required this.onAskAssistant,
    required this.onTranslate,
  });

  final Color backgroundColor;
  final bool restoring;
  final bool enabled;
  final bool isMutating;
  final VoidCallback onDeleteOrRestore;
  final VoidCallback onForward;
  final VoidCallback onReply;
  final VoidCallback onAskAssistant;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(color: tokens.border.withValues(alpha: 0.42)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height:
              56 +
              (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(0, 40) *
                  1.4,
          child: Row(
            children: [
              Expanded(
                child: _MailDetailAction(
                  icon: restoring
                      ? LucideIcons.archiveRestore300
                      : LucideIcons.trash2300,
                  label: restoring ? '恢复' : '删除',
                  onTap: enabled ? onDeleteOrRestore : null,
                  loading: isMutating,
                ),
              ),
              Expanded(
                child: _MailDetailAction(
                  icon: LucideIcons.forward300,
                  label: '转发',
                  onTap: enabled ? onForward : null,
                ),
              ),
              Expanded(
                child: _MailDetailAction(
                  icon: LucideIcons.reply300,
                  label: '回复',
                  onTap: enabled ? onReply : null,
                ),
              ),
              Expanded(
                child: _MailDetailAssistantMenu(
                  enabled: enabled,
                  onAskAssistant: onAskAssistant,
                  onTranslate: onTranslate,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MailDetailAction extends StatelessWidget {
  const _MailDetailAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.loading = false,
    this.iconWidget,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final Widget? iconWidget;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final activeColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF909397)
        : tokens.textSecondary;
    final color = onTap == null && !active ? tokens.textMuted : activeColor;
    return Tooltip(
      message: context.l10n.text(label),
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: true,
          enabled: onTap != null || active,
          label: context.l10n.text(label),
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                if (loading)
                  const SizedBox.square(
                    dimension: 22,
                    child: BnbuActivityIndicator(),
                  )
                else
                  iconWidget ?? Icon(icon, color: color, size: 22),
                SizedBox(height: tokens.space4),
                BnbuText(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w400,
                    fontSize: 11,
                    height: 1.4,
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

class _MailDetailAssistantMenu extends StatelessWidget {
  const _MailDetailAssistantMenu({
    required this.enabled,
    required this.onAskAssistant,
    required this.onTranslate,
  });

  final bool enabled;
  final VoidCallback onAskAssistant;
  final VoidCallback onTranslate;

  @override
  Widget build(BuildContext context) => BnbuMenuButton<String>(
    enabled: enabled,
    tooltip: context.l10n.text('小U'),
    onSelected: (value) {
      if (value == 'ask') {
        onAskAssistant();
      } else {
        onTranslate();
      }
    },
    itemBuilder: (context) => const [
      PopupMenuItem(value: 'ask', child: BnbuText('询问小U')),
      PopupMenuItem(value: 'translate', child: BnbuText('智能翻译')),
    ],
    child: _MailDetailAction(
      icon: LucideIcons.sparkles300,
      iconWidget: const SmallULogo(size: 20, monochrome: true),
      label: '小U',
      onTap: null,
      active: enabled,
    ),
  );
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.isLoading,
    required this.onTap,
  });

  final MailAttachment attachment;
  final bool isLoading;
  final VoidCallback? onTap;

  static IconData _iconForName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return LucideIcons.fileText300;
    }
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return LucideIcons.image300;
    }
    return LucideIcons.paperclip300;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: attachment.name,
      child: Material(
        color: tokens.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius12),
          side: BorderSide(color: tokens.border),
        ),
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: tokens.minInteractiveDimension,
              minWidth: tokens.minInteractiveDimension,
              maxWidth: 220,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: tokens.space12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconForName(attachment.name),
                    size: 20,
                    color: tokens.textSecondary,
                  ),
                  SizedBox(width: tokens.space8),
                  Flexible(
                    child: BnbuText(
                      attachment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.space8),
                  if (isLoading)
                    const SizedBox.square(
                      dimension: 16,
                      child: BnbuActivityIndicator(),
                    )
                  else
                    Icon(LucideIcons.download300, color: tokens.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuoteInfoLine extends StatelessWidget {
  const _QuoteInfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final baseStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: tokens.textPrimary);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space4),
      child: RichText(
        text: TextSpan(
          style: baseStyle,
          children: [
            TextSpan(
              text: '${context.l10n.text(label)}: ',
              style: baseStyle?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }
}
