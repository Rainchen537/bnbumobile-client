import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/cis_checkin.dart';
import '../services/cis_checkin_client.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_component_library.dart';
import '../widgets/bnbu_loading.dart';
import '../widgets/cis_checkin_cards.dart';

class CisCheckinPage extends StatefulWidget {
  const CisCheckinPage({super.key, required this.controller});
  final AppSessionController controller;
  @override
  State<CisCheckinPage> createState() => _CisCheckinPageState();
}

class _CisCheckinPageState extends State<CisCheckinPage> {
  late final AppSessionLease? _lease;
  final _recordsKey = GlobalKey();
  List<CisCheckinProject> _projects = [];
  CisCheckinProject? _selected;
  bool _loading = false;
  bool _loaded = false;
  bool _hasMore = false;
  bool _detail = false;
  int _page = 0;
  int _filter = 0;
  String? _error;
  bool get _current => mounted && _lease?.isActive == true;

  @override
  void initState() {
    super.initState();
    _lease = widget.controller.captureSessionLease();
    widget.controller.addListener(_accountChanged);
    final cached = widget.controller.cachedCheckinProjects();
    if (cached != null) {
      _projects = cached.items;
      _page = cached.page;
      _hasMore = cached.hasMore;
      _loaded = true;
    }
    unawaited(_load());
  }

  void _accountChanged() {
    if (mounted && _lease?.isActive != true) {
      setState(() {
        _projects = [];
        _selected = null;
        _error = '登录状态已变化，请重新打开打卡查看。';
        _loading = false;
      });
    }
  }

