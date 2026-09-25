import 'landmark_policy_polling.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/campus_landmark.dart';
import '../models/me_life_presentation.dart';
import '../models/landmark_review.dart';
import '../services/campus_landmark_store.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive.dart';
import 'page_backdrop.dart';
import 'landmark_photo_view.dart';
import 'me_life_badge.dart';
import 'me_life_content.dart';
import 'bnbu_reveal_search.dart';

class MeLifeMobileCatalog extends StatefulWidget {
  const MeLifeMobileCatalog({
    super.key,
    required this.store,
    required this.onOpen,
  });
  final CampusLandmarkStore store;
  final ValueChanged<CampusLandmark> onOpen;
  @override
  State<MeLifeMobileCatalog> createState() => _MeLifeMobileCatalogState();
}

class _MeLifeMobileCatalogState extends State<MeLifeMobileCatalog> {
  final search = TextEditingController();
  final focus = FocusNode();
  String? categoryId, subcategoryId;
  String get query => search.text.trim().toLowerCase();
  void focusChanged() => setState(() {});
  @override
  void initState() {
    super.initState();
    focus.addListener(focusChanged);
  }

  @override
  void dispose() {
    focus.removeListener(focusChanged);
    search.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.store.catalog;
    final theme = context.bnbuTheme;
    final width = MediaQuery.sizeOf(context).width;
    final scale = (width / 402).clamp(0.75, 1.15);
    final roots =
        data?.categories.where((c) => c.parentId == null).toList() ?? [];
    final selected = roots.any((c) => c.id == categoryId)
        ? categoryId
        : roots.firstOrNull?.id;
    final children =
        data?.categories.where((c) => c.parentId == selected).toList() ?? [];
    final allowed = {selected, ...children.map((c) => c.id)};
    final items = widget.store.rankedLandmarks
        .where(
          (i) => query.isNotEmpty
              ? [
                  ...i.names.values,
                  ...i.aliases,
                  ...i.locations.values,
                ].any((t) => t.toLowerCase().contains(query))
              : subcategoryId != null
              ? i.categoryId == subcategoryId
              : allowed.contains(i.categoryId),
        )
        .toList();
    return Scaffold(
      backgroundColor: theme.canvas,
      body: PageHeaderOverlay(
        header: Stack(
          children: [
            const Positioned.fill(
              child: PageHeaderBackdrop(
                page: 'me-life',
                translucentTail: PageHeaderOverlay.tailHeight,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      BnbuSecondaryHeader(
                        child: BnbuSecondaryAppBar(
                          bar: AppBar(
                            primary: false,
                            systemOverlayStyle: AppTheme.statusBarStyle(
                              Theme.of(context).brightness,
                            ),
                            title: Text(
                              data == null
                                  ? 'ME生活'
                                  : landmarkText(
                                      data.title,
                                      context,
                                      data.defaultLanguage,
                                    ),
                            ),
                            backgroundColor: Colors.transparent,
                            foregroundColor: theme.textPrimary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          11 * scale,
                          0,
                          11 * scale,
                          9 * scale,
                        ),
                        child: BnbuRevealSearch(
                          controller: search,
                          focusNode: focus,
                          softMode: true,
                          collapseOnTapOutside: true,
                          onChanged: (_) => setState(() {}),
                          controlKey: const ValueKey('campus-landmarks-search'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (roots.isNotEmpty)
                  Material(
                    color: Colors.transparent,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final category in roots.take(5))
                          Expanded(
                            child: InkWell(
                              key: ValueKey('life-category-${category.id}'),
                              onTap: () {
                                setState(() {
                                  categoryId = category.id;
                                  subcategoryId = null;
                                  search.clear();
                                });
                                focus.unfocus();
                                unawaited(widget.store.refresh());
                              },
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  2,
                                  4 * scale,
                                  2,
                                  10 * scale,
                                ),
                                child: Column(
                                  children: [
                                    SizedBox(
                                      width: 54 * scale,
                                      height: 50 * scale,
                                      child: LifeCategoryImage(
                                        category: category,
                                        selected: category.id == selected,
                                        store: widget.store,
                                      ),
                                    ),
                                    SizedBox(height: 3 * scale),
                                    Text(
                                      landmarkText(
                                        category.names,
                                        context,
                                        data!.defaultLanguage,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      style: TextStyle(
                                        fontSize: 12.7 * scale,
                                        height: 1.2,
                                        fontWeight: category.id == selected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: category.id == selected
                                            ? theme.brandBlue
                                            : theme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (roots.length > 5)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final category in roots.skip(5))
                          TextButton(
                            onPressed: () => setState(() {
                              categoryId = category.id;
                              subcategoryId = null;
                            }),
                            child: Text(
                              landmarkText(
                                category.names,
                                context,
                                data!.defaultLanguage,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (children.isNotEmpty && query.isEmpty)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(() => subcategoryId = null),
                          child: const BnbuText('全部'),
                        ),
                        for (final c in children)
                          TextButton(
                            onPressed: () =>
                                setState(() => subcategoryId = c.id),
                            child: Text(
                              landmarkText(
                                c.names,
                                context,
                                data!.defaultLanguage,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                SizedBox(
                  height: 2,
                  child: widget.store.refreshing && data != null
                      ? const LinearProgressIndicator(minHeight: 2)
                      : null,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ],
        ),
        body: BnbuSoftSearchBody(
          active: focus.hasFocus && query.isEmpty,
          onDismiss: focus.unfocus,
          child: data == null
              ? Center(
                  child: widget.store.failed
                      ? TextButton(
                          onPressed: widget.store.refresh,
                          child: const BnbuText('重试'),
                        )
                      : const CircularProgressIndicator(),
                )
              : items.isEmpty
              ? Center(child: BnbuText(query.isEmpty ? '暂无内容' : '暂无搜索结果'))
              : ListView.builder(
                  key: const PageStorageKey('me-life-unit-list'),
                  padding: EdgeInsets.fromLTRB(
                    8.7 * scale,
                    8.7 * scale + PageHeaderOverlay.tailHeight,
                    8.7 * scale,
                    16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) => Padding(
                    padding: EdgeInsets.only(bottom: 8.3 * scale),
                    child: LifeUnitRow(
                      key: ValueKey('life-unit-${items[index].id}'),
                      item: items[index],
                      catalog: data,
                      store: widget.store,
                      epoch: widget.store.presentationEpoch,
                      scale: scale,
                      onOpen: () => widget.onOpen(items[index]),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class LifeCategoryImage extends StatelessWidget {
  const LifeCategoryImage({
    super.key,
    required this.category,
    required this.selected,
    required this.store,
  });
  final LandmarkCategory category;
  final bool selected;
  final CampusLandmarkStore store;
  static const builtin = {
    'campus-buildings',
    'food-and-shops',
    'club-fair',
    'off-campus',
    'all-events',
  };
  @override
  Widget build(BuildContext context) {
    final photo = selected ? category.iconAfter : category.iconBefore;
    final fallback = builtin.contains(category.id)
        ? Image.asset(
            'assets/me_life/${category.id}-${selected ? 'active' : 'inactive'}.png',
            fit: BoxFit.contain,
          )
        : const Icon(LucideIcons.shapes300);
    if (photo == null) return fallback;
    return FutureBuilder<File?>(
      future: store.photo(photo),
      builder: (context, s) => s.data == null
          ? fallback
          : Image.file(
              s.data!,
              fit: BoxFit.contain,
              errorBuilder: (_, e, st) => fallback,
            ),
    );
  }
}

class LifeUnitRow extends StatefulWidget {
  const LifeUnitRow({
    super.key,
    required this.item,
    required this.catalog,
    required this.store,
    required this.epoch,
    required this.scale,
    required this.onOpen,
  });
  final CampusLandmark item;
  final LandmarkCatalog catalog;
  final CampusLandmarkStore store;
  final int epoch;
  final double scale;
  final VoidCallback onOpen;
  @override
  State<LifeUnitRow> createState() => _LifeUnitRowState();
}

class _LifeUnitRowState extends State<LifeUnitRow>
    with LandmarkPolicyPolling<LifeUnitRow> {
  LifeUnitPresentation? presentation;
  CommunityPolicy? livePolicy;
  int generation = 0, policySerial = 0;
  bool checkingPolicy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Future<void> pollLandmarkPolicy() => checkPolicy();

  @override
  void didUpdateWidget(LifeUnitRow old) {
    super.didUpdateWidget(old);
    final identityChanged =
        old.item.id != widget.item.id || old.store != widget.store;
    if (identityChanged) {
      // The next frame already has a new title; no previous entry's public
      // comment, score or policy may remain while its request is pending.
      presentation = null;
      livePolicy = null;
      policySerial++;
    }
    if (old.epoch != widget.epoch || identityChanged) load();
  }

  Future<void> load() async {
    final current = ++generation;
    checkingPolicy = false;
    final policyAtStart = policySerial;
    try {
      final p = await widget.store.presentation(
        widget.item.id,
        (widget.epoch - 1).clamp(0, 2147483647),
      );
      if (mounted && current == generation) {
        setState(() {
          presentation = p;
          if (policyAtStart == policySerial) livePolicy = p.policy;
        });
      }
    } catch (_) {
      if (mounted && current == generation) {
        setState(() {
          presentation = null;
          livePolicy = null;
        });
      }
    }
  }

  Future<void> checkPolicy() async {
    if (checkingPolicy) return;
    checkingPolicy = true;
    final current = generation;
    try {
      final p = await widget.store.presentationPolicy(widget.item.id);
      if (mounted && current == generation) {
        policySerial++;
        if (p.revision >= (livePolicy?.revision ?? 0)) {
          setState(() => livePolicy = p);
        }
      }
    } catch (_) {
      if (mounted && current == generation) {
        policySerial++;
        setState(() => livePolicy = const CommunityPolicy());
      }
    } finally {
      if (mounted && current == generation) checkingPolicy = false;
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Widget? badge(LifeTagBinding? b, {bool expand = false}) {
    if (b == null || b.tagId == widget.item.tagSlots.hidden) return null;
    final tag = widget.catalog.tag(b.tagId);
    if (tag == null) return null;
    return LifeBadge(
      text: landmarkText(tag.texts, context, widget.catalog.defaultLanguage),
      style: widget.catalog.style(b.styleId),
      scale: widget.scale,
      expand: expand,
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item,
        data = widget.catalog,
        s = widget.scale,
        theme = context.bnbuTheme;
    final title = landmarkText(item.names, context, data.defaultLanguage);
    final description = landmarkText(
      item.descriptions,
      context,
      data.defaultLanguage,
    );
    final top = badge(item.tagSlots.topLeft),
        bottom = badge(item.tagSlots.bottomLeft);
    final content = presentation?.content;
    Widget? spotlight;
    if (item.spotlight.modes.contains('tag')) {
      spotlight = badge(item.tagSlots.scoreAfter);
    } else if (content != null && livePolicy?.readComments == true) {
      spotlight = LifeBadge(
        text: content['text'] as String,
        style: data.style(content['style_id'] as String),
        scale: s,
      );
    }
    return TextFieldTapRegion(
      child: Material(
        color: theme.surface,
        borderRadius: BorderRadius.circular(7.3 * s),
        child: InkWell(
          key: ValueKey('landmark-${item.id}'),
          onTap: widget.onOpen,
          borderRadius: BorderRadius.circular(7.3 * s),
          child: Padding(
            padding: EdgeInsets.all(8.7 * s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 107 * s * item.listImageRatio,
                  height: 107 * s,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5.3 * s),
                          child: LandmarkPhotoView(
                            store: widget.store,
                            photo: item.cover,
                            label: title,
                          ),
                        ),
                      ),
                      if (top != null)
                        Positioned(
                          top: -2 * s,
                          left: -2 * s,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: 107 * s * item.listImageRatio + 2 * s,
                            ),
                            child: top,
                          ),
                        ),
                      if (bottom != null)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: 107 * s * item.listImageRatio,
                            ),
                            child: bottom,
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: 9.3 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14 * s,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: theme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 7 * s),
                      LifeIconRow(
                        item: item,
                        language: data.defaultLanguage,
                        scale: s,
                      ),
                      SizedBox(height: 6 * s),
                      Text(
                        description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12 * s,
                          height: 1.2,
                          color: theme.textSecondary,
                        ),
                      ),
                      SizedBox(height: 7 * s),
                      Row(
                        children: [
                          if (item.ratingEnabled &&
                              livePolicy?.readRatings == true &&
                              presentation?.score != null)
                            Text(
                              '${presentation!.score!.toStringAsFixed(1)}${context.l10n.text('分')}',
                              style: TextStyle(
                                fontSize: 14.7 * s,
                                height: 1.2,
                                fontWeight: FontWeight.w600,
                                color: theme.brandBlue,
                              ),
                            ),
                          if (spotlight != null) ...[
                            if (item.ratingEnabled &&
                                livePolicy?.readRatings == true &&
                                presentation?.score != null)
                              SizedBox(width: 7 * s),
                            Flexible(child: spotlight),
                          ],
                        ],
                      ),
                      SizedBox(height: 8 * s),
                      LifeTagStrip(
                        spacing: 4 * s,
                        children: lifeUnitBadges(context, item, data, scale: s),
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
