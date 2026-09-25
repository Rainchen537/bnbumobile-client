import '../pages/file_preview_page.dart';
import '../widgets/ispace_content_padding.dart';
import '../widgets/bnbu_menu.dart';
import '../widgets/ispace_course_workspace.dart';
import 'ispace_course_module_navigation.dart';
import 'dart:async';

import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../widgets/bnbu_loading.dart';
import '../theme/app_theme.dart';

import '../models/assistant_models.dart';
import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../services/assistant_context_coordinator.dart';
import '../services/assistant_resource_library_store.dart';
import '../services/course_archive_service.dart';
import '../services/moodle_api_client.dart';
import '../services/native_actions.dart';
import '../state/app_session_controller.dart';
import '../state/assistant_resource_library_controller.dart';
import '../widgets/assistant_context_scope.dart';
import '../widgets/assistant_resource_library_scope.dart';
import '../widgets/bnbu_adaptive.dart';
import '../widgets/bnbu_notice.dart';

class CourseDetailPage extends StatefulWidget {
  const CourseDetailPage({
    super.key,
    required this.controller,
    required this.course,
    this.initialBatchDownloadIntent = false,
    this.initialBatchFileScope = AssistantCourseFileScope.all,
    this.nativeActions = const NativeActions(),
    this.archiveBuilder,
    this.resourceLibrary,
  });

  final AppSessionController controller;
  final CourseSummary course;
  final bool initialBatchDownloadIntent;
  final AssistantCourseFileScope initialBatchFileScope;
  final NativeActions nativeActions;
  final CourseArchiveBuilder? archiveBuilder;
  final AssistantResourceLibraryController? resourceLibrary;

