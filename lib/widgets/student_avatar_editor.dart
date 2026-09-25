import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/student_avatar_profile.dart';
import '../state/student_avatar_controller.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive_modal.dart';
import 'student_avatar_rive.dart';

Future<void> showStudentAvatarEditor(
  BuildContext context,
  StudentAvatarController controller,
) {
  return showBnbuAdaptiveModal<void>(
    context: context,
    dialogMaxWidth: 980,
    dialogMaxHeight: 760,
    isScrollControlled: true,
    bottomSheetBackgroundColor: Colors.transparent,
    semanticLabel: context.l10n.text('虚拟形象'),
    contentKey: const ValueKey('student-avatar-editor-modal'),
    builder: (modalContext, presentation) {
      if (presentation.isDialog) {
        return SizedBox(
          height: 760,
          child: _StudentAvatarEditor(controller: controller),
        );
      }
      return DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.72,
        maxChildSize: 0.98,
        expand: false,
        builder: (context, scrollController) => Material(
          color: context.bnbuTheme.canvas,
          clipBehavior: Clip.antiAlias,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: _StudentAvatarEditor(
            controller: controller,
            scrollController: scrollController,
          ),
        ),
      );
    },
  );
}

class _StudentAvatarEditor extends StatelessWidget {
  const _StudentAvatarEditor({required this.controller, this.scrollController});

