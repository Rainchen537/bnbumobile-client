import '../pages/file_preview_page.dart';
import 'bnbu_menu.dart';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/course_summary.dart';
import '../services/course_archive_export_service.dart';
import '../services/desktop_download_service.dart';
import 'desktop_download_directory_tile.dart';
import '../services/course_archive_service.dart';
import '../services/courseware_download_plan.dart';
import '../services/moodle_api_client.dart';
import '../services/native_actions.dart';
import '../state/app_session_controller.dart';
import '../state/assistant_resource_library_controller.dart';
import '../theme/app_theme.dart';
import 'assistant_resource_library_scope.dart';
import 'bnbu_adaptive_modal.dart';
import 'bnbu_loading.dart';

class CoursewareDownloadButton extends StatefulWidget {
  const CoursewareDownloadButton({
    super.key,
    required this.controller,
    required this.course,
    this.enabled = true,
    this.fileUrls,
    this.label = '下载全部课件',
    this.iconOnly = false,
    this.nativeActions = const NativeActions(),
    this.archiveBuilder,
    this.archiveExporter = const CourseArchiveExportService(),
    this.desktopDownloads = const DesktopDownloadService(),
  });

  final AppSessionController controller;
  final CourseSummary course;
  final bool enabled;
  final Set<String>? fileUrls;
  final String label;
  final bool iconOnly;
  final NativeActions nativeActions;
  final CourseArchiveBuilder? archiveBuilder;
  final CourseArchiveExportService archiveExporter;
  final DesktopDownloadService desktopDownloads;

  @override
  State<CoursewareDownloadButton> createState() =>
      _CoursewareDownloadButtonState();
}

class _CoursewareDownloadButtonState extends State<CoursewareDownloadButton> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    if (widget.iconOnly) {
      return IconButton(
        key: const ValueKey('ispace-download-all-courseware'),
        tooltip: context.l10n.text(widget.label),
        onPressed: widget.enabled && !_open ? _showDownloads : null,
        icon: const Icon(LucideIcons.download300, size: 22),
      );
    }
    return TextButton.icon(
      key: const ValueKey('ispace-download-all-courseware'),
      onPressed: widget.enabled && !_open ? _showDownloads : null,
      icon: const Icon(LucideIcons.download300, size: 18),
      label: BnbuText(widget.label),
      style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
    );
  }

  Future<void> _showDownloads() async {
    final library = AssistantResourceLibraryScope.maybeOf(context);
    final configuration = widget;
    setState(() => _open = true);
    await showBnbuAdaptiveModal<void>(
      context: context,
      dialogMaxWidth: 660,
      semanticLabel: context.l10n.text(widget.label),
      builder: (context, presentation) => _CoursewareDownloadModal(
        fileUrls: configuration.fileUrls,
        label: configuration.label,
        controller: configuration.controller,
        course: configuration.course,
        nativeActions: configuration.nativeActions,
        archiveBuilder: configuration.archiveBuilder,
        archiveExporter: configuration.archiveExporter,
        desktopDownloads: configuration.desktopDownloads,
        library: library,
        presentation: presentation,
      ),
    );
    if (mounted) setState(() => _open = false);
  }
}

class _CoursewareDownloadModal extends StatefulWidget {
  const _CoursewareDownloadModal({
    required this.controller,
    required this.course,
    required this.fileUrls,
    required this.label,
    required this.nativeActions,
    required this.archiveBuilder,
    required this.archiveExporter,
    required this.desktopDownloads,
    required this.library,
    required this.presentation,
  });

  final Set<String>? fileUrls;
  final String label;
  final AppSessionController controller;
  final CourseSummary course;
  final NativeActions nativeActions;
  final CourseArchiveBuilder? archiveBuilder;
  final CourseArchiveExportService archiveExporter;
  final DesktopDownloadService desktopDownloads;
  final AssistantResourceLibraryController? library;
  final BnbuAdaptiveModalPresentation presentation;

