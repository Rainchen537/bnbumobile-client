/// Uses the existing device session; never accepts another user's mailbox ID.
abstract interface class MailSourceService {
  Future<Map<String, dynamic>> mailSourceRequest(
    String username,
    String endpoint, {
    Map<String, dynamic>? body,
    bool Function()? isOperationActive,
  });
}

class MailSourceException implements Exception {
  const MailSourceException(this.code);
  final String code;
  @override
  String toString() => switch (code) {
    'mail_source_consent_required' => '请重新选择邮件雷达范围并确认数据使用说明。',
    'mail_source_device_approval_required' => '邮件信息源等待管理员确认此设备。',
    'provider_not_configured' ||
    'classifier_not_configured' => '邮件信息源等待配置分析服务。',
    'disabled' || 'mail_source_disabled' => '邮件信息源暂未启用。',
    'invalid_request' => '有邮件材料校验未通过，其他邮件继续处理。',
    'platform_budget_exceeded' => '邮件采集等待平台预算恢复，已分析结果仍可领取。',
    'analysis_schema_invalid' || 'analysis_evidence_invalid' => '邮件分析结果待后台核验。',
    'quota_exceeded' => '本次领取所需额度不足。',
    _ => '邮件信息源暂时无法处理（$code）。',
  };
}

class MailSourcePending implements Exception {
  const MailSourcePending();
}

class MailSourceSkipped implements Exception {
  const MailSourceSkipped();
}
