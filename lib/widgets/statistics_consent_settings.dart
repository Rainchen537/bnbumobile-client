import 'package:flutter/material.dart';

import '../services/app_statistics_service.dart';
import '../l10n/bnbu_localizations.dart';
import 'bnbu_notice.dart';
import 'statistics_privacy_notice.dart';

/// A new processing purpose needs a new explicit choice, including restored accounts.
class StatisticsConsentSettings extends StatefulWidget {
  const StatisticsConsentSettings({super.key, required this.service});
  final AppStatisticsService service;
  @override
  State<StatisticsConsentSettings> createState() =>
      _StatisticsConsentSettingsState();
}

class _StatisticsConsentSettingsState extends State<StatisticsConsentSettings> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.service,
    builder: (context, _) => SwitchListTile.adaptive(
      title: Text(BnbuLocalizations.of(context).text('使用与提醒统计')),
      subtitle: Text(
        BnbuLocalizations.of(context).text(
          widget.service.consented
              ? (widget.service.needsProtocolUpdate
                    ? '统计上报暂不可用，待报数据已保留，请更新客户端'
                    : widget.service.appUsageEnabled ||
                          widget.service.remindersEnabled
                    ? '已同意，仅统计已接入的功能'
                    : '已同意，等待服务端启用')
              : '未同意，不采集统计事件',
        ),
      ),
      value: widget.service.consented,
      onChanged: _busy || !widget.service.hasAccount ? null : _change,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
  );

  Future<void> _change(bool enabled) async {
    setState(() => _busy = true);
    final owner = widget.service.owner;
    final epoch = widget.service.consentEpoch;
    try {
      if (enabled && !widget.service.hasConsentChoice) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(BnbuLocalizations.of(context).text('使用与提醒统计')),
            content: SingleChildScrollView(
              child: Text(
                BnbuLocalizations.of(context).text(statisticsPrivacyText),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(BnbuLocalizations.of(context).text('取消')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(BnbuLocalizations.of(context).text('同意')),
              ),
            ],
          ),
        );
        if (accepted != true || !mounted) return;
      }
      if (owner == null ||
          owner != widget.service.owner ||
          epoch != widget.service.consentEpoch ||
          !mounted) {
        return;
      }
      await widget.service.setConsent(enabled);
    } catch (_) {
      if (mounted) {
        BnbuToast.show(context, '统计设置保存失败，请重试。', kind: BnbuToastKind.warning);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