  @override
  State<_CoursewareDownloadModal> createState() =>
      _CoursewareDownloadModalState();
}

class _CoursewareDownloadModalState extends State<_CoursewareDownloadModal> {
  late final _lease = widget.controller.captureSessionLease();
  late final CourseArchiveBuilder _builder =
      widget.archiveBuilder ?? CourseArchiveService(continueOnFileError: true);
  CoursewareDownloadPlan? _plan;
  final _selected = <String>{};
  bool _loading = true;
  bool _downloading = false;
  bool _saving = false;
  bool _savedToLibrary = false;
  bool _exported = false;
  String? _error;
  CourseArchiveProgress? _progress;
  CourseArchiveResult? _result;
  List<CourseArchiveFailure> _failures = const [];

  bool get _active => mounted && (_lease?.isActive ?? false);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sessionChanged);
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sessionChanged);
    if (widget.archiveBuilder == null && _builder is CourseArchiveService) {
      _builder.dispose();
    }
    super.dispose();
  }

  void _sessionChanged() {
    if (_active || !mounted) return;
    if (widget.archiveBuilder == null && _builder is CourseArchiveService) {
      _builder.dispose();
    }
    setState(() {
      _plan = null;
      _result = null;
      _selected.clear();
      _progress = null;
      _failures = const [];
      _error = '登录状态已变化，请重新打开课程页面。';
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await widget.controller.loadCoursewareDownloadPlan(
        widget.course.id,
      );
      if (!_active) return;
      setState(() {
        _plan = CoursewareDownloadPlan(
          files: plan.files
              .where(
                (f) =>
                    widget.fileUrls == null || widget.fileUrls!.contains(f.url),
              )
              .toList(),
          unavailablePages: plan.unavailablePages,
          skippedLinks: plan.skippedLinks,
        );
        _selected
          ..clear()
          ..addAll(_plan!.files.map((file) => file.url));
      });
    } on CourseArchiveException catch (error) {
      if (_active) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取课件清单，请重试。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final files = _plan?.files
        .where((file) => _selected.contains(file.url))
        .toList();
    if (!_active || files == null || files.isEmpty || _downloading) return;
    setState(() {
      _downloading = true;
      _error = null;
      _progress = null;
      _exported = false;
    });
    try {
      // Revalidate visibility/permission at confirmation, not only when opening
      // a picker which may have been left open for a long time.
      final discovered = await widget.controller.loadCoursewareDownloadPlan(
        widget.course.id,
      );
      if (!_active) return;
      final current = CoursewareDownloadPlan(
        files: discovered.files
            .where(
              (f) =>
                  widget.fileUrls == null || widget.fileUrls!.contains(f.url),
            )
            .toList(),
        unavailablePages: discovered.unavailablePages,
        skippedLinks: discovered.skippedLinks,
      );
      final liveUrls = current.files.map((file) => file.url).toSet();
      if (!files.every((file) => liveUrls.contains(file.url))) {
        if (_builder is CourseArchiveService) {
          await _builder.discardCachedFiles();
          if (!_active) return;
        }
        setState(() {
          _result = null;
          _failures = const [];
          _plan = current;
          _selected
            ..clear()
            ..addAll(current.files.map((file) => file.url));
          _error = '课件清单已变化，请重新选择。';
        });
        return;
      }
      if (current.files
              .where((file) => _selected.contains(file.url))
              .fold<int>(0, (sum, file) => sum + file.expectedBytes) >
          512 * 1024 * 1024) {
        throw const CourseArchiveException('课程文件总大小超过 512 MB。');
      }
      final session = await widget.controller.prepareWebSession();
      if (!_active) return;
      if (!urlsHaveSameOrigin(session.baseUrl, widget.controller.baseUrl)) {
        throw const CourseArchiveException('下载会话无效。');
      }
      final cache = await widget.nativeActions
          .getMailAttachmentCacheDirectory();
      if (!_active) return;
      final result = await _builder.build(
        cacheDirectory: cache,
        archiveName: widget.course.fullName,
        baseUrl: session.baseUrl,
        cookieHeader: session.cookies
            .map((cookie) => '${cookie.name}=${cookie.value}')
            .join('; '),
        entries: current.files
            .where((file) => _selected.contains(file.url))
            .toList(),
        sessionIsActive: () => _active,
        onProgress: (progress) {
          if (_active) setState(() => _progress = progress);
        },
      );
      if (!_active) {
        final file = File(result.path);
        if (await file.exists()) await file.delete();
        return;
      }
      var available = result;
      _savedToLibrary = false;
      // Keep partial results available for export, but do not label an
      // incomplete course as an archived course pack in the resource library.
      if (widget.library != null && result.failures.isEmpty) {
        try {
          final resource = await widget.library!.importCourseArchive(
            sourcePath: result.path,
            fileName: result.fileName,
            courseTitle: widget.course.fullName,
            fileCount: result.fileCount,
            totalBytes: result.totalBytes,
            selectedFileNames: result.completedFileNames.isNotEmpty
                ? result.completedFileNames
                : files.map((file) => file.fileName).toList(),
          );
          available = CourseArchiveResult(
            path: resource.filePath,
            fileName: resource.fileName,
            fileCount: result.fileCount,
            totalBytes: result.totalBytes,
            completedFileNames: result.completedFileNames,
          );
          _savedToLibrary = true;
        } catch (_) {
          if (_active) _error = 'ZIP 已生成，但保存到资源库失败。';
        }
      }
      if (_active) {
        setState(() {
          _result = available;
          _failures = result.failures;
        });
        if (DesktopDownloadService.supported && result.failures.isEmpty) {
          await _saveZip();
        }
      }
    } on CourseArchiveException catch (error) {
      // Only locally authored archive errors are displayed, never server bodies.
      if (_active) {
        setState(() {
          _error = error.message;
          if (error.failures.isNotEmpty) _failures = error.failures;
        });
      }
    } on MoodleApiException catch (_) {
      if (_active) setState(() => _error = '课件下载未完成，请重试。');
    } catch (_) {
      if (_active) setState(() => _error = '课件下载未完成，请重试。');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _saveZip() async {
    final result = _result;
    if (!_active || result == null || _saving) return;
    setState(() => _saving = true);
    try {
      final saved = DesktopDownloadService.supported
          ? await widget.desktopDownloads.save(
                  sourcePath: result.path,
                  fileName: result.fileName,
                  purpose: DesktopDownloadPurpose.archive,
                  isActive: () => _active,
                ) !=
                null
          : await widget.archiveExporter.export(
              sourcePath: result.path,
              dialogTitle: context.l10n.text('保存 ZIP'),
              fileName: result.fileName,
              isActive: () => _active,
            );
      if (saved && _active) {
        setState(() {
          _error = null;
          _exported = true;
        });
      }
    } catch (_) {
      if (_active) setState(() => _error = 'ZIP 保存失败，请重试。');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openZip() async {
    if (!_active || _result == null) return;
    try {
      await showFilePreview(
        context,
        title: _result!.fileName,
        nativeActions: widget.nativeActions,
        path: _result!.path,
        mimeType: 'application/zip',
      );
    } catch (_) {
      if (_active) setState(() => _error = '无法打开 ZIP，请先保存到本机。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final result = _result;
    final desktop =
        !kIsWeb &&
        const {
          TargetPlatform.macOS,
          TargetPlatform.windows,
          TargetPlatform.linux,
        }.contains(defaultTargetPlatform);
    return BnbuModalFrame(
      presentation: widget.presentation,
      title: widget.label,
      icon: LucideIcons.download300,
      bottomBar: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: BnbuText(_downloading ? '取消下载' : '关闭'),
          ),
          if (result != null && !_downloading) ...[
            if (desktop)
              OutlinedButton(
                onPressed: _saving ? null : _saveZip,
                child: const BnbuText('保存 ZIP'),
              ),
            FilledButton(
              onPressed: _saving ? null : _openZip,
              child: const BnbuText('打开 ZIP'),
            ),
          ],
          if (_failures.isNotEmpty && !_downloading && !_saving && _active)
            FilledButton(onPressed: _download, child: const BnbuText('重试失败项'))
          else if (result == null && !_loading && !_downloading && _active)
            FilledButton(
              onPressed: _selected.isEmpty ? null : _download,
              child: const BnbuText('下载并生成 ZIP'),
            ),
        ],
      ),
      child: SizedBox(
        height: 440,
        child: ListView(
          children: [
            if (DesktopDownloadService.supported)
              DesktopDownloadDirectoryTile(
                purpose: DesktopDownloadPurpose.archive,
                service: widget.desktopDownloads,
                enabled: !_downloading && !_saving && _active,
              ),
            Text(
              widget.course.fullName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BnbuText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_loading || _downloading || _saving) ...[
              if (_loading)
                const BnbuInitialLoading()
              else
                LinearProgressIndicator(
                  value: _downloading && _progress != null
                      ? _progress!.completedFiles / _progress!.totalFiles
                      : null,
                ),
              const SizedBox(height: 12),
              BnbuText(
                _loading
                    ? '正在读取课件清单…'
                    : _saving
                    ? '正在保存…'
                    : '正在下载并打包…',
              ),
              if (_progress != null) ...[
                Text('${_progress!.completedFiles} / ${_progress!.totalFiles}'),
                Text(_progress!.currentFileName),
              ],
            ] else if (result != null) ...[
              Icon(
                _failures.isEmpty
                    ? LucideIcons.circleCheck300
                    : LucideIcons.circleAlert300,
                size: 32,
              ),
              const SizedBox(height: 12),
              BnbuText(_failures.isEmpty ? 'ZIP 已生成' : '部分课件已打包'),
              Text(
                '${context.l10n.text('已下载')} ${result.fileCount} / ${result.fileCount + _failures.length}',
              ),
              Text(result.fileName),
              if (_savedToLibrary) const BnbuText('已保存到本机小U资源库'),
              if (_exported) const BnbuText('ZIP 已保存到所选位置'),
            ] else if (plan != null) ...[
              if (plan.unavailablePages > 0)
                const BnbuText('部分课程页面读取失败，清单可能不完整。'),
              if (plan.skippedLinks > 0) const BnbuText('非同源或不安全的文件链接已排除。'),
              if (plan.files.isEmpty)
                const BnbuText('当前课程没有可下载的课件。')
              else ...[
                Row(
                  children: [
                    Checkbox(
                      value: _selected.length == plan.files.length,
                      onChanged: (value) => setState(() {
                        _selected.clear();
                        if (value == true) {
                          _selected.addAll(plan.files.map((file) => file.url));
                        }
                      }),
                    ),
                    const Expanded(child: BnbuText('全选')),
                    Text('${_selected.length} / ${plan.files.length}'),
                  ],
                ),
                const BnbuText('按章节生成 ZIP，仅保存到本机，单次最多 512 MB。'),
                const SizedBox(height: 8),
                for (final file in plan.files)
                  BnbuCheckTile(
                    value: _selected.contains(file.url),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selected.add(file.url);
                      } else {
                        _selected.remove(file.url);
                      }
                    }),
                    title: Text(
                      file.displayName.isEmpty
                          ? file.fileName
                          : file.displayName,
                    ),
                    subtitle: Text(
                      '${file.sectionName} · ${file.moduleName} · ${file.fileName}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              if (plan.unavailablePages > 0)
                TextButton(onPressed: _load, child: const BnbuText('重新读取')),
            ] else if (_active)
              TextButton(onPressed: _load, child: const BnbuText('重试')),
            if (_failures.isNotEmpty && !_downloading) ...[
              const SizedBox(height: 12),
              const BnbuText('未下载的文件'),
              for (final failure in _failures)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(LucideIcons.fileWarning300, size: 20),
                  title: Text(failure.entry.fileName),
                  subtitle: BnbuText(failure.message),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
