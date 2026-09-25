import 'package:flutter/foundation.dart';

class StudyModeController extends ChangeNotifier {
  Object? _activeOwner;
  Future<void> Function()? _opener;

  bool get active => _activeOwner != null;

  void activate(Object owner, Future<void> Function() opener) {
    if (identical(_activeOwner, owner) && identical(_opener, opener)) {
      return;
    }
    _activeOwner = owner;
    _opener = opener;
    notifyListeners();
  }

  void deactivate(Object owner) {
    if (!identical(_activeOwner, owner)) {
      return;
    }
    _activeOwner = null;
    _opener = null;
    notifyListeners();
  }

  Future<void> open() => _opener?.call() ?? Future<void>.value();
}
