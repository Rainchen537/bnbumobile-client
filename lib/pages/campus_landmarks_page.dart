import '../models/assistant_models.dart';
import '../services/assistant_context_coordinator.dart';
import '../widgets/assistant_context_scope.dart';
import '../state/app_session_controller.dart';
import '../widgets/landmark_share_sheet.dart';
import '../services/landmark_review_service.dart';
import '../widgets/landmark_reviews_section.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/campus_landmark.dart';
import '../services/campus_landmark_store.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_reveal_search.dart';
import '../widgets/landmark_photo_view.dart';
import '../widgets/landmark_gallery_page.dart';
import '../widgets/me_life_catalog.dart';
import '../widgets/me_life_content.dart';
import '../widgets/me_life_badge.dart' show LifeSheetPhysics;
export '../widgets/landmark_photo_view.dart';
import 'campus_navigation_page.dart';

class CampusLandmarksPage extends StatefulWidget {
  const CampusLandmarksPage({
    super.key,
    this.store,
    this.owner = 'local',
    this.reviewService,
    this.controller,
  });
  final LandmarkReviewService? reviewService;
  final AppSessionController? controller;
  final CampusLandmarkStore? store;
  final String owner;
  @override
  State<CampusLandmarksPage> createState() => _CampusLandmarksPageState();
}

