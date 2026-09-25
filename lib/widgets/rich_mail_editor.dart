import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../l10n/bnbu_localizations.dart';

bool _editorLicensesRegistered = false;

void registerMailEditorLicenses() {
  if (_editorLicensesRegistered) return;
  _editorLicensesRegistered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Local mail editor / Tiptap / ProseMirror',
    ], await rootBundle.loadString('assets/mail_editor/LICENSES.txt'));
  });
}

/// A Tiptap document exported in the two representations the mail transport
/// needs. HTML is the durable IMAP-draft representation; JSON is retained in
/// memory so the editing surface never falls back to text-prefix formatting.
@immutable
class RichMailDocument {
  const RichMailDocument({
    required this.html,
    required this.json,
    required this.text,
  });

  const RichMailDocument.empty()
    : html = '',
      json = const <String, Object?>{'type': 'doc', 'content': <Object?>[]},
      text = '';

  factory RichMailDocument.fromPlainText(String value) {
    final text = value.trimRight();
    if (text.isEmpty) return const RichMailDocument.empty();
    final html = text
        .split(RegExp(r'\r?\n'))
        .map((line) => '<p>${_escapeHtml(line)}</p>')
        .join();
    return RichMailDocument(
      html: html,
      json: <String, Object?>{'type': 'doc'},
      text: text,
    );
  }

  factory RichMailDocument.fromHtml(String html, {String fallbackText = ''}) {
    if (html.trim().isEmpty) {
      return RichMailDocument.fromPlainText(fallbackText);
    }
    return RichMailDocument(
      html: html,
      json: const <String, Object?>{'type': 'doc'},
      text: fallbackText,
    );
  }

  final String html;
  final Map<String, Object?> json;
  final String text;

  bool get isEmpty => text.trim().isEmpty && html.trim().isEmpty;

  static String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

@immutable
class RichMailToolbarState {
  const RichMailToolbarState({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.table = false,
    this.bulletList = false,
    this.orderedList = false,
    this.blockquote = false,
    this.alignment = 'left',
    this.fontFamily,
    this.fontSize,
    this.color,
    this.lineHeight,
  });

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool table;
  final bool bulletList;
  final bool orderedList;
  final bool blockquote;
  final String alignment;
  final String? fontFamily;
  final String? fontSize;
  final String? color;
  final String? lineHeight;

  factory RichMailToolbarState.fromJavaScript(Map<Object?, Object?> raw) =>
      RichMailToolbarState(
        bold: raw['bold'] == true,
        italic: raw['italic'] == true,
        underline: raw['underline'] == true,
        strike: raw['strike'] == true,
        table: raw['table'] == true,
        bulletList: raw['bulletList'] == true,
        orderedList: raw['orderedList'] == true,
        blockquote: raw['blockquote'] == true,
        alignment: raw['alignment'] is String
            ? raw['alignment'] as String
            : 'left',
        fontFamily: raw['fontFamily'] as String?,
        fontSize: raw['fontSize'] as String?,
        color: raw['color'] as String?,
        lineHeight: raw['lineHeight'] as String?,
      );
}

/// Controller for the isolated, local-only rich mail WebView.
///
/// It intentionally exposes commands rather than WebView evaluation to the
/// composing page. This keeps editor JavaScript in the bundled asset and
/// prevents mail content or an external URL from becoming executable input.
class RichMailEditorController extends ChangeNotifier {
  RichMailEditorController({RichMailDocument? initialDocument})
    : _document = initialDocument ?? const RichMailDocument.empty();

  RichMailDocument _document;
  RichMailToolbarState _toolbarState = const RichMailToolbarState();
  InAppWebViewController? _webView;
  bool _ready = false;
  bool _disposed = false;

  RichMailDocument get document => _document;
  RichMailToolbarState get toolbarState => _toolbarState;
  bool get isReady => _ready;

  Future<void> execute(String name, [Object? value]) async {
    final controller = _webView;
    if (controller == null || !_ready) return;
    final source =
        'window.bnbuMailEditorCommand(${jsonEncode(<String, Object?>{'name': name, if (value != null) 'value': value})});';
    await controller.evaluateJavascript(source: source);
  }

  Future<void> setDocument(RichMailDocument document) async {
    _document = document;
    if (!_disposed) notifyListeners();
    await execute('setContent', document.html);
  }

