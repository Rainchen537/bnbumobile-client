import '../services/me_identity_service.dart';
import '../pages/me_identity_page.dart';
import 'landmark_policy_polling.dart';
import '../services/campus_landmark_store.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dart:math';
import '../models/landmark_review.dart';
import '../services/landmark_review_service.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive_modal.dart';
import 'bnbu_notice.dart';
import 'community_avatar.dart';
import 'landmark_comment_editor.dart';
import 'me_life_content.dart';
import 'me_life_badge.dart';
import '../models/campus_landmark.dart';
import '../config/app_config.dart';

class LandmarkReviewsSection extends StatefulWidget {
  const LandmarkReviewsSection({
    super.key,
    required this.landmarkId,
    required this.username,
    this.service,
    this.policyStore,
    this.controller,
    this.title = '',
    this.onShare,
    this.toolbar,
    this.commentsKey,
    this.loadPlacePhoto,
  });
  final ValueNotifier<Widget?>? toolbar;
  final GlobalKey? commentsKey;
  final Future<Widget> Function()? loadPlacePhoto;
  final String landmarkId, title;
  final String? username;
  final LandmarkReviewService? service;
  final CampusLandmarkStore? policyStore;
  final AppSessionController? controller;
  final Future<void> Function(LandmarkReviewPage page, LandmarkReview? comment)?
  onShare;
  @override
  State<LandmarkReviewsSection> createState() => _LandmarkReviewsSectionState();
}

