import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/campus_landmark.dart';
import '../services/campus_landmark_store.dart';
import '../theme/app_theme.dart';

class LandmarkPhotoView extends StatefulWidget {
  const LandmarkPhotoView({
    super.key,
    required this.store,
    this.photo,
    this.full = false,
    this.fit = BoxFit.cover,
    required this.label,
  });
  final CampusLandmarkStore store;
  final LandmarkPhoto? photo;
  final bool full;
  final BoxFit fit;
  final String label;
  @override
  State<LandmarkPhotoView> createState() => _LandmarkPhotoViewState();
}

class _LandmarkPhotoViewState extends State<LandmarkPhotoView> {
  Future<File?>? _file;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _file = widget.photo == null
        ? null
        : widget.store.photo(widget.photo!, full: widget.full);
  }

  @override
  void didUpdateWidget(LandmarkPhotoView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo?.id != widget.photo?.id ||
        oldWidget.full != widget.full ||
        oldWidget.store != widget.store) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: FutureBuilder<File?>(
      future: _file,
      builder: (context, snapshot) {
        if (snapshot.data != null) {
          return Image.file(
            snapshot.data!,
            fit: widget.fit,
            alignment: widget.photo!.alignment,
            semanticLabel: widget.label,
            errorBuilder: (_, error, stack) => _retry(context),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return widget.photo == null
            ? const Center(child: Icon(LucideIcons.image300))
            : _retry(context);
      },
    ),
  );
  Widget _retry(BuildContext context) => Center(
    child: IconButton(
      tooltip: context.l10n.text('重试'),
      icon: const Icon(LucideIcons.rotateCw300),
      onPressed: () => setState(_load),
    ),
  );
}
