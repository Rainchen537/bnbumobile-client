import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rive/rive.dart' as rive;

import '../l10n/bnbu_localizations.dart';
import '../models/student_avatar_profile.dart';
import '../services/student_avatar_rive_runtime.dart';

class StudentAvatarRiveContract {
  StudentAvatarRiveContract._();

  static const assetPath = 'assets/avatar/student_avatar.riv';
  static const artboard = 'StudentAvatar';
  static const stateMachine = 'AvatarState';
  static const viewModel = 'StudentAvatarModel';

  static const body = 'body';
  static const skinTone = 'skinTone';
  static const hairStyle = 'hairStyle';
  static const hairColor = 'hairColor';
  static const top = 'top';
  static const bottom = 'bottom';
  static const shoes = 'shoes';
  static const accessory = 'accessory';
  static const mood = 'mood';
  static const reduceMotion = 'reduceMotion';
  static const accentColor = 'accentColor';
  static const greet = 'greet';
  static const celebrate = 'celebrate';
  static const think = 'think';
}

class StudentAvatarStage extends StatefulWidget {
  const StudentAvatarStage({
    super.key,
    required this.profile,
    this.onEdit,
    this.heroTag,
  });

  final StudentAvatarProfile profile;
  final VoidCallback? onEdit;
  final Object? heroTag;

  @override
  State<StudentAvatarStage> createState() => _StudentAvatarStageState();
}

class _StudentAvatarStageState extends State<StudentAvatarStage> {
  late final Future<bool> _hasRiveAsset = _resolveRiveAsset();

  Future<bool> _resolveRiveAsset() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      if (!manifest.listAssets().contains(
        StudentAvatarRiveContract.assetPath,
      )) {
        return false;
      }
      return await StudentAvatarRiveRuntime.initialize();
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context);
    final stage = DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.colorScheme.surface.withValues(alpha: 0.18),
        border: Border.all(
          color: tokens.colorScheme.outlineVariant.withValues(alpha: 0.44),
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: _AvatarStageBackdrop()),
          Positioned.fill(
            child: FutureBuilder<bool>(
              future: _hasRiveAsset,
              builder: (context, snapshot) {
                if (snapshot.data == true) {
                  return _StudentAvatarRiveView(profile: widget.profile);
                }
                return _StudentAvatarVectorFallback(profile: widget.profile);
              },
            ),
          ),
          if (widget.onEdit != null)
            Positioned(
              right: 12,
              top: 12,
              child: _AvatarEditButton(onTap: widget.onEdit!),
            ),
        ],
      ),
    );
    return Semantics(
      key: const ValueKey('student-avatar-stage'),
      container: true,
      image: true,
      label: context.l10n.text('学生虚拟形象'),
      child: widget.heroTag == null
          ? stage
          : Hero(tag: widget.heroTag!, child: stage),
    );
  }
}

class _StudentAvatarRiveView extends StatefulWidget {
  const _StudentAvatarRiveView({required this.profile});

  final StudentAvatarProfile profile;

  @override
  State<_StudentAvatarRiveView> createState() => _StudentAvatarRiveViewState();
}

class _StudentAvatarRiveViewState extends State<_StudentAvatarRiveView> {
  late final rive.FileLoader _fileLoader = rive.FileLoader.fromAsset(
    StudentAvatarRiveContract.assetPath,
    riveFactory: rive.Factory.rive,
  );
  _StudentAvatarRiveBinding? _binding;

  @override
  void didUpdateWidget(_StudentAvatarRiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile != oldWidget.profile) {
      _binding?.apply(
        widget.profile,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      );
    }
  }

  @override
  void dispose() {
    _binding?.dispose();
    _fileLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return rive.RiveWidgetBuilder(
      fileLoader: _fileLoader,
      artboardSelector: rive.ArtboardSelector.byName(
        StudentAvatarRiveContract.artboard,
      ),
      stateMachineSelector: rive.StateMachineSelector.byName(
        StudentAvatarRiveContract.stateMachine,
      ),
      dataBind: rive.DataBind.auto(),
      onLoaded: (state) {
        _binding?.dispose();
        final viewModel = state.viewModelInstance;
        if (viewModel == null) {
          return;
        }
        _binding = _StudentAvatarRiveBinding(viewModel)
          ..apply(
            widget.profile,
            reduceMotion: MediaQuery.disableAnimationsOf(context),
          );
      },
      builder: (context, state) => switch (state) {
        rive.RiveLoaded() => rive.RiveWidget(
          controller: state.controller,
          fit: rive.Fit.contain,
          alignment: Alignment.bottomCenter,
        ),
        rive.RiveLoading() => _StudentAvatarVectorFallback(
          profile: widget.profile,
        ),
        rive.RiveFailed() => _StudentAvatarVectorFallback(
          profile: widget.profile,
        ),
      },
    );
  }
}