  final StudentAvatarController controller;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final tokens = context.bnbuTheme;
        final profile = controller.profile;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.space24,
                tokens.space16,
                tokens.space12,
                tokens.space12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: BnbuText(
                      '虚拟形象',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.text('重置'),
                    onPressed: controller.isSaving ? null : controller.reset,
                    icon: const Icon(LucideIcons.rotateCcw300),
                  ),
                  IconButton(
                    tooltip: context.l10n.text('关闭'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x300),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final controls = _AvatarControls(
                    profile: profile,
                    onChanged: controller.update,
                  );
                  if (constraints.maxWidth >= 720) {
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        tokens.space24,
                        0,
                        tokens.space24,
                        tokens.space24,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 320,
                            child: StudentAvatarStage(profile: profile),
                          ),
                          SizedBox(width: tokens.space24),
                          Expanded(
                            child: SingleChildScrollView(child: controls),
                          ),
                        ],
                      ),
                    );
                  }
                  return CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.space16,
                          ),
                          child: SizedBox(
                            height: 310,
                            child: StudentAvatarStage(profile: profile),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          tokens.space16,
                          tokens.space16,
                          tokens.space16,
                          tokens.space32,
                        ),
                        sliver: SliverToBoxAdapter(
                          child: _AvatarControls(
                            profile: profile,
                            onChanged: controller.update,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AvatarControls extends StatelessWidget {
  const _AvatarControls({required this.profile, required this.onChanged});

  final StudentAvatarProfile profile;
  final ValueChanged<StudentAvatarProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    final children = [
      _AvatarOptionSection<StudentAvatarBody>(
        title: '体态',
        icon: LucideIcons.personStanding300,
        values: StudentAvatarBody.values,
        selected: profile.body,
        labelOf: _bodyLabel,
        onSelected: (value) => onChanged(profile.copyWith(body: value)),
      ),
      _AvatarColorSection<StudentAvatarSkinTone>(
        title: '肤色',
        icon: LucideIcons.palette300,
        values: StudentAvatarSkinTone.values,
        selected: profile.skinTone,
        labelOf: _skinToneLabel,
        colorOf: _skinToneColor,
        onSelected: (value) => onChanged(profile.copyWith(skinTone: value)),
      ),
      _AvatarOptionSection<StudentAvatarHairStyle>(
        title: '发型',
        icon: LucideIcons.sparkles300,
        values: StudentAvatarHairStyle.values,
        selected: profile.hairStyle,
        labelOf: _hairStyleLabel,
        onSelected: (value) => onChanged(profile.copyWith(hairStyle: value)),
      ),
      _AvatarColorSection<StudentAvatarHairColor>(
        title: '发色',
        icon: LucideIcons.pipette300,
        values: StudentAvatarHairColor.values,
        selected: profile.hairColor,
        labelOf: _hairColorLabel,
        colorOf: _hairColorValue,
        onSelected: (value) => onChanged(profile.copyWith(hairColor: value)),
      ),
      _AvatarOptionSection<StudentAvatarTop>(
        title: '上装',
        icon: LucideIcons.shirt300,
        values: StudentAvatarTop.values,
        selected: profile.top,
        labelOf: _topLabel,
        onSelected: (value) => onChanged(profile.copyWith(top: value)),
      ),
      _AvatarOptionSection<StudentAvatarBottom>(
        title: '下装',
        icon: LucideIcons.rows3300,
        values: StudentAvatarBottom.values,
        selected: profile.bottom,
        labelOf: _bottomLabel,
        onSelected: (value) => onChanged(profile.copyWith(bottom: value)),
      ),
      _AvatarOptionSection<StudentAvatarShoes>(
        title: '鞋',
        icon: LucideIcons.footprints300,
        values: StudentAvatarShoes.values,
        selected: profile.shoes,
        labelOf: _shoesLabel,
        onSelected: (value) => onChanged(profile.copyWith(shoes: value)),
      ),
      _AvatarOptionSection<StudentAvatarAccessory>(
        title: '配饰',
        icon: LucideIcons.backpack300,
        values: StudentAvatarAccessory.values,
        selected: profile.accessory,
        labelOf: _accessoryLabel,
        onSelected: (value) => onChanged(profile.copyWith(accessory: value)),
      ),
      _AvatarOptionSection<StudentAvatarMood>(
        title: '状态',
        icon: LucideIcons.smile300,
        values: StudentAvatarMood.values,
        selected: profile.mood,
        labelOf: _moodLabel,
        onSelected: (value) => onChanged(profile.copyWith(mood: value)),
      ),
    ];

    return Column(children: children);
  }
}

class _AvatarOptionSection<T> extends StatelessWidget {
  const _AvatarOptionSection({
    required this.title,
    required this.icon,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final String title;
  final IconData icon;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AvatarSectionTitle(title: title, icon: icon),
          SizedBox(height: tokens.space12),
          Wrap(
            spacing: tokens.space8,
            runSpacing: tokens.space8,
            children: [
              for (final value in values)
                ChoiceChip(
                  label: BnbuText(labelOf(value)),
                  selected: selected == value,
                  onSelected: (_) => onSelected(value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvatarColorSection<T> extends StatelessWidget {
  const _AvatarColorSection({
    required this.title,
    required this.icon,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.colorOf,
    required this.onSelected,
  });

  final String title;
  final IconData icon;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final Color Function(T value) colorOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AvatarSectionTitle(title: title, icon: icon),
          SizedBox(height: tokens.space12),
          Wrap(
            spacing: tokens.space12,
            runSpacing: tokens.space12,
            children: [
              for (final value in values)
                Semantics(
                  button: true,
                  selected: selected == value,
                  label: labelOf(value),
                  child: InkResponse(
                    onTap: () => onSelected(value),
                    radius: 28,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorOf(value),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected == value
                              ? context.bnbuTheme.brandBlue
                              : Colors.white.withValues(alpha: 0.72),
                          width: selected == value ? 4 : 2,
                        ),
                        boxShadow: selected == value
                            ? [
                                BoxShadow(
                                  color: context.bnbuTheme.brandBlue.withValues(
                                    alpha: 0.22,
                                  ),
                                  blurRadius: 12,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvatarSectionTitle extends StatelessWidget {
  const _AvatarSectionTitle({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: context.bnbuTheme.brandBlue),
        const SizedBox(width: 8),
        BnbuText(title, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}

String _bodyLabel(StudentAvatarBody value) => switch (value) {
  StudentAvatarBody.classic => '自然',
  StudentAvatarBody.relaxed => '松弛',
  StudentAvatarBody.athletic => '活力',
};

String _skinToneLabel(StudentAvatarSkinTone value) => switch (value) {
  StudentAvatarSkinTone.porcelain => '瓷白',
  StudentAvatarSkinTone.light => '浅色',
  StudentAvatarSkinTone.warm => '暖色',
  StudentAvatarSkinTone.tan => '小麦',
  StudentAvatarSkinTone.deep => '深色',
};

Color _skinToneColor(StudentAvatarSkinTone value) => switch (value) {
  StudentAvatarSkinTone.porcelain => const Color(0xFFFFE3D5),
  StudentAvatarSkinTone.light => const Color(0xFFF2C8B0),
  StudentAvatarSkinTone.warm => const Color(0xFFDDA47E),
  StudentAvatarSkinTone.tan => const Color(0xFFB97855),
  StudentAvatarSkinTone.deep => const Color(0xFF74462F),
};

String _hairStyleLabel(StudentAvatarHairStyle value) => switch (value) {
  StudentAvatarHairStyle.crop => '短发',
  StudentAvatarHairStyle.wave => '微卷',
  StudentAvatarHairStyle.shag => '层次',
  StudentAvatarHairStyle.bob => '齐肩',
  StudentAvatarHairStyle.bun => '束发',
};

String _hairColorLabel(StudentAvatarHairColor value) => switch (value) {
  StudentAvatarHairColor.ink => '墨黑',
  StudentAvatarHairColor.espresso => '深棕',
  StudentAvatarHairColor.chestnut => '栗色',
  StudentAvatarHairColor.ash => '灰棕',
  StudentAvatarHairColor.blueBlack => '蓝黑',
};

Color _hairColorValue(StudentAvatarHairColor value) => switch (value) {
  StudentAvatarHairColor.ink => const Color(0xFF111820),
  StudentAvatarHairColor.espresso => const Color(0xFF30221E),
  StudentAvatarHairColor.chestnut => const Color(0xFF6C3E2C),
  StudentAvatarHairColor.ash => const Color(0xFF736F72),
  StudentAvatarHairColor.blueBlack => const Color(0xFF172B46),
};

String _topLabel(StudentAvatarTop value) => switch (value) {
  StudentAvatarTop.campusHoodie => '校园卫衣',
  StudentAvatarTop.varsityJacket => '棒球夹克',
  StudentAvatarTop.smartShirt => '通勤衬衫',
  StudentAvatarTop.winterCoat => '冬季外套',
};

String _bottomLabel(StudentAvatarBottom value) => switch (value) {
  StudentAvatarBottom.greyJoggers => '灰色束脚裤',
  StudentAvatarBottom.blackCargo => '黑色工装裤',
  StudentAvatarBottom.blueDenim => '蓝色牛仔裤',
};

String _shoesLabel(StudentAvatarShoes value) => switch (value) {
  StudentAvatarShoes.runners => '运动鞋',
  StudentAvatarShoes.highTops => '高帮鞋',
  StudentAvatarShoes.sneakers => '休闲鞋',
};

String _accessoryLabel(StudentAvatarAccessory value) => switch (value) {
  StudentAvatarAccessory.none => '无',
  StudentAvatarAccessory.crossbody => '斜挎包',
  StudentAvatarAccessory.headphones => '耳机',
  StudentAvatarAccessory.backpack => '双肩包',
  StudentAvatarAccessory.scarf => '围巾',
};

String _moodLabel(StudentAvatarMood value) => switch (value) {
  StudentAvatarMood.calm => '待机',
  StudentAvatarMood.happy => '开心',
  StudentAvatarMood.focused => '专注',
  StudentAvatarMood.thinking => '思考',
};
