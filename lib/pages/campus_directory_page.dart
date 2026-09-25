import '../widgets/page_backdrop.dart';
import '../models/assistant_models.dart';
import '../services/assistant_context_coordinator.dart';
import '../widgets/assistant_context_scope.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/campus_organization_avatar.dart';
import '../widgets/bnbu_loading.dart';
import '../services/mail_sender_identity.dart';
import 'dart:async';

import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/campus_directory.dart';
import '../models/mail_models.dart';
import '../widgets/teacher_portrait.dart';
import '../services/campus_directory_service.dart';
import '../services/public_directory_cache.dart';
import '../services/directory_search.dart';
import '../services/mail_service.dart';
import '../services/mail_service_factory.dart';
import '../services/teacher_review_service.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/bnbu_component_library.dart';
import '../widgets/teacher_reviews_section.dart';
import 'mail_page.dart';
import 'official_web_page.dart';

typedef DirectoryComposeHandler =
    Future<void> Function(BuildContext context, String email);

Future<void> openDirectoryComposeEmail(
  BuildContext context, {
  required AppSessionController controller,
  required String email,
  Future<MailAccessCredentials?> Function()? mailCredentialsLoader,
  MailService Function()? mailServiceFactory,
}) async {
  final credentials =
      await (mailCredentialsLoader?.call() ??
          controller.loadMailAccessCredentials());
  if (!context.mounted) return;
  if (credentials == null) {
    BnbuToast.show(context, '请先登录后再写邮件', kind: BnbuToastKind.warning);
    return;
  }

  final service = mailServiceFactory?.call() ?? createMailService();
  var handedOff = false;
  try {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'ComposeMailPage'),
        builder: (_) => ComposeMailPage(
          senderDisplayName: mailSenderDisplayName(controller),
          mailService: service,
          credentials: credentials,
          initialRecipient: email,
          closeMailServiceOnDispose: true,
        ),
      ),
    );
    handedOff = true;
  } finally {
    if (!handedOff) {
      await service.close();
    }
  }
}

Future<bool> openOfficialTeacherByName(
  BuildContext context, {
  required AppSessionController controller,
  required String teacherName,
  CampusDirectoryService? directoryService,
  TeacherReviewService? reviewService,
  Future<OfficialTeacherPage?>? prefetchedPage,
}) async {
  final normalizedName = teacherName.trim();
  if (normalizedName.isEmpty) return false;
  final service = directoryService ?? RemoteCampusDirectoryService();
  var resolved = false;
  try {
    // Navigation must never wait for the directory or portrait network request.
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'OfficialTeacherDetailPage'),
        builder: (_) => _TeacherLookupPage(
          controller: controller,
          teacherName: normalizedName,
          service: service,
          reviewService: reviewService,
          prefetchedPage: prefetchedPage,
          onResolved: () => resolved = true,
        ),
      ),
    );
    return resolved;
  } finally {
    if (directoryService == null) service.dispose();
  }
}

class _TeacherLookupPage extends StatefulWidget {
  const _TeacherLookupPage({
    required this.controller,
    required this.teacherName,
    required this.service,
    required this.onResolved,
    this.reviewService,
    this.prefetchedPage,
  });

  final AppSessionController controller;
  final String teacherName;
  final CampusDirectoryService service;
  final TeacherReviewService? reviewService;
  final Future<OfficialTeacherPage?>? prefetchedPage;
  final VoidCallback onResolved;

  @override
  State<_TeacherLookupPage> createState() => _TeacherLookupPageState();
}

class _TeacherLookupPageState extends State<_TeacherLookupPage> {
  late Future<OfficialTeacherProfile?> _lookup = _load(widget.prefetchedPage);

  Future<OfficialTeacherProfile?> _load(
    Future<OfficialTeacherPage?>? prefetch,
  ) async {
    final page =
        await prefetch ??
        await widget.service.loadTeachers(query: widget.teacherName, limit: 20);
    final exact = page.items
        .where(
          (teacher) =>
              teacher.matchType == OfficialTeacherMatchType.exact ||
              DirectorySearch.isExactTeacherName(teacher, widget.teacherName),
        )
        .toList(growable: false);
    final uniqueCandidate =
        exact.isEmpty &&
            page.total == 1 &&
            page.items.length == 1 &&
            DirectorySearch.scoreTeacher(
                  page.items.single,
                  widget.teacherName,
                ) <
                DirectorySearch.noMatch
        ? page.items.single
        : null;
    final teacher = exact.length == 1 ? exact.single : uniqueCandidate;
    if (mounted && teacher != null) widget.onResolved();
    return teacher;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<OfficialTeacherProfile?>(
    future: _lookup,
    builder: (context, snapshot) {
      final teacher = snapshot.data;
      if (snapshot.connectionState == ConnectionState.done && teacher != null) {
        return OfficialTeacherDetailPage(
          controller: widget.controller,
          teacher: teacher,
          reviewService: widget.reviewService,
          onComposeEmail: (composeContext, email) => openDirectoryComposeEmail(
            composeContext,
            controller: widget.controller,
            email: email,
          ),
        );
      }
      final loading = snapshot.connectionState != ConnectionState.done;
      return Scaffold(
        backgroundColor: context.bnbuTheme.canvas,
        appBar: BnbuSecondaryAppBar(
          bar: AppBar(title: BnbuText(widget.teacherName)),
        ),
        body: loading
            ? const BnbuInitialLoading(key: ValueKey('teacher-profile-loading'))
            : Center(
                child: Padding(
                  padding: EdgeInsets.all(context.bnbuTheme.space24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        key: const ValueKey('teacher-profile-unavailable'),
                        liveRegion: true,
                        child: BnbuText(
                          snapshot.hasError ? '教师档案加载失败' : '该教师可能未被学校收录',
                        ),
                      ),
                      SizedBox(height: context.bnbuTheme.space12),
                      TextButton(
                        onPressed: () {
                          final next = _load(null);
                          setState(() {
                            _lookup = next;
                          });
                        },
                        child: const BnbuText('重试'),
                      ),
                    ],
                  ),
                ),
              ),
      );
    },
  );
}

class CampusDirectoryPage extends StatefulWidget {
  const CampusDirectoryPage({
    super.key,
    required this.controller,
    this.directoryService,
    this.teacherReviewService,
    this.mailCredentialsLoader,
    this.mailServiceFactory,
    this.initialOrganizationId = '',
  });

  final AppSessionController controller;
  final String initialOrganizationId;
  final CampusDirectoryService? directoryService;
  final TeacherReviewService? teacherReviewService;
  final Future<MailAccessCredentials?> Function()? mailCredentialsLoader;
  final MailService Function()? mailServiceFactory;

  @override
  State<CampusDirectoryPage> createState() => _CampusDirectoryPageState();
}

