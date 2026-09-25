import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The official Moodle 4.1 activity artwork, shared by all activity surfaces.
/// Provenance and unchanged source hashes live in assets/moodle/sources.json.
const moodleActivityAssetTypes = <String>{
  'assign',
  'quiz',
  'forum',
  'resource',
  'folder',
  'page',
  'url',
  'book',
  'choice',
  'feedback',
  'lesson',
  'workshop',
  'survey',
  'wiki',
  'glossary',
  'scorm',
  'imscp',
  'data',
  'lti',
  'label',
};

bool _licenseRegistered = false;

void registerMoodleIconLicense() {
  if (_licenseRegistered) return;
  _licenseRegistered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Moodle activity artwork',
    ], await rootBundle.loadString('assets/moodle/COPYING.txt'));
  });
}

String moodleActivityTypeKey(String moduleName, [String activityType = '']) {
  var value = (moduleName.trim().isEmpty ? activityType : moduleName)
      .trim()
      .toLowerCase();
  if (value.startsWith('mod_')) value = value.substring(4);
  return switch (value) {
    'assignment' || 'assignments' => 'assign',
    'quizzes' => 'quiz',
    'forums' => 'forum',
    'resources' || 'file' => 'resource',
    'folders' => 'folder',
    'pages' => 'page',
    'urls' || 'link' => 'url',
    _ => value,
  };
}

String? moodleActivityAssetPath(String moduleName, [String activityType = '']) {
  final type = moodleActivityTypeKey(moduleName, activityType);
  return moodleActivityAssetTypes.contains(type)
      ? 'assets/moodle/$type.svg'
      : null;
}

class MoodleActivityIcon extends StatelessWidget {
  const MoodleActivityIcon({
    super.key,
    required this.moduleName,
    this.activityType = '',
    this.size = 20,
    this.color,
    this.semanticLabel,
  });

  final String moduleName;
  final String activityType;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final asset = moodleActivityAssetPath(moduleName, activityType);
    final foreground = color ?? IconTheme.of(context).color;
    if (asset == null) {
      return Icon(
        moodleActivityTypeKey(moduleName, activityType) == 'mediasite'
            ? LucideIcons.video300
            : LucideIcons.puzzle300,
        size: size,
        color: foreground,
        semanticLabel: semanticLabel,
      );
    }
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: foreground == null
          ? null
          : ColorFilter.mode(foreground, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