  Future<void> _load({bool append = false, bool forceRefresh = false}) async {
    if (_loading || !_current) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.controller.loadCheckinProjects(
        page: append ? _page + 1 : 1,
        forceRefresh: forceRefresh,
      );
      if (!_current) return;
      setState(() {
        _projects = {
          for (final p in append ? _projects : <CisCheckinProject>[]) p.id: p,
          for (final p in result.items) p.id: p,
        }.values.toList();
        _page = result.page;
        _hasMore = result.hasMore;
        _loaded = true;
        final previousId = _selected?.id;
        _selected = _projects.where((p) => p.id == previousId).firstOrNull;
      });
    } catch (error) {
      if (_current) setState(() => _error = _checkinError(error));
    } finally {
      if (_current) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_accountChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= BnbuBreakpoints.tabletWorkspace;
      final showRecords = (wide || _detail) && _selected != null;
      final detailOnly = !wide && _detail && _selected != null;
      return PopScope<void>(
        canPop: !detailOnly,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && detailOnly) setState(() => _detail = false);
        },
        child: Scaffold(
          backgroundColor: context.bnbuTheme.canvas,
          appBar: BnbuSecondaryAppBar(
            bar: AppBar(
              title: const BnbuText('打卡查看'),
              leading: detailOnly
                  ? IconButton(
                      tooltip: context.l10n.text('返回'),
                      icon: const BnbuBackIcon(),
                      onPressed: () => setState(() => _detail = false),
                    )
                  : null,
              actions: [
                if (!detailOnly && _current)
                  Align(
                    alignment: Alignment.centerRight,
                    child: BnbuMenuButton<int>(
                      key: const ValueKey('cis-project-filter'),
                      tooltip: context.l10n.text('筛选'),
                      onSelected: (value) => setState(() => _filter = value),
                      itemBuilder: (_) => [
                        for (final filter in [
                          (0, '全部'),
                          (1, '未完成'),
                          (2, '已完成'),
                        ])
                          PopupMenuItem(
                            value: filter.$1,
                            child: BnbuText(filter.$2),
                          ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            BnbuText(['全部', '未完成', '已完成'][_filter]),
                            const SizedBox(width: 6),
                            const Icon(LucideIcons.chevronDown300, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          body: !_current
              ? _CheckinMessage(message: '登录状态已变化，请重新打开打卡查看。')
              : Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!detailOnly)
                            if (wide)
                              SizedBox(
                                width: (constraints.maxWidth * .34).clamp(
                                  280,
                                  400,
                                ),
                                child: _projectList(),
                              )
                            else
                              Expanded(child: _projectList()),
                          if (wide) const VerticalDivider(width: 1),
                          if (showRecords)
                            Expanded(
                              flex: 7,
                              child: _CisRecordsPane(
                                key: _recordsKey,
                                controller: widget.controller,
                                project: _selected,
                              ),
                            )
                          else if (wide)
                            const Expanded(
                              flex: 7,
                              child: _CheckinMessage(message: '选择项目查看打卡记录'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      );
    },
  );

  Widget _projectList() {
    final visible = _projects
        .where((p) => _filter == 0 || (_filter == 2) == p.completed)
        .toList();
    return BnbuLoadingRegion(
      child: Column(
        children: [
          BnbuUpdateProgress(active: _loading && _loaded),
          Expanded(
            child: BnbuRefreshIndicator(
              onRefresh: () => _load(forceRefresh: true),
              child: ListView(
                key: const ValueKey('cis-project-list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                children: [
                  if (_error != null)
                    _CheckinMessage(
                      message: _error!,
                      onRetry: () => _load(forceRefresh: true),
                    ),
                  if (_loading && !_loaded)
                    const SizedBox(height: 200, child: BnbuInitialLoading()),
                  for (final project in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: CisProjectCard(
                        key: ValueKey('cis-project-${project.id}'),
                        project: project,
                        selected: _selected?.id == project.id,
                        onTap: () => setState(() {
                          _selected = project;
                          _detail = true;
                        }),
                      ),
                    ),
                  if (_loaded && visible.isEmpty && _error == null)
                    const _CheckinMessage(message: '暂无符合条件的打卡项目'),
                  if (_hasMore)
                    TextButton(
                      onPressed: _loading ? null : () => _load(append: true),
                      child: const BnbuText('加载更多'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CisRecordsPane extends StatefulWidget {
  const _CisRecordsPane({super.key, required this.controller, this.project});
  final AppSessionController controller;
  final CisCheckinProject? project;
  @override
  State<_CisRecordsPane> createState() => _CisRecordsPaneState();
}

class _CisRecordsPaneState extends State<_CisRecordsPane> {
  late AppSessionLease? _lease;
  final _scroll = ScrollController();
  List<CisCheckinRecord> _records = [];
  bool _loading = false;
  bool _loaded = false;
  bool _hasMore = false;
  bool _unknownStatistics = false;
  int _page = 0;
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lease = widget.controller.captureSessionLease();
    _restoreCached();
    unawaited(load());
  }

  @override
  void didUpdateWidget(covariant _CisRecordsPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.project?.id != widget.project?.id ||
        oldWidget.controller != widget.controller) {
      _generation++;
      _lease = widget.controller.captureSessionLease();
      _records = [];
      _page = 0;
      _hasMore = false;
      _unknownStatistics = false;
      _loaded = false;
      _loading = false;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      _restoreCached();
      unawaited(load());
    }
  }

  void _restoreCached() {
    final cached = widget.controller.cachedCheckinRecords(
      projectId: widget.project?.id,
    );
    if (cached == null) return;
    _records = cached.items;
    _page = cached.page;
    _hasMore = cached.hasMore;
    _unknownStatistics = cached.hasUnknownStatistics;
    _loaded = true;
  }

  Future<void> load({bool append = false, bool forceRefresh = false}) async {
    if (_loading || _lease?.isActive != true) return;
    final generation = _generation;
    final projectId = widget.project?.id;
    bool current() =>
        mounted && _lease?.isActive == true && generation == _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      var page = append ? _page + 1 : 1;
      var unknownStatistics = append && _unknownStatistics;
      late CisCheckinPageData<CisCheckinRecord> result;
      // Empty filtered pages aren't the end of the source. Continue a bounded
      // batch; retain a Load more action if further source pages remain.
      for (var attempt = 0; attempt < 3; attempt++) {
        result = await widget.controller.loadCheckinRecords(
          projectId: projectId,
          page: page,
          forceRefresh: forceRefresh,
        );
        if (!current()) return;
        unknownStatistics |= result.hasUnknownStatistics;
        if (result.items.isNotEmpty || !result.hasMore) break;
        page = result.page + 1;
      }
      setState(() {
        _records = {
          for (final r in append ? _records : <CisCheckinRecord>[]) r.id: r,
          for (final r in result.items) r.id: r,
        }.values.toList();
        _page = result.page;
        _hasMore = result.hasMore;
        _unknownStatistics = unknownStatistics;
        _loaded = true;
      });
    } catch (error) {
      if (current()) setState(() => _error = _checkinError(error));
    } finally {
      if (current()) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BnbuLoadingRegion(
    child: Column(
      children: [
        BnbuUpdateProgress(active: _loading && _loaded),
        Expanded(
          child: BnbuRefreshIndicator(
            onRefresh: () => load(forceRefresh: true),
            child: ListView(
              key: const ValueKey('cis-record-list'),
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              children: [
                if (widget.project != null) ...[
                  CisProjectCard(project: widget.project!),
                  const SizedBox(height: 20),
                ],
                if (_error != null)
                  _CheckinMessage(
                    message: _error!,
                    onRetry: () => load(forceRefresh: true),
                  ),
                if (_loading && !_loaded)
                  const SizedBox(height: 200, child: BnbuInitialLoading()),
                for (final record in _records)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: CisRecordCard(
                      key: ValueKey('cis-record-${record.id}'),
                      record: record,
                    ),
                  ),
                if (_loaded && _records.isEmpty && _error == null)
                  _CheckinMessage(
                    message: _unknownStatistics
                        ? '学校暂未提供可确认的统计状态'
                        : '暂无已统计的打卡记录',
                  ),
                if (_hasMore)
                  TextButton(
                    onPressed: _loading ? null : () => load(append: true),
                    child: const BnbuText('加载更多'),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

String _checkinError(Object error) => error is CisCheckinException
    ? error.message
    : const CisCheckinException(CisCheckinFailure.network).message;

class _CheckinMessage extends StatelessWidget {
  const _CheckinMessage({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        BnbuText(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: context.bnbuTheme.textSecondary,
          ),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const BnbuText('重试')),
      ],
    ),
  );
}
