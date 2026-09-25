import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/course_content.dart';
import 'package:bnbu_me/services/course_archive_service.dart';
import 'package:bnbu_me/services/courseware_download_plan.dart';

const origin = 'https://ispace.example.edu';

CourseModule module({
  String kind = 'resource',
  bool visible = true,
  bool download = true,
  String html = '',
  List<Map<String, Object>> files = const [],
}) => CourseModule.fromJson({
  'id': 10,
  'instance': 20,
  'name': 'Lecture',
  'modname': kind,
  'visible': visible,
  'uservisible': visible,
  'downloadcontent': download,
  'description': html,
  'contents': files,
});

CourseContentSection section(
  List<CourseModule> modules, {
  bool visible = true,
}) => CourseContentSection(
  id: 1,
  sectionNum: 1,
  name: 'Week 1',
  summary: '',
  modules: modules,
  userVisible: visible,
);

void main() {
  test('excludes Moodle synthetic Page HTML but keeps real page attachments', () {
    final plan = buildCoursewareDownloadPlan(
      baseUrl: origin,
      sections: [
        section([
          module(
            kind: 'page',
            files: [
              for (final path in ['index.html', 'index.htm', '3/slides.pptx'])
                {
                  'type': 'file',
                  'filename': path.split('/').last,
                  'fileurl':
                      '$origin/webservice/pluginfile.php/42/mod_page/content/$path',
                },
            ],
          ),
        ]),
      ],
      pageHtmlByInstance: {
        20: '<a href="/pluginfile.php/42/mod_page/content/3/notes.pdf">Notes</a>',
      },
    );
    expect(plan.files.map((file) => file.fileName), [
      'slides.pptx',
      'notes.pdf',
    ]);
    expect(plan.skippedLinks, 0);
  });

  test('normalizes REST file URLs and removes credentials and fragments', () {
    final uri = normalizeCoursewareFileUrl(
      '$origin/webservice/pluginfile.php/1/slides.pptx?token=private#page=2',
      origin,
    )!;
    expect(
      uri.toString(),
      '$origin/pluginfile.php/1/slides.pptx?forcedownload=1',
    );
    expect(uri.queryParameters, {'forcedownload': '1'});
  });

  test('rejects foreign, insecure, credentialed, draft and script URLs', () {
    for (final url in [
      'http://ispace.example.edu/pluginfile.php/1/a.pdf',
      'https://evil.example/pluginfile.php/1/a.pdf',
      'https://ispace.example.edu.evil.example/pluginfile.php/1/a.pdf',
      'https://user@ispace.example.edu/pluginfile.php/1/a.pdf',
      '/draftfile.php/1/a.pdf',
      '/mod/resource/view.php?id=1',
      'javascript:alert(1)',
      'file:///pluginfile.php/1/a.pdf',
    ]) {
      expect(normalizeCoursewareFileUrl(url, origin), isNull, reason: url);
    }
  });

  test(
    'merges REST, page links and viewers while preserving file extensions',
    () {
      final plan = buildCoursewareDownloadPlan(
        baseUrl: origin,
        sections: [
          section([
            module(
              files: [
                {
                  'type': 'file',
                  'filename': 'slides.pptx',
                  'fileurl':
                      '$origin/webservice/pluginfile.php/1/slides.pptx?token=private',
                  'filesize': 15,
                },
              ],
            ),
            module(kind: 'page'),
          ]),
        ],
        pageHtmlByInstance: {
          20: '''
      <a href="/pluginfile.php/1/slides.pptx?forcedownload=0">Duplicate</a>
      <a href="/pluginfile.php/1/%E8%AF%BE%E4%BB%B6.pdf">Download</a>
      <object data="/pluginfile.php/1/second.ppt"></object>
      <iframe src="/pluginfile.php/1/notes.docx"></iframe>
      <img src="/pluginfile.php/1/logo.png">
      <a href="https://evil.example/pluginfile.php/1/private.pdf">External</a>
    ''',
        },
      );
      expect(plan.files.map((file) => file.fileName), [
        'slides.pptx',
        '课件.pdf',
        'second.ppt',
        'notes.docx',
      ]);
      expect(plan.knownBytes, 15);
      expect(plan.skippedLinks, 1);
      expect(plan.files.every((file) => !file.url.contains('token')), isTrue);
    },
  );

  test('excludes hidden, forbidden and student-submitted attachments', () {
    final file = {
      'type': 'file',
      'filename': 'a.pdf',
      'fileurl': '$origin/pluginfile.php/1/a.pdf',
    };
    final plan = buildCoursewareDownloadPlan(
      baseUrl: origin,
      sections: [
        section([
          module(files: [file]),
        ], visible: false),
        section([
          module(visible: false, files: [file]),
          module(download: false, files: [file]),
          module(kind: 'forum', files: [file]),
          module(kind: 'assign', files: [file]),
          module(kind: 'quiz', files: [file]),
        ]),
      ],
      unavailablePages: 2,
    );
    expect(plan.files, isEmpty);
    expect(plan.unavailablePages, 2);
  });

  test(
    'oversized discovery fails explicitly without a truncated success list',
    () {
      expect(
        () => buildCoursewareDownloadPlan(
          baseUrl: origin,
          maxFiles: 1,
          sections: [
            section([module(kind: 'page')]),
          ],
          pageHtmlByInstance: {
            20:
                '<a href="/pluginfile.php/1/a.pdf">A</a>'
                '<a href="/pluginfile.php/1/b.pdf">B</a>',
          },
        ),
        throwsA(isA<CourseArchiveException>()),
      );
    },
  );
}