  /// Reads the editor synchronously before a user-visible boundary such as
  /// save, send, close or the 小U draft handoff. The onUpdate bridge remains
  /// debounced for normal typing, but it must never be the only source of the
  /// final document.
  Future<RichMailDocument> snapshot() async {
    final controller = _webView;
    if (controller == null || !_ready) return _document;
    try {
      final raw = await controller.evaluateJavascript(
        source: 'window.bnbuMailEditorCommand({name:"snapshot"});',
      );
      final document = _documentFromJavaScript(raw);
      if (document != null) {
        _update(document);
        _updateToolbarState(_toolbarStateFromJavaScript(raw));
        return document;
      }
    } on Object {
      // A WebView that is being removed can reject evaluation. The last
      // bridged document remains the safe fallback for this closing surface.
    }
    return _document;
  }

  Future<void> addInlineImage(Uint8List bytes, {required String mimeType}) {
    if (bytes.length > 2 * 1024 * 1024) {
      throw ArgumentError.value(bytes.length, 'bytes', '内嵌图片不能超过 2 MB');
    }
    final normalizedMime = switch (mimeType.toLowerCase()) {
      'image/jpeg' || 'image/jpg' => 'image/jpeg',
      'image/png' => 'image/png',
      'image/gif' => 'image/gif',
      'image/webp' => 'image/webp',
      _ => throw ArgumentError.value(mimeType, 'mimeType', '不支持的内嵌图片格式'),
    };
    return execute(
      'addImage',
      'data:$normalizedMime;base64,${base64Encode(bytes)}',
    );
  }

  void _attach(InAppWebViewController controller) {
    _webView = controller;
  }

  Future<void> _markReady() async {
    _ready = true;
    if (!_disposed) notifyListeners();
    await execute('setContent', _document.html);
  }

  void _update(RichMailDocument document) {
    _document = document;
    if (!_disposed) notifyListeners();
  }

  void _updateToolbarState(RichMailToolbarState? state) {
    if (state == null || state == _toolbarState) return;
    _toolbarState = state;
    if (!_disposed) notifyListeners();
  }

  void _detach(InAppWebViewController controller) {
    if (identical(_webView, controller)) {
      _webView = null;
      _ready = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _webView = null;
    super.dispose();
  }
}

RichMailDocument? _documentFromJavaScript(Object? raw) {
  Object? value = raw;
  for (var depth = 0; depth < 2 && value is String; depth++) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      break;
    }
  }
  if (value is! Map) return null;
  final map = Map<Object?, Object?>.from(value);
  final html = map['html'];
  final text = map['text'];
  final json = map['json'];
  if (html is! String || text is! String || json is! Map) return null;
  return RichMailDocument(
    html: html,
    text: text,
    json: Map<String, Object?>.from(json),
  );
}

RichMailToolbarState? _toolbarStateFromJavaScript(Object? raw) {
  Object? value = raw;
  for (var depth = 0; depth < 2 && value is String; depth++) {
    try {
      value = jsonDecode(value);
    } on FormatException {
      break;
    }
  }
  if (value is! Map) return null;
  final state = Map<Object?, Object?>.from(value)['state'];
  if (state is! Map) return null;
  return RichMailToolbarState.fromJavaScript(Map<Object?, Object?>.from(state));
}

/// Real editable mail body. It runs only the bundled Tiptap asset in a fresh
/// WebView profile. This component is distinct from untrusted incoming-mail
/// rendering, where JavaScript remains disabled.
class RichMailEditor extends StatefulWidget {
  const RichMailEditor({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onPickImage,
    this.autofocus = false,
  });

  static const assetHtml = 'assets/mail_editor/index.html';

  final RichMailEditorController controller;
  final ValueChanged<RichMailDocument> onChanged;
  final Future<Uint8List?> Function()? onPickImage;
  final bool autofocus;

  @override
  State<RichMailEditor> createState() => _RichMailEditorState();
}

class _RichMailEditorState extends State<RichMailEditor> {
  InAppWebViewController? _webView;
  bool _pickingImage = false;
  Brightness? _brightness;

