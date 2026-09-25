import 'package:flutter/material.dart';
import '../models/course_content.dart';
import '../models/course_summary.dart';
import '../models/timeline_item.dart';
import '../state/app_session_controller.dart';
import 'folder_detail_page.dart';
import 'ispace_text_page.dart';
import 'timeline_detail_page.dart';
import 'web_mirror_page.dart';

/// All course entry points share the same native/read-only webpage routing.
Future<void> openIspaceCourseModule({
  required BuildContext context,
  required AppSessionController controller,
  required CourseSummary course,
  required CourseModule module,
  required List<CourseContentSection> sections,
}) async {
  if (!module.visible ||
      !module.userVisible ||
      sections.any(
        (section) =>
            (!section.visible || !section.userVisible) &&
            section.modules.any((item) => item.id == module.id),
      )) {
    return;
  }
  if (module.modName == 'label') {
    final parents = sections.where(
      (s) => s.modules.any((m) => m.id == module.id),
    );
    final anchor = parents.isEmpty
        ? ''
        : '#section-${parents.first.sectionNum}';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WebMirrorPage(
          controller: controller,
          title: module.name,
          pathOrUrl: '/course/view.php?id=${course.id}$anchor',
        ),
      ),
    );
    return;
  }
  if (module.modName == 'page') {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IspaceTextPage(
          controller: controller,
          course: course,
          module: module,
        ),
      ),
    );
    return;
  }
  final modName = module.modName.toLowerCase();
  final isResource = modName.contains('resource');
  if (modName.contains('folder')) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FolderDetailPage(
          controller: controller,
          course: course,
          module: module,
        ),
      ),
    );
    return;
  }

  final openAsTimelineDetail =
      module.isAssignment ||
      modName.contains('forum') ||
      modName.contains('mediasite');
  if (openAsTimelineDetail) {
    final resolvedInstanceId = module.instance > 0
        ? module.instance
        : module.id;
    final resolvedUrl = module.url.trim().isNotEmpty
        ? module.url
        : '/mod/${module.modName}/view.php?id=${module.id}';
    final pseudoItem = TimelineItem(
      id: -module.id,
      title: module.name,
      activityState: module.isAssignment ? '作业截止' : modName,
      activityType: module.modName,
      moduleName: module.modName,
      description: '',
      courseName: course.fullName,
      courseId: course.id,
      instanceId: resolvedInstanceId,
      url: resolvedUrl,
      sortTime: module.dates.isEmpty ? null : module.dates.first.dateTime,
      formattedTime: '',
      isOverdue: false,
    );
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TimelineDetailPage(controller: controller, item: pseudoItem),
      ),
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => WebMirrorPage(
        controller: controller,
        title: module.name,
        pathOrUrl: _moduleViewUrl(module),
        showFileActions: isResource,
        actionPathOrUrl: isResource
            ? _resourceActionUrl(controller, module)
            : null,
        studyItems: module.contents
            .map((item) => item.fileName.trim())
            .where((name) => name.isNotEmpty)
            .toList(growable: false),
      ),
    ),
  );
}

String _moduleViewUrl(CourseModule module) {
  final raw = module.url.trim();
  if (raw.isNotEmpty) {
    return raw;
  }
  return '/mod/${module.modName}/view.php?id=${module.id}';
}

String _resourceActionUrl(
  AppSessionController controller,
  CourseModule module,
) {
  for (final content in module.contents) {
    final raw = content.fileUrl.trim();
    if (raw.isEmpty) {
      continue;
    }
    final resolved = _resolveAbsoluteUrl(controller.baseUrl, raw);
    if (resolved.isEmpty) {
      continue;
    }
    final uri = Uri.tryParse(resolved);
    if (uri == null) {
      return resolved;
    }
    final normalizedPath = uri.path.replaceFirst(
      '/webservice/pluginfile.php',
      '/pluginfile.php',
    );
    final query = Map<String, String>.from(uri.queryParameters);
    query.remove('token');
    return uri
        .replace(
          path: normalizedPath,
          queryParameters: query.isEmpty ? null : query,
        )
        .toString();
  }
  return _moduleViewUrl(module);
}

String _resolveAbsoluteUrl(String baseUrl, String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/')) {
    return '$baseUrl$trimmed';
  }
  return '$baseUrl/$trimmed';
}
