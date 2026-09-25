import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

import 'assistant_history_store.dart';

class StudyWindowManager {
  const StudyWindowManager._();

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows);

  static Future<void> open(AssistantStudyDocument document) async {
    if (!supported) return;
    for (final controller in await WindowController.getAll()) {
      if (!_isStudyWindow(controller)) continue;
      try {
        final contains = await controller.invokeMethod<bool>(
          'study.containsDocument',
          document.key,
        );
        if (contains == true) {
          await controller.invokeMethod<void>('study.focus');
          return;
        }
      } catch (_) {
        // A window can close while the native window list is being enumerated.
      }
    }
    await create([document]);
  }

  static Future<WindowController> create(
    List<AssistantStudyDocument> documents,
  ) async {
    final controller = await WindowController.create(
      WindowConfiguration(
        arguments: jsonEncode({
          'kind': 'study',
          'documents': documents.map((item) => item.toJson()).toList(),
        }),
      ),
    );
    await controller.show();
    return controller;
  }

  static bool _isStudyWindow(WindowController controller) {
    try {
      final decoded = jsonDecode(controller.arguments);
      return decoded is Map && decoded['kind'] == 'study';
    } catch (_) {
      return false;
    }
  }

  static List<AssistantStudyDocument>? decodeDocuments(String arguments) {
    try {
      final decoded = jsonDecode(arguments);
      if (decoded is! Map || decoded['kind'] != 'study') return null;
      final rawDocuments = decoded['documents'];
      if (rawDocuments is! List || rawDocuments.isEmpty) return null;
      return rawDocuments
          .map(
            (item) => AssistantStudyDocument.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }
}