class _LandmarkReviewsSectionState extends State<LandmarkReviewsSection>
    with LandmarkPolicyPolling<LandmarkReviewsSection> {
  late final service = widget.service ?? RemoteLandmarkReviewService();
  LandmarkReviewPage? page;
  final _policy = ValueNotifier(const CommunityPolicy());
  DateTime? _lastPolicySuccess;
  LandmarkReviewMine mine = const LandmarkReviewMine();
  List<LandmarkReview> items = [];
  final Map<String, List<LandmarkReview>> replies = {};
  bool loading = false, busy = false, more = false;
  String? error;
  String sort = 'helpful';
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Future<void> pollLandmarkPolicy() async {
    if (!busy && !loading) await refreshPolicy();
  }

  @override
  void didUpdateWidget(LandmarkReviewsSection old) {
    super.didUpdateWidget(old);
    if (old.landmarkId != widget.landmarkId ||
        old.username != widget.username) {
      generation++;
      page = null;
      loading = false;
      _policy.value = const CommunityPolicy();
      items = [];
      replies.clear();
      mine = const LandmarkReviewMine();
      load();
    }
  }

  @override
  void dispose() {
    generation++;
    _policy.dispose();
    if (widget.service == null) service.dispose();
    super.dispose();
  }

  bool checkingPolicy = false;
  Future<void> refreshPolicy() async {
    if (checkingPolicy || page == null) return;
    checkingPolicy = true;
    final id = widget.landmarkId;
    final currentGeneration = generation;
    try {
      final next =
          await (widget.policyStore?.presentationPolicy(id) ??
              service.readPolicy(id));
      if (!mounted ||
          id != widget.landmarkId ||
          currentGeneration != generation ||
          page == null) {
        return;
      }
      setState(() {
        page = LandmarkReviewPage.withPolicy(page!, next);
        _lastPolicySuccess = DateTime.now();
      });
      _policy.value = next;
    } catch (_) {
      if (mounted &&
          currentGeneration == generation &&
          page != null &&
          (_lastPolicySuccess == null ||
              DateTime.now().difference(_lastPolicySuccess!) >
                  const Duration(minutes: 1))) {
        setState(
          () => page = LandmarkReviewPage.withPolicy(
            page!,
            const CommunityPolicy(),
          ),
        );
        _policy.value = const CommunityPolicy();
      }
    } finally {
      checkingPolicy = false;
    }
  }

  Future<void> load({bool quiet = false}) async {
    if (loading) return;
    final current = ++generation;
    setState(() {
      loading = true;
      if (!quiet) error = null;
    });
    try {
      final results = await Future.wait<Object>([
        service.browse(widget.landmarkId, sort: sort),
        widget.username == null ||
                (service is RemoteLandmarkReviewService &&
                    !MeIdentityService.shared.isBound(widget.username))
            ? Future.value(const LandmarkReviewMine(canReview: false))
            : service.mine(widget.username!, widget.landmarkId),
      ]);
      if (!mounted || current != generation) return;
      final first = results[0] as LandmarkReviewPage;
      final loaded = [...first.items];
      if (quiet && first.policy.readComments) {
        while (loaded.length < items.length && loaded.length < first.total) {
          final next = await service.browse(
            widget.landmarkId,
            sort: sort,
            offset: loaded.length,
          );
          if (next.items.isEmpty) break;
          loaded.addAll(next.items);
        }
      }
      final expanded = <String, List<LandmarkReview>>{};
      if (quiet && first.policy.readComments) {
        for (final root in replies.keys.where(
          (id) => loaded.any((row) => row.id == id),
        )) {
          try {
            final result = await service.browse(
              widget.landmarkId,
              rootId: root,
              sort: 'oldest',
            );
            expanded[root] = result.items;
          } catch (_) {
            /* A moderated parent no longer exposes its replies. */
          }
        }
      }
      if (!mounted || current != generation) return;
      setState(() {
        page = first;
        mine = results[1] as LandmarkReviewMine;
        items = loaded;
        replies
          ..clear()
          ..addAll(expanded);
        error = null;
        _lastPolicySuccess = DateTime.now();
      });
      _policy.value = first.policy;
    } catch (_) {
      if (mounted && current == generation) {
        setState(() {
          error = '评价加载失败';
          if (_lastPolicySuccess == null ||
              DateTime.now().difference(_lastPolicySuccess!) >
                  const Duration(minutes: 1)) {
            page = null;
          }
        });
        if (page == null) _policy.value = const CommunityPolicy();
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> loadMore() async {
    if (more) return;
    final current = generation;
    setState(() => more = true);
    try {
      final next = await service.browse(
        widget.landmarkId,
        offset: items.length,
        sort: sort,
      );
      if (mounted && current == generation) {
        setState(() {
          page = next;
          items = [
            ...items,
            ...next.items.where((n) => !items.any((i) => i.id == n.id)),
          ];
        });
      }
    } catch (_) {
      notice('加载失败，请重试');
    } finally {
      if (mounted) setState(() => more = false);
    }
  }

  void notice(String message) {
    if (mounted) BnbuToast.show(context, context.l10n.text(message));
  }

  bool get signedIn => widget.username != null;
  Future<bool> _ensureWriteIdentity() async {
    if (service is! RemoteLandmarkReviewService) return true;
    final wasBound = MeIdentityService.shared.isBound(widget.username);
    if (!await ensureMeBinding(context, widget.username) || !mounted) {
      return false;
    }
    if (!wasBound) await load();
    return mounted;
  }

  Future<void> rate(int stars) async {
    if (busy) return;
    if (!signedIn) {
      notice('请先登录');
      return;
    }
    if (!await _ensureWriteIdentity() || !mounted) return;
    if (mine.stars == stars) return;
    setState(() => busy = true);
    final username = widget.username!;
    final landmarkId = widget.landmarkId;
    try {
      if (mine.nextEditAt?.isAfter(DateTime.now()) == true) {
        // A remote zero interval must release a previously cached lock.
        await load(quiet: true);
        if (!mounted ||
            widget.username != username ||
            widget.landmarkId != landmarkId) {
          return;
        }
        if (mine.nextEditAt?.isAfter(DateTime.now()) == true) {
          notice('暂未到可修改评分时间，请稍后重试');
          return;
        }
      }
      final result = await service.rate(
        widget.username!,
        widget.landmarkId,
        version: mine.ratingVersion,
        stars: stars,
      );
      if (!mounted ||
          widget.username != username ||
          widget.landmarkId != landmarkId) {
        return;
      }
      setState(() => mine = result);
      notice('评分已保存');
    } catch (e) {
      notice(e is LandmarkReviewHttpException ? e.message : '评分保存未确认，请刷新查看');
    } finally {
      if (mounted) {
        setState(() => busy = false);
        await load(quiet: true);
      }
    }
  }

  String _requestId() {
    final random = Random.secure();
    final b = List<int>.generate(16, (_) => random.nextInt(256));
    b[6] = (b[6] & 15) | 64;
    b[8] = (b[8] & 63) | 128;
    final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  Future<void> compose({LandmarkReview? reply, LandmarkReview? edit}) async {
    if (reply?.readOnly == true || edit?.readOnly == true) return;
    if (busy) return;
    if (!signedIn) {
      notice('请先登录');
      return;
    }
    if (!await _ensureWriteIdentity() || !mounted) return;
    if (service is RemoteLandmarkReviewService && !mine.canReview) return;
    final authorUsername = widget.username!;
    final own = edit ?? (reply == null ? mine.review : null);
    final text = TextEditingController(
      text: own?.deleted == false ? own!.comment : '',
    );
    final requestId = own?.replyTo != null ? own!.id : _requestId();
    var anonymous = own != null && !own.deleted ? own.anonymous : false;
    var sending = false;
    var identitySynced = false;
    String? failure;
    var ratingSaving = false;
    final photo = widget.loadPlacePhoto?.call();
    await showBnbuAdaptiveModal<void>(
      context: context,
      bottomSheetBackgroundColor: Colors.transparent,
      bottomSheetBorderRadius: BorderRadius.zero,
      dialogBackgroundColor: Colors.transparent,
      dialogMaxWidth: 460,
      builder: (modal, _) => ValueListenableBuilder<CommunityPolicy>(
        valueListenable: _policy,
        builder: (modal, currentPolicy, child) => StatefulBuilder(
          builder: (modal, update) {
            final writable =
                !sending &&
                !ratingSaving &&
                currentPolicy.writeComments &&
                (mine.canReview ||
                    !MeIdentityService.shared.isBound(widget.username)) &&
                widget.username == authorUsername;
            return LandmarkCommentEditor(
              title: widget.title,
              controller: text,
              photo: photo,
              stars: mine.stars,
              showRating: currentPolicy.readRatings,
              onRate:
                  sending ||
                      ratingSaving ||
                      !currentPolicy.writeRatings ||
                      !(mine.canReview ||
                          !MeIdentityService.shared.isBound(widget.username)) ||
                      widget.username != authorUsername
                  ? null
                  : (value) async {
                      update(() => ratingSaving = true);
                      await rate(value);
                      if (modal.mounted) update(() => ratingSaving = false);
                    },
              anonymous: anonymous,
              anonymousName: mine.anonymousName,
              onIdentityChanged: writable
                  ? (v) => update(() => anonymous = v)
                  : null,
              onClose: sending ? null : () => Navigator.pop(modal),
              replyName:
                  reply?.name ??
                  (own?.replyTo != null ? context.l10n.text('评论') : null),
              replyBody: currentPolicy.readComments ? reply?.comment : null,
              sending: sending,
              editing: own != null && !own.deleted,
              failure: !currentPolicy.writeComments ? '评价功能当前不可用。' : failure,
              onDelete: !writable || own == null || own.deleted
                  ? null
                  : () async {
                      update(() => sending = true);
                      try {
                        await service.remove(
                          authorUsername,
                          widget.landmarkId,
                          own,
                        );
                        if (modal.mounted) Navigator.pop(modal);
                        await load(quiet: true);
                      } catch (_) {
                        if (modal.mounted) {
                          update(() {
                            sending = false;
                            failure = '删除失败，请刷新后重试';
                          });
                        }
                      }
                    },
              onSubmit: !writable
                  ? null
                  : () async {
                      if (text.text.trim().isEmpty) {
                        update(() => failure = '请输入评论内容');
                        return;
                      }
                      update(() {
                        sending = true;
                        failure = null;
                      });
                      try {
                        if (!anonymous && !identitySynced) {
                          final identity = await widget.controller
                              ?.readISpaceIdentity();
                          if (widget.username != authorUsername ||
                              identity == null ||
                              identity.name.isEmpty) {
                            throw const LandmarkReviewHttpException(
                              422,
                              '无法读取iSpace身份，请稍后重试',
                            );
                          }
                          await service.syncProfile(
                            authorUsername,
                            name: identity.name,
                            avatar: identity.avatar,
                            version: mine.profileVersion,
                          );
                          identitySynced = true;
                        }
                        await service.comment(
                          authorUsername,
                          widget.landmarkId,
                          version: own?.version ?? 0,
                          body: text.text.trim(),
                          anonymous: anonymous,
                          requestId: requestId,
                          replyTo: own?.replyTo ?? reply?.id,
                        );
                        if (modal.mounted) Navigator.pop(modal);
                        await load(quiet: true);
                      } catch (e) {
                        if (modal.mounted) {
                          update(() {
                            sending = false;
                            failure = e is LandmarkReviewHttpException
                                ? e.message
                                : '发布未确认，内容已保留，请重试';
                          });
                        }
                      }
                    },
            );
          },
        ),
      ),
    );
    // The closing route may still paint its field during the exit animation.
    Future<void>.delayed(const Duration(milliseconds: 400), text.dispose);
  }

  Future<void> vote(LandmarkReview row) async {
    if (row.readOnly) return;
    if (!signedIn) {
      notice('请先登录');
      return;
    }
    if (busy) return;
    if (!await _ensureWriteIdentity() || !mounted) return;
    setState(() => busy = true);
    try {
      await service.helpful(
        widget.username!,
        widget.landmarkId,
        row.id,
        !mine.helpfulIds.contains(row.id),
      );
      await load(quiet: true);
    } catch (_) {
      notice('操作失败，请重试');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openReplies(LandmarkReview row) async {
    if (more) return;
    final current = generation;
    setState(() => more = true);
    try {
      final existing = replies[row.id] ?? [];
      final result = await service.browse(
        widget.landmarkId,
        rootId: row.id,
        offset: existing.length,
        sort: 'oldest',
      );
      if (mounted && current == generation) {
        setState(
          () => replies[row.id] = [
            ...existing,
            ...result.items.where((r) => !existing.any((e) => e.id == r.id)),
          ],
        );
      }
    } catch (_) {
      notice('回复加载失败');
    } finally {
      if (mounted) setState(() => more = false);
    }
  }

  Color get scoreColor => Theme.of(context).brightness == Brightness.dark
      ? context.bnbuTheme.brandBlue
      : const Color(0xff25a5e8);

  Widget ratingCard(LandmarkReviewPage data) => LayoutBuilder(
    builder: (context, constraints) {
      final large = MediaQuery.textScalerOf(context).scale(12) > 16;
      final blue = scoreColor;
      final label = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ME评分',
            style: TextStyle(
              color: blue,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.2,
            ),
          ),
          Text(
            data.average?.toStringAsFixed(1) ?? '—',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: blue,
            ),
          ),
          Text(
            data.ratingSummary.isEmpty
                ? '${data.ratingCount} BNBUer ${context.l10n.text('评分')}'
                : '${data.ratingCount + ((data.ratingSummary['external']?['count'] as int?) ?? 0)} ${context.l10n.text('条评分')}',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              fontSize: 9,
              height: 1.25,
              color: context.bnbuTheme.textMuted,
            ),
          ),
        ],
      );
      final distribution = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.ratingSummary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: BnbuText(
                'BNBU.ME评分分布',
                style: TextStyle(
                  fontSize: 10,
                  color: context.bnbuTheme.textSecondary,
                ),
              ),
            ),
          ...List.generate(5, (i) {
            final n = 4 - i;
            final ratio = data.ratingCount == 0
                ? 0.0
                : data.counts[n] / data.ratingCount;
            return SizedBox(
              height: large ? 20 : 11,
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: List.generate(
                        n + 1,
                        (_) => Icon(
                          Icons.star,
                          size: 8,
                          color: blue.withValues(alpha: .42),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 3,
                      color: blue,
                      backgroundColor: blue.withValues(alpha: .09),
                      borderRadius: BorderRadius.zero,
                    ),
                  ),
                  const SizedBox(width: 7),
                  SizedBox(
                    width: large ? 56 : 38,
                    child: Text(
                      '${(ratio * 100).toStringAsFixed(1)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1,
                        color: context.bnbuTheme.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      );
      return Container(
        key: const ValueKey('me-rating-card'),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        decoration: BoxDecoration(
          color: blue.withValues(alpha: .035),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            if (large) ...[
              Align(alignment: Alignment.centerLeft, child: label),
              const SizedBox(height: 8),
              distribution,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 66, child: label),
                  const SizedBox(width: 6),
                  Expanded(child: distribution),
                ],
              ),
            if (large)
              Align(
                alignment: Alignment.centerLeft,
                child: BnbuText(
                  mine.stars == null ? '立即评分' : '已评分',
                  style: TextStyle(fontSize: mine.stars == null ? 13 : 11.05),
                ),
              ),
            Row(
              children: [
                if (!large)
                  Expanded(
                    child: BnbuText(
                      mine.stars == null ? '立即评分' : '已评分',
                      style: TextStyle(
                        fontSize: mine.stars == null ? 13 : 13 * .85,
                        color: context.bnbuTheme.textSecondary,
                      ),
                    ),
                  ),
                stars(mine.stars ?? 0, size: 24, interactive: true),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget actionBar(LandmarkReviewPage data) {
    final own = mine.review;
    return Material(
      key: const ValueKey('me-community-toolbar'),
      color: context.bnbuTheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: IntrinsicHeight(
            child: Row(
              children: [
                if (data.policy.writeComments &&
                    (mine.canReview ||
                        !MeIdentityService.shared.isBound(widget.username)))
                  Expanded(
                    child: InkWell(
                      onTap: () => compose(),
                      borderRadius: BorderRadius.circular(3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Container(
                          key: const ValueKey('me-comment-entry'),
                          height:
                              32 *
                              MediaQuery.textScalerOf(
                                context,
                              ).scale(1).clamp(1, 2),
                          constraints: const BoxConstraints(minHeight: 32),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: context.bnbuTheme.canvas,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: BnbuText(
                            own != null && !own.deleted ? '编辑我的评论' : '写评论',
                            style: TextStyle(
                              fontSize: 13,
                              color: context.bnbuTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: BnbuText(
                      data.policy.level == 1 ? '评论暂为只读' : '评价功能当前不可用。',
                    ),
                  ),
                if (data.policy.readComments)
                  IconButton(
                    tooltip: '${context.l10n.text('评论')} ${data.total}',
                    onPressed: () {
                      final target = widget.commentsKey?.currentContext;
                      if (target != null) {
                        Scrollable.ensureVisible(
                          target,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : const Duration(milliseconds: 200),
                          alignment: .12,
                        );
                      }
                    },
                    icon: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.messageSquare300, size: 23),
                        Text(
                          '${data.total}',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                if (widget.onShare != null)
                  IconButton(
                    tooltip: context.l10n.text('分享'),
                    onPressed: () => widget.onShare!(data, null),
                    icon: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.squareArrowOutUpRight300, size: 23),
                        BnbuText('分享', style: TextStyle(fontSize: 10)),
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

  Widget stars(int value, {double size = 18, bool interactive = false}) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(
      5,
      (i) => interactive
          ? IconButton(
              key: ValueKey('me-rating-${i + 1}'),
              tooltip: '${(i + 1) * 2} / 10',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 44),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed:
                  busy ||
                      page?.policy.writeRatings != true ||
                      !(mine.canReview ||
                          !MeIdentityService.shared.isBound(widget.username))
                  ? null
                  : () => rate(i + 1),
              icon: Icon(
                Icons.star,
                color: i < value
                    ? scoreColor
                    : context.bnbuTheme.textMuted.withValues(alpha: .25),
                size: size,
              ),
            )
          : Icon(
              Icons.star,
              size: size,
              color: i < value
                  ? scoreColor
                  : context.bnbuTheme.textMuted.withValues(alpha: .22),
            ),
    ),
  );
  Widget _commentAction({
    required String label,
    required Widget child,
    VoidCallback? onTap,
  }) => Semantics(
    button: true,
    label: label,
    child: Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(widthFactor: 1, heightFactor: 1, child: child),
        ),
      ),
    ),
  );

  Widget row(LandmarkReview item, {bool nested = false}) {
    final own =
        mine.review?.id == item.id || mine.ownedCommentIds.contains(item.id);
    return Padding(
      key: ValueKey('review-row-${item.id}'),
      padding: EdgeInsets.only(left: 0, top: nested ? 16 : 20, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommunityAvatar(
            seed: item.seed,
            url: item.avatarUrl,
            size: nested ? 24 : 32,
          ),
          SizedBox(width: nested ? 4 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          color: context.bnbuTheme.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ),

                    if (item.featured)
                      const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: BnbuText('精选'),
                      ),
                  ],
                ),
                if (item.readOnly)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: BnbuText(
                      '25度评价',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.bnbuTheme.textSecondary,
                      ),
                    ),
                  ),
                if (page?.policy.readRatings == true &&
                    item.ratingScore != null &&
                    item.readOnly)
                  Text(
                    '${item.ratingScore!.toStringAsFixed(1)} / 10',
                    style: TextStyle(fontSize: 12, color: scoreColor),
                  ),
                if (page?.policy.readRatings == true && item.rating != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: stars(item.rating!, size: 14),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: LifeCommentBody(
                    key: ValueKey('body-${item.id}'),
                    text: item.comment,
                  ),
                ),
                if (item.images.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final path in item.images)
                          GestureDetector(
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (context) => Dialog(
                                child: Stack(
                                  children: [
                                    InteractiveViewer(
                                      child: Image.network(
                                        '${AppConfig.syncServiceBaseUrl}$path',
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      child: IconButton(
                                        tooltip: context.l10n.text('关闭'),
                                        onPressed: () =>
                                            Navigator.of(context).pop(),
                                        icon: const Icon(Icons.close),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            child: Image.network(
                              '${AppConfig.syncServiceBaseUrl}$path',
                              width: 76,
                              height: 76,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(
                                width: 76,
                                height: 76,
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                if (item.merchantReply?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        BnbuText(
                          '商家回复',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.bnbuTheme.textSecondary,
                          ),
                        ),
                        LifeCommentBody(text: item.merchantReply!),
                      ],
                    ),
                  ),
                if (item.tags.isNotEmpty)
                  LifeTagStrip(
                    expandable: true,
                    children: [
                      for (final tag in item.tags)
                        LifeBadge(
                          text: landmarkText(tag.texts, context, 'zh-Hans'),
                          style: tag.style,
                          scale: .88,
                          truncate: false,
                        ),
                    ],
                  ),
                if (item.status != 'visible')
                  BnbuText(item.hidden ? '管理员已隐藏' : '待审核'),
                if (item.hiddenReason.isNotEmpty) Text(item.hiddenReason),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final actions = Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!item.readOnly && page?.policy.react == true)
                          _commentAction(
                            label: '${context.l10n.text('有用')} ${item.helpful}',
                            onTap: busy ? null : () => vote(item),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  mine.helpfulIds.contains(item.id)
                                      ? Icons.thumb_up
                                      : LucideIcons.thumbsUp300,
                                  size: 17,
                                  color: mine.helpfulIds.contains(item.id)
                                      ? scoreColor
                                      : context.bnbuTheme.textMuted,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${item.helpful}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.bnbuTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!item.readOnly &&
                            widget.onShare != null &&
                            item.status == 'visible') ...[
                          const SizedBox(width: 12),
                          _commentAction(
                            label: context.l10n.text('分享'),
                            onTap: () => widget.onShare!(page!, item),
                            child: Icon(
                              LucideIcons.squareArrowOutUpRight300,
                              size: 17,
                              color: context.bnbuTheme.textMuted,
                            ),
                          ),
                        ],
                      ],
                    );
                    final date = item.createdAt.toLocal();
                    final metadata = Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        Text(
                          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.bnbuTheme.textMuted,
                          ),
                        ),
                        if (item.editedAt != null)
                          BnbuText(
                            '已编辑',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.bnbuTheme.textMuted,
                            ),
                          ),
                        if (!item.readOnly &&
                            page?.policy.writeComments == true &&
                            (mine.canReview ||
                                !MeIdentityService.shared.isBound(
                                  widget.username,
                                )))
                          _commentAction(
                            label: context.l10n.text(own ? '编辑' : '回复'),
                            onTap: () => own
                                ? compose(edit: item)
                                : compose(reply: item),
                            child: BnbuText(
                              own ? '编辑' : '回复',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.bnbuTheme.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    );
                    if (constraints.maxWidth < 255 ||
                        MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          metadata,
                          Align(
                            alignment: Alignment.centerRight,
                            child: actions,
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: metadata),
                        const SizedBox(width: 8),
                        actions,
                      ],
                    );
                  },
                ),
                if (!nested)
                  for (final r
                      in replies[item.id] ??
                          [if (item.replyPreview != null) item.replyPreview!])
                    row(r, nested: true),
                if (!nested && (replies[item.id]?.isNotEmpty ?? false))
                  TextButton(
                    onPressed: () => setState(() => replies.remove(item.id)),
                    child: const BnbuText('收起回复'),
                  ),
                if (!nested &&
                    item.replies >
                        (replies[item.id]?.length ??
                            (item.replyPreview == null ? 0 : 1)))
                  TextButton(
                    onPressed: more ? null : () => openReplies(item),
                    child: Text(
                      '${context.l10n.text('查看回复')} (${item.replies})',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = page;
    if (widget.toolbar != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.toolbar!.value = data == null || data.policy.level == 3
              ? null
              : actionBar(data);
        }
      });
    }
    if (data == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: error != null
            ? TextButton(onPressed: load, child: BnbuText(error!))
            : const LinearProgressIndicator(minHeight: 2),
      );
    }
    if (data.policy.level == 3) return const SizedBox.shrink();
    final own = mine.review;
    final list = [
      ...items.map(
        (r) => r.id == own?.id && own!.status == 'visible' ? own : r,
      ),
      if (own != null &&
          !own.deleted &&
          own.status != 'visible' &&
          !items.any((r) => r.id == own.id))
        own,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.policy.readRatings) ratingCard(data),
        if (data.policy.readComments) ...[
          const SizedBox(height: 16),
          SizedBox(
            key: const ValueKey('me-comments-refresh-gap'),
            height: 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: context.bnbuTheme.canvas),
                if (loading)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 2,
                    child: LinearProgressIndicator(
                      key: ValueKey('me-comments-refresh-progress'),
                      minHeight: 2,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            key: widget.commentsKey,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              children: [
                Text(
                  '${context.l10n.text(sort == 'helpful' ? '热评' : '全部评论')} / ${data.total}',
                  style: TextStyle(
                    color: context.bnbuTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  color: context.bnbuTheme.canvas,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final entry in {
                        'helpful': '最有用',
                        'newest': '最晚',
                        'oldest': '最早',
                      }.entries)
                        InkWell(
                          onTap: loading
                              ? null
                              : () {
                                  setState(() => sort = entry.key);
                                  load();
                                },
                          child: Container(
                            constraints: const BoxConstraints(
                              minHeight: 24,
                              minWidth: 48,
                            ),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            color: sort == entry.key
                                ? context.bnbuTheme.surface
                                : null,
                            child: BnbuText(
                              entry.value,
                              style: TextStyle(
                                fontSize: 12,
                                color: sort == entry.key
                                    ? context.bnbuTheme.textPrimary
                                    : context.bnbuTheme.textMuted,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final item in list) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: row(item),
            ),
            Divider(
              indent: 60,
              endIndent: 16,
              height: 1,
              color: context.bnbuTheme.textMuted.withValues(alpha: .12),
            ),
          ],
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: BnbuText('暂无评论')),
            ),
          if (items.length < data.total)
            TextButton(
              onPressed: more ? null : loadMore,
              child: const BnbuText('加载更多'),
            ),
        ],
        if (widget.toolbar == null &&
            data.policy.writeComments &&
            (mine.canReview ||
                !MeIdentityService.shared.isBound(widget.username)))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: OutlinedButton.icon(
              onPressed: () => compose(),
              icon: const Icon(LucideIcons.pencil300, size: 18),
              label: BnbuText(own != null && !own.deleted ? '编辑我的评论' : '写评论'),
            ),
          ),
        if (data.policy.level == 1)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: BnbuText('评论暂为只读')),
          ),
        if (widget.toolbar == null && widget.onShare != null)
          TextButton.icon(
            onPressed: () => widget.onShare!(data, null),
            icon: const Icon(LucideIcons.share2300, size: 18),
            label: const BnbuText('分享'),
          ),
      ],
    );
  }
}

class LifeCommentBody extends StatefulWidget {
  const LifeCommentBody({super.key, required this.text});
  final String text;
  @override
  State<LifeCommentBody> createState() => _LifeCommentBodyState();
}

class _LifeCommentBodyState extends State<LifeCommentBody> {
  bool expanded = false;
  @override
  void didUpdateWidget(LifeCommentBody old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(
      TextStyle(
        fontSize: 16,
        height: 1.4,
        color: context.bnbuTheme.textPrimary,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 5,
        )..layout(maxWidth: constraints.maxWidth);
        final overflow = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (expanded || !overflow)
              SelectableText(widget.text, style: style)
            else
              Text(
                widget.text,
                style: style,
                maxLines: 5,
                overflow: TextOverflow.clip,
              ),
            if (overflow)
              TextButton(
                onPressed: () => setState(() => expanded = !expanded),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(44, 44),
                  alignment: Alignment.centerLeft,
                ),
                child: BnbuText(
                  expanded ? '收起' : '展开全文',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        );
      },
    );
  }
}
