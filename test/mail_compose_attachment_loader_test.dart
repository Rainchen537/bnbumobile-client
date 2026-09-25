import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/mail_compose_attachment_loader.dart';

void main() {
  const maxBytes = 8;

  test('reads eager picker bytes', () async {
    final bytes = await readMailComposeAttachment(
      PlatformFile(
        name: 'eager.bin',
        size: 3,
        bytes: Uint8List.fromList([1, 2, 3]),
      ),
      maxBytes: maxBytes,
    );

    expect(bytes, [1, 2, 3]);
  });

  test('reads picker stream used by Android, macOS and Windows', () async {
    final bytes = await readMailComposeAttachment(
      PlatformFile(
        name: 'stream.bin',
        size: 4,
        readStream: Stream<List<int>>.fromIterable([
          [1, 2],
          [3, 4],
        ]),
      ),
      maxBytes: maxBytes,
    );

    expect(bytes, [1, 2, 3, 4]);
  });

  test(
    'falls back to a native file path when no bytes or stream exist',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'bnbu-mail-attachment-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/path.bin');
      await file.writeAsBytes([5, 6, 7]);

      final bytes = await readMailComposeAttachment(
        PlatformFile(name: 'path.bin', path: file.path, size: 3),
        maxBytes: maxBytes,
      );

      expect(bytes, [5, 6, 7]);
    },
  );

  test('stops a stream that exceeds the configured limit', () async {
    expect(
      () => readMailComposeAttachment(
        PlatformFile(
          name: 'large.bin',
          size: 0,
          readStream: Stream<List<int>>.value(List<int>.filled(9, 1)),
        ),
        maxBytes: maxBytes,
      ),
      throwsA(
        isA<MailComposeAttachmentReadException>().having(
          (error) => error.failure,
          'failure',
          MailComposeAttachmentReadFailure.tooLarge,
        ),
      ),
    );
  });

  test('reports empty and unavailable picker results separately', () async {
    expect(
      () => readMailComposeAttachment(
        PlatformFile(name: 'empty.bin', size: 0, bytes: Uint8List(0)),
        maxBytes: maxBytes,
      ),
      throwsA(
        isA<MailComposeAttachmentReadException>().having(
          (error) => error.failure,
          'failure',
          MailComposeAttachmentReadFailure.empty,
        ),
      ),
    );
    expect(
      () => readMailComposeAttachment(
        PlatformFile(name: 'missing.bin', size: 1),
        maxBytes: maxBytes,
      ),
      throwsA(
        isA<MailComposeAttachmentReadException>().having(
          (error) => error.failure,
          'failure',
          MailComposeAttachmentReadFailure.unavailable,
        ),
      ),
    );
  });
}
