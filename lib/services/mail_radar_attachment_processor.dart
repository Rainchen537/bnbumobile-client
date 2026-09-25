import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as image;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import '../models/assistant_models.dart';
import '../models/mail_models.dart';
import 'ai_assistant_service.dart';
import 'mail_service.dart';

class MailRadarPreparedAttachment {
  const MailRadarPreparedAttachment({
    required this.name,
    this.text = '',
    this.visuals = const [],
    this.note = '',
    this.sourceComplete = true,
  });

  final String name;
  final String text;
  final List<AssistantInputAttachment> visuals;
  final String note;
  final bool sourceComplete;

  bool get hasAnalyzableContent => text.trim().isNotEmpty || visuals.isNotEmpty;
}

class MailRadarAttachmentProcessor {
  const MailRadarAttachmentProcessor({this.includeVisuals = true});

  /// Lightweight inbox classification only needs bounded extracted text.
  /// Legacy analysis can still explicitly retain PDF/Office page images.
  final bool includeVisuals;

  static const int sourceLimit = 20 * 1024 * 1024;
  static const int _textLimit = 120000;
  static const int _modelImageLimit = 2 * 1024 * 1024;

  static const _safeExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'pdf',
    'docx',
    'pptx',
    'xlsx',
    'txt',
    'md',
    'csv',
  };

  Future<MailRadarPreparedAttachment> prepare({
    required MailAccessCredentials credentials,
    required MailMessageDetail message,
    required MailAttachment attachment,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    _requireActive(isOperationActive);
    final extension = _extension(attachment.name);
    if (!_safeExtensions.contains(extension)) {
      return MailRadarPreparedAttachment(
        name: attachment.name,
        note: '已跳过不安全或未知格式',
      );
    }
    if (attachment.size > sourceLimit) {
      return MailRadarPreparedAttachment(
        name: attachment.name,
        note: '已跳过超过 20 MB 的附件',
      );
    }
    final partId = attachment.partId?.trim() ?? '';
    if (partId.isEmpty) {
      return MailRadarPreparedAttachment(
        name: attachment.name,
        note: '附件缺少可读取标识',
      );
    }
    final bytes = Uint8List.fromList(
      await mailService.downloadAttachment(
        credentials: credentials,
        folder: message.folder,
        uid: message.uid,
        partId: partId,
        expectedMailboxUidValidity: message.mailboxUidValidity,
      ),
    );
    _requireActive(isOperationActive);
    if (bytes.isEmpty) {
      return MailRadarPreparedAttachment(name: attachment.name, note: '附件内容为空');
    }
    if (bytes.length > sourceLimit) {
      return MailRadarPreparedAttachment(
        name: attachment.name,
        note: '已跳过超过 20 MB 的附件',
      );
    }

    final prepared = extension == 'pdf'
        ? await _prepare(attachment.name, extension, bytes)
        : await compute(_prepareRadarAttachmentOffThread, (
            name: attachment.name,
            extension: extension,
            bytes: bytes,
            includeVisuals: includeVisuals,
          ));
    _requireActive(isOperationActive);
    if (prepared.attachments.isEmpty && prepared.text.trim().isEmpty) {
      return MailRadarPreparedAttachment(
        name: attachment.name,
        note: '未提取到可分析内容',
      );
    }
    return MailRadarPreparedAttachment(
      name: attachment.name,
      text: prepared.text,
      visuals: prepared.attachments,
      sourceComplete:
          {'txt', 'md', 'csv'}.contains(extension) &&
          prepared.text.length < _textLimit,
    );
  }

  void _requireActive(bool Function()? isOperationActive) {
    if (isOperationActive?.call() == false) {
      throw const AiAssistantOperationCancelledException();
    }
  }

  Future<({String text, List<AssistantInputAttachment> attachments})> _prepare(
    String name,
    String extension,
    Uint8List bytes,
  ) async {
    if ({'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(extension)) {
      if (!includeVisuals) {
        return (text: '', attachments: <AssistantInputAttachment>[]);
      }
      final prepared = _prepareImage(name, bytes);
      return (
        text: '',
        attachments: prepared == null
            ? <AssistantInputAttachment>[]
            : <AssistantInputAttachment>[prepared],
      );
    }
    if (extension == 'pdf') return _preparePdf(name, bytes);
    if ({'docx', 'pptx', 'xlsx'}.contains(extension)) {
      return _prepareOffice(name, bytes);
    }
    return (
      text: _limit(utf8.decode(bytes, allowMalformed: true), _textLimit),
      attachments: <AssistantInputAttachment>[],
    );
  }

  Future<({String text, List<AssistantInputAttachment> attachments})>
  _preparePdf(String name, Uint8List bytes) async {
    final document = await PdfDocument.openData(bytes, sourceName: name);
    try {
      final text = StringBuffer();
      final visualPages = includeVisuals
          ? _representativeIndices(document.pages.length, 3)
          : const <int>{};
      final visuals = <AssistantInputAttachment>[];
      for (var index = 0; index < document.pages.length; index++) {
        if (!includeVisuals && text.length >= _textLimit) break;
        if (text.length < _textLimit) {
          final pageText = await document.pages[index].loadStructuredText();
          if (pageText.fullText.trim().isNotEmpty) {
            text.writeln('第 ${index + 1} 页：${pageText.fullText}');
          }
        }
        if (visualPages.contains(index)) {
          final page = document.pages[index];
          final scale = 1400 / page.width;
          final rendered = await page.render(
            fullWidth: 1400,
            fullHeight: page.height * scale,
          );
          if (rendered != null) {
            final decoded = image.Image.fromBytes(
              width: rendered.width,
              height: rendered.height,
              bytes: rendered.pixels.buffer,
              order: image.ChannelOrder.bgra,
            );
            rendered.dispose();
            final prepared = _prepareDecodedImage(
              '${name}_page_${index + 1}.jpg',
              decoded,
            );
            if (prepared != null) visuals.add(prepared);
          }
        }
      }
      return (text: _limit(text.toString(), _textLimit), attachments: visuals);
    } finally {
      await document.dispose();
    }
  }

  ({String text, List<AssistantInputAttachment> attachments}) _prepareOffice(
    String name,
    Uint8List bytes,
  ) {
    final archive = ZipDecoder().decodeBytes(bytes);
    var expandedBytes = 0;
    final text = StringBuffer();
    final images = <AssistantInputAttachment>[];
    for (final file in archive.files) {
      if (!file.isFile) continue;
      expandedBytes += file.size;
      if (expandedBytes > 80 * 1024 * 1024) {
        throw const FormatException('Office 附件解压后体积异常');
      }
      final path = file.name.toLowerCase();
      final content = Uint8List.fromList(file.content as List<int>);
      if (path.endsWith('.xml') && text.length < _textLimit) {
        try {
          final document = XmlDocument.parse(utf8.decode(content));
          final values = document.descendants
              .whereType<XmlElement>()
              .where((node) => const {'t', 'v'}.contains(node.name.local))
              .map((node) => node.innerText.trim())
              .where((value) => value.isNotEmpty);
          for (final value in values) {
            text.writeln(value);
            if (text.length >= _textLimit) break;
          }
        } catch (_) {
          // Ignore malformed auxiliary XML and continue with remaining parts.
        }
      }
      if (includeVisuals &&
          images.length < 3 &&
          RegExp(r'\.(png|jpe?g|webp|gif)$').hasMatch(path)) {
        final prepared = _prepareImage('${name}_${_basename(path)}', content);
        if (prepared != null) images.add(prepared);
      }
    }
    return (text: _limit(text.toString(), _textLimit), attachments: images);
  }

  AssistantInputAttachment? _prepareImage(String name, Uint8List bytes) {
    try {
      final decoded = image.decodeImage(bytes);
      return decoded == null ? null : _prepareDecodedImage(name, decoded);
    } catch (_) {
      return null;
    }
  }

  AssistantInputAttachment? _prepareDecodedImage(
    String name,
    image.Image value,
  ) {
    var prepared = image.bakeOrientation(value);
    final longest = prepared.width > prepared.height
        ? prepared.width
        : prepared.height;
    if (longest > 1800) {
      final ratio = 1800 / longest;
      prepared = image.copyResize(
        prepared,
        width: (prepared.width * ratio).round(),
        height: (prepared.height * ratio).round(),
      );
    }
    for (final quality in const [88, 78, 68, 56]) {
      final encoded = Uint8List.fromList(
        image.encodeJpg(prepared, quality: quality),
      );
      if (encoded.isNotEmpty && encoded.length <= _modelImageLimit) {
        return AssistantInputAttachment(
          name: name.replaceAll(RegExp(r'\.[^.]+$'), '.jpg'),
          mimeType: 'image/jpeg',
          bytes: encoded,
        );
      }
    }
    return null;
  }

  Set<int> _representativeIndices(int count, int limit) {
    if (count <= 0) return const {};
    if (count <= limit) return {for (var i = 0; i < count; i++) i};
    return {0, count ~/ 2, count - 1};
  }

  String _extension(String name) {
    final index = name.lastIndexOf('.');
    return index < 0 ? '' : name.substring(index + 1).toLowerCase();
  }

  String _basename(String path) => path.split('/').last;

  String _limit(String value, int length) =>
      value.length <= length ? value : value.substring(0, length);
}

Future<({String text, List<AssistantInputAttachment> attachments})>
_prepareRadarAttachmentOffThread(
  ({String name, String extension, Uint8List bytes, bool includeVisuals}) input,
) => MailRadarAttachmentProcessor(
  includeVisuals: input.includeVisuals,
)._prepare(input.name, input.extension, input.bytes);
