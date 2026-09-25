import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/study_mode_skill.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/study_document_viewer.dart';

void main() {
  group('study document format detection', () {
    test('uses PDF MIME type when the display title has no extension', () {
      expect(
        resolveStudyDocumentFormat(
          title: 'Quiz Answer (Quiz2-6)',
          mimeType: 'application/pdf; charset=binary',
        ),
        StudyDocumentFormat.pdf,
      );
    });

    test('uses PPTX MIME type when the display title has no extension', () {
      expect(
        resolveStudyDocumentFormat(
          title: 'Week 3 Slides',
          mimeType:
              'application/vnd.openxmlformats-officedocument.presentationml.presentation; charset=binary',
        ),
        StudyDocumentFormat.pptx,
      );
    });

    test('keeps extension fallback for older document metadata', () {
      expect(
        resolveStudyDocumentFormat(
          title: 'Lecture 01.PDF',
          mimeType: 'application/octet-stream',
        ),
        StudyDocumentFormat.pdf,
      );
      expect(
        resolveStudyDocumentFormat(title: 'Lecture 02.pptx', mimeType: ''),
        StudyDocumentFormat.pptx,
      );
    });
  });

  testWidgets('PPTX current page exposes a real PNG capture', (tester) async {
    StudyPageSnapshot? page;
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StudyDocumentViewer(
            title: 'Lecture',
            bytes: _pptxBytes(),
            mimeType:
                'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            onPageChanged: (value) => page = value,
            bottomPanel: const SizedBox(height: 160),
            fallback: const Text('fallback'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(page, isNotNull);
    await tester.pump();
    final bytes = await tester.runAsync(page!.captureImage!.call);
    expect(bytes, isNotNull);
    expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });
}

Uint8List _pptxBytes() {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'ppt/presentation.xml',
        '''<p:presentation xmlns:p="p" xmlns:r="r"><p:sldIdLst><p:sldId r:id="rId1"/></p:sldIdLst><p:sldSz cx="1200" cy="675"/></p:presentation>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'ppt/_rels/presentation.xml.rels',
        '''<Relationships><Relationship Id="rId1" Target="slides/slide1.xml"/></Relationships>''',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'ppt/slides/slide1.xml',
        '''<p:sld xmlns:p="p" xmlns:a="a"><p:cSld><p:spTree><p:sp><p:spPr><a:xfrm><a:off x="80" y="90"/><a:ext cx="900" cy="240"/></a:xfrm></p:spPr><p:txBody><a:p><a:r><a:rPr sz="2400" b="1"/><a:t>Encapsulation</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>''',
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
