import 'dart:typed_data';

class UploadFilePayload {
  UploadFilePayload({required this.fileName, this.filePath, this.bytes});

  final String fileName;
  final String? filePath;
  final Uint8List? bytes;

  bool get hasUsableContent =>
      (filePath != null && filePath!.trim().isNotEmpty) ||
      (bytes != null && bytes!.isNotEmpty);
}
