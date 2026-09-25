import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_content_page.dart';
import 'package:bnbu_me/services/assistant/assistant_content_reader.dart';

void main() {
  test(
    'UTF-8 paging preserves every character including supplementary Unicode',
    () {
      final original = '内容😀' * 15000;
      var offset = 0;
      final out = StringBuffer();
      while (true) {
        final page = AssistantContentPage.slice(original, offset);
        expect(utf8.encode(page.text).length, lessThanOrEqualTo(16000));
        out.write(page.text);
        if (page.nextOffset == null) break;
        expect(page.nextOffset!, greaterThan(offset));
        offset = page.nextOffset!;
      }
      expect(out.toString(), original);
    },
  );
  test(
    'Office extraction reads the tail rather than a fixed text prefix',
    () async {
      final original = 'Long requirement ' * 12000 + 'Unique final instruction';
      final bytes = utf8.encode(
        '<w:document xmlns:w="urn:test"><w:p><w:r><w:t>$original</w:t></w:r></w:p></w:document>',
      );
      final archive = Archive()
        ..addFile(ArchiveFile('word/document.xml', bytes.length, bytes));
      final zipped = Uint8List.fromList(ZipEncoder().encode(archive));
      final text = await const AssistantDocumentReader().extract(
        'assignment.docx',
        zipped,
      );
      expect(text, contains('Unique final instruction'));
    },
  );
  test('binary unknown formats are explicitly rejected', () async {
    await expectLater(
      const AssistantDocumentReader().extract('scan.png', Uint8List(4)),
      throwsFormatException,
    );
  });
}
