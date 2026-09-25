import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models/academic_calendar.dart';
import '../services/academic_calendar_service.dart';
import '../services/academic_calendar_store.dart';
import '../services/native_actions.dart';
import '../theme/app_theme.dart';
import '../widgets/bnbu_components.dart';
import '../widgets/bnbu_notice.dart';
import '../widgets/file_preview_frame.dart';
import 'file_preview_page.dart';

typedef AcademicCalendarPdfBuilder =
    Widget Function(
      BuildContext context,
      AcademicCalendarDocument document,
      Uint8List bytes,
    );

class AcademicCalendarPage extends StatefulWidget {
  const AcademicCalendarPage({
    super.key,
    this.repository,
    this.pdfBuilder,
    this.initialDocumentIndex = 0,
  });

  final int initialDocumentIndex;
  final AcademicCalendarRepository? repository;
  final AcademicCalendarPdfBuilder? pdfBuilder;

  @override
  State<AcademicCalendarPage> createState() => _AcademicCalendarPageState();
}

class _AcademicCalendarPageState extends State<AcademicCalendarPage> {
  late final AcademicCalendarRepository _repository =
      widget.repository ?? OfficialAcademicCalendarRepository();
  late Future<AcademicCalendarSnapshot> _snapshot = _repository.load();
  late AcademicCalendarDocumentKind _selected = AcademicCalendarDocumentKind
      .values[widget.initialDocumentIndex == 1 ? 1 : 0];

  @override
  void initState() {
    super.initState();
    if (widget.repository == null) {
      BnbuAcademicCalendar.revision.addListener(_calendarChanged);
      AcademicCalendarStore.shared.refresh();
    }
  }

  void _calendarChanged() {
    if (mounted) setState(() => _snapshot = _repository.load());
  }

  @override
  void dispose() {
    BnbuAcademicCalendar.revision.removeListener(_calendarChanged);
    super.dispose();
  }

  bool _sharing = false;
  Future<void> _shareCurrent() async {
    if (_sharing) return;
    _sharing = true;
    Directory? directory;
    try {
      final selected = _selected;
      final data = await _snapshot;
      final document = selected == AcademicCalendarDocumentKind.academicCalendar
          ? data.bundle.academicCalendar
          : data.bundle.classSchedule;
      directory = await (await getTemporaryDirectory()).createTemp(
        'bnbu-calendar-',
      );
      final title = document.title.toLowerCase().endsWith('.pdf')
          ? document.title
          : '${document.title}.pdf';
      final path = '${directory.path}/${safeAttachmentFileName(title)}';
      await File(path).writeAsBytes(data.bytesFor(selected), flush: true);
      if (!mounted) return;
      await saveOrSharePreview(
        context,
        path: path,
        title: title,
        mimeType: 'application/pdf',
      );
    } catch (_) {
      if (mounted) BnbuToast.show(context, context.l10n.text('文件操作未完成，请重试。'));
    } finally {
      if (directory != null) {
        try {
          await directory.delete(recursive: true);
        } catch (_) {
          /* Temporary files can be reclaimed by the OS. */
        }
      }
      _sharing = false;
    }
  }

  void _reload() {
    setState(() {
      _snapshot = widget.repository == null
          ? AcademicCalendarStore.shared
                .refresh(force: true)
                .then((_) => _repository.load())
          : _repository.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: FilePreviewAppBar(
        title: context.l10n.text('校历'),
        onReload: _reload,
        onShare: _shareCurrent,
      ),
      body: FutureBuilder<AcademicCalendarSnapshot>(
        future: _snapshot,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: BnbuLoadingState(title: '正在加载校历'));
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(tokens.space24),
                child: BnbuErrorState(
                  title: '校历加载失败',
                  message: '请检查网络后重试。',
                  action: FilledButton.icon(
                    onPressed: _reload,
                    icon: const Icon(LucideIcons.refreshCw300),
                    label: const BnbuText('重试'),
                  ),
                ),
              ),
            );
          }
          final data = snapshot.data!;
          final document = switch (_selected) {
            AcademicCalendarDocumentKind.academicCalendar =>
              data.bundle.academicCalendar,
            AcademicCalendarDocumentKind.classSchedule =>
              data.bundle.classSchedule,
          };
          final pdfBytes = data.bytesFor(_selected);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    key: const ValueKey('academic-calendar-selector'),
                    spacing: 20,
                    children: [
                      for (final kind in AcademicCalendarDocumentKind.values)
                        Semantics(
                          selected: _selected == kind,
                          child: TextButton(
                            onPressed: () => setState(() => _selected = kind),
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              foregroundColor: _selected == kind
                                  ? tokens.brandBlue
                                  : tokens.textSecondary,
                              textStyle: TextStyle(
                                fontSize: 15,
                                fontWeight: _selected == kind
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              shape: const RoundedRectangleBorder(),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BnbuText(
                                  kind ==
                                          AcademicCalendarDocumentKind
                                              .academicCalendar
                                      ? '本学期校历'
                                      : '课程计划',
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 2,
                                  width: 18,
                                  decoration: BoxDecoration(
                                    color: _selected == kind
                                        ? tokens.brandBlue
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: KeyedSubtree(
                  key: ObjectKey(pdfBytes),
                  child:
                      widget.pdfBuilder?.call(context, document, pdfBytes) ??
                      _AcademicCalendarPdf(
                        title: document.title,
                        bytes: pdfBytes,
                      ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AcademicCalendarPdf extends StatefulWidget {
  const _AcademicCalendarPdf({required this.title, required this.bytes});

  final String title;
  final Uint8List bytes;

  @override
  State<_AcademicCalendarPdf> createState() => _AcademicCalendarPdfState();
}

class _AcademicCalendarPdfState extends State<_AcademicCalendarPdf> {
  late final PdfDocumentRef _document = PdfDocumentRefData(
    widget.bytes,
    sourceName: widget.title,
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return PdfViewer(
      _document,
      params: PdfViewerParams(
        margin: FilePreviewMetrics.margin,
        normalizeMatrix: normalizeFilePreviewMatrix,
        backgroundColor: tokens.canvas,
        pageDropShadow: BoxShadow(
          color: Colors.black.withValues(alpha: .16),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ),
    );
  }
}
