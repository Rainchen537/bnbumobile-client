import 'file_preview_frame.dart';
import 'bnbu_loading.dart';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdfrx/pdfrx.dart';

import '../services/pptx_study_document.dart';
import '../services/study_mode_skill.dart';
import '../theme/app_theme.dart';

enum StudyDocumentFormat { pdf, pptx, unsupported }

StudyDocumentFormat resolveStudyDocumentFormat({
  required String title,
  required String mimeType,
}) {
  final normalizedMimeType = mimeType.split(';').first.trim().toLowerCase();
  if (normalizedMimeType == 'application/pdf') {
    return StudyDocumentFormat.pdf;
  }
  if (normalizedMimeType ==
      'application/vnd.openxmlformats-officedocument.presentationml.presentation') {
    return StudyDocumentFormat.pptx;
  }

  final normalizedTitle = title.trim().toLowerCase();
  if (normalizedTitle.contains('.pdf')) return StudyDocumentFormat.pdf;
  if (normalizedTitle.contains('.pptx')) return StudyDocumentFormat.pptx;
  return StudyDocumentFormat.unsupported;
}

class StudyDocumentViewer extends StatelessWidget {
  const StudyDocumentViewer({
    super.key,
    required this.title,
    required this.bytes,
    required this.mimeType,
    required this.bottomPanel,
    required this.onPageChanged,
    required this.fallback,
    this.thumbnailWidth = 220,
    this.onDocumentReady,
    this.onThumbnailWidthChanged,
  });

  final String title;
  final Uint8List bytes;
  final String mimeType;
  final Widget bottomPanel;
  final ValueChanged<StudyPageSnapshot> onPageChanged;
  final Widget fallback;
  final double thumbnailWidth;
  final ValueChanged<StudyDocumentAccess>? onDocumentReady;
  final ValueChanged<double>? onThumbnailWidthChanged;

  @override
  Widget build(BuildContext context) {
    final document = switch (resolveStudyDocumentFormat(
      title: title,
      mimeType: mimeType,
    )) {
      StudyDocumentFormat.pdf => _PdfStudyDocument(
        title: title,
        bytes: bytes,
        onPageChanged: onPageChanged,
        thumbnailWidth: thumbnailWidth,
        onDocumentReady: onDocumentReady,
        onThumbnailWidthChanged: onThumbnailWidthChanged,
      ),
      StudyDocumentFormat.pptx => _PptxStudyDocument(
        title: title,
        bytes: bytes,
        onPageChanged: onPageChanged,
        thumbnailWidth: thumbnailWidth,
        onDocumentReady: onDocumentReady,
        onThumbnailWidthChanged: onThumbnailWidthChanged,
      ),
      StudyDocumentFormat.unsupported => _SinglePageStudyDocument(
        title: title,
        fallback: fallback,
        onPageChanged: onPageChanged,
        onDocumentReady: onDocumentReady,
      ),
    };
    return Column(
      children: [
        Expanded(child: document),
        bottomPanel,
      ],
    );
  }
}

abstract interface class StudyDocumentAccess {
  int get pageCount;

  Future<StudyPageSnapshot?> loadPage(int pageNumber);
}

class _PdfStudyDocument extends StatefulWidget {
  const _PdfStudyDocument({
    required this.title,
    required this.bytes,
    required this.onPageChanged,
    required this.thumbnailWidth,
    this.onDocumentReady,
    this.onThumbnailWidthChanged,
  });

  final String title;
  final Uint8List bytes;
  final ValueChanged<StudyPageSnapshot> onPageChanged;
  final double thumbnailWidth;
  final ValueChanged<StudyDocumentAccess>? onDocumentReady;
  final ValueChanged<double>? onThumbnailWidthChanged;

  @override
  State<_PdfStudyDocument> createState() => _PdfStudyDocumentState();
}

