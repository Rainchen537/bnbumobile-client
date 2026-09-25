import 'dart:convert';
import 'dart:typed_data';

import 'assistant_models.dart';

enum AssistantResourceKind {
  courseArchive('course_archive');

  const AssistantResourceKind(this.wireValue);

  final String wireValue;

  static AssistantResourceKind parse(Object? value) {
    return values.firstWhere(
      (candidate) => candidate.wireValue == value,
      orElse: () => throw const FormatException('不支持的小U资源类型。'),
    );
  }
}

class AssistantResourceItem {
  const AssistantResourceItem({
    required this.id,
    required this.fileName,
    required this.storedName,
    required this.filePath,
    required this.mimeType,
    required this.byteCount,
    required this.createdAt,
    required this.kind,
    required this.sourceTitle,
    required this.summary,
  });

  final String id;
  final String fileName;
  final String storedName;
  final String filePath;
  final String mimeType;
  final int byteCount;
  final DateTime createdAt;
  final AssistantResourceKind kind;
  final String sourceTitle;
  final String summary;

  Map<String, dynamic> toManifestJson() => {
    'id': id,
    'file_name': fileName,
    'stored_name': storedName,
    'mime_type': mimeType,
    'byte_count': byteCount,
    'created_at': createdAt.toUtc().toIso8601String(),
    'kind': kind.wireValue,
    'source_title': sourceTitle,
    'summary': summary,
  };

  factory AssistantResourceItem.fromManifestJson(
    Map<String, dynamic> json, {
    required String filePath,
  }) {
    final id = json['id'];
    final fileName = json['file_name'];
    final storedName = json['stored_name'];
    final mimeType = json['mime_type'];
    final byteCount = json['byte_count'];
    final createdAt = DateTime.tryParse(json['created_at'] as String? ?? '');
    final sourceTitle = json['source_title'];
    final summary = json['summary'];
    if (id is! String ||
        id.isEmpty ||
        fileName is! String ||
        fileName.isEmpty ||
        storedName is! String ||
        storedName.isEmpty ||
        mimeType is! String ||
        mimeType.isEmpty ||
        byteCount is! int ||
        byteCount <= 0 ||
        createdAt == null ||
        sourceTitle is! String ||
        summary is! String) {
      throw const FormatException('小U资源记录格式无效。');
    }
    return AssistantResourceItem(
      id: id,
      fileName: fileName,
      storedName: storedName,
      filePath: filePath,
      mimeType: mimeType,
      byteCount: byteCount,
      createdAt: createdAt.toLocal(),
      kind: AssistantResourceKind.parse(json['kind']),
      sourceTitle: sourceTitle,
      summary: summary,
    );
  }

  AssistantInputAttachment toReferenceAttachment() {
    final reference = [
      '这是用户从本机小U资源库主动添加的资源引用。',
      '资源名称：$fileName',
      '来源：$sourceTitle',
      '类型：${kind.wireValue}',
      '大小：$byteCount 字节',
      if (summary.trim().isNotEmpty) '说明：${summary.trim()}',
      '资源文件正文未上传；不要声称已经读取压缩包内部内容。',
    ].join('\n');
    return AssistantInputAttachment(
      name: fileName,
      mimeType: 'text/plain',
      bytes: Uint8List.fromList(utf8.encode(reference)),
      resourceId: id,
      resourceByteCount: byteCount,
    );
  }
}
