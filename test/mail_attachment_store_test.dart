import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/mail_attachment_store.dart';

void main() {
  test('publishes attachment bytes without leaving partial files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'ispace-attachment-store-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/report.pdf';
    const store = IoMailAttachmentStore();

    expect(await store.exists(path), isFalse);
    await store.publish(path: path, bytes: [1, 2, 3]);

    expect(await store.exists(path), isTrue);
    expect(await File(path).readAsBytes(), [1, 2, 3]);
    expect(
      await directory
          .list()
          .where((entity) => entity.path.endsWith('.partial'))
          .isEmpty,
      isTrue,
    );
  });
}
