import 'ispace_page_content.dart';

import '../models/course_content.dart';
import 'course_archive_service.dart';
import 'native_actions.dart';

/// Native implementation of the resource/folder/page discovery approach in
/// jytpeterjiang/iSpace_Downloader (a3145d7). No userscript is executed, and no
/// school session or resource is sent to that project or to an AI service.
class CoursewareDownloadPlan {
  const CoursewareDownloadPlan({
    required this.files,
    this.unavailablePages = 0,
    this.skippedLinks = 0,
  });

  final List<CourseArchiveEntry> files;
  final int unavailablePages;
  final int skippedLinks;

  int get knownBytes =>
      files.fold(0, (total, file) => total + file.expectedBytes);
}

/// Accept only Moodle's normal file endpoint on the configured HTTPS origin.
/// Token-bearing REST URLs become cookie-authenticated URLs before leaving the
/// session layer. Draft files, arbitrary scripts and foreign origins are never
/// batch-downloaded.
Uri? normalizeCoursewareFileUrl(String value, String baseUrl) {
  if (value.trim().isEmpty) return null;
  try {
    final origin = Uri.parse(baseUrl);
    final uri = origin.resolve(value.trim());
    if (origin.scheme != 'https' ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        !urlsHaveSameOrigin(uri.toString(), origin.toString())) {
      return null;
    }
    final path = uri.path.replaceFirst(
      RegExp(r'^/webservice/pluginfile\.php/'),
      '/pluginfile.php/',
    );
    if (!path.startsWith('/pluginfile.php/')) return null;
    // Only the file path is needed for a Moodle file. Never carry token,
    // sesskey, signatures or other opaque query fields into the plan.
    return uri
        .replace(path: path, queryParameters: const {'forcedownload': '1'})
        .removeFragment();
  } on FormatException {
    return null;
  }
}

CoursewareDownloadPlan buildCoursewareDownloadPlan({
  required String baseUrl,
  required List<CourseContentSection> sections,
  Map<int, String> pageHtmlByInstance = const {},
  int unavailablePages = 0,
  int maxFiles = 100,
}) {
  final files = <String, CourseArchiveEntry>{};
  var skippedLinks = 0;

  void add(
    String rawUrl,
    CourseContentSection section,
    CourseModule module, {
    String name = '',
    String displayName = '',
    String group = '',
    int bytes = 0,
  }) {
    final uri = normalizeCoursewareFileUrl(rawUrl, baseUrl);
    if (uri == null) {
      if (rawUrl.contains('pluginfile.php') ||
          rawUrl.contains('draftfile.php')) {
        skippedLinks++;
      }
      return;
    }
    // Moodle exports the Page document itself as type=file, size=0. Its
    // /mod_page/content/index.html endpoint serves HTML, not an attachment.
    // Keep revision-qualified attachments (including real HTML files) intact.
    if (RegExp(r'/mod_page/content/index\.html?$').hasMatch(uri.path)) {
      return;
    }
    final existing = files[uri.toString()];
    if (existing != null) {
      if (displayName.isNotEmpty) {
        files[uri.toString()] = CourseArchiveEntry(
          url: existing.url,
          sectionName: existing.sectionName,
          moduleName: [module.name, if (group.isNotEmpty) group].join(' / '),
          fileName: existing.fileName,
          expectedBytes: existing.expectedBytes,
          displayName: displayName,
        );
      }
      return;
    }
    if (files.length >= maxFiles) {
      throw const CourseArchiveException('课件超过单次 100 个文件上限，请使用单文件下载。');
    }
    final pathName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    files[uri.toString()] = CourseArchiveEntry(
      url: uri.toString(),
      sectionName: section.name,
      moduleName: [module.name, if (group.isNotEmpty) group].join(' / '),
      displayName: displayName,
      fileName: safeAttachmentFileName(name.isEmpty ? pathName : name),
      expectedBytes: bytes < 0 ? 0 : bytes,
    );
  }

  void scanHtml(
    String html,
    CourseContentSection section,
    CourseModule module,
  ) {
    final content = IspacePageContent.parse(html, baseUrl);
    for (final link in content.links) {
      add(
        link.url,
        section,
        module,
        displayName: link.title,
        group: link.group,
      );
    }
  }

  for (final section in sections) {
    if (!section.userVisible || !section.visible) continue;
    for (final module in section.modules) {
      if (!module.userVisible || !module.visible || !module.downloadContent) {
        continue;
      }
      // Never collect students' forum, assignment or quiz attachments.
      if (!const {
        'resource',
        'folder',
        'page',
        'url',
        'label',
      }.contains(module.modName)) {
        continue;
      }
      for (final content in module.contents) {
        if (content.type != 'file') continue;
        add(
          content.fileUrl,
          section,
          module,
          name: content.fileName,
          bytes: content.fileSize,
        );
      }
      scanHtml(module.descriptionHtml, section, module);
      if (module.modName == 'page') {
        scanHtml(pageHtmlByInstance[module.instance] ?? '', section, module);
      } else if (module.modName == 'url') {
        add(module.url, section, module);
      }
    }
  }
  return CoursewareDownloadPlan(
    files: List.unmodifiable(files.values),
    unavailablePages: unavailablePages,
    skippedLinks: skippedLinks,
  );
}
