import '../services/me_identity_service.dart';
import '../services/sync/account_sync_storage.dart';
import '../state/account_habits.dart';
import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../widgets/bnbu_loading.dart';
import '../services/ai_assistant_service.dart';
import '../services/assistant_context_coordinator.dart';
import '../services/assistant_history_store.dart';
import '../services/study_window_manager.dart';
import '../state/ai_assistant_controller.dart';
import '../state/app_language_controller.dart';
import '../state/app_session_controller.dart';
import '../state/app_theme_mode_controller.dart';
import '../state/ta_course_controller.dart';
import '../theme/app_theme.dart';
import 'study_workspace_page.dart';

String studyWindowTitle(List<AssistantStudyDocument> documents) {
  if (documents.isEmpty) return '学业整理';
  if (documents.length == 1) return documents.first.title;
  final first = documents[0].title;
  final second = documents[1].title;
  if (documents.length == 2) return '$first和$second';
  return '$first和$second和其他共${documents.length}个页面';
}

class StudyWindowApp extends StatefulWidget {
  const StudyWindowApp({
    super.key,
    required this.windowController,
    required this.documents,
  });

  final WindowController windowController;
  final List<AssistantStudyDocument> documents;

  @override
  State<StudyWindowApp> createState() => _StudyWindowAppState();
}

class _StudyWindowAppState extends State<StudyWindowApp> {
  late final AppSessionController _sessionController =
      AppSessionController.studyWindow();
  late final AppThemeModeController _themeController = AppThemeModeController();
  late final AppLanguageController _languageController =
      AppLanguageController();
  late final TaCourseController _taController = TaCourseController(
    sessionController: _sessionController,
  );
  late final AiAssistantService _service = RemoteAiAssistantService();
  late final AssistantContextCoordinator _coordinator =
      AssistantContextCoordinator();
  late final AiAssistantController _assistantController = AiAssistantController(
    sessionController: _sessionController,
    service: _service,
    coordinator: _coordinator,
    taCourseController: _taController,
  );
  late final StudyWorkspaceTabController _tabs = StudyWorkspaceTabController(
    widget.documents,
  );
  late final Future<void> _initialization;
  final Set<String> _transferringDocuments = <String>{};

  @override
  void initState() {
    super.initState();
    _tabs.addListener(_handleTabsChanged);
    _sessionController.addListener(_meAccountChanged);
    _initialization = _initialize();
  }

  void _meAccountChanged() {
    final owner = _sessionController.isLoggedIn
        ? _sessionController.username
        : null;
    MeIdentityService.shared.setActiveOwner(owner);
    if (owner != null) {
      unawaited(
        MeIdentityService.shared.refresh(owner).catchError((Object _) {}),
      );
    }
  }

  void _handleTabsChanged() {
    if (mounted) setState(() {});
    unawaited(_syncWindowTitle());
  }

  Future<void> _syncWindowTitle() async {
    try {
      await windowManager.setTitle(studyWindowTitle(_tabs.documents));
    } catch (_) {
      // A tab transfer may finish while its source window is already closing.
    }
  }

