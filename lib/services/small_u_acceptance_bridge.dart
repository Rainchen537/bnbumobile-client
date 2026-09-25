import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/assistant_models.dart';
import '../state/ai_assistant_controller.dart';
import '../state/app_session_controller.dart';

typedef SmallUAcceptanceTurnHandler =
    Future<Map<String, Object?>> Function(SmallUAcceptanceTurnRequest request);
typedef SmallUAcceptanceStatusHandler = Map<String, Object?> Function();
typedef SmallUAcceptanceAuditHandler = Future<Map<String, Object?>> Function();

const smallUAcceptanceMaxConcurrentTurns = 80;

class SmallUAcceptanceBridgeConfig {
  const SmallUAcceptanceBridgeConfig({required this.discoveryFile});

  static const buildEnabled = bool.fromEnvironment(
    'SMALL_U_ACCEPTANCE_BRIDGE',
    defaultValue: false,
  );

  static const _argumentPrefix = '--small-u-acceptance-bridge=';
  static const _environmentKey = 'SMALL_U_ACCEPTANCE_DISCOVERY_FILE';
  static const _runtimeGateKey = 'SMALL_U_ACCEPTANCE_BRIDGE_ENABLED';

  final File discoveryFile;

  static SmallUAcceptanceBridgeConfig? fromArguments(
    List<String> arguments, {
    bool enabled = buildEnabled,
    Map<String, String>? environment,
  }) {
    final processEnvironment = environment ?? Platform.environment;
    if (!enabled && processEnvironment[_runtimeGateKey] != '1') return null;
    final argumentPaths = arguments
        .where((argument) => argument.startsWith(_argumentPrefix))
        .map((argument) => argument.substring(_argumentPrefix.length).trim())
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    final environmentPath = processEnvironment[_environmentKey]?.trim();
    final paths = <String>{
      ...argumentPaths,
      if (environmentPath != null && environmentPath.isNotEmpty)
        environmentPath,
    };
    if (paths.length > 1 || argumentPaths.length > 1) return null;
    final path = paths.isEmpty
        ? '${Directory.systemTemp.path}${Platform.pathSeparator}bnbu-small-u-acceptance.json'
        : paths.single;
    if (path.isEmpty || !File(path).isAbsolute) return null;
    return SmallUAcceptanceBridgeConfig(discoveryFile: File(path));
  }
}

class SmallUAcceptanceTurnRequest {
  const SmallUAcceptanceTurnRequest({
    required this.prompt,
    required this.newConversation,
    required this.openUi,
    required this.thinkingMode,
  });

  final String prompt;
  final bool newConversation;
  final bool openUi;
  final String? thinkingMode;

  factory SmallUAcceptanceTurnRequest.fromJson(Map<String, dynamic> json) {
    final prompt = json['prompt'];
    final newConversation = json['new_conversation'] ?? true;
    final openUi = json['open_ui'] ?? true;
    final thinkingMode = json['thinking_mode'];
    if (prompt is! String ||
        prompt.trim().isEmpty ||
        prompt.length > 4000 ||
        newConversation is! bool ||
        openUi is! bool ||
        (thinkingMode != null &&
            (thinkingMode is! String ||
                !const {'low', 'medium', 'high'}.contains(thinkingMode)))) {
      throw const SmallUAcceptanceException(
        'invalid_request',
        '小U验收请求格式无效。',
        statusCode: HttpStatus.badRequest,
      );
    }
    return SmallUAcceptanceTurnRequest(
      prompt: prompt.trim(),
      newConversation: newConversation,
      openUi: openUi,
      thinkingMode: thinkingMode as String?,
    );
  }
}

class SmallUAcceptanceException implements Exception {
  const SmallUAcceptanceException(
    this.code,
    this.message, {
    this.statusCode = HttpStatus.conflict,
  });

  final String code;
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}

class SmallUAcceptanceRuntime {
  SmallUAcceptanceRuntime({
    required AiAssistantController assistantController,
    required AppSessionController sessionController,
    required Future<void> Function() openAssistant,
    required bool Function() isAssistantPresented,
  }) : _assistantController = assistantController,
       _sessionController = sessionController,
       _openAssistant = openAssistant,
       _isAssistantPresented = isAssistantPresented;