class _StudentAvatarRiveBinding {
  _StudentAvatarRiveBinding(rive.ViewModelInstance viewModel)
    : _body = viewModel.enumerator(StudentAvatarRiveContract.body),
      _skinTone = viewModel.enumerator(StudentAvatarRiveContract.skinTone),
      _hairStyle = viewModel.enumerator(StudentAvatarRiveContract.hairStyle),
      _hairColor = viewModel.enumerator(StudentAvatarRiveContract.hairColor),
      _top = viewModel.enumerator(StudentAvatarRiveContract.top),
      _bottom = viewModel.enumerator(StudentAvatarRiveContract.bottom),
      _shoes = viewModel.enumerator(StudentAvatarRiveContract.shoes),
      _accessory = viewModel.enumerator(StudentAvatarRiveContract.accessory),
      _mood = viewModel.enumerator(StudentAvatarRiveContract.mood),
      _reduceMotion = viewModel.boolean(StudentAvatarRiveContract.reduceMotion),
      _accentColor = viewModel.color(StudentAvatarRiveContract.accentColor),
      _greet = viewModel.trigger(StudentAvatarRiveContract.greet),
      _celebrate = viewModel.trigger(StudentAvatarRiveContract.celebrate),
      _think = viewModel.trigger(StudentAvatarRiveContract.think);

  final rive.ViewModelInstanceEnum? _body;
  final rive.ViewModelInstanceEnum? _skinTone;
  final rive.ViewModelInstanceEnum? _hairStyle;
  final rive.ViewModelInstanceEnum? _hairColor;
  final rive.ViewModelInstanceEnum? _top;
  final rive.ViewModelInstanceEnum? _bottom;
  final rive.ViewModelInstanceEnum? _shoes;
  final rive.ViewModelInstanceEnum? _accessory;
  final rive.ViewModelInstanceEnum? _mood;
  final rive.ViewModelInstanceBoolean? _reduceMotion;
  final rive.ViewModelInstanceColor? _accentColor;
  final rive.ViewModelInstanceTrigger? _greet;
  final rive.ViewModelInstanceTrigger? _celebrate;
  final rive.ViewModelInstanceTrigger? _think;

  void apply(StudentAvatarProfile profile, {required bool reduceMotion}) {
    _body?.value = profile.body.name;
    _skinTone?.value = profile.skinTone.name;
    _hairStyle?.value = profile.hairStyle.name;
    _hairColor?.value = profile.hairColor.name;
    _top?.value = profile.top.name;
    _bottom?.value = profile.bottom.name;
    _shoes?.value = profile.shoes.name;
    _accessory?.value = profile.accessory.name;
    _mood?.value = profile.mood.name;
    _reduceMotion?.value = reduceMotion;
    _accentColor?.value = const Color(0xFF1779C6);
  }

  void dispose() {
    _body?.dispose();
    _skinTone?.dispose();
    _hairStyle?.dispose();
    _hairColor?.dispose();
    _top?.dispose();
    _bottom?.dispose();
    _shoes?.dispose();
    _accessory?.dispose();
    _mood?.dispose();
    _reduceMotion?.dispose();
    _accentColor?.dispose();
    _greet?.dispose();
    _celebrate?.dispose();
    _think?.dispose();
  }
}

class _AvatarStageBackdrop extends StatelessWidget {
  const _AvatarStageBackdrop();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(painter: _AvatarStageBackdropPainter(isDark: isDark));
  }
}

class _AvatarStageBackdropPainter extends CustomPainter {
  const _AvatarStageBackdropPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final accent = isDark ? const Color(0xFF3B91D2) : const Color(0xFF1779C6);
    final grid = Paint()
      ..color = accent.withValues(alpha: isDark ? 0.08 : 0.065)
      ..strokeWidth = 1;
    const spacing = 32.0;
    for (double x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x - size.height, size.height), grid);
    }
    final glow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              accent.withValues(alpha: isDark ? 0.22 : 0.18),
              accent.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.5, size.height * 0.60),
              radius: size.shortestSide * 0.58,
            ),
          );
    canvas.drawRect(Offset.zero & size, glow);
  }

  @override
  bool shouldRepaint(_AvatarStageBackdropPainter oldDelegate) {
    return isDark != oldDelegate.isDark;
  }
}

