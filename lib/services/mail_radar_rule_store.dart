import '../state/account_habits.dart';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mail_radar_models.dart';

/// Explicit, device-local sender rules. Never inferred from a single correction.
class MailRadarRule {
  const MailRadarRule({
    required this.sender,
    required this.category,
    this.enabled = true,
  });
  final String sender;
  final MailRadarCategory category;
  final bool enabled;

  static String senderAddress(String sender) =>
      RegExp(
        r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+',
      ).firstMatch(sender)?.group(0)?.toLowerCase() ??
      '';

  bool matches(MailRadarItem item) =>
      enabled && sender.isNotEmpty && senderAddress(item.sender) == sender;
  Map<String, Object> toJson() => {
    'sender': sender,
    'category': category.name,
    'enabled': enabled,
  };
}

class MailRadarRuleStore {
  const MailRadarRuleStore();
  String _key(String owner) =>
      'mail_radar_rules_${sha256.convert(utf8.encode(owner.trim().toLowerCase()))}';

  Future<List<MailRadarRule>> load(String owner) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = AccountHabits.shared.isFor(owner)
        ? jsonEncode(AccountHabits.shared.read<List>('mail.radar.rules', []))
        : prefs.getString(_key(owner));
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded
        .whereType<Map>()
        .map(
          (value) => MailRadarRule(
            sender: value['sender'] as String,
            category: MailRadarCategory.values.byName(
              value['category'] as String,
            ),
            enabled: value['enabled'] == true,
          ),
        )
        .toList();
  }

  Future<void> save(String owner, List<MailRadarRule> rules) async {
    if (rules.length > 100) throw const FormatException('最多保存100条分类规则。');
    if (AccountHabits.shared.isFor(owner)) {
      await AccountHabits.shared.set(
        'mail.radar.rules',
        rules.map((r) => r.toJson()).toList(),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _key(owner),
      jsonEncode(rules.map((rule) => rule.toJson()).toList()),
    )) {
      throw StateError('分类规则保存失败。');
    }
  }
}