class _CampusDirectoryPageState extends State<CampusDirectoryPage> {
  late final CampusDirectoryService _service =
      widget.directoryService ?? RemoteCampusDirectoryService();
  late final bool _ownsService = widget.directoryService == null;
  late Future<List<CampusDirectoryOrganization>> _organizationsFuture = _service
      .loadOrganizations();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  CampusDirectoryCategory _category = CampusDirectoryCategory.college;
  CampusDirectoryOrganization? _selected;
  List<OfficialTeacherProfile> _teacherMatches = const [];
  Timer? _searchDebounce;
  int _searchGeneration = 0;
  bool _searchingTeachers = false;
  String _query = '';
  int _teacherTotal = 0;
  int _teacherOffset = 0;
  String? _teacherSearchError;
  bool _searchNeedsReset = false;
  DirectorySyncInfo? _teacherSync;
  bool _checkingSearchSnapshot = false;
  AssistantContextCoordinator? _contextCoordinator;
  AssistantContextRegistration? _contextRegistration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AssistantContextScope.maybeOf(context);
    if (identical(next, _contextCoordinator)) return;
    _contextRegistration?.dispose();
    _contextCoordinator = next;
    _contextRegistration = next?.register(
      AssistantContextContribution(
        currentPage: () => AssistantCurrentPageContext(
          pageType: 'directory',
          title: '政教信息',
          selectedItemId: _selected?.id ?? '',
          summary: _selected?.nameCn ?? '',
        ),
      ),
    );
  }

  bool get _searchFocused => _searchFocusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    if (_ownsService) {
      PublicDirectoryCache.shared.revision.addListener(_refreshPublicSnapshot);
    }
    if (widget.initialOrganizationId.isNotEmpty) {
      unawaited(_openInitialOrganization());
    }
  }

  Future<void> _openInitialOrganization() async {
    try {
      final organizations = await _organizationsFuture;
      if (!mounted) return;
      final target = organizations
          .where((item) => item.id == widget.initialOrganizationId)
          .firstOrNull;
      if (target == null) {
        BnbuToast.show(context, '该机构已更新，请重新查询', kind: BnbuToastKind.warning);
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openOrganization(target);
      });
    } catch (_) {
      if (mounted) {
        BnbuToast.show(context, '政教目录暂时不可用', kind: BnbuToastKind.warning);
      }
    }
  }

  void _refreshPublicSnapshot() {
    if (mounted) {
      setState(() {
        _organizationsFuture = _service.loadOrganizations();
      });
      unawaited(_checkSearchSnapshot());
    }
  }

  Future<void> _checkSearchSnapshot() async {
    if (_checkingSearchSnapshot ||
        _searchingTeachers ||
        _teacherSync == null ||
        _query.trim().length < 2) {
      return;
    }
    _checkingSearchSnapshot = true;
    final generation = _searchGeneration;
    try {
      final page = await _service.loadTeachers(query: _query.trim(), limit: 60);
      if (!mounted || generation != _searchGeneration) return;
      if (page.sync?.version != _teacherSync?.version) {
        setState(() {
          _searchNeedsReset = true;
          _teacherSearchError = '师资目录已更新，请重新加载';
        });
      } else {
        setState(() => _teacherSync = page.sync);
      }
    } catch (_) {
      // Background revalidation must preserve the existing result canvas.
    } finally {
      _checkingSearchSnapshot = false;
    }
  }

  void _handleSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _contextRegistration?.dispose();
    if (_ownsService) {
      PublicDirectoryCache.shared.revision.removeListener(
        _refreshPublicSnapshot,
      );
    }
    _searchDebounce?.cancel();
    _searchFocusNode
      ..removeListener(_handleSearchFocusChanged)
      ..dispose();
    _searchController.dispose();
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Scaffold(
          backgroundColor: tokens.canvas,
          body: PageHeaderOverlay(
            overlap: wide || _query.trim().isNotEmpty
                ? 0
                : PageHeaderOverlay.tailHeight,
            header: Stack(
              children: [
                Positioned.fill(
                  child: PageHeaderBackdrop(
                    page: 'directory',
                    translucentTail: wide || _query.trim().isNotEmpty
                        ? 0
                        : PageHeaderOverlay.tailHeight,
                  ),
                ),
                SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BnbuSecondaryAppBar(
                        bar: AppBar(
                          primary: false,
                          title: const BnbuText('政教信息'),
                          backgroundColor: Colors.transparent,
                          foregroundColor: tokens.textPrimary,
                          systemOverlayStyle: AppTheme.statusBarStyle(
                            Theme.of(context).brightness,
                          ),
                        ),
                      ),
                      _buildSearchTopbar(context, wide: wide),
                      if (!wide && _query.trim().isEmpty)
                        _buildCategorySelector(context),
                      if (!wide) const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
            body: FutureBuilder<List<CampusDirectoryOrganization>>(
              future: _organizationsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done &&
                    !snapshot.hasData) {
                  return const Center(child: BnbuActivityIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: BnbuErrorState(
                      title: '目录加载失败',
                      message: '${snapshot.error}',
                    ),
                  );
                }
                final organizations = snapshot.data ?? const [];
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final searchingAll = _query.trim().isNotEmpty;
                    var filtered =
                        organizations
                            .where(
                              (item) =>
                                  searchingAll ||
                                  item.category.browseCategory == _category,
                            )
                            .where(
                              (item) => DirectorySearch.matchesOrganization(
                                item,
                                _query,
                              ),
                            )
                            .toList(growable: false)
                          ..sort(
                            (left, right) =>
                                DirectorySearch.scoreOrganization(
                                  left,
                                  _query,
                                ).compareTo(
                                  DirectorySearch.scoreOrganization(
                                    right,
                                    _query,
                                  ),
                                ),
                          );
                    var teachers = _teacherMatches.toList(growable: false)
                      ..sort(
                        (left, right) =>
                            DirectorySearch.scoreTeacher(
                              left,
                              _query,
                            ).compareTo(
                              DirectorySearch.scoreTeacher(right, _query),
                            ),
                      );
                    final exactTeachers = teachers
                        .where(
                          (teacher) =>
                              teacher.matchType ==
                                  OfficialTeacherMatchType.exact ||
                              DirectorySearch.isExactTeacherName(
                                teacher,
                                _query,
                              ),
                        )
                        .toList(growable: false);
                    if (exactTeachers.isNotEmpty) {
                      teachers = exactTeachers;
                      filtered = filtered
                          .where(
                            (organization) =>
                                DirectorySearch.isExactOrganizationName(
                                  organization,
                                  _query,
                                ),
                          )
                          .toList(growable: false);
                    }
                    CampusDirectoryOrganization? selected = filtered
                        .where((item) => item.id == _selected?.id)
                        .firstOrNull;
                    if (wide &&
                        (selected == null ||
                            (!searchingAll &&
                                selected.category.browseCategory !=
                                    _category) ||
                            !filtered.contains(selected))) {
                      selected = filtered.firstOrNull;
                      _selected = selected;
                    }

                    final workspace = searchingAll
                        ? _buildSearchResults(
                            context,
                            organizations,
                            filtered,
                            teachers,
                          )
                        : !wide
                        ? _buildCompactDirectory(context, filtered, teachers)
                        : _buildWideDirectory(
                            context,
                            filtered,
                            selected,
                            teachers,
                          );
                    final recess = _searchFocused && _query.trim().isEmpty;
                    return BnbuSoftSearchBody(
                      active: recess,
                      onDismiss: _searchFocusNode.unfocus,
                      child: ColoredBox(color: tokens.canvas, child: workspace),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    List<CampusDirectoryOrganization> allOrganizations,
    List<CampusDirectoryOrganization> matchingOrganizations,
    List<OfficialTeacherProfile> teachers,
  ) {
    final tokens = context.bnbuTheme;
    final groupedTeachers =
        <CampusDirectoryOrganization, List<OfficialTeacherProfile>>{};
    final ungroupedTeachers = <String, List<OfficialTeacherProfile>>{};
    for (final teacher in teachers) {
      final organization = allOrganizations
          .where(
            (item) =>
                DirectorySearch.teacherBelongsToOrganization(teacher, item),
          )
          .firstOrNull;
      if (organization != null) {
        groupedTeachers.putIfAbsent(organization, () => []).add(teacher);
        continue;
      }
      final label = teacher.unitNames.firstOrNull ?? '其他师资';
      ungroupedTeachers.putIfAbsent(label, () => []).add(teacher);
    }

    final organizations =
        <CampusDirectoryOrganization>{
          ...matchingOrganizations,
          ...groupedTeachers.keys,
        }.toList(growable: false)..sort((left, right) {
          final category = left.category.index.compareTo(right.category.index);
          return category != 0 ? category : left.nameCn.compareTo(right.nameCn);
        });
    final ungrouped = ungroupedTeachers.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    final hasResults = organizations.isNotEmpty || ungrouped.isNotEmpty;

    return Column(
      key: const ValueKey('campus-directory-search-results'),
      children: [
        if (_teacherTotal > 0)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${context.l10n.text('师资队伍')} $_teacherOffset / $_teacherTotal',
                key: const ValueKey('directory-search-count'),
              ),
            ),
          ),
        SizedBox(
          height: 2,
          child: BnbuUpdateProgress(active: _searchingTeachers && hasResults),
        ),
        Expanded(
          child: !hasResults
              ? _searchingTeachers
                    ? const BnbuInitialLoading()
                    : _teacherSearchError != null
                    ? Center(child: _searchFooter())
                    : const Center(child: BnbuEmptyState(title: '没有匹配的政教信息'))
              : CustomScrollView(
                  key: const PageStorageKey('directory-search-scroll'),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        tokens.space16,
                        tokens.space16,
                        tokens.space16,
                        tokens.space32,
                      ),
                      sliver: SliverList.list(
                        children: [
                          for (final organization in organizations) ...[
                            _DirectorySearchOrganizationGroup(
                              organization: organization,
                              teachers:
                                  groupedTeachers[organization] ?? const [],
                              onOpenOrganization: () =>
                                  _openOrganization(organization),
                              onOpenTeacher: _openTeacher,
                            ),
                            SizedBox(height: tokens.space24),
                          ],
                          for (final entry in ungrouped) ...[
                            _DirectorySearchTeacherGroup(
                              label: entry.key,
                              teachers: entry.value,
                              onOpenTeacher: _openTeacher,
                            ),
                            SizedBox(height: tokens.space24),
                          ],
                          _searchFooter(),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildCompactDirectory(
    BuildContext context,
    List<CampusDirectoryOrganization> organizations,
    List<OfficialTeacherProfile> teachers,
  ) {
    final tokens = context.bnbuTheme;
    return Column(
      children: [
        Expanded(
          child: organizations.isEmpty && teachers.isEmpty
              ? _searchingTeachers
                    ? const BnbuInitialLoading()
                    : const Center(child: BnbuEmptyState(title: '没有匹配的政教信息'))
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    tokens.space16,
                    tokens.space16 + PageHeaderOverlay.tailHeight,
                    tokens.space16,
                    tokens.space16,
                  ),
                  itemCount: organizations.length + teachers.length,
                  separatorBuilder: (_, _) => SizedBox(height: tokens.space8),
                  itemBuilder: (context, index) {
                    if (index < organizations.length) {
                      final organization = organizations[index];
                      return _OrganizationTile(
                        organization: organization,
                        selected: false,
                        onTap: () => _openOrganization(organization),
                      );
                    }
                    final teacher = teachers[index - organizations.length];
                    return _TeacherCard(
                      teacher: teacher,
                      onTap: () => _openTeacher(teacher),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildWideDirectory(
    BuildContext context,
    List<CampusDirectoryOrganization> organizations,
    CampusDirectoryOrganization? selected,
    List<OfficialTeacherProfile> teachers,
  ) {
    final tokens = context.bnbuTheme;
    return Row(
      children: [
        SizedBox(
          key: const ValueKey('campus-directory-master-pane'),
          width: 300,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(right: BorderSide(color: tokens.border)),
            ),
            child: Column(
              children: [
                _buildCategorySelector(context),
                Expanded(
                  child: organizations.isEmpty && teachers.isEmpty
                      ? _searchingTeachers
                            ? const SizedBox.shrink()
                            : const Center(
                                child: BnbuEmptyState(title: '没有匹配的政教信息'),
                              )
                      : ListView.separated(
                          padding: EdgeInsets.all(tokens.space12),
                          itemCount: organizations.length + teachers.length,
                          separatorBuilder: (_, _) =>
                              SizedBox(height: tokens.space4),
                          itemBuilder: (context, index) {
                            if (index < organizations.length) {
                              final organization = organizations[index];
                              return _OrganizationTile(
                                organization: organization,
                                selected: organization == selected,
                                onTap: () {
                                  setState(() => _selected = organization);
                                },
                              );
                            }
                            final teacher =
                                teachers[index - organizations.length];
                            return _TeacherCard(
                              teacher: teacher,
                              onTap: () => _openTeacher(teacher),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: selected == null
              ? const Center(child: BnbuEmptyState(title: '没有匹配的机构'))
              : CampusDirectoryOrganizationView(
                  key: ValueKey('campus-directory-detail-${selected.id}'),
                  controller: widget.controller,
                  organization: selected,
                  directoryService: _service,
                  teacherReviewService: widget.teacherReviewService,
                  showBackButton: false,
                  onComposeEmail: _openComposeEmail,
                ),
        ),
      ],
    );
  }

  Widget _buildCategorySelector(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final entry in const [
            (CampusDirectoryCategory.college, '学院'),
            (CampusDirectoryCategory.administration, '政务'),
          ])
            Expanded(
              child: Semantics(
                selected: _category == entry.$1,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    foregroundColor: _category == entry.$1
                        ? tokens.brandBlue
                        : tokens.textSecondary,
                    textStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: _category == entry.$1
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  onPressed: () => setState(() {
                    _category = entry.$1;
                    _selected = null;
                  }),
                  child: BnbuText(entry.$2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchTopbar(BuildContext context, {required bool wide}) {
    final search = wide ? BnbuRevealSearch.persistent : BnbuRevealSearch.hidden;
    return Padding(
      key: const ValueKey('campus-directory-search-toolbar'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        key: const ValueKey('campus-directory-search-shell'),
        width: double.infinity,
        child: search(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _onSearchChanged,
          hintText: context.l10n.text('搜索全部政教信息'),
          isLoading: _searchingTeachers,
          expandedMaxWidth: 560,
          softMode: !wide,
          preserveQueryOnDismiss: true,
          onTapOutside: (_) => _searchFocusNode.unfocus(),
          controlKey: const ValueKey('campus-directory-search'),
          closeKey: const ValueKey('campus-directory-search-close'),
        ),
      ),
    );
  }

  void _openOrganization(CampusDirectoryOrganization organization) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => CampusDirectoryOrganizationView(
          controller: widget.controller,
          organization: organization,
          directoryService: _service,
          teacherReviewService: widget.teacherReviewService,
          showBackButton: true,
          onComposeEmail: _openComposeEmail,
        ),
      ),
    );
  }

  void _openTeacher(OfficialTeacherProfile teacher) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => OfficialTeacherDetailPage(
          controller: widget.controller,
          teacher: teacher,
          reviewService: widget.teacherReviewService,
          onComposeEmail: _openComposeEmail,
        ),
      ),
    );
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    ++_searchGeneration;
    final query = value.trim();
    setState(() {
      _query = value;
      _teacherMatches = const [];
      _teacherTotal = 0;
      _teacherOffset = 0;
      _teacherSync = null;
      _teacherSearchError = null;
      _searchNeedsReset = false;
      _searchingTeachers = query.length >= 2;
    });
    if (query.length < 2) return;
    _searchDebounce = Timer(
      const Duration(milliseconds: 250),
      () => _loadSearchPage(reset: true),
    );
  }

  Future<void> _loadSearchPage({
    required bool reset,
    bool refresh = false,
  }) async {
    final query = _query.trim();
    if (query.length < 2) return;
    final generation = _searchGeneration;
    final offset = reset ? 0 : _teacherOffset;
    setState(() {
      _searchingTeachers = true;
      _teacherSearchError = null;
    });
    try {
      final service = _service;
      final page = service is VersionedCampusDirectoryService
          ? await (service as VersionedCampusDirectoryService)
                .loadTeacherSnapshot(
                  query: query,
                  offset: offset,
                  limit: 60,
                  refresh: refresh,
                  snapshotVersion: reset ? '' : (_teacherSync?.version ?? ''),
                )
          : await service.loadTeachers(query: query, offset: offset, limit: 60);
      if (!mounted || generation != _searchGeneration) return;
      final version = page.sync?.version ?? '';
      if (!reset &&
          (_teacherSync?.version.isNotEmpty ?? false) &&
          version != _teacherSync!.version) {
        throw const CampusDirectoryException(
          '师资目录已更新，请重新加载',
          snapshotChanged: true,
        );
      }
      if (page.offset != offset ||
          (page.items.isEmpty && offset < page.total)) {
        throw const CampusDirectoryException('师资目录加载失败');
      }
      final seen = <String>{};
      final merged = [if (!reset) ..._teacherMatches, ...page.items]
          .where((teacher) => seen.add('${teacher.reviewKey}|${teacher.name}'))
          .toList(growable: false);
      setState(() {
        _teacherMatches = merged;
        _teacherOffset = offset + page.items.length;
        _teacherTotal = page.total;
        _teacherSync = page.sync;
        _searchNeedsReset = false;
        _searchingTeachers = false;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchingTeachers = false;
        _searchNeedsReset =
            error is CampusDirectoryException && error.snapshotChanged;
        _teacherSearchError = _searchNeedsReset ? '师资目录已更新，请重新加载' : '师资目录加载失败';
      });
    }
  }

  Widget _searchFooter() => Column(
    children: [
      if (_teacherSync != null) _DirectorySyncStatus(sync: _teacherSync),
      if (_teacherSearchError != null)
        Semantics(
          liveRegion: true,
          child: BnbuErrorState(
            title: _teacherSearchError!,
            action: TextButton(
              key: const ValueKey('directory-search-retry'),
              onPressed: _searchingTeachers
                  ? null
                  : () => _loadSearchPage(
                      reset: _searchNeedsReset || _teacherOffset == 0,
                      refresh: true,
                    ),
              child: const BnbuText('重试'),
            ),
          ),
        )
      else if (_teacherOffset < _teacherTotal)
        TextButton.icon(
          key: const ValueKey('directory-search-load-more'),
          onPressed: _searchingTeachers
              ? null
              : () => _loadSearchPage(reset: false),
          icon: _searchingTeachers
              ? const SizedBox.square(
                  dimension: 18,
                  child: BnbuActivityIndicator(),
                )
              : const Icon(LucideIcons.chevronDown300),
          label: const BnbuText('加载更多'),
        ),
    ],
  );

  Future<void> _openComposeEmail(BuildContext context, String email) async {
    await openDirectoryComposeEmail(
      context,
      controller: widget.controller,
      email: email,
      mailCredentialsLoader: widget.mailCredentialsLoader,
      mailServiceFactory: widget.mailServiceFactory,
    );
  }
}

class CampusDirectoryOrganizationView extends StatelessWidget {
  const CampusDirectoryOrganizationView({
    super.key,
    required this.controller,
    required this.organization,
    required this.directoryService,
    required this.teacherReviewService,
    required this.showBackButton,
    required this.onComposeEmail,
  });

  final AppSessionController controller;
  final CampusDirectoryOrganization organization;
  final CampusDirectoryService directoryService;
  final TeacherReviewService? teacherReviewService;
  final bool showBackButton;
  final DirectoryComposeHandler onComposeEmail;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final content = CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            tokens.space24,
            tokens.space24,
            tokens.space24,
            tokens.space32,
          ),
          sliver: SliverList.list(
            children: [
              _OrganizationHeader(
                controller: controller,
                organization: organization,
                onComposeEmail: onComposeEmail,
              ),
              if (organization.responsibilities.isNotEmpty) ...[
                SizedBox(height: tokens.space24),
                const BnbuSectionHeader(title: '职责'),
                SizedBox(height: tokens.space8),
                _ResponsibilityGrid(
                  responsibilities: organization.responsibilities,
                ),
              ],
              if (organization.teacherUnit.isNotEmpty ||
                  organization.embeddedStaff.isNotEmpty) ...[
                SizedBox(height: tokens.space24),
                _TeacherDirectorySection(
                  controller: controller,
                  organization: organization,
                  directoryService: directoryService,
                  teacherReviewService: teacherReviewService,
                  onComposeEmail: onComposeEmail,
                ),
              ],
              if (organization.contacts.isNotEmpty) ...[
                SizedBox(height: tokens.space24),
                const BnbuSectionHeader(title: '部门与联系人'),
                SizedBox(height: tokens.space8),
                for (final contact in organization.contacts) ...[
                  _ContactCard(
                    contact: contact,
                    onComposeEmail: onComposeEmail,
                  ),
                  SizedBox(height: tokens.space8),
                ],
              ],
              if (organization.services.isNotEmpty) ...[
                SizedBox(height: tokens.space24),
                const BnbuSectionHeader(title: '办事分工'),
                SizedBox(height: tokens.space8),
                for (final service in organization.services) ...[
                  _ContactCard(
                    contact: service,
                    onComposeEmail: onComposeEmail,
                  ),
                  SizedBox(height: tokens.space8),
                ],
              ],
              if (organization.sources.isNotEmpty) ...[
                SizedBox(height: tokens.space24),
                const BnbuSectionHeader(title: '官方来源'),
                SizedBox(height: tokens.space8),
                for (final source in organization.sources.where(
                  (s) =>
                      s['status'] == 'restricted' ||
                      s['status'] == 'historical_reference' ||
                      s['status'] == 'stale',
                ))
                  Text(
                    '${Uri.tryParse(source['url']?.toString() ?? '')?.host ?? ''} · ${context.l10n.text(source['status'] == 'restricted'
                        ? '访问受限'
                        : source['status'] == 'historical_reference'
                        ? '历史资料'
                        : '沿用上次资料')}',
                  ),
                for (final stamp
                    in organization.sources
                        .map(
                          (s) => DateTime.tryParse(
                            (s['last_success_at'] ?? s['verified_at'] ?? '')
                                .toString(),
                          ),
                        )
                        .whereType<DateTime>()
                        .map(
                          (d) => d
                              .toUtc()
                              .add(const Duration(hours: 8))
                              .toIso8601String()
                              .substring(0, 10),
                        )
                        .toSet()
                        .take(1))
                  Text('${context.l10n.text('补充资料核验')} $stamp'),
              ],
            ],
          ),
        ),
      ],
    );
    if (!showBackButton) {
      return ColoredBox(color: tokens.canvas, child: content);
    }
    return AssistantPageContext(
      currentPage: () => AssistantCurrentPageContext(
        pageType: 'directory',
        title: organization.nameCn,
        selectedItemId: organization.id,
      ),
      child: Scaffold(
        backgroundColor: tokens.canvas,
        appBar: BnbuSecondaryAppBar(
          bar: AppBar(
            title: BnbuText(organization.nameCn),
            backgroundColor: tokens.canvas,
            foregroundColor: tokens.textPrimary,
          ),
        ),
        body: content,
      ),
    );
  }
}

class _OrganizationHeader extends StatelessWidget {
  const _OrganizationHeader({
    required this.controller,
    required this.organization,
    required this.onComposeEmail,
  });

  final AppSessionController controller;
  final CampusDirectoryOrganization organization;
  final DirectoryComposeHandler onComposeEmail;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CampusOrganizationAvatar(
                organization: organization,
                diameter: 40,
              ),
              SizedBox(width: tokens.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BnbuText(
                      organization.nameCn,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (organization.nameEn.isNotEmpty) ...[
                      SizedBox(height: tokens.space4),
                      BnbuText(
                        organization.nameEn,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _openOfficialPage(
                  context,
                  controller: controller,
                  title: organization.nameCn,
                  url: organization.websiteUrl,
                ),
                tooltip: context.l10n.text('打开官网'),
                icon: const Icon(LucideIcons.externalLink300),
              ),
            ],
          ),
          if (organization.office.isNotEmpty ||
              organization.phones.isNotEmpty ||
              organization.emails.isNotEmpty) ...[
            SizedBox(height: tokens.space24),
            Divider(height: 1, color: tokens.border),
            SizedBox(height: tokens.space16),
            Wrap(
              spacing: tokens.space8,
              runSpacing: tokens.space8,
              children: [
                if (organization.office.isNotEmpty)
                  _ContactChip(
                    icon: LucideIcons.mapPin300,
                    label: organization.office,
                  ),
                for (final phone in organization.phones)
                  _ContactChip(
                    icon: LucideIcons.phone300,
                    label: phone,
                    onTap: () => _launchPhone(phone),
                  ),
                for (final email in organization.emails)
                  _ContactChip(
                    icon: LucideIcons.mail300,
                    label: email,
                    onTap: () => onComposeEmail(context, email),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ResponsibilityGrid extends StatelessWidget {
  const _ResponsibilityGrid({required this.responsibilities});
  final List<String> responsibilities;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final item in responsibilities)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: BnbuText(item, style: Theme.of(context).textTheme.bodyLarge),
        ),
    ],
  );
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.contact, required this.onComposeEmail});

  final CampusDirectoryContact contact;
  final DirectoryComposeHandler onComposeEmail;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    return BnbuSurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.contactRound300, color: tokens.brandBlue),
          SizedBox(width: tokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BnbuText(
                  contact.nameCn,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (contact.nameEn.isNotEmpty) ...[
                  SizedBox(height: tokens.space4),
                  BnbuText(
                    contact.nameEn,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
                if (contact.responsibilities.isNotEmpty) ...[
                  SizedBox(height: tokens.space8),
                  BnbuText(contact.responsibilities.join(' · ')),
                ],
                if (contact.serviceHours.isNotEmpty) ...[
                  SizedBox(height: tokens.space8),
                  BnbuText(contact.serviceHours),
                ],
                SizedBox(height: tokens.space8),
                Wrap(
                  spacing: tokens.space8,
                  runSpacing: tokens.space8,
                  children: [
                    if (contact.office.isNotEmpty)
                      _ContactChip(
                        icon: LucideIcons.mapPin300,
                        label: contact.office,
                      ),
                    for (final phone in contact.phones)
                      _ContactChip(
                        icon: LucideIcons.phone300,
                        label: phone,
                        onTap: () => _launchPhone(phone),
                      ),
                    for (final email in contact.emails)
                      _ContactChip(
                        icon: LucideIcons.mail300,
                        label: email,
                        onTap: () => onComposeEmail(context, email),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectorySearchOrganizationGroup extends StatelessWidget {
  const _DirectorySearchOrganizationGroup({
    required this.organization,
    required this.teachers,
    required this.onOpenOrganization,
    required this.onOpenTeacher,
  });

  final CampusDirectoryOrganization organization;
  final List<OfficialTeacherProfile> teachers;
  final VoidCallback onOpenOrganization;
  final ValueChanged<OfficialTeacherProfile> onOpenTeacher;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFieldTapRegion(
          key: ValueKey('directory-search-group-${organization.id}'),
          child: _OrganizationTile(
            organization: organization,
            selected: false,
            onTap: onOpenOrganization,
          ),
        ),
        if (teachers.isNotEmpty) ...[
          SizedBox(height: tokens.space12),
          _DirectorySearchTeacherGrid(
            teachers: teachers,
            onOpenTeacher: onOpenTeacher,
          ),
        ],
      ],
    );
  }
}

class _DirectorySearchTeacherGroup extends StatelessWidget {
  const _DirectorySearchTeacherGroup({
    required this.label,
    required this.teachers,
    required this.onOpenTeacher,
  });

  final String label;
  final List<OfficialTeacherProfile> teachers;
  final ValueChanged<OfficialTeacherProfile> onOpenTeacher;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BnbuSectionHeader(title: label),
        SizedBox(height: tokens.space12),
        _DirectorySearchTeacherGrid(
          teachers: teachers,
          onOpenTeacher: onOpenTeacher,
        ),
      ],
    );
  }
}

class _DirectorySearchTeacherGrid extends StatelessWidget {
  const _DirectorySearchTeacherGrid({
    required this.teachers,
    required this.onOpenTeacher,
  });

  final List<OfficialTeacherProfile> teachers;
  final ValueChanged<OfficialTeacherProfile> onOpenTeacher;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final spacing = tokens.space12;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final teacher in teachers)
              SizedBox(
                key: ValueKey('directory-search-teacher-${teacher.email}'),
                width: width,
                child: TextFieldTapRegion(
                  child: _TeacherCard(
                    teacher: teacher,
                    onTap: () => onOpenTeacher(teacher),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TeacherDirectorySection extends StatefulWidget {
  const _TeacherDirectorySection({
    required this.controller,
    required this.organization,
    required this.directoryService,
    required this.teacherReviewService,
    required this.onComposeEmail,
  });

  final AppSessionController controller;
  final CampusDirectoryOrganization organization;
  final CampusDirectoryService directoryService;
  final TeacherReviewService? teacherReviewService;
  final DirectoryComposeHandler onComposeEmail;

  @override
  State<_TeacherDirectorySection> createState() =>
      _TeacherDirectorySectionState();
}

class _TeacherDirectorySectionState extends State<_TeacherDirectorySection> {
  List<OfficialTeacherProfile> _teachers = const [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _total = 0;
  int _remoteOffset = 0;
  int _loadGeneration = 0;
  String _snapshotVersion = '';

  @override
  void initState() {
    super.initState();
    _resetForOrganization();
  }

  @override
  void didUpdateWidget(covariant _TeacherDirectorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.organization.id != widget.organization.id ||
        oldWidget.organization.sync?.version !=
            widget.organization.sync?.version ||
        oldWidget.organization.sync?.status !=
            widget.organization.sync?.status ||
        oldWidget.organization.sync?.lastSuccessAt !=
            widget.organization.sync?.lastSuccessAt ||
        !identical(
          oldWidget.organization.embeddedStaff,
          widget.organization.embeddedStaff,
        )) {
      _resetForOrganization();
    }
  }

  void _resetForOrganization() {
    _loadGeneration++;
    _snapshotVersion = '';
    if (widget.organization.embeddedStaff.isNotEmpty &&
        (widget.organization.teacherUnit.isEmpty ||
            const {
              'college-gs',
              'research-ias',
            }.contains(widget.organization.id))) {
      _teachers = widget.organization.embeddedStaff;
      _total = _teachers.length;
      _loading = false;
      _error = null;
      return;
    }
    unawaited(_load(reset: true));
  }

  Future<void> _load({required bool reset}) async {
    final generation = ++_loadGeneration;
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _teachers = const [];
        _total = 0;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final service = widget.directoryService;
      final page = service is VersionedCampusDirectoryService
          ? await (service as VersionedCampusDirectoryService)
                .loadTeacherSnapshot(
                  unit: widget.organization.teacherUnit,
                  offset: reset ? 0 : _remoteOffset,
                  limit: 60,
                  snapshotVersion: reset ? '' : _snapshotVersion,
                  refresh: reset,
                )
          : await service.loadTeachers(
              unit: widget.organization.teacherUnit,
              offset: reset ? 0 : _remoteOffset,
              limit: 60,
            );
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _remoteOffset = (reset ? 0 : _remoteOffset) + page.items.length;
        _snapshotVersion = page.sync?.version ?? '';
        bool same(OfficialTeacherProfile a, OfficialTeacherProfile b) =>
            ((a.email.isNotEmpty && a.email == b.email) ||
                (a.profileUrl.isNotEmpty && a.profileUrl == b.profileUrl) ||
                (a.email.isEmpty &&
                    b.email.isEmpty &&
                    a.profileUrl.isEmpty &&
                    b.profileUrl.isEmpty)) &&
            [a.name, a.nameEn].any(
              (name) => name.isNotEmpty && [b.name, b.nameEn].contains(name),
            );
        final combined = reset ? <OfficialTeacherProfile>[] : [..._teachers];
        for (final item in page.items) {
          final index = combined.indexWhere((old) => same(old, item));
          if (index < 0) {
            combined.add(item);
          } else {
            combined[index] = item;
          }
        }
        for (final member in widget.organization.embeddedStaff) {
          if (!combined.any((p) => same(p, member))) combined.add(member);
        }
        _teachers = combined;
        _total =
            combined.length + (page.total - _remoteOffset).clamp(0, page.total);
      });
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: BnbuSectionHeader(
                title:
                    widget.organization.category ==
                        CampusDirectoryCategory.administration
                    ? '人员'
                    : '师资与人员',
              ),
            ),
            if (_total > 0) BnbuText('$_total 位'),
          ],
        ),
        _DirectorySyncStatus(sync: widget.organization.sync),
        SizedBox(height: tokens.space8),
        BnbuUpdateProgress(active: _loading && _teachers.isNotEmpty),
        if (_loading && _teachers.isEmpty)
          const BnbuInitialLoading()
        else if (_error != null)
          BnbuErrorState(
            title: '师资目录加载失败',
            message: _error!,
            action: TextButton(
              onPressed: () => _load(reset: true),
              child: const BnbuText('重试'),
            ),
          )
        else if (_teachers.isEmpty)
          const BnbuEmptyState(title: '暂无师资数据')
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 980
                  ? 3
                  : constraints.maxWidth >= 600
                  ? 2
                  : 1;
              final spacing = tokens.space12;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final teacher in _teachers)
                    SizedBox(
                      width: width,
                      child: _TeacherCard(
                        teacher: teacher,
                        onTap: () => _openTeacher(context, teacher),
                      ),
                    ),
                ],
              );
            },
          ),
          if (_teachers.length < _total) ...[
            SizedBox(height: tokens.space16),
            OutlinedButton.icon(
              onPressed: _loadingMore ? null : () => _load(reset: false),
              icon: _loadingMore
                  ? const SizedBox.square(
                      dimension: 18,
                      child: BnbuActivityIndicator(),
                    )
                  : const Icon(LucideIcons.chevronDown300),
              label: const BnbuText('加载更多'),
            ),
          ],
        ],
      ],
    );
  }

  void _openTeacher(BuildContext context, OfficialTeacherProfile teacher) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => OfficialTeacherDetailPage(
          controller: widget.controller,
          teacher: teacher,
          reviewService: widget.teacherReviewService,
          onComposeEmail: widget.onComposeEmail,
        ),
      ),
    );
  }
}

