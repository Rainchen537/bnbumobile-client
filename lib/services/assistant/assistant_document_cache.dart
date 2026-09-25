import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'assistant_content_reader.dart';

/// Public document text only. Private account content keeps its own scoped reader.
class AssistantDocumentTextCache {
  AssistantDocumentTextCache({
    Future<String> Function(String, Uint8List)? extract,
  }) : _extract = extract ?? const AssistantDocumentReader().extract;
  final Future<String> Function(String, Uint8List) _extract;
  final _texts = <String, String>{};
  final _loading = <String, Future<String>>{};
  static const maxCharacters = 2 * 1024 * 1024;

  Future<String> read(String name, Uint8List bytes) {
    final key =
        '${name.split('.').last.toLowerCase()}:${sha256.convert(bytes)}';
    final cached = _texts.remove(key);
    if (cached != null) {
      _texts[key] = cached;
      return Future.value(cached);
    }
    return _loading[key] ??= _extract(name, bytes)
        .then((text) {
          if (text.length <= maxCharacters) {
            while (_texts.isNotEmpty &&
                (_texts.length >= 4 ||
                    _texts.values.fold(0, (n, value) => n + value.length) +
                            text.length >
                        maxCharacters)) {
              _texts.remove(_texts.keys.first);
            }
            _texts[key] = text;
          }
          return text;
        })
        .whenComplete(() {
          _loading.remove(key);
        });
  }
}
