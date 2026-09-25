import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/campus_directory.dart';
import 'campus_directory_service.dart';

/// Public contact metadata only. Shared by startup, mail and teacher avatars.
class CampusContactIndex {
  CampusContactIndex({
    RemoteCampusDirectoryService? service,
    Future<Directory> Function()? directory,
    AssetBundle? bundle,
  }) : _service = service ?? RemoteCampusDirectoryService(),
       _directory = directory ?? getApplicationSupportDirectory,
       _bundle = bundle ?? rootBundle;

  static final shared = CampusContactIndex();
  final RemoteCampusDirectoryService _service;
  final Future<Directory> Function() _directory;
  final AssetBundle _bundle;
  List<CampusDirectoryOrganization> organizations = const [];
  List<OfficialTeacherProfile> teachers = const [];
  Future<void>? _local;
  Future<void>? _refresh;
  DateTime? _updatedAt;
  DateTime? _retryAt;

  Future<File> _file() async =>
      File('${(await _directory()).path}/public-contacts-v1.json');

  Future<void> loadLocal() => _local ??= _loadLocal();

  Future<void> _loadLocal() async {
    final raw =
        jsonDecode(
              await _bundle.loadString('assets/catalog/bnbu_directory.json'),
            )
            as Map;
    organizations = (raw['organizations'] as List)
        .map(
          (item) => CampusDirectoryOrganization.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
        )
        .toList();
    try {
      final file = await _file();
      if (await file.length() > 4 * 1024 * 1024) return;
      final cached = jsonDecode(await file.readAsString()) as Map;
      teachers = (cached['items'] as List)
          .map(
            (item) => OfficialTeacherProfile.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList();
      _updatedAt = DateTime.tryParse(cached['updated_at'] as String);
    } on Object {
      /* A public cache miss keeps the packaged contacts available. */
    }
  }

  Future<void> refresh({bool force = false}) => _refresh ??= _refreshOnce(
    force: force,
  ).whenComplete(() => _refresh = null);

  Future<void> _refreshOnce({bool force = false}) async {
    await loadLocal();
    // The public response cache handles its own freshness and failure retention.
    // Organizations must refresh even while the 24h lightweight index is fresh.
    organizations = await _service.loadOrganizations();
    final now = DateTime.now();
    if (!force &&
        _updatedAt != null &&
        now.difference(_updatedAt!) < const Duration(hours: 24)) {
      return;
    }
    if (_retryAt != null && now.isBefore(_retryAt!)) {
      throw const CampusDirectoryException('联系人目录暂时不可用，请稍后重试。');
    }
    try {
      final fresh = await _service.loadContactIndex();
      teachers = fresh;
      _updatedAt = now;
      _retryAt = null;
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        final pending = File('${file.path}.tmp');
        await pending.writeAsString(
          jsonEncode({
            'updated_at': now.toIso8601String(),
            'items': [
              for (final teacher in fresh)
                {
                  'name': teacher.name,
                  'name_en': teacher.nameEn,
                  'email': teacher.email,
                  'unit_names': teacher.unitNames,
                  'photo_url': teacher.photoUrl,
                },
            ],
          }),
          flush: true,
        );
        await pending.rename(file.path);
      } on Object {
        /* Disk failure must not discard a usable in-memory index. */
      }
    } on Object {
      _retryAt = now.add(const Duration(minutes: 1));
      rethrow;
    }
  }
}