class _StudentAvatarVectorFallback extends StatefulWidget {
  const _StudentAvatarVectorFallback({required this.profile});

  final StudentAvatarProfile profile;

  @override
  State<_StudentAvatarVectorFallback> createState() =>
      _StudentAvatarVectorFallbackState();
}

class _StudentAvatarVectorFallbackState
    extends State<_StudentAvatarVectorFallback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      key: const ValueKey('student-avatar-vector-fallback'),
      animation: _controller,
      builder: (context, _) => CustomPaint(
        painter: _StudentAvatarPainter(
          profile: widget.profile,
          phase: Curves.easeInOut.transform(_controller.value),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _StudentAvatarPainter extends CustomPainter {
  const _StudentAvatarPainter({required this.profile, required this.phase});

  final StudentAvatarProfile profile;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width / 320, size.height / 520);
    final center = Offset(size.width / 2, size.height * 0.49);
    final breathe = (phase - 0.5) * 4;
    canvas.save();
    canvas.translate(center.dx, center.dy + 14 - breathe);
    canvas.scale(scale, scale);

    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    canvas.drawOval(const Rect.fromLTWH(-86, 219, 172, 24), shadow);

    final skin = _skinColor(profile.skinTone);
    final hair = _hairColor(profile.hairColor);
    final top = _topColor(profile.top);
    final bottom = _bottomColor(profile.bottom);
    final shoe = _shoeColor(profile.shoes);
    final outline = Paint()
      ..color = const Color(0xFF071827).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    _drawLeg(canvas, const Offset(-42, 100), bottom, shoe, outline);
    _drawLeg(canvas, const Offset(18, 100), bottom, shoe, outline);

    final torso = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-83, -45, 166, 170),
      const Radius.circular(40),
    );
    canvas.drawRRect(torso, Paint()..color = top);
    canvas.drawRRect(torso, outline);
    _drawTopDetails(canvas, top);

    final (leftArmDirection, rightArmDirection) = switch (profile.mood) {
      StudentAvatarMood.happy => (-2.25 - phase * 0.05, -0.89 + phase * 0.05),
      StudentAvatarMood.thinking => (2.06, -1.76 + phase * 0.04),
      StudentAvatarMood.calm ||
      StudentAvatarMood.focused => (2.06 - phase * 0.025, 1.08 + phase * 0.025),
    };
    _drawArm(
      canvas,
      shoulder: const Offset(-76, -15),
      direction: leftArmDirection,
      sleeveColor: top,
      skinColor: skin,
      outline: outline,
    );
    _drawArm(
      canvas,
      shoulder: const Offset(76, -15),
      direction: rightArmDirection,
      sleeveColor: top,
      skinColor: skin,
      outline: outline,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-23, -74, 46, 42),
        const Radius.circular(18),
      ),
      Paint()..color = skin,
    );

    final head = Rect.fromCenter(
      center: const Offset(0, -119),
      width: 112,
      height: 124,
    );
    canvas.drawOval(head, Paint()..color = skin);
    canvas.drawOval(head, outline);
    _drawHair(canvas, hair, head);
    _drawFace(canvas);
    _drawAccessory(canvas);

    canvas.restore();
  }

  void _drawLeg(
    Canvas canvas,
    Offset origin,
    Color bottom,
    Color shoe,
    Paint outline,
  ) {
    final leg = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.dx, origin.dy, 60, 116),
      const Radius.circular(22),
    );
    canvas.drawRRect(leg, Paint()..color = bottom);
    canvas.drawRRect(leg, outline);
    final foot = RRect.fromRectAndRadius(
      Rect.fromLTWH(origin.dx - 7, origin.dy + 98, 73, 35),
      const Radius.circular(16),
    );
    canvas.drawRRect(foot, Paint()..color = shoe);
    canvas.drawRRect(foot, outline);
    canvas.drawLine(
      Offset(origin.dx + 3, origin.dy + 119),
      Offset(origin.dx + 56, origin.dy + 119),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.72)
        ..strokeWidth = 3,
    );
  }

  void _drawArm(
    Canvas canvas, {
    required Offset shoulder,
    required double direction,
    required Color sleeveColor,
    required Color skinColor,
    required Paint outline,
  }) {
    final elbow =
        shoulder + Offset(math.cos(direction), math.sin(direction)) * 76;
    final wrist = elbow + Offset(math.cos(direction), math.sin(direction)) * 54;
    final sleeveOutline = Paint()
      ..color = outline.color
      ..strokeWidth = 42
      ..strokeCap = StrokeCap.round;
    final sleeve = Paint()
      ..color = sleeveColor
      ..strokeWidth = 38
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(shoulder, elbow, sleeveOutline);
    canvas.drawLine(elbow, wrist, sleeveOutline);
    canvas.drawLine(shoulder, elbow, sleeve);
    canvas.drawLine(elbow, wrist, sleeve);
    canvas.drawCircle(wrist, 17, Paint()..color = outline.color);
    canvas.drawCircle(wrist, 15, Paint()..color = skinColor);
  }

  void _drawTopDetails(Canvas canvas, Color top) {
    final light = Color.lerp(top, Colors.white, 0.30)!;
    switch (profile.top) {
      case StudentAvatarTop.campusHoodie:
        canvas.drawArc(
          const Rect.fromLTWH(-38, -58, 76, 62),
          0.10,
          math.pi - 0.20,
          false,
          Paint()
            ..color = light.withValues(alpha: 0.62)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4,
        );
        canvas.drawLine(
          const Offset(-12, -18),
          const Offset(-15, 24),
          Paint()
            ..color = light
            ..strokeWidth = 3,
        );
        canvas.drawLine(
          const Offset(12, -18),
          const Offset(15, 24),
          Paint()
            ..color = light
            ..strokeWidth = 3,
        );
      case StudentAvatarTop.varsityJacket:
        canvas.drawLine(
          const Offset(0, -42),
          const Offset(0, 116),
          Paint()
            ..color = light
            ..strokeWidth = 4,
        );
        canvas.drawCircle(const Offset(0, 2), 3, Paint()..color = light);
        canvas.drawCircle(const Offset(0, 30), 3, Paint()..color = light);
      case StudentAvatarTop.smartShirt:
        final collar = Path()
          ..moveTo(-24, -44)
          ..lineTo(0, -14)
          ..lineTo(24, -44);
        canvas.drawPath(
          collar,
          Paint()
            ..color = light
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5,
        );
        canvas.drawLine(
          const Offset(0, -14),
          const Offset(0, 112),
          Paint()
            ..color = light
            ..strokeWidth = 3,
        );
      case StudentAvatarTop.winterCoat:
        canvas.drawLine(
          const Offset(-20, -40),
          const Offset(8, 116),
          Paint()
            ..color = light.withValues(alpha: 0.72)
            ..strokeWidth = 5,
        );
        canvas.drawCircle(const Offset(1, 6), 4, Paint()..color = light);
        canvas.drawCircle(const Offset(7, 40), 4, Paint()..color = light);
    }
  }

  void _drawHair(Canvas canvas, Color color, Rect head) {
    final paint = Paint()..color = color;
    final hairPath = Path()
      ..moveTo(head.left + 4, head.center.dy - 6)
      ..quadraticBezierTo(
        head.left + 2,
        head.top - 13,
        head.center.dx,
        head.top - 16,
      )
      ..quadraticBezierTo(
        head.right - 1,
        head.top - 12,
        head.right - 3,
        head.center.dy + 2,
      )
      ..quadraticBezierTo(
        head.right - 18,
        head.top + 18,
        head.center.dx + 14,
        head.top + 28,
      )
      ..quadraticBezierTo(
        head.center.dx - 7,
        head.top + 13,
        head.left + 4,
        head.center.dy - 6,
      )
      ..close();
    canvas.drawPath(hairPath, paint);

    if (profile.hairStyle == StudentAvatarHairStyle.bob ||
        profile.hairStyle == StudentAvatarHairStyle.shag) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(head.left - 2, head.top + 30, 18, 82),
          const Radius.circular(9),
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(head.right - 16, head.top + 30, 18, 82),
          const Radius.circular(9),
        ),
        paint,
      );
    }
    if (profile.hairStyle == StudentAvatarHairStyle.bun) {
      canvas.drawCircle(Offset(head.center.dx + 28, head.top - 10), 25, paint);
    }
  }

  void _drawFace(Canvas canvas) {
    final eyePaint = Paint()
      ..color = const Color(0xFF101820)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final eyeY = -121.0;
    if (profile.mood == StudentAvatarMood.happy) {
      canvas.drawArc(
        const Rect.fromLTWH(-32, -126, 18, 12),
        0.15,
        math.pi - 0.30,
        false,
        eyePaint..style = PaintingStyle.stroke,
      );
      canvas.drawArc(
        const Rect.fromLTWH(14, -126, 18, 12),
        0.15,
        math.pi - 0.30,
        false,
        eyePaint,
      );
    } else {
      canvas.drawCircle(Offset(-23, eyeY), 4, eyePaint);
      canvas.drawCircle(Offset(23, eyeY), 4, eyePaint);
    }
    final smile = Path()
      ..moveTo(-12, -92)
      ..quadraticBezierTo(
        0,
        profile.mood == StudentAvatarMood.focused ? -87 : -82,
        12,
        -92,
      );
    canvas.drawPath(
      smile,
      Paint()
        ..color = const Color(0xFF8B3F43)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawAccessory(Canvas canvas) {
    switch (profile.accessory) {
      case StudentAvatarAccessory.none:
        return;
      case StudentAvatarAccessory.crossbody:
        canvas.drawLine(
          const Offset(-54, -34),
          const Offset(53, 112),
          Paint()
            ..color = const Color(0xFF111C28)
            ..strokeWidth = 12
            ..strokeCap = StrokeCap.round,
        );
      case StudentAvatarAccessory.headphones:
        canvas.drawArc(
          const Rect.fromLTWH(-66, -173, 132, 112),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = const Color(0xFF142F52)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9,
        );
      case StudentAvatarAccessory.backpack:
        canvas.drawArc(
          const Rect.fromLTWH(-83, -26, 166, 150),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = const Color(0xFF071827)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9,
        );
      case StudentAvatarAccessory.scarf:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-48, -56, 96, 33),
            const Radius.circular(14),
          ),
          Paint()..color = const Color(0xFF4F73A1),
        );
    }
  }

  Color _skinColor(StudentAvatarSkinTone value) => switch (value) {
    StudentAvatarSkinTone.porcelain => const Color(0xFFFFE3D5),
    StudentAvatarSkinTone.light => const Color(0xFFF2C8B0),
    StudentAvatarSkinTone.warm => const Color(0xFFDDA47E),
    StudentAvatarSkinTone.tan => const Color(0xFFB97855),
    StudentAvatarSkinTone.deep => const Color(0xFF74462F),
  };

  Color _hairColor(StudentAvatarHairColor value) => switch (value) {
    StudentAvatarHairColor.ink => const Color(0xFF111820),
    StudentAvatarHairColor.espresso => const Color(0xFF30221E),
    StudentAvatarHairColor.chestnut => const Color(0xFF6C3E2C),
    StudentAvatarHairColor.ash => const Color(0xFF736F72),
    StudentAvatarHairColor.blueBlack => const Color(0xFF172B46),
  };

  Color _topColor(StudentAvatarTop value) => switch (value) {
    StudentAvatarTop.campusHoodie => const Color(0xFF112F59),
    StudentAvatarTop.varsityJacket => const Color(0xFF1E4D7B),
    StudentAvatarTop.smartShirt => const Color(0xFF8DB4D5),
    StudentAvatarTop.winterCoat => const Color(0xFF182B3C),
  };

  Color _bottomColor(StudentAvatarBottom value) => switch (value) {
    StudentAvatarBottom.greyJoggers => const Color(0xFF8B9199),
    StudentAvatarBottom.blackCargo => const Color(0xFF1B232D),
    StudentAvatarBottom.blueDenim => const Color(0xFF587B9C),
  };

  Color _shoeColor(StudentAvatarShoes value) => switch (value) {
    StudentAvatarShoes.runners => const Color(0xFFF1F4F7),
    StudentAvatarShoes.highTops => const Color(0xFF152D4A),
    StudentAvatarShoes.sneakers => const Color(0xFFD8DADD),
  };

  @override
  bool shouldRepaint(_StudentAvatarPainter oldDelegate) {
    return profile != oldDelegate.profile || phase != oldDelegate.phase;
  }
}

class _AvatarEditButton extends StatelessWidget {
  const _AvatarEditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.text('编辑虚拟形象'),
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.76),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: const SizedBox.square(
            dimension: 48,
            child: Icon(LucideIcons.slidersHorizontal300, size: 21),
          ),
        ),
      ),
    );
  }
}