  Future<void> _initialize() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: Size(1440, 900),
        minimumSize: Size(980, 680),
        center: true,
        title: studyWindowTitle(_tabs.documents),
        backgroundColor: Colors.black,
      ),
      () async {
        await _syncWindowTitle();
        await windowManager.show();
        await windowManager.focus();
      },
    );
    await widget.windowController.setWindowMethodHandler(_handleWindowMethod);
    await Future.wait([
      _themeController.restore(),
      _languageController.restore(
        preferredLocales: WidgetsBinding.instance.platformDispatcher.locales,
      ),
      _sessionController.restoreSessionIfPossible(),
    ]);
    _meAccountChanged();
    final owner = _sessionController.username;
    if (owner != null) await MeIdentityService.shared.restore(owner);
    await _refreshHabitSnapshot();
    await _assistantController.initialize();
  }

  Future<void> _refreshHabitSnapshot() async {
    final username = _sessionController.username;
    final owner = username == null
        ? null
        : AccountSyncStorage.account(username);
    if (owner == null) {
      AccountHabits.shared.detachWindowSnapshot();
      return;
    }
    for (final window in await WindowController.getAll()) {
      if (window.windowId == widget.windowController.windowId) continue;
      try {
        final raw = await window.invokeMethod<Object?>('habits.read', {
          'owner': owner,
        });
        if (raw is! Map || raw['owner'] != owner || !mounted) continue;
        AccountHabits.shared.attachWindowSnapshot(
          owner,
          Map<String, dynamic>.from(raw['values'] as Map),
          (key, value) async {
            final saved = await window.invokeMethod<Object?>('habits.write', {
              'owner': owner,
              'key': key,
              'value': value,
            });
            if (saved is! Map || saved['owner'] != owner) {
              throw StateError('Account changed');
            }
            await _refreshHabitSnapshot();
          },
        );
        await _themeController.restore();
        await _languageController.restore(
          preferredLocales: WidgetsBinding.instance.platformDispatcher.locales,
        );
        return;
      } catch (_) {}
    }
    AccountHabits.shared.detachWindowSnapshot();
  }

  Future<Object?> _handleWindowMethod(MethodCall call) async {
    switch (call.method) {
      case 'habits.changed':
        await _refreshHabitSnapshot();
        return null;
      case 'study.containsDocument':
        return _tabs.contains(call.arguments as String? ?? '');
      case 'study.focus':
        await windowManager.show();
        await windowManager.focus();
        return true;
      case 'study.hitTest':
        final point = Map<String, dynamic>.from(call.arguments as Map);
        final bounds = await windowManager.getBounds();
        final x = (point['x'] as num).toDouble();
        final y = (point['y'] as num).toDouble();
        return x >= bounds.left &&
            x <= bounds.right &&
            y >= bounds.top &&
            y <= bounds.top + 96;
      case 'study.acceptDocument':
        final document = AssistantStudyDocument.fromJson(
          Map<String, dynamic>.from(call.arguments as Map),
        );
        _tabs.add(document, activate: true);
        await _syncWindowTitle();
        await windowManager.show();
        await windowManager.focus();
        return true;
    }
    return null;
  }

  Future<void> _handleExternalDrop(
    AssistantStudyDocument document,
    Offset localOffset,
  ) async {
    if (!_transferringDocuments.add(document.key)) return;
    try {
      final ownBounds = await windowManager.getBounds();
      final screenPoint = ownBounds.topLeft + localOffset;
      // Releasing a tab anywhere inside its current window cancels the detach.
      // Previously only the title strip was protected, so an ordinary drag over
      // the document could unexpectedly create a new window.
      if (screenPoint.dx >= ownBounds.left &&
          screenPoint.dx <= ownBounds.right &&
          screenPoint.dy >= ownBounds.top &&
          screenPoint.dy <= ownBounds.bottom) {
        return;
      }
      for (final controller in await WindowController.getAll()) {
        if (controller.windowId == widget.windowController.windowId) continue;
        try {
          final accepts = await controller.invokeMethod<bool>('study.hitTest', {
            'x': screenPoint.dx,
            'y': screenPoint.dy,
          });
          if (accepts == true) {
            await controller.invokeMethod<void>(
              'study.acceptDocument',
              document.toJson(),
            );
            _tabs.remove(document.key);
            await _closeIfEmpty();
            return;
          }
        } catch (_) {
          // Ignore windows that are closing or are not study workspaces.
        }
      }
      await StudyWindowManager.create([document]);
      _tabs.remove(document.key);
      await _closeIfEmpty();
    } finally {
      _transferringDocuments.remove(document.key);
    }
  }

  Future<void> _closeIfEmpty() async {
    // On macOS window_manager.destroy() calls NSApp.terminate(nil), which
    // closes the entire application. A study child window must only close its
    // own NSWindow after its final tab has moved away.
    if (_tabs.documents.isEmpty) await windowManager.close();
  }

  @override
  void dispose() {
    _sessionController.removeListener(_meAccountChanged);
    unawaited(widget.windowController.setWindowMethodHandler(null));
    _tabs.removeListener(_handleTabsChanged);
    _tabs.dispose();
    _assistantController.dispose();
    _service.dispose();
    _coordinator.dispose();
    _taController.dispose();
    _themeController.dispose();
    _languageController.dispose();
    _sessionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_themeController, _languageController]),
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: studyWindowTitle(_tabs.documents),
        theme: AppTheme.monochrome(Brightness.light),
        darkTheme: AppTheme.monochrome(Brightness.dark),
        themeMode: _themeController.themeMode,
        locale: _languageController.locale,
        localeListResolutionCallback: (locales, supportedLocales) =>
            _languageController.resolveLocale(locales),
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: FutureBuilder<void>(
          future: _initialization,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: BnbuActivityIndicator()),
              );
            }
            if (snapshot.hasError || !_sessionController.isLoggedIn) {
              return Scaffold(
                body: Center(
                  child: BnbuText(
                    snapshot.error?.toString() ?? '请先在 BNBU.ME 完成登录',
                  ),
                ),
              );
            }
            return Scaffold(
              body: StudyWorkspaceView(
                sessionController: _sessionController,
                assistantController: _assistantController,
                initialDocument: widget.documents.first,
                tabController: _tabs,
                onExternalTabDrop: _handleExternalDrop,
                onAllDocumentsClosed: () => unawaited(_closeIfEmpty()),
                fallback: const Center(child: BnbuText('课件无法预览')),
              ),
            );
          },
        ),
      ),
    );
  }
}
