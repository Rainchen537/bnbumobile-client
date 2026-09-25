import '../services/me_identity_service.dart';
import '../pages/me_identity_page.dart';
import '../services/community_policy_service.dart';
import 'student_review_components.dart';
import 'bnbu_loading.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/campus_directory.dart';
import '../models/teacher_review.dart';
import '../models/teacher_review_reference.dart';
import '../models/timetable_data.dart';
import '../services/directory_search.dart';
import '../services/teacher_review_reference_repository.dart';
import '../services/teacher_review_service.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive_modal.dart';
import 'bnbu_creation_form.dart';
import 'bnbu_components.dart';
import 'bnbu_notice.dart';

class TeacherReviewsSection extends StatefulWidget {
  const TeacherReviewsSection({
    super.key,
    required this.teacher,
    required this.username,
    required this.timetable,
    this.reviewService,
    this.referenceRepository,
  });

  final OfficialTeacherProfile teacher;
  final String? username;
  final TimetableData? timetable;
  final TeacherReviewService? reviewService;
  final TeacherReviewReferenceRepository? referenceRepository;

  @override
  State<TeacherReviewsSection> createState() => _TeacherReviewsSectionState();
}

class _TeacherReviewsSectionState extends State<TeacherReviewsSection>
    with WidgetsBindingObserver {
  Timer? _policyTimer;
  void _startPolicyTimer() {
    _policyTimer?.cancel();
    _policyTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_loading) unawaited(_load());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_load());
      _startPolicyTimer();
    } else {
      _policyTimer?.cancel();
    }
  }

  late final TeacherReviewService _service =
      widget.reviewService ?? RemoteTeacherReviewService();
  late final bool _ownsService = widget.reviewService == null;
  late final TeacherReviewReferenceRepository _referenceRepository =
      widget.referenceRepository ?? AssetTeacherReviewReferenceRepository();
  TeacherReviewPageData? _page;
  TeacherReviewMineState? _mine;
  List<TeacherReviewReference> _references = const [];
  bool _loading = true;
  bool _remoteClosed = true;
  bool _loadingMore = false;
  bool _courseLinkedOnly = false;
  String? _error;
  String? _referenceError;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    WidgetsBinding.instance.addObserver(this);
    if (_ownsService) _startPolicyTimer();
  }

  @override
  void didUpdateWidget(covariant TeacherReviewsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teacher.reviewKey != widget.teacher.reviewKey ||
        oldWidget.username != widget.username ||
        oldWidget.timetable != widget.timetable) {
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    _policyTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsService) {
      _service.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _references = const [];
        _referenceError = null;
      });
    }
    if (_ownsService) {
      final policy = await readCommunityPolicy(
        'teacher:${widget.teacher.reviewKey}',
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _remoteClosed = !policy.readComments;
        _loading = false;
      });
      if (_remoteClosed) return;
    } else {
      _remoteClosed = false;
    }
    final evidence = _courseEvidence(widget.teacher, widget.timetable);
    unawaited(_loadReferences(generation, evidence));
    try {
      final username = widget.username?.trim() ?? '';
      final publicFuture = _service.loadReviews(
        widget.teacher.reviewKey,
        courseLinkedOnly: _courseLinkedOnly,
      );
      final mineFuture =
          username.isEmpty ||
              (_service is RemoteTeacherReviewService &&
                  !MeIdentityService.shared.isBound(username))
          ? Future.value(
              const TeacherReviewMineState(
                review: null,
                suspendedUntil: null,
                canReview: false,
              ),
            )
          : _service.loadMine(username, widget.teacher.reviewKey);
      final results = await Future.wait<Object>([publicFuture, mineFuture]);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _page = results[0] as TeacherReviewPageData;
        _mine = results[1] as TeacherReviewMineState;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadReferences(
    int generation,
    List<TeacherReviewCourseEvidence> evidence,
  ) async {
    try {
      final references = await _referenceRepository.loadFor(
        teacherKey: widget.teacher.reviewKey,
        courseEvidence: evidence,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _references = references);
    } on Object {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _references = const [];
        _referenceError = '历史选课参考暂时无法读取';
      });
    }
  }

  Future<void> _toggleCourseFilter() async {
    setState(() {
      _courseLinkedOnly = !_courseLinkedOnly;
    });
    await _load();
  }

  Future<void> _loadMore() async {
    final current = _page;
    if (current == null ||
        current.items.length >= current.total ||
        _loadingMore) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final next = await _service.loadReviews(
        widget.teacher.reviewKey,
        courseLinkedOnly: _courseLinkedOnly,
        offset: current.items.length,
      );
      if (!mounted) return;
      final knownIds = current.items.map((item) => item.id).toSet();
      setState(() {
        _page = TeacherReviewPageData(
          summary: next.summary,
          total: next.total,
          offset: 0,
          limit: next.limit,
          items: [
            ...current.items,
            ...next.items.where((item) => knownIds.add(item.id)),
          ],
        );
      });
    } on Object catch (error) {
      if (mounted) {
        BnbuToast.show(context, error.toString(), kind: BnbuToastKind.danger);
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openEditor() async {
    final username = widget.username?.trim() ?? '';
    if (username.isEmpty) {
      BnbuToast.show(context, '登录后可评价', kind: BnbuToastKind.warning);
      return;
    }
    if (_service is RemoteTeacherReviewService) {
      final wasBound = MeIdentityService.shared.isBound(username);
      if (!await ensureMeBinding(context, username) || !mounted) return;
      if (!wasBound) await _load();
      if (!mounted) return;
    }
    final existing = _mine?.review;
    final evidence = _courseEvidence(widget.teacher, widget.timetable);
    final saved = await showBnbuCreationModal<TeacherReviewMineState>(
      context: context,
      bottomSheetBorderRadius: const BorderRadius.vertical(
        top: Radius.circular(20),
      ),
      maxWidth: 680,
      maxHeight: 760,
      semanticLabel: context.l10n.text(existing == null ? '发表教师评价' : '编辑教师评价'),
      contentKey: const ValueKey('teacher-review-editor-modal'),
      builder: (modalContext, presentation) => _TeacherReviewEditor(
        presentation: presentation,
        existing: existing,
        evidence: evidence,
        onSave: (draft) async {
          try {
            final result = await _service.saveReview(
              username,
              widget.teacher.reviewKey,
              draft,
            );
            if (modalContext.mounted) {
              Navigator.of(modalContext).pop(result);
            }
          } on Object catch (error) {
            if (modalContext.mounted) {
              BnbuToast.show(
                modalContext,
                error.toString(),
                kind: BnbuToastKind.danger,
              );
            }
          }
        },
      ),
    );
    if (!mounted || saved == null) return;
    setState(() => _mine = saved);
    BnbuToast.show(context, '评价已保存', kind: BnbuToastKind.success);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_remoteClosed) return const SizedBox.shrink();
    final tokens = context.bnbuTheme;
    final page = _page;
    final mine = _mine;
    final ownId = mine?.review?.id;
    final publicItems = page?.items
        .where((review) => review.id != ownId)
        .toList(growable: false);
    final canOpenEditor = mine?.suspendedUntil == null;
    final courseEvidence = _courseEvidence(widget.teacher, widget.timetable);
    final visibleReferences = _courseLinkedOnly
        ? _references
              .where(
                (reference) => reference.matchesCourseEvidence(courseEvidence),
              )
              .toList(growable: false)
        : _references;
    final showHeaderAction =
        mine?.review == null &&
        (_loading || _error != null || (page?.summary.count ?? 0) > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BnbuSectionHeader(
          title: '同学评价',
          trailing: showHeaderAction
              ? StudentReviewAction(
                  key: const ValueKey('teacher-review-edit-action'),
                  onPressed: canOpenEditor ? _openEditor : null,
                  label: '评价',
                )
              : null,
        ),
        SizedBox(height: tokens.space8),
        if (visibleReferences.isNotEmpty) ...[
          _HistoricalReferenceSection(references: visibleReferences),
          SizedBox(height: tokens.space12),
        ],
        if (_referenceError != null) ...[
          BnbuNotice(
            message: _referenceError!,
            kind: BnbuStatusKind.warning,
            icon: LucideIcons.archiveX300,
          ),
          SizedBox(height: tokens.space12),
        ],
        BnbuUpdateProgress(active: _loading && page != null),
        if (_loading && page == null)
          const BnbuInitialLoading()
        else if (_error != null)
          BnbuNotice(
            message: '教师评价加载失败',
            kind: BnbuStatusKind.danger,
            icon: LucideIcons.triangleAlert300,
            action: IconButton(
              tooltip: context.l10n.text('重试'),
              onPressed: _load,
              icon: const Icon(LucideIcons.refreshCw300, size: 18),
            ),
          )
        else ...[
          if (page!.summary.count > 0) ...[
            _ReviewSummaryPanel(
              summary: page.summary,
              loadedReviews: page.items,
            ),
            SizedBox(height: tokens.space12),
          ],
          if (page.summary.count > 0 || _courseLinkedOnly) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _ReviewScopePicker(
                courseLinkedOnly: _courseLinkedOnly,
                onChanged: (_) => _toggleCourseFilter(),
              ),
            ),
            SizedBox(height: tokens.space12),
          ],
          if (mine?.suspendedUntil != null) ...[
            BnbuNotice(
              message:
                  '评价功能暂停至 ${context.l10n.formatMediumDateTime(mine!.suspendedUntil!.toLocal())}',
              kind: BnbuStatusKind.warning,
              icon: LucideIcons.shieldOff300,
            ),
            SizedBox(height: tokens.space12),
          ],
          if (publicItems!.isEmpty && mine?.review == null)
            _ReviewEmptyState(
              filtered: _courseLinkedOnly,
              canReview: canOpenEditor,
              onPrimaryAction: _courseLinkedOnly
                  ? _toggleCourseFilter
                  : _openEditor,
            )
          else
            _ReviewFeed(
              mine: mine?.review,
              publicItems: publicItems,
              onEditMine: canOpenEditor ? _openEditor : null,
            ),
          if (page.items.length < page.total) ...[
            SizedBox(height: tokens.space12),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _loadingMore ? null : _loadMore,
                icon: _loadingMore
                    ? const SizedBox.square(
                        dimension: 18,
                        child: BnbuActivityIndicator(),
                      )
                    : const Icon(LucideIcons.chevronsDown300, size: 18),
                label: const BnbuText('加载更多'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _HistoricalReferenceSection extends StatelessWidget {
  const _HistoricalReferenceSection({required this.references});

  final List<TeacherReviewReference> references;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return BnbuSurfaceCard(
      key: const ValueKey('teacher-review-historical-references'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.all(tokens.space16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.infoContainer,
                    borderRadius: BorderRadius.circular(tokens.radius12),
                  ),
                  child: Icon(
                    LucideIcons.archive300,
                    size: 20,
                    color: tokens.brandBlue,
                  ),
                ),
                SizedBox(width: tokens.space12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BnbuText(
                        '历史选课参考',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      SizedBox(height: tokens.space4),
                      BnbuText(
                        '历史匿名经验，内容主观且样本有限，仅供选课参考；不计入同学评价评分与数量。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < references.length; index++) ...[
            Divider(height: 1, color: tokens.border),
            _HistoricalReferenceTile(
              reference: references[index],
              initiallyExpanded: references.length == 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoricalReferenceTile extends StatelessWidget {
  const _HistoricalReferenceTile({
    required this.reference,
    required this.initiallyExpanded,
  });

  final TeacherReviewReference reference;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final date = reference.curatedAt == null
        ? ''
        : context.l10n.formatMediumDate(reference.curatedAt!);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('teacher-review-reference-${reference.id}'),
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.symmetric(
          horizontal: tokens.space16,
          vertical: tokens.space4,
        ),
        childrenPadding: EdgeInsets.fromLTRB(
          tokens.space16,
          0,
          tokens.space16,
          tokens.space16,
        ),
        title: BnbuText(
          reference.courseNames.first,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: tokens.space4),
          child: BnbuText(
            [
              reference.sourceLabel,
              if (date.isNotEmpty) '整理于 $date',
            ].join(' · '),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: tokens.textMuted),
          ),
        ),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: BnbuText(
              reference.summary,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                height: 1.5,
              ),
            ),
          ),
          if (reference.highlights.isNotEmpty) ...[
            SizedBox(height: tokens.space12),
            for (final highlight in reference.highlights) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: tokens.space8),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: tokens.brandBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  SizedBox(width: tokens.space8),
                  Expanded(
                    child: BnbuText(
                      highlight,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: tokens.space8),
            ],
          ],
        ],
      ),
    );
  }
}

class _ReviewSummaryPanel extends StatelessWidget {
  const _ReviewSummaryPanel({
    required this.summary,
    required this.loadedReviews,
  });
  final TeacherReviewSummary summary;
  final List<TeacherReviewEntry> loadedReviews;
  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Container(
      key: const ValueKey('teacher-review-summary'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const BnbuText(
            '教学风格与课程体验',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _IconCount(
                icon: LucideIcons.messagesSquare300,
                label: '评价',
                count: summary.count,
              ),
              _IconCount(
                icon: LucideIcons.bookCheck300,
                label: '课表匹配',
                count: summary.courseLinkedCount,
              ),
            ],
          ),
          for (final dimension in TeacherStyleDimension.values)
            if ((summary.styleDistribution[dimension.name] ?? const <int>[])
                .any((count) => count > 0))
              _StyleDistribution(
                dimension: dimension,
                counts: summary.styleDistribution[dimension.name]!,
              ),
        ],
      ),
    );
  }
}

