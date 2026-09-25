import '../models/campus_landmark.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/assistant_models.dart';
import '../models/campus_place.dart';
import '../models/campus_user_place.dart';
import '../models/web_session_snapshot.dart';
import '../services/assistant_context_coordinator.dart';
import '../services/campus_user_place_store.dart';
import '../theme/app_theme.dart';
import '../widgets/assistant_context_scope.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_adaptive_modal.dart';
import '../widgets/bnbu_creation_form.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/bnbu_reveal_search.dart';
import '../widgets/native_mirror_webview.dart';
import 'official_campus_map_page.dart';

typedef CampusMapViewBuilder =
    Widget Function(BuildContext context, NativeMirrorWebView webView);

class CampusNavigationPage extends StatefulWidget {
  const CampusNavigationPage({
    super.key,
    this.initialQuery = '',
    this.initialLandmark,
    this.landmarkName,
    this.owner = 'local',
    this.userPlaceStore,
    this.mapViewBuilder,
  });

  final String initialQuery;
  final CampusLandmark? initialLandmark;
  final String? landmarkName;
  final String owner;
  final CampusUserPlaceStore? userPlaceStore;
  final CampusMapViewBuilder? mapViewBuilder;

  @override
  State<CampusNavigationPage> createState() => _CampusNavigationPageState();
}

class _CampusNavigationPageState extends State<CampusNavigationPage> {
  static const _campusSearchName = '北京师范大学-香港浸会大学联合国际学院';
  static const _mapResourceDomains = <String>[
    'amap.com',
    'autonavi.com',
    'alicdn.com',
  ];

  final TextEditingController _searchController = TextEditingController();
  final NativeMirrorWebViewController _mapController =
      NativeMirrorWebViewController();
  late final CampusUserPlaceStore _userPlaceStore;
  late final String _mapOrigin;
  late final String _mapUrl;
  late final WebSessionSnapshot _mapSession;
  AssistantContextCoordinator? _contextCoordinator;
  AssistantContextRegistration? _contextRegistration;
  CampusPlace _selectedPlace = campusPlaces.first;
  CampusUserPlace? _selectedUserPlace;
  List<CampusUserPlace> _userPlaces = const <CampusUserPlace>[];
  bool _isLoadingUserPlaces = true;
  bool _isAddingUserPlace = false;
  bool _mapReady = false;
  String _query = '';
  late bool _landmarkSelected = widget.initialLandmark?.longitude != null;

