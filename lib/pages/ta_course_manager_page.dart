import '../widgets/bnbu_menu.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/fixed_schedule_transfer.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/assistant_models.dart';
import '../models/ta_course_entry.dart';
import '../widgets/fixed_schedule_editor.dart';
import '../theme/course_color_palette.dart';
import '../services/assistant_action_runtime.dart';
import '../services/assistant_context_coordinator.dart';
import '../services/prepared_assistant_action.dart';
import '../services/ta_course_repository.dart';
import '../state/ta_course_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/assistant_context_scope.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_adaptive_modal.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/bnbu_notice.dart';

enum _TaCoursePageAction { importEntries, exportEntries }

class TaCourseManagerPage extends StatefulWidget {
  const TaCourseManagerPage({
    super.key,
    required this.controller,
    this.initialAssistantIntent,
  });

  final TaCourseController controller;
  final AssistantTaCourseIntent? initialAssistantIntent;

  @override
  State<TaCourseManagerPage> createState() => _TaCourseManagerPageState();
}

class _TaCourseManagerPageState extends State<TaCourseManagerPage> {
  AssistantContextCoordinator? _contextCoordinator;
  AssistantContextRegistration? _contextRegistration;
  bool _assistantIntentHandled = false;

  List<TaCourseEntry> get _entries => widget.controller.entries;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    _scheduleAssistantIntent();
  }

  @override
  void didUpdateWidget(covariant TaCourseManagerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
    }
    if (!identical(
      oldWidget.initialAssistantIntent,
      widget.initialAssistantIntent,
    )) {
      _assistantIntentHandled = false;
      _scheduleAssistantIntent();
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
          pageType: 'schedule',
          title: '固定日程',
          summary: '共 ${_entries.length} 条日程',
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _contextRegistration?.dispose();
    super.dispose();
  }

  void _scheduleAssistantIntent() {
    if (_assistantIntentHandled || widget.initialAssistantIntent == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _assistantIntentHandled) {
        return;
      }
      _assistantIntentHandled = true;
      _handleAssistantIntent(widget.initialAssistantIntent!);
    });
  }

  Future<void> _handleAssistantIntent(AssistantTaCourseIntent intent) async {
    if (!_assistantIntentIsCurrent(intent)) {
      _showSnackBar('日程已变化，请重新询问小U。');
      return;
    }
    switch (intent.kind) {
      case AssistantTaCourseIntentKind.open:
        return;
      case AssistantTaCourseIntentKind.add:
        final draft = intent.entry;
        if (draft == null) {
          return;
        }
        final created = await _openEditor(initialEntry: draft, isNew: true);
        if (created == null || !mounted) {
          return;
        }
        if (!_assistantIntentIsCurrent(intent)) {
          _showSnackBar('日程已变化，请重新预览后再保存。');
          return;
        }
        final result = await widget.controller.addEntry(
          created,
          expectedRevision: intent.expectedCollectionRevision,
        );
        _showMutationResult(result, successMessage: '已新增日程');
        return;
      case AssistantTaCourseIntentKind.update:
        final draft = intent.entry;
        final expectedEntryRevision = intent.expectedEntryRevision;
        if (draft == null || expectedEntryRevision == null) {
          return;
        }
        final updated = await _openEditor(initialEntry: draft);
        if (updated == null || !mounted) {
          return;
        }
        if (!_assistantIntentIsCurrent(intent)) {
          _showSnackBar('日程已变化，请重新预览后再保存。');
          return;
        }
        final result = await widget.controller.updateEntry(
          updated,
          expectedRevision: expectedEntryRevision,
        );
        _showMutationResult(result, successMessage: '已保存日程');
        return;
      case AssistantTaCourseIntentKind.delete:
        final entry = intent.entry;
        final expectedEntryRevision = intent.expectedEntryRevision;
        if (entry == null || expectedEntryRevision == null) {
          return;
        }
        final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const BnbuText('删除日程'),
            content: BnbuText('确定删除「${entry.displayTitle}」吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const BnbuText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const BnbuText('删除'),
              ),
            ],
          ),
        );
        if (shouldDelete != true || !mounted) {
          return;
        }
        if (!_assistantIntentIsCurrent(intent)) {
          _showSnackBar('日程已变化，请重新预览后再删除。');
          return;
        }
        final result = await widget.controller.deleteEntry(
          entry.id,
          expectedRevision: expectedEntryRevision,
        );
        _showMutationResult(result, successMessage: '已删除日程');
        return;
    }
  }

  bool _assistantIntentIsCurrent(AssistantTaCourseIntent intent) {
    if (widget.controller.revision != intent.expectedCollectionRevision) {
      return false;
    }
    switch (intent.kind) {
      case AssistantTaCourseIntentKind.open:
      case AssistantTaCourseIntentKind.add:
        return intent.targetIdentity ==
            AssistantActionRuntime.taCourseCollectionIdentity(
              collectionRevision: widget.controller.revision,
            );
      case AssistantTaCourseIntentKind.update:
      case AssistantTaCourseIntentKind.delete:
        final entry = intent.entry;
        final expectedEntryRevision = intent.expectedEntryRevision;
        if (entry == null || expectedEntryRevision == null) {
          return false;
        }
        final matches = widget.controller.entries.where(
          (candidate) => candidate.id == entry.id,
        );
        if (matches.length != 1) {
          return false;
        }
        final liveEntry = matches.single;
        return liveEntry.revision == expectedEntryRevision &&
            intent.targetIdentity ==
                AssistantActionRuntime.taCourseEntryIdentity(
                  entry: liveEntry,
                  collectionRevision: widget.controller.revision,
                );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: BnbuSecondaryAppBar(
        bar: AppBar(
          title: BnbuText(
            '固定日程',
            style: TextStyle(
              fontSize: BnbuHeaderMetrics.titleSize,
              fontWeight: FontWeight.w500,
            ),
          ),
          centerTitle: true,
          backgroundColor: tokens.canvas,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          actions: [
            BnbuMenuButton<_TaCoursePageAction>(
              tooltip: context.l10n.text('更多操作'),
              icon: const Icon(LucideIcons.ellipsis300),
              onSelected: (action) {
                switch (action) {
                  case _TaCoursePageAction.importEntries:
                    _importEntries();
                  case _TaCoursePageAction.exportEntries:
                    _exportEntries();
                }
              },
              itemBuilder: (context) => [
                BnbuMenuItem(
                  value: _TaCoursePageAction.importEntries,
                  icon: LucideIcons.download300,
                  child: const BnbuText('导入配置'),
                ),
                BnbuMenuItem(
                  value: _TaCoursePageAction.exportEntries,
                  enabled: _entries.isNotEmpty,
                  icon: LucideIcons.upload300,
                  child: const BnbuText('导出配置'),
                ),
              ],
            ),
          ],
        ),
      ),
      body: widget.controller.isLoading
          ? const Center(child: BnbuLoadingState(title: '正在加载日程'))
          : BnbuConstrainedContent(
              maxWidth: 1000,
              child: _buildCourseList(context),
            ),
    );
  }

  Widget _buildCourseList(BuildContext context) {
    final tokens = context.bnbuTheme;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        tokens.space16,
        tokens.space12,
        tokens.space16,
        tokens.space24,
      ),
      itemCount: _entries.length + 1,
      separatorBuilder: (_, _) => SizedBox(height: tokens.space12),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _buildCourseHeader(context);
        }
        return _buildCourseCard(context, _entries[index - 1]);
      },
    );
  }

  Widget _buildCourseHeader(BuildContext context) => Row(
    children: [
      Expanded(
        child: BnbuText(
          _entries.isEmpty ? '暂无固定日程' : '固定日程',
          style: TextStyle(
            fontSize: 14,
            color: context.bnbuTheme.textSecondary,
          ),
        ),
      ),
      TextButton.icon(
        onPressed: widget.controller.isSaving ? null : _addEntry,
        icon: const Icon(LucideIcons.plus300, size: 18),
        label: const BnbuText('新建日程'),
      ),
    ],
  );

  Widget _buildCourseCard(BuildContext context, TaCourseEntry entry) {
    final tokens = context.bnbuTheme;
    final timetable = widget.controller.timetable;
    final color = timetable == null
        ? tokens.brandBlue
        : CourseColorPalette.build(
                timetable,
                _entries,
                tokens,
              )[CourseColorPalette.taCourseSeed(entry)] ??
              tokens.brandBlue;
    return Material(
      color: color.withValues(alpha: .04),
      child: InkWell(
        onTap: widget.controller.isSaving ? null : () => _editEntry(entry),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: color.withValues(alpha: .7), width: 1.5),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BnbuText(
                      entry.displayTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    BnbuText(
                      '${context.l10n.text(_weekdayLabel(entry.weekday))}  ${entry.timeRangeLabel}',
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    BnbuText(
                      '${context.l10n.text(entry.kindLabel)} · ${context.l10n.text(_repeatLabel(entry))}${entry.location.isEmpty ? '' : ' · ${entry.location}'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                    if (entry.isTa && entry.resolveCourse(timetable) == null)
                      BnbuText(
                        '所属课程暂不可用',
                        style: TextStyle(fontSize: 12, color: tokens.warning),
                      ),
                  ],
                ),
              ),
              _buildCourseMenu(entry),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCourseMenu(TaCourseEntry entry) {
    return BnbuMenuButton<String>(
      tooltip: context.l10n.text('课程操作'),
      padding: EdgeInsets.zero,
      icon: const Icon(LucideIcons.ellipsisVertical300),
      onSelected: (value) {
        if (value == 'edit') {
          _editEntry(entry);
        } else if (value == 'delete') {
          _deleteEntry(entry);
        }
      },
      itemBuilder: (context) => [
        BnbuMenuItem(
          value: 'edit',
          icon: LucideIcons.pencil300,
          child: const BnbuText('编辑'),
        ),
        BnbuMenuItem(
          value: 'delete',
          icon: LucideIcons.trash2300,
          destructive: true,
          child: const BnbuText('删除'),
        ),
      ],
    );
  }

  Future<void> _addEntry() async {
    final created = await _openEditor();
    if (created == null) {
      return;
    }
    final result = await widget.controller.addEntry(
      created,
      expectedRevision: widget.controller.revision,
    );
    _showMutationResult(result, successMessage: '已新增日程');
  }

  Future<void> _editEntry(TaCourseEntry entry) async {
    final updated = await _openEditor(initialEntry: entry);
    if (updated == null) {
      return;
    }
    final result = await widget.controller.updateEntry(
      updated,
      expectedRevision: entry.revision,
    );
    _showMutationResult(result, successMessage: '已保存日程');
  }

  Future<void> _deleteEntry(TaCourseEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const BnbuText('删除日程'),
          content: BnbuText('确定删除「${entry.displayTitle}」吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const BnbuText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const BnbuText('删除'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true) {
      return;
    }
    final result = await widget.controller.deleteEntry(
      entry.id,
      expectedRevision: entry.revision,
    );
    _showMutationResult(result, successMessage: '已删除日程');
  }

  Future<void> _exportEntries() async {
    try {
      final payload = FixedScheduleTransfer.encode(_entries);
      final savedPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出日程配置',
        fileName: 'fixed_schedules.json',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: Uint8List.fromList(utf8.encode(payload)),
      );
      if (!mounted || savedPath == null) {
        return;
      }
      _showSnackBar('已导出日程配置');
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('导出失败，请稍后重试');
    }
  }

  Future<void> _importEntries() async {
    try {
      final pickerResult = await FilePicker.platform.pickFiles(
        dialogTitle: '导入日程配置',
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (!mounted || pickerResult == null || pickerResult.files.isEmpty) {
        return;
      }
      final file = pickerResult.files.single;
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) {
        throw const FormatException('未能读取导入文件');
      }
      final importedEntries = FixedScheduleTransfer.decode(utf8.decode(bytes));
      final diff = widget.controller.previewImport(importedEntries);
      if (!await _confirmImportDiff(diff)) {
        return;
      }
      final result = await widget.controller.applyImportDiff(diff);
      _showMutationResult(result, successMessage: _importSummary(diff));
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('导入失败，请确认文件格式正确');
    }
  }

  Future<TaCourseEntry?> _openEditor({
    TaCourseEntry? initialEntry,
    bool isNew = false,
  }) {
    return showBnbuAdaptiveModal<TaCourseEntry>(
      context: context,
      borderRadius: BorderRadius.circular(20),
      bottomSheetBackgroundColor: fixedScheduleFormBackground(context),
      dialogBackgroundColor: fixedScheduleFormBackground(context),
      dialogMaxWidth: 680,
      dialogMaxHeight: 720,
      isScrollControlled: true,
      semanticLabel: context.l10n.text(
        initialEntry == null || isNew ? '新增日程' : '编辑日程',
      ),
      contentKey: const ValueKey('ta-course-editor-modal'),
      builder: (modalContext, presentation) {
        return FixedScheduleEditor(
          timetable: widget.controller.timetable,
          initialEntry: initialEntry,
          isNew: isNew,
          showCloseButton: presentation.isDialog,
        );
      },
    );
  }

  void _handleControllerChanged() {
    if (!mounted) {
      return;
    }
    setState(() {});
    final message = widget.controller.errorMessage;
    if (message != null) {
      _showSnackBar(message);
      widget.controller.clearErrors();
    }
  }

  Future<bool> _confirmImportDiff(TaCourseImportDiff diff) async {
    if (diff.conflicts.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const BnbuText('导入存在冲突'),
            content: BnbuText(
              '导入文件中有 ${diff.conflicts.length} 条日程与当前配置冲突。'
              '请先导出最新配置并合并后再导入。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const BnbuText('知道了'),
              ),
            ],
          );
        },
      );
      return false;
    }
    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const BnbuText('确认导入日程'),
          content: BnbuText(
            '将新增 ${diff.additions.length} 条、更新 ${diff.updates.length} 条、'
            '删除 ${diff.deletions.length} 条。导入会按当前版本再次校验，'
            '不会直接覆盖整表。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const BnbuText('取消'),
            ),
            FilledButton(
              onPressed: diff.hasChanges
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const BnbuText('导入'),
            ),
          ],
        );
      },
    );
    if (!diff.hasChanges) {
      _showSnackBar('没有需要导入的变化');
    }
    return shouldApply == true;
  }

  void _showMutationResult(
    TaCourseMutationResult result, {
    required String successMessage,
  }) {
    if (!mounted) {
      return;
    }
    if (result.isSuccess) {
      _showSnackBar(successMessage);
      return;
    }
    final message = widget.controller.errorMessage;
    if (message != null) {
      _showSnackBar(message);
      widget.controller.clearErrors();
    }
  }

  String _importSummary(TaCourseImportDiff diff) {
    return '已导入：新增 ${diff.additions.length} 条、更新 ${diff.updates.length} 条、删除 ${diff.deletions.length} 条';
  }

  String _repeatLabel(TaCourseEntry entry) {
    if (entry.repeatType == TaCourseRepeatType.weekly) {
      return entry.activeWeekStarts == null
          ? '每周重复'
          : '已选 ${entry.activeWeekStarts!.length} 周';
    }
    final weekStart = entry.weekStart;
    if (weekStart == null) {
      return '单独周';
    }
    return '${context.l10n.formatMonthDay(weekStart)} 所在周';
  }

  String _weekdayLabel(int weekday) {
    const labels = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[(weekday - 1).clamp(0, 6)];
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: BnbuText(message)));
  }
}