  final AiAssistantController _assistantController;
  final AppSessionController _sessionController;
  final Future<void> Function() _openAssistant;
  final bool Function() _isAssistantPresented;
  Future<void> _turnSetupMutation = Future<void>.value();

  Map<String, Object?> status() => {
    'logged_in': _sessionController.isLoggedIn,
    'assistant_enabled': _assistantController.enabled,
    'assistant_loading': _assistantController.loading,
    'assistant_sending': _assistantController.sending,
    'assistant_presented': _isAssistantPresented(),
    'thinking_mode': _assistantController.thinkingMode.wireValue,
  };

  Future<Map<String, Object?>> auditSnapshot() async {
    if (!_sessionController.isLoggedIn ||
        (_sessionController.username?.trim().isEmpty ?? true)) {
      throw const SmallUAcceptanceException(
        'not_logged_in',
        '请先在测试版 BNBU.ME 中完成登录恢复。',
      );
    }
    await _sessionController.refreshCourses();
    await _sessionController.refreshTimeline();

    final courseSnapshots = <Map<String, Object?>>[];
    final loadFailures = <Map<String, Object?>>[];
    final courses = _sessionController.courses.toList(growable: false);
    for (var courseIndex = 0; courseIndex < courses.length; courseIndex++) {
      final course = courses[courseIndex];
      final sections = <Map<String, Object?>>[];
      try {
        final loadedSections = await _sessionController.loadCourseContents(
          course.id,
        );
        for (
          var sectionIndex = 0;
          sectionIndex < loadedSections.length;
          sectionIndex++
        ) {
          final section = loadedSections[sectionIndex];
          sections.add({
            'section_index': sectionIndex + 1,
            'name': section.name,
            'visible': section.visible,
            'user_visible': section.userVisible,
            'modules': [
              for (
                var moduleIndex = 0;
                moduleIndex < section.modules.length;
                moduleIndex++
              )
                {
                  'module_index': moduleIndex + 1,
                  'name': section.modules[moduleIndex].name,
                  'type': section.modules[moduleIndex].modName,
                  'visible': section.modules[moduleIndex].visible,
                  'user_visible': section.modules[moduleIndex].userVisible,
                  'availability': section.modules[moduleIndex].availabilityInfo,
                  'completion_tracking':
                      section.modules[moduleIndex].completionTracking,
                  'completion_state':
                      section.modules[moduleIndex].completionData?.state,
                  'completion_is_automatic':
                      section.modules[moduleIndex].completionData?.isAutomatic,
                  'download_content':
                      section.modules[moduleIndex].downloadContent,
                  'dates': [
                    for (final date in section.modules[moduleIndex].dates)
                      {
                        'label': date.label,
                        'data_id': date.dataId,
                        'at': date.dateTime?.toUtc().toIso8601String(),
                      },
                  ],
                  'files': [
                    for (final content in section.modules[moduleIndex].contents)
                      {
                        'name': content.fileName,
                        'type': content.type,
                        'mime_type': content.mimeType,
                        'size': content.fileSize,
                        'modified_at': content.timeModifiedAt
                            ?.toUtc()
                            .toIso8601String(),
                      },
                  ],
                },
            ],
          });
        }
      } catch (_) {
        loadFailures.add({
          'course_index': courseIndex + 1,
          'reason': 'course_contents_unavailable',
        });
      }
      courseSnapshots.add({
        'course_index': courseIndex + 1,
        'full_name': course.fullName,
        'short_name': course.shortName,
        'category': course.categoryName,
        'progress': course.progress,
        'start_at': course.startAt?.toUtc().toIso8601String(),
        'end_at': course.endAt?.toUtc().toIso8601String(),
        'visible': course.visible,
        'hidden': course.hidden,
        'completion_enabled': course.enableCompletion,
        'completion_user_tracked': course.completionUserTracked,
        'completed': course.completed,
        'show_grades': course.showGrades,
        'sections': sections,
      });
    }

    final profile = _sessionController.moodleRuntimeProfile;
    return {
      'schema_version': 1,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'profile': profile == null
          ? null
          : {
              'release': profile.release,
              'version': profile.version,
              'function_count': profile.functionVersions.length,
              'download_files': profile.downloadFiles,
              'upload_files': profile.uploadFiles,
              'normalized_capabilities': profile.normalizedCapabilities
                  .map((capability) => capability.name)
                  .toList(growable: false),
            },
      'courses': courseSnapshots,
      'timeline': [
        for (final item in _sessionController.timelineItems)
          {
            'title': item.title,
            'activity_state': item.activityState,
            'activity_type': item.activityType,
            'module_name': item.moduleName,
            'course_name': item.courseName,
            'sort_time': item.sortTime?.toUtc().toIso8601String(),
            'formatted_time': item.formattedTime,
            'is_overdue': item.isOverdue,
          },
      ],
      'load_failures': loadFailures,
    };
  }