class _StyleDistribution extends StatelessWidget {
  const _StyleDistribution({required this.dimension, required this.counts});
  final TeacherStyleDimension dimension;
  final List<int> counts;
  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final total = counts.fold(0, (sum, count) => sum + count);
    return Padding(
      key: ValueKey('teacher-style-distribution-${dimension.name}'),
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: BnbuText(
                  dimension.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                '$total',
                style: TextStyle(color: tokens.textSecondary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < 3; index++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: index == 2 ? 0 : 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: total == 0 ? 0 : counts[index] / total,
                            minHeight: 4,
                            backgroundColor: tokens.surfaceMuted,
                            color: tokens.brandBlue,
                            semanticsLabel: context.l10n.text(
                              dimension.choices[index],
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        BnbuText(
                          dimension.choices[index],
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${counts[index]}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconCount extends StatelessWidget {
  const _IconCount({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: tokens.textSecondary),
        SizedBox(width: tokens.space4),
        BnbuText(
          '$label $count',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: tokens.textSecondary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ReviewScopePicker extends StatelessWidget {
  const _ReviewScopePicker({
    required this.courseLinkedOnly,
    required this.onChanged,
  });
  final bool courseLinkedOnly;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      for (final linked in [false, true])
        Semantics(
          selected: courseLinkedOnly == linked,
          child: TextButton(
            key: linked ? const ValueKey('teacher-review-course-filter') : null,
            onPressed: () => onChanged(linked),
            style: TextButton.styleFrom(
              foregroundColor: courseLinkedOnly == linked
                  ? context.bnbuTheme.brandBlue
                  : context.bnbuTheme.textSecondary,
              textStyle: TextStyle(
                fontSize: 14,
                fontWeight: courseLinkedOnly == linked
                    ? FontWeight.w500
                    : FontWeight.w400,
              ),
            ),
            child: BnbuText(linked ? '课表匹配' : '全部'),
          ),
        ),
    ],
  );
}

class _ReviewEmptyState extends StatelessWidget {
  const _ReviewEmptyState({
    required this.filtered,
    required this.canReview,
    required this.onPrimaryAction,
  });
  final bool filtered, canReview;
  final VoidCallback onPrimaryAction;
  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey('teacher-review-empty'),
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: BnbuText(
            filtered ? '暂无课表匹配评价' : '暂无同学评价',
            style: TextStyle(
              fontSize: 14,
              color: context.bnbuTheme.textSecondary,
            ),
          ),
        ),
        if (filtered || canReview)
          StudentReviewAction(
            key: const ValueKey('teacher-review-empty-action'),
            label: filtered ? '查看全部' : '评价',
            onPressed: onPrimaryAction,
          ),
      ],
    ),
  );
}

class _ReviewFeed extends StatelessWidget {
  const _ReviewFeed({
    required this.mine,
    required this.publicItems,
    required this.onEditMine,
  });

  final TeacherReviewEntry? mine;
  final List<TeacherReviewEntry> publicItems;
  final VoidCallback? onEditMine;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    final entries = <({TeacherReviewEntry review, bool isMine})>[
      if (mine != null) (review: mine!, isMine: true),
      for (final review in publicItems) (review: review, isMine: false),
    ];
    return ClipRRect(
      key: const ValueKey('teacher-review-feed'),
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            _ReviewEntryRow(
              review: entries[index].review,
              isMine: entries[index].isMine,
              onEdit: entries[index].isMine ? onEditMine : null,
            ),
            if (index < entries.length - 1)
              Divider(height: 1, color: tokens.border),
          ],
        ],
      ),
    );
  }
}

