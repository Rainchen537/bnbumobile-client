import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/assistant_resource.dart';
import 'native_actions.dart';

abstract interface class AssistantResourceLibraryStore {
  Future<List<AssistantResourceItem>> load(String owner);

  Future<AssistantResourceItem> importFile(
    String owner, {
    required String sourcePath,
    required String fileName,
    required String mimeType,
    required AssistantResourceKind kind,
    required String sourceTitle,
    required String summary,
  });

  Future<void> delete(String owner, AssistantResourceItem item);
}

class FileSystemAssistantResourceLibraryStore
    implements AssistantResourceLibraryStore {
  FileSystemAssistantResourceLibraryStore({
    Future<Directory> Function()? documentsDirectoryLoader,
    Random? random,
  }) : _documentsDirectoryLoader =
           documentsDirectoryLoader ?? getApplicationDocumentsDirectory,
       _random = random ?? Random.secure();

  static const _manifestFileName = 'manifest.json';
  static const _maxResources = 100;
  static const _maxSingleResourceBytes = 512 * 1024 * 1024;
  static const _maxTotalResourceBytes = 2 * 1024 * 1024 * 1024;

  final Future<Directory> Function() _documentsDirectoryLoader;
  final Random _random;

  @override
  Future<List<AssistantResourceItem>> load(String owner) async {
    final root = await _ownerRoot(owner);
    final manifest = File('${root.path}/$_manifestFileName');
    if (!await manifest.exists()) {
      return const [];
    }
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['resources'] is! List) {
      throw const AssistantResourceLibraryException('小U资源库索引格式无效。');
    }
    final items = <AssistantResourceItem>[];
    for (final raw in (decoded['resources'] as List).take(_maxResources)) {
      if (raw is! Map) continue;
      final json = raw.map((key, value) => MapEntry(key.toString(), value));
      final storedName = json['stored_name'];
      if (storedName is! String || !_isSafeStoredName(storedName)) {
        continue;
      }
      final file = File('${root.path}/$storedName');
      if (!await file.exists()) {
        continue;
      }
      try {
        final item = AssistantResourceItem.fromManifestJson(
          json,
          filePath: file.path,
        );
        final actualBytes = await file.length();
        if (actualBytes != item.byteCount) {
          continue;
        }
        items.add(item);
      } on FormatException {
        continue;
      }
    }
    items.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return List.unmodifiable(items);
  }

  @override
  Future<AssistantResourceItem> importFile(
    String owner, {
    required String sourcePath,
    required String fileName,
    required String mimeType,
    required AssistantResourceKind kind,
    required String sourceTitle,
    required String summary,
  }) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw const AssistantResourceLibraryException('要保存的资源文件不存在。');
    }
    final byteCount = await source.length();
    if (byteCount <= 0 || byteCount > _maxSingleResourceBytes) {
      throw const AssistantResourceLibraryException('资源文件大小超出允许范围。');
    }
    final existing = await load(owner);
    if (existing.length >= _maxResources) {
      throw const AssistantResourceLibraryException(
        '小U资源库已达到 100 项，请先删除不再需要的资源。',
      );
    }
    final totalBytes = existing.fold<int>(
      byteCount,
      (total, item) => total + item.byteCount,
    );
    if (totalBytes > _maxTotalResourceBytes) {
      throw const AssistantResourceLibraryException(
        '小U资源库已达到 2 GB，请先删除不再需要的资源。',
      );
    }

    final root = await _ownerRoot(owner);
    await root.create(recursive: true);
    final safeName = safeAttachmentFileName(fileName);
    final id = _resourceId(owner, safeName);
    final storedName = '${id}_$safeName';
    final destination = File('${root.path}/$storedName');
    await source.copy(destination.path);

    final item = AssistantResourceItem(
      id: id,
      fileName: safeName,
      storedName: storedName,
      filePath: destination.path,
      mimeType: mimeType.trim().isEmpty
          ? 'application/octet-stream'
          : mimeType.trim().toLowerCase(),
      byteCount: byteCount,
      createdAt: DateTime.now(),
      kind: kind,
      sourceTitle: _boundedText(sourceTitle, 240),
      summary: _boundedText(summary, 2000),
    );
    try {
      await _writeManifest(root, [item, ...existing]);
    } catch (_) {
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
    return item;
  }

  @override
  Future<void> delete(String owner, AssistantResourceItem item) async {
    final root = await _ownerRoot(owner);
    final existing = await load(owner);
    final retained = existing
        .where((candidate) => candidate.id != item.id)
        .toList(growable: false);
    if (retained.length == existing.length) {
      return;
    }
    final file = File('${root.path}/${item.storedName}');
    if (await file.exists()) {
      await file.delete();
    }
    await _writeManifest(root, retained);
  }

  Future<Directory> _ownerRoot(String owner) async {
    final normalized = owner.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw const AssistantResourceLibraryException('当前登录账号不可用。');
    }
    final documents = await _documentsDirectoryLoader();
    final ownerDigest = sha256.convert(utf8.encode(normalized)).toString();
    return Directory(
      '${documents.path}/SmallU Resources/${ownerDigest.substring(0, 32)}',
    );
  }

  String _resourceId(String owner, String fileName) {
    final nonce = List<int>.generate(16, (_) => _random.nextInt(256));
    final material = [
      owner.trim().toLowerCase(),
      fileName,
      DateTime.now().microsecondsSinceEpoch.toString(),
      base64UrlEncode(nonce),
    ].join('\u0000');
    return sha256.convert(utf8.encode(material)).toString().substring(0, 24);
  }

  Future<void> _writeManifest(
    Directory root,
    List<AssistantResourceItem> items,
  ) async {
    await root.create(recursive: true);
    final manifest = File('${root.path}/$_manifestFileName');
    final temporary = File('${root.path}/$_manifestFileName.tmp');
    final encoded = jsonEncode({
      'version': 1,
      'resources': items
          .take(_maxResources)
          .map((item) => item.toManifestJson())
          .toList(growable: false),
    });
    await temporary.writeAsString(encoded, flush: true);
    await temporary.rename(manifest.path);
  }

  bool _isSafeStoredName(String value) {
    return value.isNotEmpty &&
        value == safeAttachmentFileName(value) &&
        !value.contains('/') &&
        !value.contains('\\');
  }

  String _boundedText(String value, int maxLength) {
    final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized.length <= maxLength
        ? normalized
        : normalized.substring(0, maxLength);
  }
}

class AssistantResourceLibraryException implements Exception {
  const AssistantResourceLibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}
