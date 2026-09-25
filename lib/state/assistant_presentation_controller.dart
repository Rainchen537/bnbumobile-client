import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/assistant_models.dart';

class AssistantPresentationController extends ChangeNotifier {
  AssistantPresentationController({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _floatingAnchorPreferenceKey = 'assistant.floating_anchor.v1';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Route<void>? _assistantRoute;
  Future<void>? _presentationFuture;
  Offset _floatingAnchor = const Offset(1, 1);
  bool _floatingEdgeHidden = false;
  Future<void>? _floatingAnchorRestore;
  int _floatingAnchorRevision = 0;
  String? _runtimeOwner;
  Object _assistantDraftOwnerToken = Object();
  bool _wasSending = false;
  int _successfulReplyCount = 0;
  bool _isAssistantBusy = false;
  bool _hasUnseenCompletedReply = false;
  String _assistantDraftText = '';
  List<AssistantInputAttachment> _assistantDraftAttachments = const [];
  int _floatingOverlaySuppressionCount = 0;
  double _assistantBottomAvoidance = 0;
  Rect? _assistantComposerRect;
  Object? _assistantBottomAvoidanceOwner;
  bool _isDisposed = false;

  bool get isAssistantPresented => _assistantRoute != null;
  Offset get floatingAnchor => _floatingAnchor;
  bool get floatingEdgeHidden => _floatingEdgeHidden;
  bool get isAssistantBusy => _isAssistantBusy;
  bool get hasUnseenCompletedReply => _hasUnseenCompletedReply;
  String get assistantDraftText => _assistantDraftText;
  List<AssistantInputAttachment> get assistantDraftAttachments =>
      _assistantDraftAttachments;
  Object get assistantDraftOwnerToken => _assistantDraftOwnerToken;
  bool get isFloatingOverlaySuppressed => _floatingOverlaySuppressionCount > 0;
  double get assistantBottomAvoidance => _assistantBottomAvoidance;
  Rect? get assistantComposerRect => _assistantComposerRect;

  @visibleForTesting
  Route<void>? get assistantRoute => _assistantRoute;

  Future<void> restoreFloatingAnchor() {
    final activeRestore = _floatingAnchorRestore;
    if (activeRestore != null) {
      return activeRestore;
    }
    final revision = _floatingAnchorRevision;
    final future = _restoreFloatingAnchor(revision);
    _floatingAnchorRestore = future;
    return future.whenComplete(() {
      if (identical(_floatingAnchorRestore, future)) {
        _floatingAnchorRestore = null;
      }
    });
  }

  Future<void> _restoreFloatingAnchor(int revision) async {
    try {
      final preferences = await _preferencesLoader();
      final rawValue = preferences.getString(_floatingAnchorPreferenceKey);
      if (rawValue == null || revision != _floatingAnchorRevision) {
        return;
      }
      final decoded = jsonDecode(rawValue);
      if (decoded is! Map) {
        return;
      }
      final x = decoded['x'];
      final y = decoded['y'];
      if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
        return;
      }
      final restored = Offset(
        x.toDouble().clamp(0, 1),
        y.toDouble().clamp(0, 1),
      );
      final edgeHidden = decoded['edge_hidden'] == true;
      if (restored != _floatingAnchor || edgeHidden != _floatingEdgeHidden) {
        _floatingAnchor = restored;
        _floatingEdgeHidden = edgeHidden;
        notifyListeners();
      }
    } catch (_) {
      // A damaged cosmetic preference must never block the app shell.
    }
  }

  void updateFloatingAnchor(Offset value, {bool edgeHidden = false}) {
    final normalized = Offset(
      value.dx.isFinite ? value.dx.clamp(0, 1) : _floatingAnchor.dx,
      value.dy.isFinite ? value.dy.clamp(0, 1) : _floatingAnchor.dy,
    );
    _floatingAnchorRevision += 1;
    if (normalized == _floatingAnchor && edgeHidden == _floatingEdgeHidden) {
      return;
    }
    _floatingAnchor = normalized;
    _floatingEdgeHidden = edgeHidden;
    notifyListeners();
  }

  Future<void> persistFloatingAnchor() async {
    final anchor = _floatingAnchor;
    try {
      final preferences = await _preferencesLoader();
      await preferences.setString(
        _floatingAnchorPreferenceKey,
        jsonEncode(<String, dynamic>{
          'x': anchor.dx,
          'y': anchor.dy,
          'edge_hidden': _floatingEdgeHidden,
        }),
      );
    } catch (_) {
      // Position persistence is best effort; dragging remains usable in memory.
    }
  }

  void synchronizeAssistantRuntime({
    required String? owner,
    required bool isLoggedIn,
    required bool isSending,
    required int successfulReplyCount,
  }) {
    final normalizedOwner = owner?.trim().toLowerCase();
    final activeOwner = normalizedOwner == null || normalizedOwner.isEmpty
        ? null
        : normalizedOwner;
    final ownerChanged = activeOwner != _runtimeOwner;
    final shouldReset = !isLoggedIn || activeOwner == null || ownerChanged;

    var changed = false;
    if (shouldReset) {
      if (ownerChanged || !isLoggedIn || activeOwner == null) {
        _assistantDraftOwnerToken = Object();
      }
      _runtimeOwner = isLoggedIn ? activeOwner : null;
      _wasSending = false;
      _successfulReplyCount = successfulReplyCount;
      if (_assistantDraftText.isNotEmpty ||
          _assistantDraftAttachments.isNotEmpty) {
        _assistantDraftText = '';
        _assistantDraftAttachments = const [];
        changed = true;
      }
      if (_isAssistantBusy) {
        _isAssistantBusy = false;
        changed = true;
      }
      if (_hasUnseenCompletedReply) {
        _hasUnseenCompletedReply = false;
        changed = true;
      }
    } else {
      final completedSuccessfully =
          _wasSending &&
          !isSending &&
          successfulReplyCount > _successfulReplyCount;
      if (completedSuccessfully &&
          !isAssistantPresented &&
          !_hasUnseenCompletedReply) {
        _hasUnseenCompletedReply = true;
        changed = true;
      }
      if (_isAssistantBusy != isSending) {
        _isAssistantBusy = isSending;
        changed = true;
      }
      _wasSending = isSending;
      _successfulReplyCount = successfulReplyCount;
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Keeps the unsent composer state alive while the full-page route is
  /// collapsed. This state is process-only and is deliberately never written
  /// to SharedPreferences because attachments can contain bytes or local paths.
  void updateAssistantDraft({
    required Object ownerToken,
    required String text,
    required List<AssistantInputAttachment> attachments,
  }) {
    if (!identical(ownerToken, _assistantDraftOwnerToken)) return;
    _assistantDraftText = text;
    _assistantDraftAttachments = List.unmodifiable(attachments.take(3));
  }

  void clearAssistantDraft(Object ownerToken) {
    if (!identical(ownerToken, _assistantDraftOwnerToken)) return;
    _assistantDraftText = '';
    _assistantDraftAttachments = const [];
  }

  void clearCompletedReplyIndicator() {
    if (!_hasUnseenCompletedReply) {
      return;
    }
    _hasUnseenCompletedReply = false;
    notifyListeners();
  }

  /// The full 小U page reports the live composer region while it is mounted.
  /// This is presentation-only state: it never affects the saved floating
  /// anchor and is cleared when the route leaves the tree.
  void updateAssistantBottomAvoidance({
    required Object owner,
    required double value,
    Rect? rect,
  }) {
    final normalized = value.isFinite ? value.clamp(0, 600).toDouble() : 0.0;
    if (identical(_assistantBottomAvoidanceOwner, owner) &&
        (_assistantBottomAvoidance - normalized).abs() < 1 &&
        _assistantComposerRect == rect) {
      return;
    }
    _assistantBottomAvoidanceOwner = owner;
    _assistantBottomAvoidance = normalized;
    _assistantComposerRect = rect;
    notifyListeners();
  }

  /// Clears only the departing page's presentation data. This deliberately
  /// does not notify: widget disposal runs while the tree can be locked, and
  /// the enclosing route completion will issue the safe visibility update.
  void clearAssistantBottomAvoidance(Object owner) {
    if (!identical(_assistantBottomAvoidanceOwner, owner)) {
      return;
    }
    _assistantBottomAvoidanceOwner = null;
    _assistantBottomAvoidance = 0;
    _assistantComposerRect = null;
  }

  VoidCallback suppressFloatingOverlay() {
    _floatingOverlaySuppressionCount += 1;
    _notifyOverlayVisibilityChanged();
    var released = false;
    return () {
      if (released) {
        return;
      }
      released = true;
      if (_floatingOverlaySuppressionCount == 0) {
        return;
      }
      _floatingOverlaySuppressionCount -= 1;
      _notifyOverlayVisibilityChanged();
    };
  }

  void _notifyOverlayVisibilityChanged() {
    if (_isDisposed) {
      return;
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) {
          notifyListeners();
        }
      });
      return;
    }
    notifyListeners();
  }

