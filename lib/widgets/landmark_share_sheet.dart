import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/landmark_review.dart';
import '../services/landmark_review_service.dart';
import '../services/native_actions.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive_modal.dart';
import 'bnbu_notice.dart';
import 'community_avatar.dart';

Future<void> showLandmarkShare(
  BuildContext context, {
  required String id,
  required String title,
  required String subtitle,
  File? image,
  LandmarkReview? comment,
}) async {
  final service = RemoteLandmarkReviewService();
  try {
    final page = await service.browse(id);
    if (!context.mounted) return;
    if (page.policy.level >= 2 || !page.policy.readRatings) {
      BnbuToast.show(context, context.l10n.text('分享暂不可用'));
      return;
    }
    // A selected comment must still be publicly readable when generating a poster.
    LandmarkReview? current;
    if (comment != null) {
      current = await service.readComment(id, comment.id);
    }
    if (!context.mounted) return;
    if (image != null) await precacheImage(FileImage(image), context);
    if (!context.mounted) return;
    await showBnbuAdaptiveModal<void>(
      context: context,
      builder: (context, _) => _ShareSheet(
        id: id,
        title: title,
        subtitle: subtitle,
        image: image,
        page: page,
        comment: current,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      BnbuToast.show(context, context.l10n.text('分享生成失败，请重试'));
    }
  } finally {
    service.dispose();
  }
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.page,
    this.image,
    this.comment,
  });
  final String id, title, subtitle;
  final File? image;
  final LandmarkReviewPage page;
  final LandmarkReview? comment;
  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final key = GlobalKey();
  bool busy = false;
  Future<void> export(bool save) async {
    if (busy) return;
    setState(() => busy = true);
    final service = RemoteLandmarkReviewService();
    try {
      final fresh = await service.browse(widget.id);
      if (fresh.policy.level >= 2 || !fresh.policy.readRatings) {
        throw const FormatException('closed');
      }
      if (widget.comment != null) {
        final comment = await service.readComment(
          widget.id,
          widget.comment!.id,
        );
        if (comment.version != widget.comment!.version) {
          throw const FormatException('changed');
        }
      }
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = data!.buffer.asUint8List();
      if (save) {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'ME生活',
          fileName: 'ME-life.png',
          type: FileType.custom,
          allowedExtensions: ['png'],
          bytes: bytes,
        );
        if (path != null &&
            (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
          await File(path).writeAsBytes(bytes, flush: true);
        }
      } else {
        final dir = await Directory(
          '${(await getTemporaryDirectory()).path}/me-life-share',
        ).create(recursive: true);
        final file = File(
          '${dir.path}/ME-life-${DateTime.now().millisecondsSinceEpoch}.png',
        );
        await file.writeAsBytes(bytes, flush: true);
        await NativeActions().shareLocalFile(
          path: file.path,
          filename: 'ME-life.png',
          mimeType: 'image/png',
        );
      }
    } catch (_) {
      if (mounted) BnbuToast.show(context, context.l10n.text('分享未完成，请重试'));
    } finally {
      service.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              key: key,
              child: Container(
                width: 480,
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xff203345), Color(0xff677777)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BNBU.ME',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 26),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.image != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      widget.image!,
                                      width: 96,
                                      height: 84,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Text(
                                  widget.title,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  widget.subtitle,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('ME评分'),
                              Text(
                                widget.page.average?.toStringAsFixed(1) ?? '—',
                                style: const TextStyle(
                                  fontSize: 48,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${widget.page.ratingCount} BNBUer',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                      if (widget.comment != null) ...[
                        const SizedBox(height: 26),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          color: Colors.white,
                          child: DefaultTextStyle(
                            style: const TextStyle(
                              color: Color(0xff17232d),
                              fontSize: 17,
                              height: 1.5,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CommunityAvatar(
                                      seed: widget.comment!.seed,
                                      url: widget.comment!.avatarUrl,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        widget.comment!.name,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    Text(
                                      '${widget.comment!.helpful} ${context.l10n.text('有用')}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                                if (widget.comment!.rating != null)
                                  Text(
                                    '★' * widget.comment!.rating!,
                                    style: const TextStyle(
                                      color: Color(0xff249adc),
                                    ),
                                  ),
                                const SizedBox(height: 12),
                                Text(widget.comment!.comment),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'ME生活',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          QrImageView(
                            data: 'https://bnbu.yunwai.cloud/download',
                            size: 88,
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.all(6),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: busy ? null : () => export(true),
                  child: const BnbuText('保存图片'),
                ),
                if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)
                  TextButton(
                    onPressed: busy ? null : () => export(false),
                    child: const BnbuText('分享'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const BnbuText('关闭'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
