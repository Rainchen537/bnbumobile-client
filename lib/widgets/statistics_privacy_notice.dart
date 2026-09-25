import 'package:flutter/material.dart';

import '../l10n/bnbu_localizations.dart';
import '../services/app_statistics_service.dart';
import 'bnbu_notice.dart';

const statisticsLoginSummary =
    '本次隐私确认包含使用与提醒统计：同意并登录后默认开启，可在“通知与同步”关闭；此前关闭的选择保持不变。';
const statisticsPrivacyText =
    '同意后记录实际进入 App 的次数，以及系统能够确认已发出的课表和 DDL 提醒。仅上报随机事件标识、类型、时间、平台、版本与状态，不上传课程名、作业标题或通知正文。\n\n离线事件最多补报31天，明细去重记录保留90天，按日累计保留至账号或设备删除。Apple 提醒统计可能遗漏已清除的通知，不代表送达或已读。可随时关闭，关闭后停止采集并清除本机待报数据。';

/// Restored logins with no statistics choice see the new notice once, after unlock.
/// Existing agreements and withdrawals bypass it; nothing is collected beforehand.
class StatisticsLoginGate extends StatefulWidget {
  const StatisticsLoginGate({
    super.key,
    required this.service,
    required this.ready,
    required this.child,
  });

  final AppStatisticsService service;
  final bool ready;
  final Widget child;

  @override
  State<StatisticsLoginGate> createState() => _StatisticsLoginGateState();
}

class _StatisticsLoginGateState extends State<StatisticsLoginGate> {
  bool _busy = false;

  Future<void> _choose(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.service.setConsent(enabled);
    } catch (_) {
      if (mounted) {
        BnbuToast.show(context, '统计设置保存失败，请重试。', kind: BnbuToastKind.warning);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.service,
    builder: (context, _) {
      if (!widget.ready ||
          !widget.service.supported ||
          !widget.service.hasAccount ||
          widget.service.hasConsentChoice) {
        return widget.child;
      }
      final l10n = BnbuLocalizations.of(context);
      return Scaffold(
        key: const ValueKey('statistics-login-notice'),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.text('隐私说明更新'),
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 20),
                            Text(l10n.text('登录已恢复，请确认新增的使用与提醒统计说明。')),
                            const SizedBox(height: 20),
                            Text(l10n.text(statisticsPrivacyText)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: _busy ? null : () => _choose(false),
                          child: Text(l10n.text('暂不开启，继续')),
                        ),
                        FilledButton(
                          onPressed: _busy ? null : () => _choose(true),
                          child: Text(l10n.text('同意并继续')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