  Future<void> presentAssistant({
    required NavigatorState navigator,
    required Route<void> Function() routeBuilder,
  }) {
    final activePresentation = _presentationFuture;
    if (_assistantRoute != null && activePresentation != null) {
      return activePresentation;
    }

    final route = routeBuilder();
    _assistantRoute = route;
    _hasUnseenCompletedReply = false;
    notifyListeners();

    final future = navigator.push<void>(route).whenComplete(() {
      if (identical(_assistantRoute, route)) {
        _assistantRoute = null;
        _presentationFuture = null;
        _assistantBottomAvoidanceOwner = null;
        _assistantBottomAvoidance = 0;
        notifyListeners();
      }
    });
    _presentationFuture = future;
    return future;
  }

  Future<void> dismissAssistant() async {
    final route = _assistantRoute;
    if (route == null) {
      return;
    }
    final navigator = route.navigator;
    if (navigator == null) {
      if (identical(_assistantRoute, route)) {
        _assistantRoute = null;
        _presentationFuture = null;
        _assistantBottomAvoidanceOwner = null;
        _assistantBottomAvoidance = 0;
        notifyListeners();
      }
      return;
    }

    final presentationFuture = _presentationFuture;
    navigator.removeRoute<void>(route);
    await presentationFuture;
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
