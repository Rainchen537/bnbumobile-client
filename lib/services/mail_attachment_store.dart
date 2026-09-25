import 'dart:io';
import 'dart:math';

abstract class MailAttachmentStore {
  const MailAttachmentStore();

  Future<bool> exists(String path);

  Future<void> publish({required String path, required List<int> bytes});
}

class IoMailAttachmentStore implements MailAttachmentStore {
  const IoMailAttachmentStore();

  @override
  Future<bool> exists(String path) => File(path).exists();

  @override
  Future<void> publish({required String path, required List<int> bytes}) async {
    final file = File(path);
    final temporaryFile = File(
      '${file.parent.path}/.${DateTime.now().microsecondsSinceEpoch}.'
      '${Random.secure().nextInt(1 << 32)}.partial',
    );

    try {
      await temporaryFile.writeAsBytes(bytes, flush: true);
      try {
        await temporaryFile.rename(file.path);
      } on FileSystemException {
        if (!await file.exists()) rethrow;
      }
    } finally {
      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }
}