  Future<Map<String, Object?>> runTurn(
    SmallUAcceptanceTurnRequest request,
  ) async {
    if (!_sessionController.isLoggedIn ||
        (_sessionController.username?.trim().isEmpty ?? true)) {
      throw const SmallUAcceptanceException(
        'not_logged_in',
        '请先在测试版 BNBU.ME 中完成登录恢复。',
      );
    }
    final prepared = await _serializeTurnSetup(() async {
      await _assistantController.initialize();
      final capabilities = _assistantController.capabilities;
      if (!_assistantController.enabled ||
          capabilities == null ||
          !capabilities.available) {
        throw SmallUAcceptanceException(
          'assistant_unavailable',
          _assistantController.error ?? '小U当前不可用。',
        );
      }

      final requestedThinkingMode = request.thinkingMode;
      if (requestedThinkingMode != null) {
        await _assistantController.setThinkingMode(
          AssistantThinkingMode.parse(requestedThinkingMode),
        );
      }
      final effectiveThinkingMode = _assistantController.thinkingMode;
      if (request.newConversation) {
        await _assistantController.startNewConversation();
      }
      final conversationId = _assistantController.currentConversationId;
      final before = _assistantController.currentConversation?.messages.length;
      if (conversationId == null || before == null) {
        throw const SmallUAcceptanceException(
          'conversation_unavailable',
          '小U验收会话暂时不可用。',
        );
      }

      if (request.openUi && !_isAssistantPresented()) {
        unawaited(_openAssistant());
        await Future<void>.delayed(Duration.zero);
      }

      // send() captures the current thinking mode and marks this exact
      // conversation pending before its first await. Returning its Future lets
      // the next setup proceed without allowing either value to race.
      final completion = _assistantController.send(
        request.prompt,
        conversationId: conversationId,
      );
      return _PreparedAcceptanceTurn(
        conversationId: conversationId,
        messageCountBeforeTurn: before,
        thinkingMode: effectiveThinkingMode,
        completion: completion,
      );
    });

    await prepared.completion;
    final conversation = _assistantController.conversationById(
      prepared.conversationId,
    );
    if (conversation == null ||
        conversation.messages.length <= prepared.messageCountBeforeTurn) {
      throw SmallUAcceptanceException(
        'turn_not_started',
        _assistantController.error ?? '小U没有开始处理这轮问题。',
      );
    }
    final addedMessages = conversation.messages
        .skip(prepared.messageCountBeforeTurn)
        .toList(growable: false);
    final assistantMessages = addedMessages
        .where((message) => message.role == 'assistant')
        .toList(growable: false);
    if (assistantMessages.isEmpty) {
      throw const SmallUAcceptanceException(
        'turn_incomplete',
        '小U这轮问题没有产生终态回答。',
      );
    }
    final answer = assistantMessages.last;
    final catalogDiagnostics = _assistantController
        .ispaceCatalogDiagnosticsForConversation(prepared.conversationId);
    return {
      'schema_version': 1,
      'conversation_id': conversation.id,
      'conversation_title': conversation.title,
      'thinking_mode': prepared.thinkingMode.wireValue,
      'answer': answer.content,
      'is_error': answer.isError,
      'compact_error': answer.compactError,
      'activities': answer.activities
          .map((activity) => activity.toJson())
          .toList(growable: false),
      'actions': answer.actions
          .map((action) => action.toJson())
          .toList(growable: false),
      'suggestions': answer.suggestions
          .map((suggestion) => suggestion.toJson())
          .toList(growable: false),
      'memory_suggestions': answer.memorySuggestions
          .map((suggestion) => suggestion.toJson())
          .toList(growable: false),
      if (catalogDiagnostics != null)
        'ispace_catalog_diagnostics': catalogDiagnostics.toJson(),
      'public_tool_receipts': _assistantController
          .publicToolReceiptsForConversation(prepared.conversationId),
      'created_at': answer.createdAt.toUtc().toIso8601String(),
    };
  }

