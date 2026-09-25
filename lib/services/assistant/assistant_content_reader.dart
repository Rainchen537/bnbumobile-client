import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

class AssistantDocumentReader {
  const AssistantDocumentReader();
  Future<String> extract(String name, Uint8List bytes) async {
    final extension = name.split('.').last.toLowerCase();
    if (bytes.length > 64 * 1024 * 1024) {
      throw const FormatException('文件超过本机解析内存预算');
    }
    if (extension == 'pdf') {
      final document = await PdfDocument.openData(bytes, sourceName: name);
      try {
        final out = StringBuffer();
        for (final page in document.pages) {
          final content = await page.loadStructuredText();
          out.writeln(content.fullText);
        }
        final value = out.toString().trim();
        if (value.isEmpty) throw const FormatException('扫描PDF需要图像识别，当前未取得文字');
        return value;
      } finally {
        await document.dispose();
      }
    }
    if (const {'docx', 'pptx'}.contains(extension)) {
      final archive = ZipDecoder().decodeBytes(bytes);
      var expanded = 0;
      final out = StringBuffer();
      final files = archive.files.where((f) => f.isFile).toList()
        ..sort(
          (a, b) => a.name
              .replaceAllMapped(RegExp(r'\d+'), (m) => m[0]!.padLeft(12, '0'))
              .compareTo(
                b.name.replaceAllMapped(
                  RegExp(r'\d+'),
                  (m) => m[0]!.padLeft(12, '0'),
                ),
              ),
        );
      for (final file in files) {
        expanded += file.size;
        if (expanded > 128 * 1024 * 1024) {
          throw const FormatException('文档解压超过内存预算');
        }
        if (!RegExp(
          r'^(word/(document|footnotes|endnotes)|ppt/(slides/slide\d+|notesSlides/notesSlide\d+)|xl/(sharedStrings|worksheets/sheet\d+))\.xml$',
        ).hasMatch(file.name)) {
          continue;
        }
        final document = XmlDocument.parse(
          utf8.decode(file.content as List<int>),
        );
        for (final node in document.descendants.whereType<XmlElement>().where(
          (n) => n.name.local == 't' || n.name.local == 'v',
        )) {
          out.writeln(node.innerText);
        }
      }
      return out.toString();
    }
    if (const {
      'txt',
      'md',
      'csv',
      'json',
      'xml',
      'html',
      'htm',
    }.contains(extension)) {
      final text = utf8.decode(bytes);
      return const {'html', 'htm'}.contains(extension)
          ? html.parse(text).body?.text ?? ''
          : text;
    }
    throw const FormatException('该文件格式尚不能提取正文');
  }
}
