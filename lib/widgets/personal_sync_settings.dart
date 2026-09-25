import 'package:flutter/material.dart';

import '../l10n/bnbu_localizations.dart';
import '../state/account_habits.dart';
import '../state/personal_sync_controller.dart';

class PersonalSyncSettings extends StatelessWidget {
  const PersonalSyncSettings({super.key, required this.controller});
  final PersonalSyncController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, AccountHabits.shared]),
    builder: (context, _) {
      final error = controller.error ?? AccountHabits.shared.error;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            key: const ValueKey('personal-sync-status'),
            title: const BnbuText(
              '多端同步',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            ),
            trailing: BnbuText(
              controller.syncing
                  ? '同步中'
                  : error != null
                  ? '等待重试'
                  : controller.lastSyncedAt != null
                  ? '已同步'
                  : '自动同步',
            ),
          ),
          if (controller.syncing) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(liveRegion: true, child: BnbuText(error)),
                  TextButton(
                    onPressed: controller.syncing
                        ? null
                        : controller.ready
                        ? controller.synchronize
                        : controller.retryLoading,
                    child: const BnbuText('重试'),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}