class _CampusLandmarksPageState extends State<CampusLandmarksPage>
    with WidgetsBindingObserver {
  late final store = widget.store ?? CampusLandmarkStore.shared;
  final search = TextEditingController();
  final searchFocus = FocusNode();
  void _searchFocusChanged() => setState(() {});
  String? categoryId, subcategoryId;
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
          pageType: 'me_life',
          title: 'ME生活',
          selectedItemId: subcategoryId ?? categoryId ?? '',
          summary: 'catalog_version=${store.catalog?.version ?? 0}',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    searchFocus.addListener(_searchFocusChanged);
    unawaited(store.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Content is refreshed only by explicit navigation or user actions.
  }

  @override
  void dispose() {
    _contextRegistration?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    searchFocus.removeListener(_searchFocusChanged);
    searchFocus.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final data = store.catalog;
      final roots =
          data?.categories.where((c) => c.parentId == null).toList() ?? [];
      final selected = roots.any((c) => c.id == categoryId)
          ? categoryId
          : roots.firstOrNull?.id;
      final children =
          data?.categories.where((c) => c.parentId == selected).toList() ?? [];
      final childId = children.any((c) => c.id == subcategoryId)
          ? subcategoryId
          : null;
      final allowed = {selected, ...children.map((c) => c.id)};
      final query = search.text.trim().toLowerCase();
      final items = store.rankedLandmarks
          .where(
            (i) =>
                (query.isNotEmpty ||
                    (childId == null
                        ? allowed.contains(i.categoryId)
                        : i.categoryId == childId)) &&
                (query.isEmpty ||
                    [
                      ...i.names.values,
                      ...i.aliases,
                      ...i.locations.values,
                    ].any((t) => t.toLowerCase().contains(query))),
          )
          .toList();
      if (MediaQuery.sizeOf(context).width < 700) {
        return MeLifeMobileCatalog(
          store: store,
          onOpen: (item) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CampusLandmarkDetailPage(
                id: item.id,
                store: store,
                owner: widget.owner,
                reviewService: widget.reviewService,
                controller: widget.controller,
              ),
            ),
          ),
        );
      }
      return Scaffold(
        backgroundColor: context.bnbuTheme.canvas,
        appBar: BnbuSecondaryAppBar(
          bar: AppBar(
            title: Text(
              data == null
                  ? context.l10n.text('ME生活')
                  : landmarkText(data.title, context, data.defaultLanguage),
            ),
            actions: [
              IconButton(
                onPressed: store.refreshing ? null : store.refresh,
                tooltip: context.l10n.text('刷新'),
                icon: const Icon(LucideIcons.refreshCw300),
              ),
            ],
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 2,
                child: store.refreshing && data != null
                    ? const LinearProgressIndicator(minHeight: 2)
                    : null,
              ),
              Expanded(
                child: data == null
                    ? Center(
                        child: store.failed
                            ? TextButton.icon(
                                onPressed: store.refresh,
                                icon: const Icon(LucideIcons.rotateCw300),
                                label: const BnbuText('重试'),
                              )
                            : const CircularProgressIndicator(),
                      )
                    : RefreshIndicator(
                        onRefresh: store.refresh,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth < 1000 ? 1 : 2;
                            final list = CustomScrollView(
                              key: const PageStorageKey('campus-landmark-list'),
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 1440,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        child: Column(
                                          children: [
                                            if (columns >= 1)
                                              _searchField(soft: false),
                                            if (query.isEmpty)
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  children: roots
                                                      .map(
                                                        (c) => TextButton(
                                                          onPressed: () =>
                                                              setState(() {
                                                                categoryId =
                                                                    c.id;
                                                                subcategoryId =
                                                                    null;
                                                              }),
                                                          style: TextButton.styleFrom(
                                                            foregroundColor:
                                                                c.id == selected
                                                                ? Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary
                                                                : Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurface,
                                                            textStyle: TextStyle(
                                                              fontSize: 17,
                                                              fontWeight:
                                                                  c.id ==
                                                                      selected
                                                                  ? FontWeight
                                                                        .w600
                                                                  : FontWeight
                                                                        .w400,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            landmarkText(
                                                              c.names,
                                                              context,
                                                              data.defaultLanguage,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                                ),
                                              ),
                                            if (query.isEmpty &&
                                                children.isNotEmpty)
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: Wrap(
                                                  spacing: 8,
                                                  children: [
                                                    ChoiceChip(
                                                      label: const BnbuText(
                                                        '全部',
                                                      ),
                                                      selected: childId == null,
                                                      onSelected: (_) =>
                                                          setState(
                                                            () =>
                                                                subcategoryId =
                                                                    null,
                                                          ),
                                                    ),
                                                    ...children.map(
                                                      (c) => ChoiceChip(
                                                        label: Text(
                                                          landmarkText(
                                                            c.names,
                                                            context,
                                                            data.defaultLanguage,
                                                          ),
                                                        ),
                                                        selected:
                                                            childId == c.id,
                                                        onSelected: (_) =>
                                                            setState(
                                                              () =>
                                                                  subcategoryId =
                                                                      c.id,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (store.failed)
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: TextButton.icon(
                                                  onPressed: store.refresh,
                                                  icon: const Icon(
                                                    LucideIcons.rotateCw300,
                                                    size: 16,
                                                  ),
                                                  label: const BnbuText('重试'),
                                                ),
                                              ),
                                            const SizedBox(height: 8),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (items.isEmpty)
                                  const SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: Center(child: BnbuText('暂无内容')),
                                  )
                                else
                                  SliverList.builder(
                                    itemCount: (items.length / columns).ceil(),
                                    itemBuilder: (context, row) => Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 1440,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            8,
                                            0,
                                            8,
                                            8,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              for (
                                                var col = 0;
                                                col < columns;
                                                col++
                                              ) ...[
                                                if (col > 0)
                                                  const SizedBox(width: 8),
                                                Expanded(
                                                  child:
                                                      row * columns + col >=
                                                          items.length
                                                      ? const SizedBox.shrink()
                                                      : _card(
                                                          context,
                                                          data,
                                                          items[row * columns +
                                                              col],
                                                          compact: columns == 2,
                                                        ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                            if (columns >= 1) return list;
                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: _searchField(soft: true),
                                ),
                                Expanded(
                                  child: BnbuSoftSearchBody(
                                    active:
                                        searchFocus.hasFocus && query.isEmpty,
                                    onDismiss: searchFocus.unfocus,
                                    child: list,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _searchField({required bool soft}) => BnbuRevealSearch(
    controller: search,
    focusNode: searchFocus,
    softMode: soft,
    collapseOnTapOutside: true,
    onChanged: (_) => setState(() {}),
    controlKey: const ValueKey('campus-landmarks-search'),
  );

  Widget _card(
    BuildContext context,
    LandmarkCatalog data,
    CampusLandmark item, {
    required bool compact,
  }) {
    return LifeUnitRow(
      key: ValueKey('life-unit-${item.id}'),
      item: item,
      catalog: data,
      store: store,
      epoch: store.presentationEpoch,
      scale: 1.1,
      onOpen: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CampusLandmarkDetailPage(
            id: item.id,
            store: store,
            owner: widget.owner,
            reviewService: widget.reviewService,
            controller: widget.controller,
          ),
        ),
      ),
    );
  }
}

class CampusLandmarkDetailPage extends StatefulWidget {
  const CampusLandmarkDetailPage({
    super.key,
    required this.id,
    required this.store,
    this.owner = 'local',
    this.reviewService,
    this.controller,
  });
  final LandmarkReviewService? reviewService;
  final AppSessionController? controller;
  final String owner, id;
  final CampusLandmarkStore store;
  @override
  State<CampusLandmarkDetailPage> createState() =>
      _CampusLandmarkDetailPageState();
}

class _CampusLandmarkDetailPageState extends State<CampusLandmarkDetailPage> {
  final scroll = ScrollController();
  final toolbar = ValueNotifier<Widget?>(null);
  final commentsKey = GlobalKey();
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
        currentPage: () {
          final item = widget.store.catalog?.landmarks
              .where((i) => i.id == widget.id)
              .firstOrNull;
          return AssistantCurrentPageContext(
            pageType: 'me_life_detail',
            title: item?.names.values.firstOrNull ?? 'ME生活',
            selectedItemId: item?.id ?? '',
            summary: 'catalog_version=${widget.store.catalog?.version ?? 0}',
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _contextRegistration?.dispose();
    scroll.dispose();
    toolbar.dispose();
    super.dispose();
  }

  void gallery(CampusLandmark item, String title) {
    if (item.photos.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LandmarkGalleryPage(
          store: widget.store,
          photos: item.photos,
          title: title,
          initialPhotoId: item.cover?.id,
          defaultLanguage: widget.store.catalog!.defaultLanguage,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final data = widget.store.catalog;
      final item = data?.landmarks.where((i) => i.id == widget.id).firstOrNull;
      if (item == null) {
        return Scaffold(
          appBar: BnbuSecondaryAppBar(
            bar: AppBar(title: const BnbuText('ME生活')),
          ),
          body: const Center(child: BnbuText('暂无内容')),
        );
      }
      final title = landmarkText(item.names, context, data!.defaultLanguage);
      final description = landmarkText(
        item.descriptions,
        context,
        data.defaultLanguage,
      );
      final location = landmarkText(
        item.locations,
        context,
        data.defaultLanguage,
      );
      final hours = landmarkText(
        item.openingHours,
        context,
        data.defaultLanguage,
      );
      final thumb = item.avatar ?? item.cover;
      final theme = context.bnbuTheme;
      final top = MediaQuery.paddingOf(context).top;
      return LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 700;
          final headerHeight = top + (wide ? 180.0 : 72.0);
          final avatarHeight = wide ? 120.0 : 90.0;
          final avatarWidth = avatarHeight * item.avatarRatio;
          final textScale = MediaQuery.textScalerOf(context).scale(20) / 20;
          final stacked = constraints.maxWidth < 360 && textScale > 1.3;
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                key: const ValueKey('landmark-detail-title'),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: theme.textPrimary,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LifeIconRow(
                  item: item,
                  language: data.defaultLanguage,
                  detail: true,
                ),
              ),
              if (hours.isNotEmpty &&
                  !item.iconRow.any((e) => e.source == 'hours'))
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    hours,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: theme.textMuted,
                    ),
                  ),
                ),
              if (item.longitude != null)
                InkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CampusNavigationPage(
                        owner: widget.owner,
                        initialLandmark: item,
                        landmarkName: title,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.mapPin300,
                          size: 15,
                          color: theme.brandBlue,
                        ),
                        const SizedBox(width: 5),
                        const BnbuText('查看位置'),
                      ],
                    ),
                  ),
                ),
            ],
          );
          return Scaffold(
            backgroundColor: theme.surface,
            bottomNavigationBar: ValueListenableBuilder<Widget?>(
              valueListenable: toolbar,
              builder: (context, child, _) => child ?? const SizedBox.shrink(),
            ),
            body: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ConstrainedBox(
                      key: const ValueKey('landmark-fixed-background'),
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: SizedBox(
                        height: headerHeight + 30,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRect(
                              child: ImageFiltered(
                                imageFilter: ui.ImageFilter.blur(
                                  sigmaX: 12,
                                  sigmaY: 12,
                                ),
                                child: Transform.scale(
                                  scale: 1.12,
                                  child: LandmarkPhotoView(
                                    store: widget.store,
                                    photo: item.cover,
                                    full: true,
                                    label: title,
                                  ),
                                ),
                              ),
                            ),
                            const IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0x35000000),
                                      Color(0x18000000),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  controller: scroll,
                  physics: const LifeSheetPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  key: const ValueKey('landmark-detail-scroll'),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Stack(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(top: headerHeight),
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.surface,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(12),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            minHeight: avatarHeight + 4,
                                          ),
                                          child: Padding(
                                            padding: EdgeInsets.fromLTRB(
                                              stacked ? 0 : avatarWidth + 8,
                                              stacked ? avatarHeight + 2 : 14,
                                              0,
                                              16,
                                            ),
                                            child: info,
                                          ),
                                        ),
                                        Positioned(
                                          top: -12,
                                          left: 0,
                                          child: SizedBox(
                                            width: avatarWidth,
                                            height: avatarHeight,
                                            child: Material(
                                              color: theme.canvas,
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    item.avatarRatio > 1
                                                        ? 5
                                                        : 2,
                                                  ),
                                              clipBehavior: Clip.antiAlias,
                                              child: InkWell(
                                                key: const ValueKey(
                                                  'landmark-open-gallery',
                                                ),
                                                onTap: () =>
                                                    gallery(item, title),
                                                child: IgnorePointer(
                                                  child: LandmarkPhotoView(
                                                    store: widget.store,
                                                    photo: thumb,
                                                    full: true,
                                                    label: title,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      12,
                                    ),
                                    child: LifeTagStrip(
                                      key: ValueKey('detail-tags-${item.id}'),
                                      expandable: true,
                                      children: lifeUnitBadges(
                                        context,
                                        item,
                                        data,
                                        detail: true,
                                      ),
                                    ),
                                  ),
                                  if (description.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        0,
                                        16,
                                        18,
                                      ),
                                      child: SelectableText(
                                        description,
                                        key: const ValueKey(
                                          'landmark-full-description',
                                        ),
                                        style: TextStyle(
                                          fontSize: 13,
                                          height: 1.5,
                                          color: theme.textSecondary,
                                        ),
                                      ),
                                    ),
                                  LifeEvidenceDetails(
                                    key: ValueKey('evidence-${item.id}'),
                                    item: item,
                                    catalog: data,
                                  ),
                                  LandmarkReviewsSection(
                                    key: ValueKey('reviews-${widget.id}'),
                                    landmarkId: item.id,
                                    username: widget.owner == 'local'
                                        ? null
                                        : widget.owner,
                                    service: widget.reviewService,
                                    policyStore: widget.reviewService == null
                                        ? widget.store
                                        : null,
                                    controller: widget.controller,
                                    title: title,
                                    loadPlacePhoto: thumb == null
                                        ? null
                                        : () async => LandmarkPhotoView(
                                            store: widget.store,
                                            photo: thumb,
                                            fit: BoxFit.cover,
                                            label: title,
                                          ),
                                    toolbar: toolbar,
                                    commentsKey: commentsKey,
                                    onShare: (page, comment) async {
                                      final photo = thumb == null
                                          ? null
                                          : await widget.store.photo(
                                              thumb,
                                              full: true,
                                            );
                                      if (!context.mounted) return;
                                      await showLandmarkShare(
                                        context,
                                        id: item.id,
                                        title: title,
                                        subtitle: location,
                                        image: photo,
                                        comment: comment,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: scroll,
                  builder: (context, _) {
                    final offset = scroll.hasClients ? scroll.offset : 0.0;
                    // The large title reaches the toolbar before the rest of the card.
                    final progress =
                        ((offset - (headerHeight + 14 - top - 44)) / 26).clamp(
                          0.0,
                          1.0,
                        );
                    final color = wide
                        ? theme.textPrimary
                        : Color.lerp(
                            Colors.white,
                            theme.textPrimary,
                            progress,
                          )!;
                    return Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: ColoredBox(
                        color: theme.surface.withValues(alpha: progress),
                        child: Padding(
                          padding: EdgeInsets.only(top: top),
                          child: SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: context.l10n.text('返回'),
                                  color: color,
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  icon: const Icon(
                                    LucideIcons.chevronLeft300,
                                    size: 24,
                                  ),
                                ),
                                Expanded(
                                  child: Opacity(
                                    key: const ValueKey(
                                      'landmark-navbar-title',
                                    ),
                                    opacity: progress,
                                    child: Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class LandmarkGallery extends StatefulWidget {
  const LandmarkGallery({
    super.key,
    required this.store,
    required this.photos,
    required this.title,
    this.initialPhotoId,
  });
  final CampusLandmarkStore store;
  final List<LandmarkPhoto> photos;
  final String title;
  final String? initialPhotoId;
  @override
  State<LandmarkGallery> createState() => _LandmarkGalleryState();
}

class _LandmarkGalleryState extends State<LandmarkGallery> {
  late int index = widget.photos
      .indexWhere((p) => p.id == widget.initialPhotoId)
      .clamp(0, widget.photos.length);
  late final controller = PageController(initialPage: index);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LandmarkGallery old) {
    super.didUpdateWidget(old);
    if (old.photos.map((p) => p.id).join() !=
        widget.photos.map((p) => p.id).join()) {
      index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.hasClients) controller.jumpToPage(0);
      });
    }
  }

  void go(int next) {
    if (next < 0 || next >= widget.photos.length) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(next);
    } else {
      controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: SizedBox(
            key: const ValueKey('landmark-gallery-frame'),
            height: (constraints.maxWidth * 0.6).clamp(160.0, 260.0),
            child: widget.photos.isEmpty
                ? LandmarkPhotoView(store: widget.store, label: widget.title)
                : PageView.builder(
                    controller: controller,
                    itemCount: widget.photos.length,
                    onPageChanged: (v) => setState(() => index = v),
                    itemBuilder: (context, i) => LandmarkPhotoView(
                      key: ValueKey(widget.photos[i].id),
                      store: widget.store,
                      photo: widget.photos[i],
                      full: true,
                      fit: BoxFit.cover,
                      label: '${widget.title} ${i + 1}/${widget.photos.length}',
                    ),
                  ),
          ),
        ),
        if (widget.photos.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('landmark-gallery-previous'),
                tooltip: context.l10n.text('上一张'),
                onPressed: index > 0 ? () => go(index - 1) : null,
                icon: const Icon(LucideIcons.chevronLeft300, size: 20),
              ),
              Text(
                '${index + 1} / ${widget.photos.length}',
                style: TextStyle(
                  fontSize: 13,
                  color: context.bnbuTheme.textSecondary,
                ),
              ),
              IconButton(
                key: const ValueKey('landmark-gallery-next'),
                tooltip: context.l10n.text('下一张'),
                onPressed: index + 1 < widget.photos.length
                    ? () => go(index + 1)
                    : null,
                icon: const Icon(LucideIcons.chevronRight300, size: 20),
              ),
            ],
          ),
      ],
    ),
  );
}
