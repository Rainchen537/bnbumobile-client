import 'package:flutter/material.dart';
import '../models/leave_application_form.dart';
import '../theme/app_theme.dart';

/// School wording is rendered verbatim. Consent starts unchecked every time.
/// This widget neither writes a field nor submits a request on its own.
class LeaveApplicationReview extends StatefulWidget {
  const LeaveApplicationReview({super.key, required this.form});
  final LeaveApplicationForm form;

  @override
  State<LeaveApplicationReview> createState() => _LeaveApplicationReviewState();
}

class _LeaveApplicationReviewState extends State<LeaveApplicationReview> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    final completion = form.completion;
    return AlertDialog(
      title: const BnbuText('核对请假申请'),
      content: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .6,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${form.field('chineseName').display} · ${form.field('englishName').display}',
              ),
              Text(form.field('studentNo').display),
              Text(form.field('mobile').value),
              Text(form.field('familyPhone').value),
              const SizedBox(height: 16),
              Text(
                '${form.field('beginDate').value} ${form.field('beginTime').value} →\n${form.field('endDate').value} ${form.field('endTime').value}',
              ),
              Text(form.field('reason').display),
              Text(form.field('details').value),
              const SizedBox(height: 16),
              for (final row in form.courses)
                Text(
                  [
                    row['code'],
                    row['title'],
                    row['section'],
                    row['teacher'],
                    row['type'],
                    row['time'],
                  ].whereType<String>().join(' · '),
                ),
              for (final file in completion.files) Text(file.name),
              const Divider(height: 32),
              const BnbuText('申请须知'),
              for (final notice in completion.notices)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(notice),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(completion.declaration),
              ),
              CheckboxListTile(
                key: const ValueKey('leave-acknowledgement'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(completion.acknowledgement),
                value: _acknowledged,
                onChanged: completion.canSubmit
                    ? (value) => setState(() => _acknowledged = value == true)
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const BnbuText('返回修改'),
        ),
        FilledButton(
          key: const ValueKey('leave-confirm-submit'),
          onPressed: _acknowledged && completion.canSubmit
              ? () => Navigator.pop(context, true)
              : null,
          child: const BnbuText('确认提交给学校'),
        ),
      ],
    );
  }
}
