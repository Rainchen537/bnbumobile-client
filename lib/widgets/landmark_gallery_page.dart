import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/campus_landmark.dart';
import '../services/campus_landmark_store.dart';
import '../theme/app_theme.dart';
import 'landmark_photo_view.dart';

/// Controls float over a screen-sized canvas so attribution never shifts photos.
class LandmarkGalleryPage extends StatefulWidget {
  const LandmarkGalleryPage({
    super.key,
    required this.store,
    required this.photos,
    required this.title,
    required this.defaultLanguage,
    this.initialPhotoId,
  });
  final CampusLandmarkStore store;
  final List<LandmarkPhoto> photos;
  final String title, defaultLanguage;
  final String? initialPhotoId;

  @override
  State<LandmarkGalleryPage> createState() => _LandmarkGalleryPageState();
}

class _LandmarkGalleryPageState extends State<LandmarkGalleryPage> {
  late int index = widget.photos
      .indexWhere((p) => p.id == widget.initialPhotoId)
      .clamp(0, (widget.photos.length - 1).clamp(0, 1000));
  late final pages = PageController(initialPage: index);
  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  Future<void> openSource(LandmarkPhoto photo) async {
    final uri = Uri.tryParse(photo.sourceUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.text('无法打开链接'))));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.text('无法打开链接'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos.isEmpty ? null : widget.photos[index];
    final attribution = photo == null
        ? ''
        : [
            photo.source,
            photo.author,
            photo.license,
          ].where((v) => v.isNotEmpty).join(' · ');
    final note = photo == null
        ? ''
        : landmarkText(photo.note, context, widget.defaultLanguage);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              key: const ValueKey('landmark-fullscreen-canvas'),
              controller: pages,
              itemCount: widget.photos.length,
              onPageChanged: (value) => setState(() => index = value),
              itemBuilder: (_, i) => InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: LandmarkPhotoView(
                    store: widget.store,
                    photo: widget.photos[i],
                    full: true,
                    fit: BoxFit.contain,
                    label: '${widget.title} ${i + 1}/${widget.photos.length}',
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  color: Colors.black54,
                  child: Row(
                    children: [
                      BackButton(color: Colors.white),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      if (MediaQuery.sizeOf(context).width >= 700)
                        IconButton(
                          tooltip: context.l10n.text('上一张'),
                          onPressed: index > 0
                              ? () => pages.jumpToPage(index - 1)
                              : null,
                          color: Colors.white,
                          disabledColor: Colors.white38,
                          icon: const Icon(LucideIcons.chevronLeft300),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '${photo == null ? 0 : index + 1} / ${widget.photos.length}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if (MediaQuery.sizeOf(context).width >= 700)
                        IconButton(
                          tooltip: context.l10n.text('下一张'),
                          onPressed: index + 1 < widget.photos.length
                              ? () => pages.jumpToPage(index + 1)
                              : null,
                          color: Colors.white,
                          disabledColor: Colors.white38,
                          icon: const Icon(LucideIcons.chevronRight300),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (attribution.isNotEmpty || note.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Container(
                    color: Colors.black.withValues(alpha: .72),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.sizeOf(context).height * .25,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (attribution.isNotEmpty)
                              TextButton(
                                key: const ValueKey('landmark-photo-source'),
                                onPressed: photo!.sourceUrl.isEmpty
                                    ? null
                                    : () => openSource(photo),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: Colors.white,
                                  minimumSize: const Size(44, 44),
                                ),
                                child: Text(
                                  attribution,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            if (note.isNotEmpty)
                              Text(
                                note,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