  @override
  void initState() {
    super.initState();
    final syncBaseUrl = AppConfig.normalizedHttpsBaseUrl(
      AppConfig.syncServiceBaseUrl,
      settingName: 'SYNC_SERVICE_BASE_URL',
    );
    final syncUri = Uri.parse(syncBaseUrl);
    _mapOrigin = syncUri
        .replace(path: '', query: null, fragment: null)
        .toString();
    _mapUrl = '$syncBaseUrl/public/campus-map';
    _mapSession = WebSessionSnapshot(
      baseUrl: _mapOrigin,
      cookies: const <WebSessionCookie>[],
      allowedOrigins: <String>[_mapOrigin],
      allowedDomains: const <String>[],
      useEphemeralSession: true,
    );
    _userPlaceStore =
        widget.userPlaceStore ?? SharedPreferencesCampusUserPlaceStore();
    _loadUserPlaces();
    final initialQuery = widget.initialQuery.trim();
    if (initialQuery.isEmpty) {
      return;
    }
    _query = initialQuery;
    _searchController.text = initialQuery;
    for (final place in campusPlaces) {
      if (place.matches(initialQuery)) {
        _selectedPlace = place;
        break;
      }
    }
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
        currentPage: () => AssistantCurrentPageContext(
          pageType: 'campus_navigation',
          title: _landmarkSelected
              ? '校园导航'
              : _selectedUserPlace == null
              ? _selectedPlace.displayName
              : '我的地点',
          selectedItemId: !_landmarkSelected && _selectedUserPlace == null
              ? _selectedPlace.id
              : '',
          summary: !_landmarkSelected && _selectedUserPlace == null
              ? _selectedPlace.areaHint
              : '',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _contextRegistration?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<CampusPlace> get _matches {
    final matches = campusPlaces
        .where((place) => place.matches(_query))
        .toList(growable: false);
    if (_query.trim().isEmpty) {
      return matches.take(8).toList(growable: false);
    }
    return matches.take(12).toList(growable: false);
  }

  List<CampusUserPlace> get _userPlaceMatches => _userPlaces
      .where((place) => place.matches(_query))
      .take(12)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: BnbuSecondaryAppBar(
        bar: AppBar(
          title: const BnbuText('校园导航'),
          actions: [
            IconButton(
              tooltip: context.l10n.text('打开官方校园地图'),
              onPressed: _openOfficialMap,
              icon: const Icon(LucideIcons.externalLink300),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final windowClass = BnbuBreakpoints.fromWidth(constraints.maxWidth);
            final padding = EdgeInsets.fromLTRB(
              windowClass == BnbuWindowClass.compact
                  ? tokens.space16
                  : tokens.space24,
              tokens.space12,
              windowClass == BnbuWindowClass.compact
                  ? tokens.space16
                  : tokens.space24,
              tokens.space32,
            );
            if (windowClass == BnbuWindowClass.compact) {
              return ListView(
                padding: padding,
                children: [
                  _buildSearchField(
                    context,
                    mode: BnbuRevealSearchMode.pageCentered,
                  ),
                  SizedBox(height: tokens.space16),
                  _buildMapCard(context, aspectRatio: 0.92),
                  SizedBox(height: tokens.space12),
                  _buildSearchResults(context),
                  if (_userPlaceMatches.isNotEmpty) ...[
                    SizedBox(height: tokens.space12),
                    _buildUserPlaceResults(context),
                  ],
                  SizedBox(height: tokens.space16),
                  _buildPlaceCard(context),
                ],
              );
            }
            return SingleChildScrollView(
              padding: padding,
              child: BnbuConstrainedContent(
                maxWidth: 1280,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildSearchField(
                            context,
                            mode: BnbuRevealSearchMode.local,
                          ),
                          SizedBox(height: tokens.space12),
                          _buildSearchResults(context),
                          if (_userPlaceMatches.isNotEmpty) ...[
                            SizedBox(height: tokens.space12),
                            _buildUserPlaceResults(context),
                          ],
                          SizedBox(height: tokens.space16),
                          _buildPlaceCard(context),
                        ],
                      ),
                    ),
                    SizedBox(width: tokens.space24),
                    Expanded(
                      flex: 7,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_buildMapCard(context, aspectRatio: 1.28)],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchField(
    BuildContext context, {
    required BnbuRevealSearchMode mode,
  }) {
    return BnbuRevealSearch(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      hintText: context.l10n.text('搜索 T3、格物楼、图书馆或 T3-602'),
      mode: mode,
      softMode: mode == BnbuRevealSearchMode.pageCentered,
      controlKey: const ValueKey('campus-navigation-search'),
      closeKey: const ValueKey('campus-navigation-search-close'),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final matches = _matches;
    if (matches.isEmpty) {
      return const BnbuNotice(
        message: '没有找到对应楼宇。可尝试输入楼号、中文名、英文名或房间前缀。',
        kind: BnbuStatusKind.warning,
      );
    }
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: matches.length,
        separatorBuilder: (_, _) => SizedBox(width: context.bnbuTheme.space8),
        itemBuilder: (context, index) {
          final place = matches[index];
          return TextFieldTapRegion(
            child: ChoiceChip(
              label: BnbuText(place.displayName),
              selected:
                  !_landmarkSelected &&
                  _selectedUserPlace == null &&
                  place.id == _selectedPlace.id,
              onSelected: (_) => _selectPlace(place),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUserPlaceResults(BuildContext context) {
    final matches = _userPlaceMatches;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BnbuText(
          '我的地点',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: context.bnbuTheme.space8),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: matches.length,
            separatorBuilder: (_, _) =>
                SizedBox(width: context.bnbuTheme.space8),
            itemBuilder: (context, index) {
              final place = matches[index];
              return TextFieldTapRegion(
                child: ChoiceChip(
                  avatar: const Icon(LucideIcons.bookmark300, size: 16),
                  label: BnbuText(place.name),
                  selected: place.id == _selectedUserPlace?.id,
                  onSelected: (_) => _selectUserPlace(place),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMapCard(BuildContext context, {required double aspectRatio}) {
    final webView = NativeMirrorWebView(
      key: const ValueKey('campus-amap-sdk-view'),
      content: NativeWebContent.url(_mapUrl),
      session: _mapSession,
      controller: _mapController,
      participatesInSessionCleanup: false,
      resourceOnlyDomains: _mapResourceDomains,
      onNavigationBlocked: _handleMapNavigation,
      errorTitle: '高德地图加载失败',
      errorMessage: '请检查网络后重新加载。',
      onRetry: _mapController.reload,
      showLoadingIndicator: false,
    );
    final mapContent = widget.mapViewBuilder?.call(context, webView) ?? webView;
    return BnbuSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              context.bnbuTheme.space12,
              context.bnbuTheme.space12,
              context.bnbuTheme.space8,
              context.bnbuTheme.space8,
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.map300, size: 18),
                SizedBox(width: context.bnbuTheme.space8),
                const Expanded(child: BnbuText('高德校园地图')),
                TextButton.icon(
                  key: const ValueKey('campus-add-place-button'),
                  onPressed: _isLoadingUserPlaces
                      ? null
                      : _toggleAddingUserPlace,
                  icon: Icon(
                    _isAddingUserPlace
                        ? LucideIcons.x300
                        : LucideIcons.mapPinPlus300,
                    size: 18,
                  ),
                  label: BnbuText(_isAddingUserPlace ? '取消选点' : '标记地点'),
                ),
                IconButton(
                  tooltip: context.l10n.text('重置地图'),
                  onPressed: _syncMapState,
                  icon: const Icon(LucideIcons.focus300),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(context.bnbuTheme.radius16),
              ),
              child: mapContent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceCard(BuildContext context) {
    if (_landmarkSelected) {
      return BnbuSurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Text(
          widget.landmarkName ?? '',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      );
    }
    final userPlace = _selectedUserPlace;
    if (userPlace != null) {
      return _buildUserPlaceCard(context, userPlace);
    }
    final place = _selectedPlace;
    final tokens = context.bnbuTheme;
    return BnbuSurfaceCard(
      padding: EdgeInsets.all(tokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.brandBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(tokens.radius12),
                  border: Border.all(
                    color: tokens.brandBlue.withValues(alpha: 0.14),
                  ),
                ),
                child: Icon(LucideIcons.mapPin300, color: tokens.brandBlue),
              ),
              SizedBox(width: tokens.space12),
              Expanded(
                child: BnbuText(
                  place.displayName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space16),
          OutlinedButton.icon(
            onPressed: _openOfficialMap,
            icon: const Icon(LucideIcons.globe2300),
            label: const BnbuText('官方地图'),
          ),
        ],
      ),
    );
  }

  Widget _buildUserPlaceCard(BuildContext context, CampusUserPlace place) {
    final tokens = context.bnbuTheme;
    return BnbuSurfaceCard(
      padding: EdgeInsets.all(tokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.brandBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(tokens.radius12),
                  border: Border.all(
                    color: tokens.brandBlue.withValues(alpha: 0.14),
                  ),
                ),
                child: Icon(LucideIcons.bookmark300, color: tokens.brandBlue),
              ),
              SizedBox(width: tokens.space12),
              Expanded(
                child: BnbuText(
                  place.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: context.l10n.text('编辑地点'),
                onPressed: () => _editUserPlace(place),
                icon: const Icon(LucideIcons.pencil300),
              ),
              IconButton(
                tooltip: context.l10n.text('删除地点'),
                onPressed: () => _confirmDeleteUserPlace(place),
                icon: const Icon(LucideIcons.trash2300),
              ),
            ],
          ),
          if (place.note.isNotEmpty) ...[
            SizedBox(height: tokens.space16),
            BnbuText(place.note),
          ],
        ],
      ),
    );
  }

  void _selectPlace(CampusPlace place) {
    setState(() {
      _landmarkSelected = false;
      _selectedPlace = place;
      _selectedUserPlace = null;
      _isAddingUserPlace = false;
    });
    unawaited(_syncMapState());
  }

  void _toggleAddingUserPlace() {
    final nextValue = !_isAddingUserPlace;
    setState(() => _isAddingUserPlace = nextValue);
    unawaited(_setMapMarkMode(nextValue));
  }

  void _selectUserPlace(CampusUserPlace place) {
    setState(() {
      _landmarkSelected = false;
      _selectedUserPlace = place;
      _isAddingUserPlace = false;
    });
    unawaited(_setMapMarkMode(false));
    unawaited(_syncMapState());
  }

  Future<void> _loadUserPlaces() async {
    try {
      final places = await _userPlaceStore.load(widget.owner);
      if (!mounted) return;
      setState(() {
        _userPlaces = places;
        _isLoadingUserPlaces = false;
      });
      unawaited(_syncMapState());
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingUserPlaces = false);
      BnbuToast.show(context, '我的地点加载失败', kind: BnbuToastKind.danger);
    }
  }

  void _handleMapNavigation(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'handsbnbu' ||
        uri.host != 'campus-map' ||
        uri.pathSegments.length != 1) {
      return;
    }
    switch (uri.pathSegments.single) {
      case 'ready':
        _mapReady = true;
        unawaited(_syncMapState());
        unawaited(_setMapMarkMode(_isAddingUserPlace));
      case 'tap':
        if (!_isAddingUserPlace) return;
        final longitude = double.tryParse(
          uri.queryParameters['longitude'] ?? '',
        );
        final latitude = double.tryParse(uri.queryParameters['latitude'] ?? '');
        if (longitude == null ||
            latitude == null ||
            !longitude.isFinite ||
            !latitude.isFinite ||
            longitude < -180 ||
            longitude > 180 ||
            latitude < -90 ||
            latitude > 90) {
          return;
        }
        unawaited(_handleMapTap(longitude, latitude));
      case 'select':
        final id = uri.queryParameters['id'];
        if (id == null) return;
        if (widget.initialLandmark != null &&
            id == 'landmark-${widget.initialLandmark!.id}') {
          setState(() {
            _landmarkSelected = true;
            _selectedUserPlace = null;
          });
          unawaited(_syncMapState());
          return;
        }
        for (final place in _userPlaces) {
          if (place.id == id) {
            _selectUserPlace(place);
            return;
          }
        }
    }
  }

  Future<void> _setMapMarkMode(bool enabled) async {
    if (!_mapReady) return;
    try {
      await _mapController.evaluateJavascript(
        'window.handsBnbuCampusMap && '
        'window.handsBnbuCampusMap.setMarkMode(${enabled ? 'true' : 'false'});',
      );
    } catch (_) {
      // Reload and the ready bridge will restore the current mode.
    }
  }

  Future<void> _syncMapState() async {
    if (!_mapReady) return;
    final state = <String, Object?>{
      'officialQuery': _landmarkSelected
          ? ''
          : _selectedUserPlace == null
          ? '$_campusSearchName ${_selectedPlace.displayName}'
          : '',
      'selectedUserId': _landmarkSelected
          ? 'landmark-${widget.initialLandmark!.id}'
          : _selectedUserPlace?.id ?? '',
      'userPlaces': [
        if (widget.initialLandmark?.longitude != null)
          {
            'id': 'landmark-${widget.initialLandmark!.id}',
            'name': widget.landmarkName ?? '',
            'longitude': widget.initialLandmark!.longitude,
            'latitude': widget.initialLandmark!.latitude,
          },
        ..._userPlaces
            .where((place) => place.longitude != null && place.latitude != null)
            .map(
              (place) => <String, Object?>{
                'id': place.id,
                'name': place.name,
                'longitude': place.longitude,
                'latitude': place.latitude,
              },
            ),
      ],
    };
    try {
      await _mapController.evaluateJavascript(
        'window.handsBnbuCampusMap && '
        'window.handsBnbuCampusMap.applyState(${jsonEncode(state)});',
      );
    } catch (_) {
      // The next ready event or explicit reset retries synchronization.
    }
  }

  Future<void> _handleMapTap(double longitude, double latitude) async {
    setState(() => _isAddingUserPlace = false);
    final draft = await _openUserPlaceEditor();
    if (draft == null || !mounted) return;
    final now = DateTime.now().toUtc();
    final place = CampusUserPlace(
      id: 'place-${now.microsecondsSinceEpoch}',
      name: draft.name,
      note: draft.note,
      longitude: longitude,
      latitude: latitude,
      createdAt: now,
      updatedAt: now,
    );
    if (_userPlaces.length >= SharedPreferencesCampusUserPlaceStore.maxPlaces) {
      BnbuToast.show(
        context,
        '最多保存 ${SharedPreferencesCampusUserPlaceStore.maxPlaces} 个地点',
        kind: BnbuToastKind.warning,
      );
      return;
    }
    final next = <CampusUserPlace>[place, ..._userPlaces];
    await _persistUserPlaces(next, selected: place, message: '地点已保存');
  }

  Future<void> _editUserPlace(CampusUserPlace place) async {
    final draft = await _openUserPlaceEditor(initialPlace: place);
    if (draft == null || !mounted) return;
    final updated = place.copyWith(
      name: draft.name,
      note: draft.note,
      updatedAt: DateTime.now().toUtc(),
    );
    final next = _userPlaces
        .map((item) => item.id == place.id ? updated : item)
        .toList(growable: false);
    await _persistUserPlaces(next, selected: updated, message: '地点已更新');
  }

  Future<void> _confirmDeleteUserPlace(CampusUserPlace place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const BnbuText('删除地点'),
        content: BnbuText(place.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const BnbuText('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(LucideIcons.trash2300),
            label: const BnbuText('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final next = _userPlaces
        .where((item) => item.id != place.id)
        .toList(growable: false);
    await _persistUserPlaces(next, selected: null, message: '地点已删除');
  }

  Future<void> _persistUserPlaces(
    List<CampusUserPlace> places, {
    required CampusUserPlace? selected,
    required String message,
  }) async {
    try {
      await _userPlaceStore.save(widget.owner, places);
      if (!mounted) return;
      setState(() {
        _userPlaces = List<CampusUserPlace>.unmodifiable(places);
        _landmarkSelected = false;
        _selectedUserPlace = selected;
      });
      unawaited(_syncMapState());
      BnbuToast.show(context, message, kind: BnbuToastKind.success);
    } catch (_) {
      if (!mounted) return;
      BnbuToast.show(context, '地点保存失败', kind: BnbuToastKind.danger);
    }
  }

  Future<_CampusUserPlaceDraft?> _openUserPlaceEditor({
    CampusUserPlace? initialPlace,
  }) {
    return showBnbuCreationModal<_CampusUserPlaceDraft>(
      context: context,
      maxWidth: 520,
      maxHeight: 440,
      semanticLabel: context.l10n.text(initialPlace == null ? '标记地点' : '编辑地点'),
      contentKey: const ValueKey('campus-user-place-editor'),
      builder: (modalContext, presentation) => _CampusUserPlaceEditor(
        presentation: presentation,
        initialPlace: initialPlace,
      ),
    );
  }

  Future<void> _openOfficialMap() {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const OfficialCampusMapPage()),
    );
  }
}

class _CampusUserPlaceDraft {
  const _CampusUserPlaceDraft({required this.name, required this.note});

  final String name;
  final String note;
}

class _CampusUserPlaceEditor extends StatefulWidget {
  const _CampusUserPlaceEditor({required this.presentation, this.initialPlace});

  final BnbuAdaptiveModalPresentation presentation;
  final CampusUserPlace? initialPlace;

  @override
  State<_CampusUserPlaceEditor> createState() => _CampusUserPlaceEditorState();
}

class _CampusUserPlaceEditorState extends State<_CampusUserPlaceEditor> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialPlace?.name ?? '',
  );
  late final TextEditingController _noteController = TextEditingController(
    text: widget.initialPlace?.note ?? '',
  );
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(
      _CampusUserPlaceDraft(
        name: _nameController.text.trim(),
        note: _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BnbuCreationForm(
      title: widget.initialPlace == null ? '标记地点' : '编辑地点',
      avoidKeyboard: !widget.presentation.isDialog,
      action: BnbuCreationAction(label: '保存', onPressed: _save),
      child: Form(
        key: _formKey,
        child: BnbuCreationGroup(
          children: [
            TextFormField(
              key: const ValueKey('campus-user-place-name'),
              controller: _nameController,
              autofocus: true,
              maxLength: 60,
              textInputAction: TextInputAction.next,
              style: BnbuCreationStyle.fieldText(context),
              decoration: BnbuCreationStyle.input(context, hint: '地点名称'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? context.l10n.text('请输入地点名称')
                  : null,
            ),
            TextFormField(
              key: const ValueKey('campus-user-place-note'),
              controller: _noteController,
              maxLength: 160,
              minLines: 3,
              maxLines: 5,
              style: BnbuCreationStyle.fieldText(context),
              decoration: BnbuCreationStyle.input(context, hint: '备注'),
            ),
          ],
        ),
      ),
    );
  }
}
