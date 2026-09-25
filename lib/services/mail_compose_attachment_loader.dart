import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

enum MailComposeAttachmentReadFailure { empty, tooLarge, unavailable }

class MailComposeAttachmentReadException implements Exception {
  const MailComposeAttachmentReadException(this.failure, this.fileName);

  final MailComposeAttachmentReadFailure failure;
  final String fileName;

  @override
  String toString() => '无法读取附件 $fileName：${failure.name}';
}

/// Reads a file-picker result without assuming that every platform eagerly
/// returns in-memory bytes. Android may expose a cached path, while macOS and
/// Windows commonly expose a stream or a path instead.
Future<Uint8List> readMailComposeAttachment(
  PlatformFile file, {
  required int maxBytes,
}) async {
  if (file.size > maxBytes) {
    throw MailComposeAttachmentReadException(
      MailComposeAttachmentReadFailure.tooLarge,
      file.name,
    );
  }

  final eagerBytes = file.bytes;
  if (eagerBytes != null) {
    return _validateMailComposeAttachmentBytes(
      eagerBytes,
      fileName: file.name,
      maxBytes: maxBytes,
    );
  }

  Stream<List<int>>? stream = file.readStream;
  if (stream == null && file.path?.trim().isNotEmpty == true) {
    try {
      stream = file.xFile.openRead();
    } on Object {
      stream = null;
    }
  }
  if (stream == null) {
    throw MailComposeAttachmentReadException(
      MailComposeAttachmentReadFailure.unavailable,
      file.name,
    );
  }

  final builder = BytesBuilder(copy: false);
  var received = 0;
  try {
    await for (final chunk in stream) {
      received += chunk.length;
      if (received > maxBytes) {
        throw MailComposeAttachmentReadException(
          MailComposeAttachmentReadFailure.tooLarge,
          file.name,
        );
      }
      builder.add(chunk);
    }
  } on MailComposeAttachmentReadException {
    rethrow;
  } on Object {
    throw MailComposeAttachmentReadException(
      MailComposeAttachmentReadFailure.unavailable,
      file.name,
    );
  }

  return _validateMailComposeAttachmentBytes(
    builder.takeBytes(),
    fileName: file.name,
    maxBytes: maxBytes,
  );
}

Uint8List _validateMailComposeAttachmentBytes(
  Uint8List bytes, {
  required String fileName,
  required int maxBytes,
}) {
  if (bytes.isEmpty) {
    throw MailComposeAttachmentReadException(
      MailComposeAttachmentReadFailure.empty,
      fileName,
    );
  }
  if (bytes.length > maxBytes) {
    throw MailComposeAttachmentReadException(
      MailComposeAttachmentReadFailure.tooLarge,
      fileName,
    );
  }
  return bytes;
}