class _TeacherCard extends StatelessWidget {
  const _TeacherCard({required this.teacher, required this.onTap});

  final OfficialTeacherProfile teacher;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    return BnbuSurfaceCard(
      backgroundColor: Colors.transparent,
      borderColor: tokens.border.withValues(alpha: 0.45),
      borderRadius: BorderRadius.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      onTap: onTap,
      child: Row(
        children: [
          TeacherPortrait(photoUrl: teacher.photoUrl, size: 48),
          SizedBox(width: tokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BnbuText(
                  teacher.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (teacher.nameEn.isNotEmpty &&
                    teacher.nameEn != teacher.displayName) ...[
                  SizedBox(height: tokens.space4),
                  BnbuText(
                    teacher.nameEn,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
                if (teacher.displayTitle.isNotEmpty) ...[
                  SizedBox(height: tokens.space8),
                  BnbuText(
                    teacher.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight300, color: tokens.textMuted),
        ],
      ),
    );
  }
}

class OfficialTeacherDetailPage extends StatelessWidget {
  const OfficialTeacherDetailPage({
    super.key,
    required this.controller,
    required this.teacher,
    required this.onComposeEmail,
    this.reviewService,
  });

  final AppSessionController controller;
  final OfficialTeacherProfile teacher;
  final DirectoryComposeHandler onComposeEmail;
  final TeacherReviewService? reviewService;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return AssistantPageContext(
      currentPage: () => AssistantCurrentPageContext(
        pageType: 'directory_person',
        title: teacher.displayName,
        selectedItemId: teacher.reviewKey,
        summary: '${teacher.name} ${teacher.nameEn} ${teacher.personKind}',
      ),
      child: Scaffold(
        backgroundColor: tokens.canvas,
        appBar: BnbuSecondaryAppBar(
          bar: AppBar(
            title: BnbuText(teacher.displayName),
            backgroundColor: tokens.canvas,
            foregroundColor: tokens.textPrimary,
          ),
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(tokens.space24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TeacherIdentity(
                    controller: controller,
                    teacher: teacher,
                    onComposeEmail: onComposeEmail,
                  ),
                  if (teacher.academicCn.isNotEmpty ||
                      teacher.academicEn.isNotEmpty) ...[
                    SizedBox(height: tokens.space24),
                    const BnbuSectionHeader(title: '研究领域'),
                    SizedBox(height: tokens.space8),
                    _TeacherTextSection(
                      primary: teacher.academicCn,
                      secondary: teacher.academicEn,
                    ),
                  ],
                  if (teacher.educationCn.isNotEmpty ||
                      teacher.educationEn.isNotEmpty) ...[
                    SizedBox(height: tokens.space24),
                    const BnbuSectionHeader(title: '教育经历'),
                    SizedBox(height: tokens.space8),
                    _TeacherTextSection(
                      primary: teacher.educationCn,
                      secondary: teacher.educationEn,
                    ),
                  ],
                  for (final section in teacher.sections) ...[
                    SizedBox(height: tokens.space24),
                    BnbuSectionHeader(title: section.name),
                    SizedBox(height: tokens.space8),
                    _TeacherProfileSection(
                      controller: controller,
                      section: section,
                    ),
                  ],
                  if (teacher.personKind == 'teacher') ...[
                    SizedBox(height: tokens.space24),
                    TeacherReviewsSection(
                      teacher: teacher,
                      username: controller.username,
                      timetable: controller.timetable,
                      reviewService: reviewService,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TeacherIdentity extends StatelessWidget {
  const _TeacherIdentity({
    required this.controller,
    required this.teacher,
    required this.onComposeEmail,
  });

  final AppSessionController controller;
  final OfficialTeacherProfile teacher;
  final DirectoryComposeHandler onComposeEmail;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final information = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BnbuText(
                teacher.displayName,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (teacher.nameEn.isNotEmpty &&
                  teacher.nameEn != teacher.displayName) ...[
                SizedBox(height: tokens.space4),
                BnbuText(
                  teacher.nameEn,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
              if (teacher.displayTitle.isNotEmpty) ...[
                SizedBox(height: tokens.space12),
                BnbuText(
                  teacher.displayTitle,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              SizedBox(height: tokens.space16),
              Wrap(
                spacing: tokens.space8,
                runSpacing: tokens.space8,
                children: [
                  for (final email in {
                    if (teacher.email.isNotEmpty) teacher.email,
                    ...teacher.contactEmails,
                  })
                    _ContactChip(
                      icon: LucideIcons.mail300,
                      label: email,
                      onTap: () => onComposeEmail(context, email),
                    ),
                  if (teacher.telephone.isNotEmpty)
                    _ContactChip(
                      icon: LucideIcons.phone300,
                      label: teacher.telephone,
                      onTap: () => _launchPhone(teacher.telephone),
                    ),
                  if (teacher.office.isNotEmpty)
                    _ContactChip(
                      icon: LucideIcons.mapPin300,
                      label: teacher.office,
                    ),
                ],
              ),
              if (teacher.unitNames.isNotEmpty) ...[
                SizedBox(height: tokens.space16),
                BnbuText(
                  teacher.unitNames.join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
              if (teacher.responsibilities.isNotEmpty) ...[
                SizedBox(height: tokens.space16),
                const BnbuSectionHeader(title: '职责'),
                SizedBox(height: tokens.space8),
                _ResponsibilityGrid(responsibilities: teacher.responsibilities),
              ],
              if (teacher.sourceUrls.isNotEmpty) ...[
                SizedBox(height: tokens.space16),
                _TeacherLinkGroup(
                  title: '官方来源',
                  icon: LucideIcons.link300,
                  links: teacher.sourceUrls
                      .map(
                        (url) => OfficialTeacherLink(
                          name: Uri.tryParse(url)?.host ?? '官网',
                          url: url,
                        ),
                      )
                      .toList(),
                  onOpen: (link) => _openTeacherLink(
                    context,
                    controller: controller,
                    link: link,
                  ),
                ),
              ],
              if (teacher.timetable != null ||
                  teacher.primaryAppointments.isNotEmpty ||
                  teacher.crossAppointments.isNotEmpty ||
                  teacher.profileLinks.isNotEmpty) ...[
                SizedBox(height: tokens.space16),
                Divider(height: 1, color: tokens.border),
                SizedBox(height: tokens.space12),
                if (teacher.timetable case final timetable?)
                  _TeacherLinkGroup(
                    title: '时间表',
                    icon: LucideIcons.calendarDays300,
                    links: [timetable],
                    onOpen: (link) => _openTeacherLink(
                      context,
                      controller: controller,
                      link: link,
                    ),
                  ),
                if (teacher.primaryAppointments.isNotEmpty)
                  _TeacherLinkGroup(
                    title: '主要任职',
                    icon: LucideIcons.briefcaseBusiness300,
                    links: teacher.primaryAppointments,
                    onOpen: (link) => _openTeacherLink(
                      context,
                      controller: controller,
                      link: link,
                    ),
                  ),
                if (teacher.crossAppointments.isNotEmpty)
                  _TeacherLinkGroup(
                    title: '交叉任职',
                    icon: LucideIcons.network300,
                    links: teacher.crossAppointments,
                    onOpen: (link) => _openTeacherLink(
                      context,
                      controller: controller,
                      link: link,
                    ),
                  ),
                if (teacher.profileLinks.isNotEmpty)
                  _TeacherLinkGroup(
                    title: '个人主页',
                    icon: LucideIcons.link300,
                    links: teacher.profileLinks,
                    onOpen: (link) => _openTeacherLink(
                      context,
                      controller: controller,
                      link: link,
                    ),
                  ),
              ],
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TeacherPortrait(photoUrl: teacher.photoUrl, size: 112),
                SizedBox(height: tokens.space16),
                information,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TeacherPortrait(photoUrl: teacher.photoUrl, size: 144),
              SizedBox(width: tokens.space24),
              Expanded(child: information),
            ],
          );
        },
      ),
    );
  }
}

class _TeacherTextSection extends StatelessWidget {
  const _TeacherTextSection({required this.primary, required this.secondary});

  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (primary.isNotEmpty)
            SelectableText(primary, style: const TextStyle(height: 1.7)),
          if (primary.isNotEmpty && secondary.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.space16),
              child: Divider(height: 1, color: tokens.border),
            ),
          if (secondary.isNotEmpty)
            SelectableText(secondary, style: const TextStyle(height: 1.7)),
        ],
      ),
    );
  }
}

class _TeacherLinkGroup extends StatelessWidget {
  const _TeacherLinkGroup({
    required this.title,
    required this.icon,
    required this.links,
    required this.onOpen,
  });

  final String title;
  final IconData icon;
  final List<OfficialTeacherLink> links;
  final ValueChanged<OfficialTeacherLink> onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: Icon(icon, size: 18, color: tokens.textSecondary),
          ),
          SizedBox(width: tokens.space8),
          SizedBox(
            width: 80,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: BnbuText(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: tokens.space8,
              runSpacing: tokens.space8,
              children: [
                for (final link in links)
                  ActionChip(
                    avatar: link.url.isEmpty
                        ? null
                        : const Icon(LucideIcons.externalLink300, size: 16),
                    label: BnbuText(link.name),
                    onPressed: link.url.isEmpty ? null : () => onOpen(link),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherProfileSection extends StatelessWidget {
  const _TeacherProfileSection({
    required this.controller,
    required this.section,
  });

  final AppSessionController controller;
  final OfficialTeacherSection section;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < section.items.length; index++) ...[
            if (index > 0)
              Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.space12),
                child: Divider(height: 1, color: tokens.border),
              ),
            if (section.items[index].title.isNotEmpty)
              SelectableText(
                section.items[index].title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1.55,
                ),
              ),
            if (section.items[index].title.isNotEmpty &&
                section.items[index].content.isNotEmpty)
              SizedBox(height: tokens.space8),
            if (section.items[index].content.isNotEmpty)
              SelectableText(
                section.items[index].content,
                style: const TextStyle(height: 1.7),
              ),
            if (section.items[index].link.isNotEmpty) ...[
              SizedBox(height: tokens.space8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => _openTeacherLink(
                    context,
                    controller: controller,
                    link: OfficialTeacherLink(
                      name: section.items[index].title.isEmpty
                          ? section.name
                          : section.items[index].title,
                      url: section.items[index].link,
                    ),
                  ),
                  icon: const Icon(LucideIcons.externalLink300, size: 18),
                  label: const BnbuText('打开'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _OrganizationTile extends StatelessWidget {
  const _OrganizationTile({
    required this.organization,
    required this.selected,
    required this.onTap,
  });

  final CampusDirectoryOrganization organization;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final theme = Theme.of(context);
    return Material(
      color: selected ? tokens.selectedSurface : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: EdgeInsets.all(tokens.space12),
            child: Row(
              children: [
                CampusOrganizationAvatar(
                  organization: organization,
                  diameter: 44,
                ),
                SizedBox(width: tokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      BnbuText(
                        organization.nameCn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: tokens.space4),
                      BnbuText(
                        organization.nameEn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight300, color: tokens.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContactChip extends StatelessWidget {
  const _ContactChip({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(tokens.radius12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radius12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 17, color: tokens.textSecondary),
                SizedBox(width: tokens.space8),
                Flexible(
                  child: BnbuText(
                    label,
                    style: TextStyle(color: tokens.textPrimary),
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

Future<void> _openOfficialPage(
  BuildContext context, {
  required AppSessionController controller,
  required String title,
  required String url,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) =>
          OfficialWebPage(controller: controller, title: title, url: url),
    ),
  );
}

Future<void> _launchPhone(String phone) {
  final number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  return launchUrl(Uri(scheme: 'tel', path: number));
}

Future<void> _openTeacherLink(
  BuildContext context, {
  required AppSessionController controller,
  required OfficialTeacherLink link,
}) {
  final uri = Uri.tryParse(link.url);
  final host = uri?.host.toLowerCase() ?? '';
  if (uri != null &&
      uri.scheme == 'https' &&
      (host == 'bnbu.edu.cn' || host.endsWith('.bnbu.edu.cn'))) {
    return _openOfficialPage(
      context,
      controller: controller,
      title: link.name,
      url: link.url,
    );
  }
  if (uri == null || uri.scheme != 'https') return Future<void>.value();
  return launchUrl(uri, mode: LaunchMode.externalApplication).then((_) {});
}

class _DirectorySyncStatus extends StatelessWidget {
  const _DirectorySyncStatus({this.sync});
  final DirectorySyncInfo? sync;
  @override
  Widget build(BuildContext context) {
    final value = sync;
    if (value == null) return const SizedBox.shrink();
    final stamp = value.lastSuccessAt?.toUtc().add(const Duration(hours: 8));
    final time = stamp == null
        ? ''
        : '${stamp.year}-${stamp.month.toString().padLeft(2, '0')}-${stamp.day.toString().padLeft(2, '0')} ${stamp.hour.toString().padLeft(2, '0')}:${stamp.minute.toString().padLeft(2, '0')}';
    final status =
        value.status == 'stale' ||
            (value.lastSuccessAt != null &&
                DateTime.now().toUtc().difference(
                      value.lastSuccessAt!.toUtc(),
                    ) >
                    const Duration(hours: 36))
        ? '沿用上次资料'
        : stamp == null
        ? '尚未核验'
        : '最近核验';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Semantics(
        liveRegion: true,
        child: Text(
          '${context.l10n.text(status)}${time.isEmpty ? '' : ' $time (${context.l10n.text('北京时间')})'}',
        ),
      ),
    );
  }
}