  Future<T> _serializeTurnSetup<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _turnSetupMutation = _turnSetupMutation.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

class _PreparedAcceptanceTurn {
  const _PreparedAcceptanceTurn({
    required this.conversationId,
    required this.messageCountBeforeTurn,
    required this.thinkingMode,
    required this.completion,
  });

  final String conversationId;
  final int messageCountBeforeTurn;
  final AssistantThinkingMode thinkingMode;
  final Future<void> completion;
}

class SmallUAcceptanceBridge {
  SmallUAcceptanceBridge({
    required SmallUAcceptanceBridgeConfig config,
    required SmallUAcceptanceTurnHandler turnHandler,
    required SmallUAcceptanceStatusHandler statusHandler,
    required SmallUAcceptanceAuditHandler auditHandler,
  }) : _config = config,
       _turnHandler = turnHandler,
       _statusHandler = statusHandler,
       _auditHandler = auditHandler;

  static const _maxRequestBytes = 16 * 1024;
  static const _maxConcurrentTurns = smallUAcceptanceMaxConcurrentTurns;

  final SmallUAcceptanceBridgeConfig _config;
  final SmallUAcceptanceTurnHandler _turnHandler;
  final SmallUAcceptanceStatusHandler _statusHandler;
  final SmallUAcceptanceAuditHandler _auditHandler;
  HttpServer? _server;
  String? _token;
  int _activeTurns = 0;
  bool _auditInProgress = false;

  Future<void> start() async {
    if (_server != null) return;
    await _validateDiscoveryLocation();
    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
      shared: false,
    );
    final token = _generateToken();
    _server = server;
    _token = token;
    unawaited(_serve(server));
    try {
      await _writeDiscoveryFile(server, token);
    } catch (_) {
      _server = null;
      _token = null;
      await server.close(force: true);
      rethrow;
    }
  }

