import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../services/moodle_api_client.dart';
import '../state/app_session_controller.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive_modal.dart';
import 'bnbu_notice.dart';
import 'community_avatar.dart';

class PersonalizationSettings extends StatefulWidget {
  const PersonalizationSettings({super.key, required this.controller});
  final AppSessionController controller;
  @override
  State<PersonalizationSettings> createState() =>
      _PersonalizationSettingsState();
}

class _PersonalizationSettingsState extends State<PersonalizationSettings> {
  ISpaceIdentity? identity;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.controller.readISpaceIdentity();
      if (mounted) setState(() => identity = result);
    } catch (_) {
      if (mounted) setState(() => error = '头像读取失败');
    }
  }

  Future<void> edit() async {
    if (busy) return;
    if (!widget.controller.canUpdateISpacePicture) {
      BnbuToast.show(context, context.l10n.text('学校当前未开放头像修改'));
      return;
    }
    setState(() => busy = true);
    try {
      Uint8List? bytes;
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (picked == null) return;
        final f = picked.files.single;
        if (f.size > 20 * 1024 * 1024) {
          throw const FormatException('image size');
        }
        bytes = f.bytes ?? await File(f.path!).readAsBytes();
      } else {
        final f = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 2048,
          maxHeight: 2048,
        );
        if (f == null) return;
        if (await f.length() > 20 * 1024 * 1024) {
          throw const FormatException('image size');
        }
        bytes = await f.readAsBytes();
      }
      final info = img.findDecoderForData(bytes)?.startDecode(bytes);
      if (info == null || info.width * info.height > 40000000) {
        throw const FormatException('image size');
      }
      final decoded = img.decodeImage(bytes);
      if (decoded == null || decoded.width * decoded.height > 40000000) {
        throw const FormatException('image');
      }
      final source = img.bakeOrientation(decoded);
      final bounded = source.width > 2048 || source.height > 2048
          ? img.copyResize(
              source,
              width: source.width >= source.height ? 2048 : null,
              height: source.height > source.width ? 2048 : null,
            )
          : source;
      if (!mounted) return;
      final crop = await showBnbuAdaptiveModal<Uint8List>(
        context: context,
        builder: (context, _) => _AvatarCrop(image: bounded),
      );
      if (crop == null || !mounted) return;
      await widget.controller.updateISpacePicture(crop);
      await load();
      if (mounted) BnbuToast.show(context, context.l10n.text('iSpace头像已更新'));
    } catch (failure) {
      if (mounted) {
        final message = failure is MoodleApiException
            ? failure.message
            : '头像更新未确认，请刷新查看后重试';
        BnbuToast.show(context, context.l10n.text(message));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ListTile(
        title: const BnbuText('iSpace头像'),
        subtitle: Text(
          identity?.name ?? widget.controller.session?.fullName ?? '',
        ),
        trailing: SizedBox.square(
          dimension: 56,
          child: identity?.avatar == null
              ? AccountCommunityAvatar(
                  username: widget.controller.username ?? 'local',
                  size: 56,
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    identity!.avatar!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, e, s) => AccountCommunityAvatar(
                      username: widget.controller.username ?? 'local',
                      size: 56,
                    ),
                  ),
                ),
        ),
        onTap: busy ? null : edit,
      ),
      if (busy) const LinearProgressIndicator(minHeight: 2),
      if (error != null) TextButton(onPressed: load, child: BnbuText(error!)),
      if (!widget.controller.canUpdateISpacePicture)
        const Padding(
          padding: EdgeInsets.all(16),
          child: BnbuText('学校当前未开放头像修改'),
        ),
    ],
  );
}

class _AvatarCrop extends StatefulWidget {
  const _AvatarCrop({required this.image});
  final img.Image image;
  @override
  State<_AvatarCrop> createState() => _AvatarCropState();
}

class _AvatarCropState extends State<_AvatarCrop> {
  late final bytes = Uint8List.fromList(
    img.encodeJpg(widget.image, quality: 92),
  );
  double zoom = 1, startZoom = 1;
  Offset offset = Offset.zero,
      startOffset = Offset.zero,
      startFocal = Offset.zero;
  double side = 280;
  double get base =>
      side /
      (widget.image.width < widget.image.height
          ? widget.image.width
          : widget.image.height);
  Offset clamp(Offset v, double scale) => Offset(
    v.dx.clamp(side - widget.image.width * scale, 0),
    v.dy.clamp(side - widget.image.height * scale, 0),
  );
  bool initialized = false;
  void save() {
    final scale = base * zoom;
    final square = (side / scale).round().clamp(
      1,
      widget.image.width < widget.image.height
          ? widget.image.width
          : widget.image.height,
    );
    final crop = img.copyCrop(
      widget.image,
      x: (-offset.dx / scale).round().clamp(0, widget.image.width - square),
      y: (-offset.dy / scale).round().clamp(0, widget.image.height - square),
      width: square,
      height: square,
    );
    Navigator.pop(
      context,
      Uint8List.fromList(
        img.encodeJpg(
          img.copyResize(crop, width: 512, height: 512),
          quality: 90,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
              const Expanded(child: Center(child: BnbuText('裁剪头像'))),
              TextButton(onPressed: save, child: const BnbuText('使用')),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) {
              final next = c.maxWidth.clamp(180.0, 360.0);
              if (!initialized || side != next) {
                side = next;
                zoom = 1;
                offset = Offset(
                  (side - widget.image.width * base) / 2,
                  (side - widget.image.height * base) / 2,
                );
                initialized = true;
              }
              return GestureDetector(
                onScaleStart: (d) {
                  startZoom = zoom;
                  startOffset = offset;
                  startFocal = d.localFocalPoint;
                },
                onScaleUpdate: (d) => setState(() {
                  zoom = (startZoom * d.scale).clamp(1.0, 4.0);
                  offset = clamp(
                    d.localFocalPoint -
                        (startFocal - startOffset) * (zoom / startZoom),
                    base * zoom,
                  );
                }),
                child: ClipRect(
                  child: SizedBox.square(
                    dimension: side,
                    child: Stack(
                      children: [
                        Positioned(
                          left: offset.dx,
                          top: offset.dy,
                          width: widget.image.width * base * zoom,
                          height: widget.image.height * base * zoom,
                          child: Image.memory(bytes, fit: BoxFit.fill),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
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
            },
          ),
          Slider(
            value: zoom,
            min: 1,
            max: 4,
            label: zoom.toStringAsFixed(1),
            onChanged: (v) => setState(() {
              final center = Offset(side / 2, side / 2);
              offset = clamp(center - (center - offset) * (v / zoom), base * v);
              zoom = v;
            }),
          ),
          const BnbuText('更新将同步到iSpace'),
        ],
      ),
    ),
  );
}