  @override
  State<CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends State<CourseDetailPage> {
  static const int _maxBatchCandidates = 100;
  static const int _maxBatchSelection = 100;
  static const int _maxKnownBatchBytes = 512 * 1024 * 1024;

  AssistantContextCoordinator? _contextCoordinator;
  AssistantContextRegistration? _contextRegistration;
  AssistantResourceLibraryController? _resourceLibrary;

  bool _loading = true;
  bool _isBatchDownloading = false;
  late final CourseArchiveBuilder _archiveBuilder =
      widget.archiveBuilder ?? CourseArchiveService();
  late final bool _ownsArchiveBuilder = widget.archiveBuilder == null;
  late bool _pendingInitialBatchDownload = widget.initialBatchDownloadIntent;
  String? _error;
  String? _batchProgress;
  CourseArchiveResult? _archiveResult;
  List<CourseContentSection> _sections = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resourceLibrary =
        widget.resourceLibrary ??
        AssistantResourceLibraryScope.maybeOf(context);
    final coordinator = AssistantContextScope.maybeOf(context);
    if (coordinator == null || identical(coordinator, _contextCoordinator)) {
      return;
    }
    _contextRegistration?.dispose();
    _contextCoordinator = coordinator;
    _contextRegistration = coordinator.register(
      AssistantContextContribution(
        currentPage: () => AssistantCurrentPageContext(
          pageType: 'course',
          title: widget.course.fullName,
          selectedItemId: widget.course.id.toString(),
          summary: widget.course.categoryName,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _contextRegistration?.dispose();
    if (_ownsArchiveBuilder && _archiveBuilder is CourseArchiveService) {
      _archiveBuilder.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sections = await widget.controller.loadCourseContents(
        widget.course.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sections = sections;
      });
    } on MoodleApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '课程内容加载失败，请稍后重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
        if (_error == null && _pendingInitialBatchDownload) {
          _pendingInitialBatchDownload = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(
                _startBatchDownload(
                  automaticallySelectSafeFiles: true,
                  initialScope: widget.initialBatchFileScope,
                ),
              );
            }
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bnbuTheme.canvas,
      appBar: BnbuSecondaryAppBar(
        bar: AppBar(
          title: BnbuText(widget.course.fullName),
          actions: [
            IconButton(
              onPressed: _loading || _isBatchDownloading
                  ? null
                  : _startBatchDownload,
              icon: _isBatchDownloading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: BnbuActivityIndicator(),
                    )
                  : const Icon(LucideIcons.fileDown300),
              tooltip: context.l10n.text(
                _isBatchDownloading ? '正在批量下载' : '批量下载课程文件',
              ),
            ),
            IconButton(
              onPressed: _loading || _isBatchDownloading ? null : _load,
              icon: const Icon(LucideIcons.refreshCw300),
              tooltip: context.l10n.text('刷新'),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: BnbuConstrainedContent(
          maxWidth: BnbuBreakpoints.contentMax,
          child: BnbuLoadingRegion(
            child: Column(
              children: [
                for (final overview in _courseOverviewChildren())
                  IspaceContentPadding(child: overview),
                Expanded(
                  child: IspaceCourseWorkspace(
                    course: widget.course,
                    sections: _sections,
                    controller: widget.controller,
                    loading: _loading,
                    error: _error,
                    showCourseHeading: false,
                    onRefresh: _load,
                    onOpenModule: (module) => openIspaceCourseModule(
                      context: context,
                      controller: widget.controller,
                      course: widget.course,
                      module: module,
                      sections: _sections,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _courseOverviewChildren() {
    return [
      if (_batchProgress case final progress?) ...[
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BnbuUpdateProgress(active: true),
                const SizedBox(height: 10),
                BnbuText(
                  progress,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (_archiveResult case final result?) ...[
        _archiveCard(result),
        const SizedBox(height: 12),
      ],
    ];
  }

  Widget _archiveCard(CourseArchiveResult result) {
    return Card(
      key: const ValueKey('course-archive-card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const CircleAvatar(child: Icon(LucideIcons.archive300)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BnbuText(
                    result.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  BnbuText(
                    '${result.fileCount} 个文件 · ${_formatBytes(result.totalBytes)}',
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              key: const ValueKey('open-course-archive'),
              onPressed: () => _openArchive(result),
              icon: const Icon(LucideIcons.download300),
              label: const BnbuText('打开 ZIP'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startBatchDownload({
    bool automaticallySelectSafeFiles = false,
    AssistantCourseFileScope initialScope = AssistantCourseFileScope.all,
  }) async {
    if (_loading || _isBatchDownloading || !mounted) {
      return;
    }

    final plan = _buildBatchDownloadPlan();
    if (plan.files.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('当前课程没有可安全批量下载的文件。')));
      return;
    }

    final selected = automaticallySelectSafeFiles
        ? _defaultSelectionForScope(plan, initialScope)
        : await _selectCourseFiles(plan, initialScope: initialScope);
    if (!mounted || selected == null || selected.isEmpty) {
      if (automaticallySelectSafeFiles && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: BnbuText(
              '小U没有找到符合“${_courseFileScopeLabel(initialScope)}”的文件，'
              '请回到对话补充要打包的类型。',
            ),
          ),
        );
      }
      return;
    }
    final confirmed = await _confirmCourseDownload(
      selected,
      assistantSelected: automaticallySelectSafeFiles,
      scope: initialScope,
    );
    if (!mounted || confirmed != true) {
      return;
    }
    await _downloadCourseFiles(selected);
  }

  _CourseDownloadPlan _buildBatchDownloadPlan({
    List<CourseContentSection>? sections,
  }) {
    final uniqueFiles = <String, _CourseDownloadFile>{};
    var invalidCount = 0;
    var duplicateCount = 0;

    for (final section in sections ?? _sections) {
      if (!section.visible || !section.userVisible) continue;
      for (final module in section.modules) {
        if (!module.visible || !module.userVisible) continue;
        for (final content in module.contents) {
          final url = _normalizedCourseFileUrl(content.fileUrl);
          if (url.isEmpty) {
            if (content.fileUrl.trim().isNotEmpty) {
              invalidCount++;
            }
            continue;
          }
          if (uniqueFiles.containsKey(url)) {
            duplicateCount++;
            continue;
          }
          uniqueFiles[url] = _CourseDownloadFile(
            url: url,
            fileName: safeAttachmentFileName(content.fileName),
            sectionName: section.name,
            moduleName: module.name,
            size: content.fileSize < 0 ? 0 : content.fileSize,
          );
        }
      }
    }

    final allFiles = uniqueFiles.values.toList(growable: false);
    final visibleFiles = allFiles
        .take(_maxBatchCandidates)
        .toList(growable: false);
    return _CourseDownloadPlan(
      files: visibleFiles,
      invalidCount: invalidCount,
      duplicateCount: duplicateCount,
      truncatedCount: allFiles.length - visibleFiles.length,
    );
  }

  String _normalizedCourseFileUrl(String rawUrl) {
    final source = rawUrl.trim();
    final baseUri = Uri.tryParse(widget.controller.baseUrl);
    final parsed = Uri.tryParse(source);
    if (source.isEmpty || baseUri == null || parsed == null) {
      return '';
    }

    final resolved = parsed.hasScheme || parsed.hasAuthority
        ? parsed
        : baseUri.resolveUri(parsed);
    if (resolved.userInfo.isNotEmpty ||
        !urlsHaveSameOrigin(resolved.toString(), baseUri.toString())) {
      return '';
    }

    final normalizedPath = resolved.path.replaceFirst(
      '/webservice/pluginfile.php',
      '/pluginfile.php',
    );
    if (!normalizedPath.contains('/pluginfile.php')) {
      return '';
    }
    final query = Map<String, String>.from(resolved.queryParameters)
      ..removeWhere((key, _) => key.toLowerCase() == 'token')
      ..['forcedownload'] = '1';
    return resolved
        .replace(path: normalizedPath, queryParameters: query, fragment: '')
        .toString();
  }

  Future<List<_CourseDownloadFile>?> _selectCourseFiles(
    _CourseDownloadPlan plan, {
    AssistantCourseFileScope initialScope = AssistantCourseFileScope.all,
  }) {
    final selectedUrls = _defaultSelectionForScope(
      plan,
      initialScope,
    ).map((file) => file.url).toSet();
    var selectionError = '';

    return showDialog<List<_CourseDownloadFile>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final selectedFiles = plan.files
                .where((file) => selectedUrls.contains(file.url))
                .toList(growable: false);
            final selectedBytes = selectedFiles.fold<int>(
              0,
              (total, file) => total + file.size,
            );
            final notices = <String>[
              if (initialScope != AssistantCourseFileScope.all)
                selectedUrls.isEmpty
                    ? '小U没有自动识别到${_courseFileScopeLabel(initialScope)}，请手动核对'
                    : '小U已预选${_courseFileScopeLabel(initialScope)}，其他文件保持未选',
              if (plan.duplicateCount > 0) '已去重 ${plan.duplicateCount} 个重复文件',
              if (plan.invalidCount > 0) '已忽略 ${plan.invalidCount} 个非同源或无效地址',
              if (plan.truncatedCount > 0)
                '文件较多，本次仅显示前 $_maxBatchCandidates 个，另有 ${plan.truncatedCount} 个未列出',
            ];

            return AlertDialog(
              title: const BnbuText('选择课程文件'),
              content: SizedBox(
                width: 560,
                height: MediaQuery.sizeOf(context).height * 0.58,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BnbuText(
                      '已选 ${selectedFiles.length}/$_maxBatchSelection 个'
                      '${selectedBytes > 0 ? ' · ${_formatBytes(selectedBytes)}' : ''}',
                    ),
                    if (notices.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      BnbuText(
                        notices.join('；'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    if (selectionError.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      BnbuText(
                        selectionError,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: plan.files.length,
                        itemBuilder: (context, index) {
                          final file = plan.files[index];
                          final isSelected = selectedUrls.contains(file.url);
                          return BnbuCheckTile(
                            value: isSelected,
                            title: BnbuText(
                              file.fileName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: BnbuText(
                              '${_courseFileCategoryLabel(file)} · '
                              '${file.sectionName} · ${file.moduleName}'
                              '${file.size > 0 ? ' · ${_formatBytes(file.size)}' : ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged: (value) {
                              setDialogState(() {
                                selectionError = '';
                                if (value != true) {
                                  selectedUrls.remove(file.url);
                                  return;
                                }
                                if (selectedUrls.length >= _maxBatchSelection) {
                                  selectionError =
                                      '一次最多选择 $_maxBatchSelection 个文件。';
                                  return;
                                }
                                final nextBytes = selectedBytes + file.size;
                                if (file.size > 0 &&
                                    nextBytes > _maxKnownBatchBytes) {
                                  selectionError = '已知文件总大小不能超过 512 MB。';
                                  return;
                                }
                                selectedUrls.add(file.url);
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      selectedUrls.clear();
                      selectionError = '';
                    });
                  },
                  child: const BnbuText('清空'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const BnbuText('取消'),
                ),
                FilledButton(
                  onPressed: selectedFiles.isEmpty
                      ? null
                      : () => Navigator.of(dialogContext).pop(selectedFiles),
                  child: const BnbuText('下一步'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<_CourseDownloadFile> _defaultSelectionForScope(
    _CourseDownloadPlan plan,
    AssistantCourseFileScope scope,
  ) {
    final matches = scope == AssistantCourseFileScope.all
        ? plan.files
        : plan.files.where((file) => _matchesCourseFileScope(file, scope));
    return _boundedSafeSelection(matches);
  }

  List<_CourseDownloadFile> _boundedSafeSelection(
    Iterable<_CourseDownloadFile> files,
  ) {
    final selected = <_CourseDownloadFile>[];
    var knownBytes = 0;
    for (final file in files) {
      if (selected.length >= _maxBatchSelection) {
        break;
      }
      final nextBytes = knownBytes + file.size;
      if (file.size > 0 && nextBytes > _maxKnownBatchBytes) {
        continue;
      }
      selected.add(file);
      knownBytes = nextBytes;
    }
    return List.unmodifiable(selected);
  }

  bool _matchesCourseFileScope(
    _CourseDownloadFile file,
    AssistantCourseFileScope scope,
  ) {
    final extension = _courseFileExtension(file.fileName);
    const presentations = {'ppt', 'pptx', 'pptm', 'key', 'odp'};
    const documents = {
      'pdf',
      'doc',
      'docx',
      'odt',
      'rtf',
      'txt',
      'md',
      'xls',
      'xlsx',
      'csv',
    };
    const media = {'mp3', 'm4a', 'wav', 'aac', 'mp4', 'mov', 'm4v', 'webm'};
    const archives = {'zip', 'rar', '7z', 'tar', 'gz', 'dmg', 'pkg', 'exe'};
    return switch (scope) {
      AssistantCourseFileScope.all => true,
      AssistantCourseFileScope.presentations => presentations.contains(
        extension,
      ),
      AssistantCourseFileScope.presentationsAndPdf =>
        presentations.contains(extension) || extension == 'pdf',
      AssistantCourseFileScope.documents => documents.contains(extension),
      AssistantCourseFileScope.media => media.contains(extension),
      AssistantCourseFileScope.archives => archives.contains(extension),
    };
  }

  String _courseFileCategoryLabel(_CourseDownloadFile file) {
    final extension = _courseFileExtension(file.fileName);
    if (const {'ppt', 'pptx', 'pptm', 'key', 'odp'}.contains(extension)) {
      return '演示文稿';
    }
    if (extension == 'pdf') {
      return 'PDF 课件/文档';
    }
    if (const {
      'doc',
      'docx',
      'odt',
      'rtf',
      'txt',
      'md',
      'xls',
      'xlsx',
      'csv',
    }.contains(extension)) {
      return '文档';
    }
    if (const {
      'mp3',
      'm4a',
      'wav',
      'aac',
      'mp4',
      'mov',
      'm4v',
      'webm',
    }.contains(extension)) {
      return '音视频';
    }
    if (const {
      'zip',
      'rar',
      '7z',
      'tar',
      'gz',
      'dmg',
      'pkg',
      'exe',
    }.contains(extension)) {
      return '压缩包/安装文件';
    }
    return extension.isEmpty ? '其他文件' : extension.toUpperCase();
  }

  String _courseFileScopeLabel(AssistantCourseFileScope scope) {
    return switch (scope) {
      AssistantCourseFileScope.all => '全部课程文件',
      AssistantCourseFileScope.presentations => '演示文稿',
      AssistantCourseFileScope.presentationsAndPdf => '演示文稿与 PDF 课件',
      AssistantCourseFileScope.documents => '文档',
      AssistantCourseFileScope.media => '音视频',
      AssistantCourseFileScope.archives => '压缩包',
    };
  }

  String _courseFileExtension(String fileName) {
    final normalized = fileName.trim().toLowerCase();
    final separator = normalized.lastIndexOf('.');
    if (separator < 0 || separator == normalized.length - 1) {
      return '';
    }
    return normalized.substring(separator + 1);
  }

  Future<bool?> _confirmCourseDownload(
    List<_CourseDownloadFile> selected, {
    bool assistantSelected = false,
    AssistantCourseFileScope scope = AssistantCourseFileScope.all,
  }) {
    final knownBytes = selected.fold<int>(
      0,
      (total, file) => total + file.size,
    );
    final preview = selected
        .take(6)
        .map((file) => '• ${file.fileName}')
        .join('\n');
    final remaining = selected.length - 6;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: BnbuText(assistantSelected ? '小U已选好打包内容' : '确认生成 ZIP'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BnbuText(
                    assistantSelected
                        ? '小U按“${_courseFileScopeLabel(scope)}”匹配了 '
                              '${selected.length} 个文件'
                              '${knownBytes > 0 ? '，已知总大小 ${_formatBytes(knownBytes)}' : ''}。'
                        : '将在本机整理 ${selected.length} 个课程文件'
                              '${knownBytes > 0 ? '，已知总大小 ${_formatBytes(knownBytes)}' : ''}。',
                  ),
                  const SizedBox(height: 12),
                  BnbuText(
                    preview,
                    style: Theme.of(dialogContext).textTheme.bodyMedium,
                  ),
                  if (remaining > 0) ...[
                    const SizedBox(height: 4),
                    BnbuText(
                      '另有 $remaining 个文件',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  BnbuText(
                    '确认后会按“章节 / 活动 / 文件名”生成 ZIP 并保存到小U资源库。'
                    '登录 Cookie 只会发送到 iSpace 同源地址，文件正文不会交给小U服务端。',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const BnbuText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const BnbuText('生成 ZIP'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadCourseFiles(List<_CourseDownloadFile> selected) async {
    final lease = widget.controller.captureSessionLease();
    if (lease == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: BnbuText('登录状态已失效，请重新登录后下载。')));
      return;
    }

    setState(() {
      _isBatchDownloading = true;
      _batchProgress = context.l10n.isEnglish
          ? 'Checking course files…'
          : context.l10n.text('正在核对课件列表…');
    });

    try {
      final latest = await widget.controller.loadCourseContents(
        widget.course.id,
      );
      if (!mounted || !lease.isActive) {
        throw MoodleApiException('登录状态已变化，请重新打开课程页面。');
      }
      setState(() => _sections = latest);
      final current = {
        for (final file in _buildBatchDownloadPlan(sections: latest).files)
          file.url: file,
      };
      final approved = [
        for (final file in selected)
          if (current[file.url] case final currentFile?) currentFile,
      ];
      if (approved.length != selected.length ||
          approved.fold<int>(0, (sum, file) => sum + file.size) >
              _maxKnownBatchBytes) {
        throw MoodleApiException(
          context.l10n.isEnglish
              ? 'The course file list has changed. Select the files again before downloading.'
              : context.l10n.text('课件列表已变化，请重新选择后下载。'),
        );
      }
      final snapshot = await widget.controller.prepareWebSession();
      if (!lease.isActive ||
          !urlsHaveSameOrigin(snapshot.baseUrl, widget.controller.baseUrl)) {
        throw MoodleApiException('登录状态已变化，请重新打开课程页面。');
      }
      final cookieHeader = snapshot.cookies
          .where((cookie) => cookie.name.trim().isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
      if (cookieHeader.isEmpty) {
        throw MoodleApiException('未能建立安全下载会话，请稍后重试。');
      }
      final cacheDirectory = await widget.nativeActions
          .getMailAttachmentCacheDirectory();
      final result = await _archiveBuilder.build(
        cacheDirectory: cacheDirectory,
        archiveName: widget.course.fullName,
        baseUrl: snapshot.baseUrl,
        cookieHeader: cookieHeader,
        entries: approved
            .map(
              (file) => CourseArchiveEntry(
                url: file.url,
                sectionName: file.sectionName,
                moduleName: file.moduleName,
                fileName: file.fileName,
                expectedBytes: file.size,
              ),
            )
            .toList(growable: false),
        sessionIsActive: () => lease.isActive,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _batchProgress =
                '正在整理 ${progress.completedFiles}/${progress.totalFiles}：'
                '${progress.currentFileName}';
          });
        },
      );
      if (!lease.isActive) {
        throw MoodleApiException('登录状态已变化，请重新打开课程页面。');
      }
      var availableResult = result;
      var savedToLibrary = false;
      final resourceLibrary = widget.resourceLibrary ?? _resourceLibrary;
      if (resourceLibrary != null) {
        try {
          final resource = await resourceLibrary.importCourseArchive(
            sourcePath: result.path,
            fileName: result.fileName,
            courseTitle: widget.course.fullName,
            fileCount: result.fileCount,
            totalBytes: result.totalBytes,
            selectedFileNames: approved
                .map((file) => file.fileName)
                .toList(growable: false),
          );
          availableResult = CourseArchiveResult(
            path: resource.filePath,
            fileName: resource.fileName,
            fileCount: result.fileCount,
            totalBytes: result.totalBytes,
          );
          savedToLibrary = true;
        } on AssistantResourceLibraryException catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: BnbuText('ZIP 已生成，但加入资源库失败：${error.message}')),
            );
          }
        }
      }
      if (mounted) {
        setState(() => _archiveResult = availableResult);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: BnbuText(
                savedToLibrary
                    ? '已生成 ${result.fileName}，并保存到小U资源库。'
                    : '已生成 ${result.fileName}，可在课程页打开或存储。',
              ),
              duration: const Duration(seconds: 8),
            ),
          );
      }
    } on MoodleApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: BnbuText(error.message)));
      }
      return;
    } on CourseArchiveException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: BnbuText(error.message)));
      }
      return;
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: BnbuText(error.message ?? '无法访问本机文件目录。')),
          );
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: BnbuText('批量下载准备失败，请稍后重试。')));
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isBatchDownloading = false;
          _batchProgress = null;
        });
      }
    }
  }

  Future<void> _openArchive(CourseArchiveResult result) async {
    try {
      await showFilePreview(
        context,
        title: result.fileName,
        nativeActions: widget.nativeActions,
        path: result.path,
        mimeType: 'application/zip',
      );
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: BnbuText(error.message ?? '无法打开 ZIP 文件。')),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _CourseDownloadPlan {
  const _CourseDownloadPlan({
    required this.files,
    required this.invalidCount,
    required this.duplicateCount,
    required this.truncatedCount,
  });

  final List<_CourseDownloadFile> files;
  final int invalidCount;
  final int duplicateCount;
  final int truncatedCount;
}

class _CourseDownloadFile {
  const _CourseDownloadFile({
    required this.url,
    required this.fileName,
    required this.sectionName,
    required this.moduleName,
    required this.size,
  });

  final String url;
  final String fileName;
  final String sectionName;
  final String moduleName;
  final int size;
}