  Future<void> close() async {
    final server = _server;
    final token = _token;
    _server = null;
    _token = null;
    if (server != null) {
      await server.close(force: true);
    }
    final discovery = _config.discoveryFile;
    if (token == null || !await discovery.exists()) return;
    try {
      final decoded = jsonDecode(await discovery.readAsString());
      if (decoded is Map && decoded['token'] == token) {
        await discovery.delete();
      }
    } catch (_) {
      // A replaced or damaged discovery file does not belong to this bridge.
    }
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final remote = request.connectionInfo?.remoteAddress;
      if (remote == null || !remote.isLoopback) {
        throw const SmallUAcceptanceException(
          'loopback_required',
          '小U验收桥只接受本机连接。',
          statusCode: HttpStatus.forbidden,
        );
      }
      if ((request.headers.value('origin') ?? '').isNotEmpty) {
        throw const SmallUAcceptanceException(
          'browser_origin_rejected',
          '小U验收桥不接受浏览器 Origin 请求。',
          statusCode: HttpStatus.forbidden,
        );
      }
      final authorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      if (!_constantTimeEquals(authorization ?? '', 'Bearer ${_token ?? ''}')) {
        throw const SmallUAcceptanceException(
          'unauthorized',
          '小U验收桥鉴权失败。',
          statusCode: HttpStatus.unauthorized,
        );
      }
      if (request.method == 'GET' && request.uri.path == '/v1/status') {
        await _writeJson(request.response, HttpStatus.ok, {
          'schema_version': 1,
          ..._statusHandler(),
          'active_turns': _activeTurns,
        });
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/v1/audit-snapshot') {
        if (_activeTurns > 0 || _auditInProgress) {
          throw const SmallUAcceptanceException(
            'turn_in_progress',
            '已有一轮小U验收问题正在执行。',
          );
        }
        _auditInProgress = true;
        try {
          await _writeJson(
            request.response,
            HttpStatus.ok,
            await _auditHandler(),
          );
        } finally {
          _auditInProgress = false;
        }
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/v1/turns') {
        if (_auditInProgress) {
          throw const SmallUAcceptanceException(
            'audit_in_progress',
            'iSpace 能力审计正在执行。',
          );
        }
        if (_activeTurns >= _maxConcurrentTurns) {
          throw const SmallUAcceptanceException(
            'turn_capacity_reached',
            '小U验收并发已达到上限。',
            statusCode: HttpStatus.tooManyRequests,
          );
        }
        final contentType = request.headers.contentType;
        if (contentType?.mimeType != 'application/json') {
          throw const SmallUAcceptanceException(
            'json_required',
            '小U验收桥只接受 JSON 请求。',
            statusCode: HttpStatus.unsupportedMediaType,
          );
        }
        _activeTurns += 1;
        try {
          final decoded = jsonDecode(await _readBody(request));
          if (decoded is! Map) {
            throw const SmallUAcceptanceException(
              'invalid_request',
              '小U验收请求必须是 JSON 对象。',
              statusCode: HttpStatus.badRequest,
            );
          }
          final turn = SmallUAcceptanceTurnRequest.fromJson(
            decoded.cast<String, dynamic>(),
          );
          final result = await _turnHandler(turn);
          await _writeJson(request.response, HttpStatus.ok, result);
        } finally {
          _activeTurns -= 1;
        }
        return;
      }
      throw const SmallUAcceptanceException(
        'not_found',
        '小U验收桥路径不存在。',
        statusCode: HttpStatus.notFound,
      );
    } on SmallUAcceptanceException catch (error) {
      await _writeJson(request.response, error.statusCode, {
        'error': error.code,
        'message': error.message,
      });
    } on FormatException {
      await _writeJson(request.response, HttpStatus.badRequest, const {
        'error': 'invalid_json',
        'message': '小U验收请求 JSON 无效。',
      });
    } catch (_) {
      await _writeJson(request.response, HttpStatus.internalServerError, const {
        'error': 'bridge_failure',
        'message': '小U验收桥执行失败。',
      });
    }
  }

  Future<String> _readBody(HttpRequest request) async {
    final declaredLength = request.contentLength;
    if (declaredLength > _maxRequestBytes) {
      throw const SmallUAcceptanceException(
        'request_too_large',
        '小U验收请求过大。',
        statusCode: HttpStatus.requestEntityTooLarge,
      );
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request) {
      bytes.add(chunk);
      if (bytes.length > _maxRequestBytes) {
        throw const SmallUAcceptanceException(
          'request_too_large',
          '小U验收请求过大。',
          statusCode: HttpStatus.requestEntityTooLarge,
        );
      }
    }
    return utf8.decode(bytes.takeBytes());
  }

  Future<void> _validateDiscoveryLocation() async {
    final discovery = _config.discoveryFile;
    if (await discovery.exists()) {
      throw const SmallUAcceptanceException(
        'discovery_exists',
        '小U验收桥发现文件已存在。',
      );
    }
    final parent = discovery.parent;
    if (!await parent.exists()) {
      throw const SmallUAcceptanceException(
        'discovery_parent_missing',
        '小U验收桥发现目录不存在。',
      );
    }
    final systemTemp = await Directory.systemTemp.resolveSymbolicLinks();
    final resolvedParent = await parent.resolveSymbolicLinks();
    final root = systemTemp.endsWith(Platform.pathSeparator)
        ? systemTemp
        : '$systemTemp${Platform.pathSeparator}';
    if (resolvedParent != systemTemp && !resolvedParent.startsWith(root)) {
      throw const SmallUAcceptanceException(
        'unsafe_discovery_path',
        '小U验收桥发现文件必须位于系统临时目录。',
      );
    }
  }

  Future<void> _writeDiscoveryFile(HttpServer server, String token) async {
    final discovery = _config.discoveryFile;
    final temporary = File(
      '${discovery.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    await temporary.writeAsString(
      jsonEncode({
        'schema_version': 1,
        'base_url': 'http://127.0.0.1:${server.port}',
        'token': token,
        'pid': pid,
        'started_at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await temporary.rename(discovery.path);
  }

  static String _generateToken() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static bool _constantTimeEquals(String left, String right) {
    var difference = left.length ^ right.length;
    final length = max(left.length, right.length);
    for (var index = 0; index < length; index++) {
      final leftCode = index < left.length ? left.codeUnitAt(index) : 0;
      final rightCode = index < right.length ? right.codeUnitAt(index) : 0;
      difference |= leftCode ^ rightCode;
    }
    return difference == 0;
  }

  static Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(jsonEncode(body));
    await response.close();
  }
}