  String get _editorTheme => _brightness == Brightness.dark ? 'dark' : 'light';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (_brightness == brightness) return;
    _brightness = brightness;
    unawaited(_syncTheme());
  }

  Future<void> _syncTheme() async {
    try {
      await widget.controller.execute('setTheme', _editorTheme);
    } on Object {
      // A closing platform view may reject evaluation. A new view receives
      // the current App appearance again before its editor is initialized.
    }
  }

  @override
  void dispose() {
    final controller = _webView;
    if (controller != null) widget.controller._detach(controller);
    super.dispose();
  }

  Future<dynamic> _handleEditorEvent(List<dynamic> arguments) async {
    if (arguments.isEmpty || arguments.first is! Map) return null;
    final raw = Map<Object?, Object?>.from(arguments.first as Map);
    final event = raw['type'];
    final rawState = raw['state'];
    if (rawState is Map) {
      widget.controller._updateToolbarState(
        RichMailToolbarState.fromJavaScript(
          Map<Object?, Object?>.from(rawState),
        ),
      );
    }
    if (event == 'editorReady') {
      await widget.controller._markReady();
      await _syncTheme();
      if (widget.autofocus) {
        await widget.controller.execute('focus');
      }
      return null;
    }
    if (event == 'requestImage') {
      await _pickInlineImage();
      return null;
    }
    if (event == 'selectionChanged') return null;
    if (event != 'documentChanged') return null;
    final html = raw['html'];
    final text = raw['text'];
    final json = raw['json'];
    if (html is! String || text is! String || json is! Map) return null;
    final document = RichMailDocument(
      html: html,
      text: text,
      json: Map<String, Object?>.from(json),
    );
    widget.controller._update(document);
    widget.onChanged(document);
    return null;
  }

  Future<void> _pickInlineImage() async {
    if (_pickingImage || widget.onPickImage == null) return;
    _pickingImage = true;
    try {
      final bytes = await widget.onPickImage!();
      if (bytes == null || bytes.isEmpty) return;
      final mimeType = _inferImageMimeType(bytes);
      if (mimeType == null || !mounted) return;
      await widget.controller.addInlineImage(bytes, mimeType: mimeType);
    } finally {
      _pickingImage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Widget tests do not register a native WebView implementation. The
    // fallback keeps compose, recipient and draft tests deterministic while
    // production devices always take the isolated editor branch below.
    if (InAppWebViewPlatform.instance == null) {
      return _RichMailEditorFallback(
        controller: widget.controller,
        onChanged: widget.onChanged,
        autofocus: widget.autofocus,
      );
    }
    return Semantics(
      textField: true,
      label: context.l10n.text('邮件正文'),
      child: InAppWebView(
        key: const ValueKey('compose-rich-mail-editor'),
        initialFile: RichMailEditor.assetHtml,
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source:
                'window.bnbuMailEditorTheme = ${jsonEncode(_editorTheme)};'
                'if (document.documentElement) {'
                'document.documentElement.dataset.theme = window.bnbuMailEditorTheme;'
                '}',
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ]),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          javaScriptCanOpenWindowsAutomatically: false,
          thirdPartyCookiesEnabled: false,
          sharedCookiesEnabled: false,
          incognito: true,
          domStorageEnabled: false,
          databaseEnabled: false,
          cacheEnabled: false,
          blockNetworkLoads: true,
          allowContentAccess: false,
          allowFileAccess: true,
          allowFileAccessFromFileURLs: false,
          allowUniversalAccessFromFileURLs: false,
          useShouldOverrideUrlLoading: true,
          mediaPlaybackRequiresUserGesture: true,
          transparentBackground: true,
          disableInputAccessoryView: true,
        ),
        onWebViewCreated: (controller) {
          _webView = controller;
          widget.controller._attach(controller);
          controller.addJavaScriptHandler(
            handlerName: 'bnbuMailEditor',
            callback: _handleEditorEvent,
          );
        },
        shouldOverrideUrlLoading: (_, navigationAction) async {
          final url = navigationAction.request.url;
          return url != null &&
                  url.scheme == 'file' &&
                  url.path.endsWith('/assets/mail_editor/index.html')
              ? NavigationActionPolicy.ALLOW
              : NavigationActionPolicy.CANCEL;
        },
        onLoadStop: (controller, _) async {
          _webView = controller;
          widget.controller._attach(controller);
        },
      ),
    );
  }
}

class _RichMailEditorFallback extends StatefulWidget {
  const _RichMailEditorFallback({
    required this.controller,
    required this.onChanged,
    required this.autofocus,
  });

  final RichMailEditorController controller;
  final ValueChanged<RichMailDocument> onChanged;
  final bool autofocus;

  @override
  State<_RichMailEditorFallback> createState() =>
      _RichMailEditorFallbackState();
}

class _RichMailEditorFallbackState extends State<_RichMailEditorFallback> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.document.text,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyedSubtree(
    key: const ValueKey('compose-rich-mail-editor'),
    child: TextField(
      key: const ValueKey('compose-body'),
      controller: _text,
      autofocus: widget.autofocus,
      expands: true,
      maxLines: null,
      minLines: null,
      textAlignVertical: TextAlignVertical.top,
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: null,
      ),
      onChanged: (value) {
        final document = RichMailDocument.fromPlainText(value);
        widget.controller._update(document);
        widget.onChanged(document);
      },
    ),
  );
}

String? _inferImageMimeType(Uint8List bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'image/png';
  }
  if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return 'image/jpeg';
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return 'image/gif';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}
