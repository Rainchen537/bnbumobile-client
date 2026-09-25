import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:bnbu_me/services/pptx_study_document.dart';
import 'package:bnbu_me/services/study_mode_skill.dart';

void main() {
  final validPng = Uint8List.fromList(
    image.encodePng(image.Image(width: 2, height: 2)),
  );

  test('study organizer exposes an editable annotation preset', () {
    expect(
      StudyModeSkill.defaultOrganizationInstruction,
      contains('逐题解释题干和每个选项'),
    );
    expect(StudyModeSkill.defaultOrganizationInstruction, contains('以整理为主'));
  });

  test(
    'study organizer stays page-scoped and treats translation as optional',
    () async {
      const skill = StudyModeSkill();
      final request = await skill.organize(
        page: StudyPageSnapshot(
          documentTitle: 'Lecture.pdf',
          pageNumber: 3,
          pageCount: 12,
          text: 'Neural networks optimize a loss function.',
          captureImage: () async => validPng,
        ),
        outputLanguage: 'zh-CN',
        customInstruction: '保留中英双语术语',
      );

      expect(request.prompt, contains('只处理提供的这一页'));
      expect(request.prompt, contains('第 3 页 / 共 12 页'));
      expect(request.prompt, contains('翻译只是表达优化'));
      expect(request.prompt, contains('保留中英双语术语'));
      expect(request.prompt, contains('逐个解释每一个选项'));
      expect(request.prompt, contains('不得设置“答案”'));
      expect(request.attachments.single.name, 'study-page-3.jpg');
      expect(request.attachments.single.mimeType, 'image/jpeg');
      expect(request.attachments.single.bytes.take(2), [0xff, 0xd8]);
      expect(
        request.attachments.single.bytes.length,
        lessThanOrEqualTo(2 << 20),
      );
      expect(request.prompt, contains('必须实际读取这些图像'));
    },
  );

  test('pptx parser preserves slide order and extracts page text', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'ppt/presentation.xml',
          '''<p:presentation xmlns:p="p" xmlns:r="r"><p:sldMasterIdLst/><p:sldIdLst><p:sldId r:id="rId1"/><p:sldId r:id="rId2"/></p:sldIdLst><p:sldSz cx="1200" cy="675"/></p:presentation>''',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'ppt/_rels/presentation.xml.rels',
          '''<Relationships><Relationship Id="rId1" Target="slides/slide1.xml"/><Relationship Id="rId2" Target="slides/slide2.xml"/></Relationships>''',
        ),
      )
      ..addFile(
        ArchiveFile.string('ppt/slides/slide1.xml', _slideXml('第一页', x: 10)),
      )
      ..addFile(
        ArchiveFile.string('ppt/slides/slide2.xml', _slideXml('第二页', x: 20)),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    final document = PptxStudyDocument.parse(bytes);

    expect(document.pages, hasLength(2));
    expect(document.pages.first.text, '第一页');
    expect(document.pages.last.text, '第二页');
    expect(
      document.pages.last.elements.single.rect.left,
      closeTo(20 / 1200, .0001),
    );
  });

  test(
    'study question skill supports selected pages with bounded images',
    () async {
      const skill = StudyModeSkill();
      final pages = [
        for (var page = 1; page <= 8; page++)
          StudyPageSnapshot(
            documentTitle: 'Lecture.pdf',
            pageNumber: page,
            pageCount: 8,
            text: '第 $page 页内容',
            captureImage: () async => validPng,
          ),
      ];

      final request = await skill.answerPages(
        pages: pages,
        question: '比较这些页面的概念',
        outputLanguage: 'zh-CN',
        scope: StudyQuestionScope.selectedPages,
      );

      expect(request.prompt, contains('问答范围：所选页面'));
      expect(request.prompt, contains('第 8 页 / 共 8 页'));
      expect(request.attachments, hasLength(8));
      expect(request.attachments.last.name, 'study-page-8.jpg');
      expect(
        request.attachments.fold<int>(
          0,
          (total, attachment) => total + attachment.bytes.length,
        ),
        lessThanOrEqualTo(8 * 1024 * 1024),
      );
    },
  );

  test('whole-document requests sample visual pages across the file', () async {
    const skill = StudyModeSkill();
    final pages = [
      for (var page = 1; page <= 20; page++)
        StudyPageSnapshot(
          documentTitle: 'Lecture.pdf',
          pageNumber: page,
          pageCount: 20,
          text: '第 $page 页内容',
          captureImage: () async => validPng,
        ),
    ];

    final request = await skill.answerPages(
      pages: pages,
      question: '概括全文件',
      outputLanguage: 'zh-CN',
      scope: StudyQuestionScope.wholeDocument,
    );

    expect(request.attachments, hasLength(StudyModeSkill.maxVisualPages));
    expect(request.attachments.first.name, 'study-page-1.jpg');
    expect(request.attachments.last.name, 'study-page-20.jpg');
  });

  test(
    'current-page study requests fail locally when page capture is missing',
    () {
      const skill = StudyModeSkill();

      expect(
        () => skill.organize(
          page: const StudyPageSnapshot(
            documentTitle: 'Lecture.pdf',
            pageNumber: 1,
            pageCount: 1,
            text: '',
          ),
          outputLanguage: 'zh-CN',
        ),
        throwsA(isA<StudyPageImageUnavailableException>()),
      );
    },
  );

  test('current-page study requests reject invalid captured image bytes', () {
    const skill = StudyModeSkill();

    expect(
      () => skill.answer(
        page: StudyPageSnapshot(
          documentTitle: 'Lecture.pdf',
          pageNumber: 1,
          pageCount: 1,
          text: '本页文字',
          captureImage: () async => Uint8List.fromList([1, 2, 3]),
        ),
        question: '解释本页',
        outputLanguage: 'zh-CN',
      ),
      throwsA(isA<StudyPageImageUnavailableException>()),
    );
  });

  test(
    'current-page study requests convert capture failures to a retryable error',
    () {
      const skill = StudyModeSkill();

      expect(
        () => skill.answer(
          page: StudyPageSnapshot(
            documentTitle: 'Lecture.pdf',
            pageNumber: 2,
            pageCount: 4,
            text: '本页文字',
            captureImage: () async => throw StateError('renderer unavailable'),
          ),
          question: '解释本页',
          outputLanguage: 'zh-CN',
        ),
        throwsA(
          isA<StudyPageImageUnavailableException>().having(
            (error) => error.pageNumber,
            'pageNumber',
            2,
          ),
        ),
      );
    },
  );
}

String _slideXml(String text, {required int x}) =>
    '''<p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree><p:sp><p:spPr><a:xfrm><a:off x="$x" y="30"/><a:ext cx="600" cy="200"/></a:xfrm></p:spPr><p:txBody><a:p><a:r><a:rPr sz="2400" b="1"/><a:t>$text</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>''';
