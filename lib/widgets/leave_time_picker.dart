import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'bnbu_creation_form.dart';

/// A draft-only, 24-hour wheel picker. The editor writes HH:mm only on confirm;
/// school validation and duration calculation remain in the school form.
class LeaveTimePicker extends StatefulWidget {
  const LeaveTimePicker({
    super.key,
    required this.title,
    required this.initialTime,
  });

  final String title;
  final TimeOfDay initialTime;

  @override
  State<LeaveTimePicker> createState() => _LeaveTimePickerState();
}

class _LeaveTimePickerState extends State<LeaveTimePicker> {
  late final _hours = FixedExtentScrollController(
    initialItem: widget.initialTime.hour,
  );
  late final _minutes = FixedExtentScrollController(
    initialItem: widget.initialTime.minute,
  );
  late int _hour = widget.initialTime.hour;
  late int _minute = widget.initialTime.minute;

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Widget _wheel({
    required String label,
    required String id,
    required int count,
    required FixedExtentScrollController controller,
    required ValueChanged<int> onChanged,
  }) => Expanded(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BnbuText(
          label,
          style: TextStyle(
            color: context.bnbuTheme.textSecondary,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 176,
          child: Semantics(
            label: context.l10n.text(label),
            child: CupertinoPicker(
              key: ValueKey(id),
              scrollController: controller,
              itemExtent: (MediaQuery.textScalerOf(context).scale(22) + 18)
                  .clamp(44, double.infinity),
              onSelectedItemChanged: onChanged,
              children: [
                for (var value = 0; value < count; value++)
                  Center(
                    child: Text(
                      value.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: 22,
                        color: context.bnbuTheme.textPrimary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.bnbuTheme.surface,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BnbuText(
              widget.title,
              textAlign: TextAlign.center,
              style: BnbuCreationStyle.fieldText(
                context,
              ).copyWith(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                _wheel(
                  label: '小时',
                  id: 'leave-time-hour',
                  count: 24,
                  controller: _hours,
                  onChanged: (value) => _hour = value,
                ),
                const SizedBox(width: 16),
                _wheel(
                  label: '分钟',
                  id: 'leave-time-minute',
                  count: 60,
                  controller: _minutes,
                  onChanged: (value) => _minute = value,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: BnbuCreationAction(
                    label: '取消',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BnbuCreationAction(
                    label: '确定',
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(TimeOfDay(hour: _hour, minute: _minute)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
