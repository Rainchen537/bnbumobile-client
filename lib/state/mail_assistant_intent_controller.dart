import 'package:flutter/foundation.dart';

import '../models/mail_models.dart';

enum AssistantMailIntentKind { delete, restore }

class AssistantMailIntent {
  const AssistantMailIntent({
    required this.kind,
    required this.folder,
    required this.uid,
    required this.mailboxUidValidity,
    required this.targetIdentity,
  });

  final AssistantMailIntentKind kind;
  final MailFolder folder;
  final int uid;
  final int mailboxUidValidity;
  final String targetIdentity;
}

class MailAssistantIntentController extends ChangeNotifier {
  AssistantMailIntent? _pendingIntent;

  AssistantMailIntent? takePendingIntent() {
    final intent = _pendingIntent;
    _pendingIntent = null;
    return intent;
  }

  void publish(AssistantMailIntent intent) {
    _pendingIntent = intent;
    notifyListeners();
  }

  void clear() {
    _pendingIntent = null;
  }
}