class _PdfStudyDocumentState extends State<_PdfStudyDocument>
    implements StudyDocumentAccess {
  late final PdfDocumentRef _documentRef;
  final PdfViewerController _controller = PdfViewerController();
  int _selectedPage = 1;
  int _selectionGeneration = 0;
  int _pageCount = 0;

  @override
  int get pageCount => _pageCount;

  @override
  void initState() {
    super.initState();
    _documentRef = PdfDocumentRefData(widget.bytes, sourceName: widget.title);
  }

  Future<void> _selectPage(int pageNumber) async {
    if (pageNumber < 1) return;
    if (mounted) setState(() => _selectedPage = pageNumber);
    if (_controller.isReady && _controller.pageNumber != pageNumber) {
      unawaited(_controller.goToPage(pageNumber: pageNumber));
    }
    final generation = ++_selectionGeneration;
    final snapshot = await loadPage(pageNumber);
    if (mounted && generation == _selectionGeneration && snapshot != null) {
      widget.onPageChanged(snapshot);
    }
  }

  @override
  Future<StudyPageSnapshot?> loadPage(int pageNumber) async {
    return await _controller.useDocument<StudyPageSnapshot?>((document) async {
      if (pageNumber < 1 || pageNumber > document.pages.length) return null;
      final text = await document.pages[pageNumber - 1].loadStructuredText();
      return StudyPageSnapshot(
        documentTitle: widget.title,
        pageNumber: pageNumber,
        pageCount: document.pages.length,
        text: text.fullText,
        captureImage: () => _renderPage(pageNumber),
      );
    });
  }

  Future<Uint8List?> _renderPage(int pageNumber) async {
    return _controller.useDocument<Uint8List?>((document) async {
      if (pageNumber > document.pages.length) return null;
      final page = document.pages[pageNumber - 1];
      final scale = 1440 / page.width;
      final rendered = await page.render(
        fullWidth: 1440,
        fullHeight: page.height * scale,
      );
      if (rendered == null) return null;
      final image = await rendered.createImage();
      rendered.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data?.buffer.asUint8List();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return PdfDocumentViewBuilder(
      documentRef: _documentRef,
      builder: (context, document) {
        if (document == null) {
          return const Center(child: BnbuActivityIndicator());
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _pageCount = document.pages.length;
          widget.onDocumentReady?.call(this);
          if (_selectionGeneration == 0) _selectPage(1);
        });
        return Row(
          children: [
            SizedBox(
              width: widget.thumbnailWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surface,
                  border: Border(right: BorderSide(color: tokens.border)),
                ),
                child: ListView.builder(
                  key: const ValueKey('study-page-thumbnail-list'),
                  padding: EdgeInsets.all(tokens.space12),
                  itemCount: document.pages.length,
                  itemBuilder: (context, index) {
                    final page = index + 1;
                    return _ThumbnailFrame(
                      pageNumber: page,
                      selected: page == _selectedPage,
                      onTap: () => _selectPage(page),
                      child: PdfPageView(
                        document: document,
                        pageNumber: page,
                        maximumDpi: 96,
                        decoration: const BoxDecoration(color: Colors.white),
                      ),
                    );
                  },
                ),
              ),
            ),
            _StudyDivider(
              axis: Axis.vertical,
              onDelta: widget.onThumbnailWidthChanged,
            ),
            Expanded(
              child: PdfViewer(
                _documentRef,
                controller: _controller,
                params: PdfViewerParams(
                  margin: FilePreviewMetrics.margin,
                  normalizeMatrix: normalizeFilePreviewMatrix,
                  backgroundColor: tokens.canvas,
                  pageDropShadow: BoxShadow(
                    color: Colors.black.withValues(alpha: .18),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                  onViewerReady: (document, controller) => _selectPage(1),
                  onPageChanged: (page) {
                    if (page != null) unawaited(_selectPage(page));
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PptxStudyDocument extends StatefulWidget {
  const _PptxStudyDocument({
    required this.title,
    required this.bytes,
    required this.onPageChanged,
    required this.thumbnailWidth,
    this.onDocumentReady,
    this.onThumbnailWidthChanged,
  });

  final String title;
  final Uint8List bytes;
  final ValueChanged<StudyPageSnapshot> onPageChanged;
  final double thumbnailWidth;
  final ValueChanged<StudyDocumentAccess>? onDocumentReady;
  final ValueChanged<double>? onThumbnailWidthChanged;

  @override
  State<_PptxStudyDocument> createState() => _PptxStudyDocumentState();
}

class _PptxStudyDocumentState extends State<_PptxStudyDocument>
    implements StudyDocumentAccess {
  final GlobalKey _pageKey = GlobalKey();
  late final Future<PptxStudyDocument> _document = _load();
  int _selectedPage = 0;
  bool _reportedInitialPage = false;
  PptxStudyDocument? _loadedDocument;

  @override
  int get pageCount => _loadedDocument?.pages.length ?? 0;

  @override
  Future<StudyPageSnapshot?> loadPage(int pageNumber) async {
    final document = _loadedDocument;
    if (document == null ||
        pageNumber < 1 ||
        pageNumber > document.pages.length) {
      return null;
    }
    return StudyPageSnapshot(
      documentTitle: widget.title,
      pageNumber: pageNumber,
      pageCount: document.pages.length,
      text: document.pages[pageNumber - 1].text,
      captureImage: pageNumber == _selectedPage + 1 ? _capturePage : null,
    );
  }

  Future<PptxStudyDocument> _load() async {
    if (widget.bytes.length > 64 * 1024 * 1024) {
      throw const FormatException('PPTX 文件超过 64 MB，无法在学业模式中展开');
    }
    return PptxStudyDocument.parse(widget.bytes);
  }

  void _select(PptxStudyDocument document, int index) {
    if (index < 0 || index >= document.pages.length) return;
    setState(() => _selectedPage = index);
    widget.onPageChanged(
      StudyPageSnapshot(
        documentTitle: widget.title,
        pageNumber: index + 1,
        pageCount: document.pages.length,
        text: document.pages[index].text,
        captureImage: _capturePage,
      ),
    );
  }

  Future<Uint8List?> _capturePage() async {
    var boundary = _pageKey.currentContext?.findRenderObject();
    if (boundary is RenderRepaintBoundary && boundary.debugNeedsPaint) {
      await WidgetsBinding.instance.endOfFrame;
      boundary = _pageKey.currentContext?.findRenderObject();
    }
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 1.5);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return FutureBuilder<PptxStudyDocument>(
      future: _document,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: BnbuActivityIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: BnbuText(snapshot.error?.toString() ?? 'PPTX 无法读取'),
          );
        }
        final document = snapshot.data!;
        _loadedDocument = document;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onDocumentReady?.call(this);
          if (mounted && !_reportedInitialPage) {
            _reportedInitialPage = true;
            _select(document, 0);
          }
        });
        return Row(
          children: [
            SizedBox(
              width: widget.thumbnailWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.surface,
                  border: Border(right: BorderSide(color: tokens.border)),
                ),
                child: ListView.builder(
                  key: const ValueKey('study-page-thumbnail-list'),
                  padding: EdgeInsets.all(tokens.space12),
                  itemCount: document.pages.length,
                  itemBuilder: (context, index) => _ThumbnailFrame(
                    pageNumber: index + 1,
                    selected: index == _selectedPage,
                    onTap: () => _select(document, index),
                    child: _PptxPageCanvas(
                      document: document,
                      page: document.pages[index],
                      compact: true,
                    ),
                  ),
                ),
              ),
            ),
            _StudyDivider(
              axis: Axis.vertical,
              onDelta: widget.onThumbnailWidthChanged,
            ),
            Expanded(
              child: ColoredBox(
                color: tokens.canvas,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: RepaintBoundary(
                      key: _pageKey,
                      child: _PptxPageCanvas(
                        document: document,
                        page: document.pages[_selectedPage],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StudyDivider extends StatelessWidget {
  const _StudyDivider({required this.axis, this.onDelta});

  final Axis axis;
  final ValueChanged<double>? onDelta;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return MouseRegion(
      cursor: axis == Axis.vertical
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: axis == Axis.vertical && onDelta != null
            ? (details) => onDelta!(details.delta.dx)
            : null,
        onVerticalDragUpdate: axis == Axis.horizontal && onDelta != null
            ? (details) => onDelta!(details.delta.dy)
            : null,
        child: SizedBox(
          width: axis == Axis.vertical ? 6 : null,
          height: axis == Axis.horizontal ? 6 : null,
          child: Center(
            child: ColoredBox(
              color: tokens.border,
              child: SizedBox(
                width: axis == Axis.vertical ? 1 : double.infinity,
                height: axis == Axis.horizontal ? 1 : double.infinity,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PptxPageCanvas extends StatelessWidget {
  const _PptxPageCanvas({
    required this.document,
    required this.page,
    this.compact = false,
  });

  final PptxStudyDocument document;
  final PptxStudyPage page;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: document.size.aspectRatio,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: compact
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .2),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (final element in page.elements)
                Positioned(
                  left: constraints.maxWidth * element.rect.left,
                  top: constraints.maxHeight * element.rect.top,
                  width: constraints.maxWidth * element.rect.width,
                  height: constraints.maxHeight * element.rect.height,
                  child: element.image != null
                      ? Image.memory(element.image!, fit: BoxFit.contain)
                      : ColoredBox(
                          color: element.fill ?? Colors.transparent,
                          child: Padding(
                            padding: EdgeInsets.all(compact ? 2 : 6),
                            child: BnbuText(
                              element.text ?? '',
                              maxLines: compact ? 5 : null,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                color: element.foreground,
                                fontSize:
                                    element.fontSize *
                                    constraints.maxWidth /
                                    960,
                                height: 1.15,
                                fontWeight: element.bold
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SinglePageStudyDocument extends StatefulWidget {
  const _SinglePageStudyDocument({
    required this.title,
    required this.fallback,
    required this.onPageChanged,
    this.onDocumentReady,
  });

  final String title;
  final Widget fallback;
  final ValueChanged<StudyPageSnapshot> onPageChanged;
  final ValueChanged<StudyDocumentAccess>? onDocumentReady;

  @override
  State<_SinglePageStudyDocument> createState() =>
      _SinglePageStudyDocumentState();
}

class _SinglePageStudyDocumentState extends State<_SinglePageStudyDocument>
    implements StudyDocumentAccess {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onDocumentReady?.call(this);
      widget.onPageChanged(
        StudyPageSnapshot(
          documentTitle: widget.title,
          pageNumber: 1,
          pageCount: 1,
          text: '',
        ),
      );
    });
  }

  @override
  int get pageCount => 1;

  @override
  Future<StudyPageSnapshot?> loadPage(int pageNumber) async => pageNumber == 1
      ? StudyPageSnapshot(
          documentTitle: widget.title,
          pageNumber: 1,
          pageCount: 1,
          text: '',
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(right: BorderSide(color: tokens.border)),
            ),
            child: _ThumbnailFrame(
              pageNumber: 1,
              selected: true,
              onTap: () {},
              child: Center(
                child: BnbuText(widget.title, textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
        Expanded(child: widget.fallback),
      ],
    );
  }
}

class _ThumbnailFrame extends StatelessWidget {
  const _ThumbnailFrame({
    required this.pageNumber,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final int pageNumber;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space12),
      child: Material(
        color: selected ? tokens.surfaceMuted : tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius12),
          side: BorderSide(
            color: selected ? tokens.textPrimary : tokens.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            child: Column(
              children: [
                AspectRatio(
                  aspectRatio: 16 / 10,
                  child: ColoredBox(color: Colors.white, child: child),
                ),
                const SizedBox(height: 5),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BnbuText(
                    '$pageNumber',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected
                          ? tokens.textPrimary
                          : tokens.textSecondary,
                      fontWeight: FontWeight.w600,
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
}