class _ReviewEntryRow extends StatelessWidget {
  const _ReviewEntryRow({
    required this.review,
    required this.isMine,
    required this.onEdit,
  });
  final TeacherReviewEntry review;
  final bool isMine;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) => StudentReviewRow(
    key: ValueKey('teacher-review-${isMine ? 'mine' : review.id}'),
    comment: review.comment,
    updatedAt: review.updatedAt,
    isMine: isMine,
    hidden: review.moderationStatus == TeacherReviewModerationStatus.hidden,
    hiddenReason: review.hiddenReason,
    onEdit: onEdit,
    editKey: const ValueKey('teacher-review-mine-edit-action'),
    badges: [
      if (review.courseLinked)
        BnbuText(
          '课表匹配',
          style: TextStyle(
            fontSize: 12,
            color: context.bnbuTheme.textSecondary,
          ),
        ),
    ],
    details: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (review.courseEvidence.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CourseEvidenceRail(courses: review.courseEvidence),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (review.styleDimensions.isEmpty)
              BnbuText(
                '历史评价',
                style: TextStyle(
                  fontSize: 12,
                  color: context.bnbuTheme.textMuted,
                ),
              ),
            for (final dimension in TeacherStyleDimension.values)
              if (review.styleDimensions[dimension.name] case final value?)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: context.bnbuTheme.surfaceMuted,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: BnbuText(
                    dimension.choice(value),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
          ],
        ),
      ],
    ),
  );
}

