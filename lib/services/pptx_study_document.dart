import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

class PptxStudyDocument {
  const PptxStudyDocument({required this.size, required this.pages});

  final Size size;
  final List<PptxStudyPage> pages;

  static PptxStudyDocument parse(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      files[file.name] = file.content;
    }
    final presentation = _xml(files, 'ppt/presentation.xml');
    final sizeNode = presentation.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'sldSz')
        .firstOrNull;
    final width = _number(sizeNode, 'cx', fallback: 12192000);
    final height = _number(sizeNode, 'cy', fallback: 6858000);
    final presentationRels = _relationships(
      files,
      'ppt/_rels/presentation.xml.rels',
      ownerPath: 'ppt/presentation.xml',
    );
    final slideIds = presentation.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'sldId')
        .toList(growable: false);
    final pages = <PptxStudyPage>[];
    for (final slideId in slideIds) {
      final relationId = _attribute(slideId, 'id', prefix: 'r');
      final path = presentationRels[relationId];
      if (path == null || !files.containsKey(path)) continue;
      pages.add(_parseSlide(files, path, width, height));
    }
    if (pages.isEmpty) {
      throw const FormatException('PPTX 中没有可读取的幻灯片');
    }
    return PptxStudyDocument(
      size: Size(width, height),
      pages: List.unmodifiable(pages),
    );
  }

  static PptxStudyPage _parseSlide(
    Map<String, Uint8List> files,
    String path,
    double documentWidth,
    double documentHeight,
  ) {
    final slide = _xml(files, path);
    final relName = '${_directory(path)}/_rels/${_basename(path)}.rels';
    final relationships = _relationships(files, relName, ownerPath: path);
    final elements = <PptxStudyElement>[];
    final textBlocks = <String>[];

    for (final shape in slide.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 'sp',
    )) {
      final text = shape.descendants
          .whereType<XmlElement>()
          .where((node) => node.name.local == 't')
          .map((node) => node.innerText.trim())
          .where((value) => value.isNotEmpty)
          .join('\n');
      if (text.isEmpty) continue;
      textBlocks.add(text);
      elements.add(
        PptxStudyElement(
          rect: _rect(shape, documentWidth, documentHeight),
          text: text,
          fontSize: _fontSize(shape),
          foreground: _color(shape) ?? const Color(0xFF171715),
          fill: _fillColor(shape),
          bold: shape.descendants.whereType<XmlElement>().any(
            (node) =>
                (node.name.local == 'rPr' || node.name.local == 'defRPr') &&
                _attribute(node, 'b') == '1',
          ),
        ),
      );
    }

    for (final picture in slide.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 'pic',
    )) {
      final blip = picture.descendants
          .whereType<XmlElement>()
          .where((node) => node.name.local == 'blip')
          .firstOrNull;
      final relationId = blip == null
          ? null
          : _attribute(blip, 'embed', prefix: 'r');
      final imagePath = relationships[relationId];
      final image = imagePath == null ? null : files[imagePath];
      if (image == null) continue;
      elements.add(
        PptxStudyElement(
          rect: _rect(picture, documentWidth, documentHeight),
          image: image,
        ),
      );
    }

    // 表格和 SmartArt 的文字也纳入本页语义，即使当前轻量渲染器无法完全还原样式。
    for (final frame in slide.descendants.whereType<XmlElement>().where(
      (node) => node.name.local == 'graphicFrame',
    )) {
      final text = frame.descendants
          .whereType<XmlElement>()
          .where((node) => node.name.local == 't')
          .map((node) => node.innerText.trim())
          .where((value) => value.isNotEmpty)
          .join('  ');
      if (text.isEmpty) continue;
      textBlocks.add(text);
      elements.add(
        PptxStudyElement(
          rect: _rect(frame, documentWidth, documentHeight),
          text: text,
          fontSize: 18,
          foreground: const Color(0xFF171715),
          fill: const Color(0xFFF4F4F1),
        ),
      );
    }

    elements.sort((left, right) {
      if (left.image != null && right.image == null) return -1;
      if (left.image == null && right.image != null) return 1;
      return 0;
    });
    return PptxStudyPage(
      text: textBlocks.join('\n\n'),
      elements: List.unmodifiable(elements),
    );
  }

  static XmlDocument _xml(Map<String, Uint8List> files, String path) {
    final bytes = files[path];
    if (bytes == null) throw FormatException('PPTX 缺少 $path');
    return XmlDocument.parse(utf8.decode(bytes));
  }

  static Map<String, String> _relationships(
    Map<String, Uint8List> files,
    String relPath, {
    required String ownerPath,
  }) {
    final bytes = files[relPath];
    if (bytes == null) return const {};
    final document = XmlDocument.parse(utf8.decode(bytes));
    return {
      for (final node in document.descendants.whereType<XmlElement>().where(
        (node) => node.name.local == 'Relationship',
      ))
        if ((_attribute(node, 'TargetMode') ?? '').toLowerCase() != 'external')
          _attribute(node, 'Id') ?? '': _resolvePath(
            ownerPath,
            _attribute(node, 'Target') ?? '',
          ),
    }..remove('');
  }

  static Rect _rect(XmlElement node, double width, double height) {
    final transform = node.descendants
        .whereType<XmlElement>()
        .where((item) => item.name.local == 'xfrm')
        .firstOrNull;
    final offset = transform?.children
        .whereType<XmlElement>()
        .where((item) => item.name.local == 'off')
        .firstOrNull;
    final extent = transform?.children
        .whereType<XmlElement>()
        .where((item) => item.name.local == 'ext')
        .firstOrNull;
    final x = _number(offset, 'x') / width;
    final y = _number(offset, 'y') / height;
    final w = _number(extent, 'cx', fallback: width * .4) / width;
    final h = _number(extent, 'cy', fallback: height * .15) / height;
    return Rect.fromLTWH(
      x.clamp(0, 1),
      y.clamp(0, 1),
      w.clamp(.01, 1),
      h.clamp(.01, 1),
    );
  }

  static double _fontSize(XmlElement shape) {
    for (final node in shape.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'rPr' && node.name.local != 'defRPr') continue;
      final size = double.tryParse(_attribute(node, 'sz') ?? '');
      if (size != null) return (size / 100).clamp(8, 48);
    }
    return 20;
  }

  static Color? _fillColor(XmlElement shape) {
    final fill = shape.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'solidFill')
        .firstOrNull;
    return fill == null ? null : _color(fill);
  }

  static Color? _color(XmlElement node) {
    final value = node.descendants
        .whereType<XmlElement>()
        .where((item) => item.name.local == 'srgbClr')
        .map((item) => _attribute(item, 'val'))
        .whereType<String>()
        .firstOrNull;
    if (value == null || value.length != 6) return null;
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? null : Color(0xFF000000 | parsed);
  }

  static double _number(XmlElement? node, String name, {double fallback = 0}) =>
      double.tryParse(_attribute(node, name) ?? '') ?? fallback;

  static String? _attribute(XmlElement? node, String local, {String? prefix}) {
    if (node == null) return null;
    for (final attribute in node.attributes) {
      if (attribute.name.local == local &&
          (prefix == null || attribute.name.prefix == prefix)) {
        return attribute.value;
      }
    }
    return null;
  }

  static String _resolvePath(String owner, String target) {
    if (target.startsWith('/')) return target.substring(1);
    final segments = <String>[
      ..._directory(owner).split('/'),
      ...target.split('/'),
    ];
    final normalized = <String>[];
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (normalized.isNotEmpty) normalized.removeLast();
      } else {
        normalized.add(segment);
      }
    }
    return normalized.join('/');
  }

  static String _directory(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  static String _basename(String path) {
    final index = path.lastIndexOf('/');
    return index < 0 ? path : path.substring(index + 1);
  }
}

class PptxStudyPage {
  const PptxStudyPage({required this.text, required this.elements});

  final String text;
  final List<PptxStudyElement> elements;
}

class PptxStudyElement {
  const PptxStudyElement({
    required this.rect,
    this.text,
    this.image,
    this.fontSize = 20,
    this.foreground = const Color(0xFF171715),
    this.fill,
    this.bold = false,
  });

  final Rect rect;
  final String? text;
  final Uint8List? image;
  final double fontSize;
  final Color foreground;
  final Color? fill;
  final bool bold;
}