class _CourseEvidenceRail extends StatelessWidget {
  const _CourseEvidenceRail({required this.courses});

  final List<TeacherReviewCourseEvidence> courses;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceMuted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(tokens.radius12),
        border: BorderDirectional(
          start: BorderSide(color: tokens.success, width: 4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.space12,
          vertical: tokens.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < courses.length; index++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.bookOpen300,
                    size: 16,
                    color: tokens.textSecondary,
                  ),
                  SizedBox(width: tokens.space8),
                  Expanded(
                    child: BnbuText(
                      courses[index].displayLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              if (index < courses.length - 1) SizedBox(height: tokens.space4),
            ],
          ],
        ),
      ),
    );
  }
}

class _TeacherReviewEditor extends StatefulWidget {
  const _TeacherReviewEditor({
    required this.presentation,
    required this.existing,
    required this.evidence,
    required this.onSave,
  });

  final BnbuAdaptiveModalPresentation presentation;
  final TeacherReviewEntry? existing;
  final List<TeacherReviewCourseEvidence> evidence;
  final Future<void> Function(TeacherReviewDraft draft) onSave;

  @override
  State<_TeacherReviewEditor> createState() => _TeacherReviewEditorState();
}

class _TeacherReviewEditorState extends State<_TeacherReviewEditor> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, int> _styles = Map.of(
    widget.existing?.styleDimensions ?? const {},
  );
  late final TextEditingController _commentController = TextEditingController(
    text: widget.existing?.comment ?? '',
  );
  bool _submitting = false;
  bool _showValidationErrors = false;
  bool get _complete => _styles.isNotEmpty;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_submitting) return;
    if (!_complete) {
      setState(() => _showValidationErrors = true);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) return;
    setState(() => _submitting = true);
    await widget.onSave(
      TeacherReviewDraft(
        expectedVersion: widget.existing?.version ?? 0,
        styleDimensions: Map.unmodifiable(_styles),
        comment: _commentController.text.trim(),
        courseEvidence: widget.evidence,
      ),
    );
    if (mounted) setState(() => _submitting = false);
  }

  void _updateRating(VoidCallback update) {
    setState(() {
      update();
      if (_complete) _showValidationErrors = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return BnbuCreationForm(
      title: widget.existing == null ? '发表评价' : '编辑评价',
      avoidKeyboard: !widget.presentation.isDialog,
      closeEnabled: !_submitting,
      action: BnbuCreationAction(
        key: const ValueKey('teacher-review-save'),
        label: '保存',
        onPressed: _save,
        busy: _submitting,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BnbuCreationGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: _EditorCourseEvidence(courses: widget.evidence),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _EditorSectionTitle(
                label: '教学风格与课程体验',
                value: '${_styles.length}',
              ),
            ),
            BnbuCreationGroup(
              children: [
                for (final dimension in TeacherStyleDimension.values)
                  _StylePicker(
                    dimension: dimension,
                    value: _styles[dimension.name],
                    onChanged: (value) => _updateRating(() {
                      if (value == null) {
                        _styles.remove(dimension.name);
                      } else {
                        _styles[dimension.name] = value;
                      }
                    }),
                  ),
              ],
            ),
            if (_showValidationErrors && !_complete)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: BnbuText(
                  '请选择至少一项课堂体验',
                  style: TextStyle(color: tokens.danger, fontSize: 13),
                ),
              ),
            const SizedBox(height: 24),
            BnbuCreationGroup(
              children: [
                TextFormField(
                  controller: _commentController,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 2000,
                  textInputAction: TextInputAction.newline,
                  style: BnbuCreationStyle.fieldText(context),
                  decoration: BnbuCreationStyle.input(context, hint: '评价内容'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorCourseEvidence extends StatelessWidget {
  const _EditorCourseEvidence({required this.courses});

  final List<TeacherReviewCourseEvidence> courses;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    if (courses.isEmpty) {
      return const Align(
        alignment: AlignmentDirectional.centerStart,
        child: BnbuStatusBadge(
          label: '未匹配课表',
          kind: BnbuStatusKind.neutral,
          icon: LucideIcons.bookX300,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BnbuStatusBadge(
          label: '课表匹配',
          kind: BnbuStatusKind.success,
          icon: LucideIcons.bookCheck300,
        ),
        SizedBox(height: tokens.space8),
        _CourseEvidenceRail(courses: courses),
      ],
    );
  }
}

class _EditorSectionTitle extends StatelessWidget {
  const _EditorSectionTitle({required this.label, this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Row(
      children: [
        Expanded(
          child: BnbuText(label, style: BnbuCreationStyle.fieldText(context)),
        ),
        if (value != null)
          BnbuText(
            value!,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: tokens.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class _StylePicker extends StatelessWidget {
  const _StylePicker({
    required this.dimension,
    required this.value,
    required this.onChanged,
  });
  final TeacherStyleDimension dimension;
  final int? value;
  final ValueChanged<int?> onChanged;
  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: BnbuText(
                  dimension.label,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              if (value != null)
                IconButton(
                  key: ValueKey('teacher-style-${dimension.name}-clear'),
                  onPressed: () => onChanged(null),
                  tooltip: context.l10n.text('清除选择'),
                  icon: Icon(
                    LucideIcons.x300,
                    size: 16,
                    color: tokens.textMuted,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                )
              else
                const SizedBox(height: 44),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked =
                  MediaQuery.textScalerOf(context).scale(14) > 20 ||
                  constraints.maxWidth < 260;
              final choices = [
                for (var index = 1; index <= 3; index++)
                  Semantics(
                    selected: value == index,
                    button: true,
                    child: Material(
                      color: value == index
                          ? tokens.brandBlue.withValues(alpha: .12)
                          : tokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        key: ValueKey('teacher-style-${dimension.name}-$index'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onChanged(value == index ? null : index),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 12,
                            ),
                            child: Center(
                              child: BnbuText(
                                dimension.choice(index),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: value == index
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: value == index
                                      ? tokens.brandBlue
                                      : tokens.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ];
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < choices.length; index++) ...[
                      if (index > 0) const SizedBox(height: 8),
                      choices[index],
                    ],
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < choices.length; index++) ...[
                    if (index > 0) const SizedBox(width: 8),
                    Expanded(child: choices[index]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

List<TeacherReviewCourseEvidence> _courseEvidence(
  OfficialTeacherProfile teacher,
  TimetableData? timetable,
) {
  if (timetable == null) return const [];
  final evidence = <TeacherReviewCourseEvidence>[];
  for (final course in timetable.courses) {
    final names = course.teacher
        .split(RegExp(r'\s*(?:;|；|,|，|、|&|/)\s*'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
    if (!names.any(
      (name) => DirectorySearch.isExactTeacherName(teacher, name),
    )) {
      continue;
    }
    evidence.add(
      TeacherReviewCourseEvidence(
        courseCode: course.code,
        courseName: course.name,
        semesterId: timetable.selectedSemesterId,
        semesterName: timetable.selectedSemesterName,
      ),
    );
    if (evidence.length == 8) break;
  }
  return evidence;
}
