import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'traditional_chinese.dart';

class BnbuLocalizations {
  const BnbuLocalizations(this.locale);

  final Locale locale;

  // Flutter falls back to the first supported locale when the device locale
  // has no language match. Keep English first so international students with
  // another system language do not unexpectedly receive Chinese UI.
  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale('zh', 'CN'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('zh', 'TW'),
    Locale('zh', 'HK'),
    Locale('zh', 'MO'),
  ];

  static const LocalizationsDelegate<BnbuLocalizations> delegate =
      _BnbuLocalizationsDelegate();

  static BnbuLocalizations of(BuildContext context) {
    return Localizations.of<BnbuLocalizations>(context, BnbuLocalizations) ??
        const BnbuLocalizations(Locale('zh'));
  }

  bool get isEnglish => locale.languageCode == 'en';
  bool get isTraditionalChinese =>
      locale.languageCode == 'zh' &&
      (locale.scriptCode == 'Hant' ||
          locale.countryCode == 'TW' ||
          locale.countryCode == 'HK' ||
          locale.countryCode == 'MO');

  DateFormat dateTimeFormatter({bool fullMonth = false}) {
    if (isEnglish) {
      return DateFormat(
        '${fullMonth ? 'MMMM' : 'MMM'} d, yyyy, HH:mm',
        'en_US',
      );
    }
    return DateFormat('yyyy年M月d日 HH:mm');
  }

  String formatMonth(DateTime value) {
    if (isEnglish) {
      return DateFormat('MMM', 'en_US').format(value).toUpperCase();
    }
    return DateFormat('MM').format(value);
  }

  String formatMonthDay(DateTime value) {
    if (isEnglish) {
      return DateFormat('MMM d', 'en_US').format(value);
    }
    return DateFormat('M月d日').format(value);
  }

  String formatMonthDayTime(DateTime value) {
    if (isEnglish) {
      return DateFormat('MMM d, HH:mm', 'en_US').format(value);
    }
    return DateFormat('M月d日 HH:mm').format(value);
  }

  String formatMediumDate(DateTime value) {
    if (isEnglish) {
      return DateFormat('MMM d, yyyy', 'en_US').format(value);
    }
    return DateFormat('yyyy年M月d日').format(value);
  }

  String formatFullDate(DateTime value) {
    if (isEnglish) {
      return DateFormat('MMMM d, yyyy', 'en_US').format(value);
    }
    return DateFormat('yyyy年M月d日').format(value);
  }

  String formatMediumDateTime(DateTime value) =>
      dateTimeFormatter().format(value);

  String formatFullDateTime(DateTime value) =>
      dateTimeFormatter(fullMonth: true).format(value);

  String formatWeekday(DateTime value) {
    if (isEnglish) {
      return DateFormat('EEEE', 'en_US').format(value);
    }
    return const <String>[
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ][value.weekday - 1];
  }

  String formatMonthDayWithWeekday(DateTime value) {
    if (isEnglish) {
      return DateFormat('EEEE, MMMM d', 'en_US').format(value);
    }
    return '${formatMonthDay(value)} ${formatWeekday(value)}';
  }

  String text(String source) {
    if (source.isEmpty) return source;
    if (!isEnglish) {
      final chinese = _chinese[source] ?? source;
      return isTraditionalChinese
          ? (_traditionalOverrides[chinese] ?? toTraditionalChinese(chinese))
          : chinese;
    }
    final exact = _english[source];
    if (exact != null) return exact;
    return _translateDynamic(source);
  }

  String _translateDynamic(String source) {
    Match? match;
    match = RegExp(r'^对话分支 (\d+)，共 (\d+) 个$').firstMatch(source);
    if (match != null) return 'Chat branch ${match[1]} of ${match[2]}';
    match = RegExp(r'^小U提供了(\d+)个选项$').firstMatch(source);
    if (match != null) return 'MiU offers ${match[1]} options';
    match = RegExp(r'^已添加附件 (.+)$').firstMatch(source);
    if (match != null) return 'Attachment added: ${match[1]}';
    match = RegExp(r'^(添加|移除|附件|邮件) (.+)$').firstMatch(source);
    if (match != null) return '${text(match[1]!)} ${match[2]}';
    match = RegExp(r'^记忆(仅本机|等待同步|同步中|已同步)$').firstMatch(source);
    if (match != null) return 'Memory: ${text(match[1]!)}';
    match = RegExp(r'^(展开|收起|打开)小U AI 助手(，正在回复|，有新回复)?$').firstMatch(source);
    if (match != null) {
      final status = switch (match[2]) {
        '，正在回复' => ', responding',
        '，有新回复' => ', new response',
        _ => '',
      };
      return '${text(match[1]!)} MiU AI Assistant$status';
    }
    match = RegExp(r'^(.+) 的图片格式暂不支持。$').firstMatch(source);
    if (match != null) {
      return 'The image format of ${match[1]} is not supported.';
    }
    match = RegExp(r'^(.+) 的格式暂不支持。$').firstMatch(source);
    if (match != null) return 'The format of ${match[1]} is not supported.';
    match = RegExp(r'^(.+) 无法作为本机作业文件读取。$').firstMatch(source);
    if (match != null) {
      return '${match[1]} could not be read as a local assignment file.';
    }
    match = RegExp(r'^(.+) 超过允许的大小。$').firstMatch(source);
    if (match != null) return '${match[1]} exceeds the size limit.';
    match = RegExp(r'^(.+) 超过 (.+)。$').firstMatch(source);
    if (match != null) return '${match[1]} exceeds ${match[2]}.';
    match = RegExp(r'^(.+) 是空文件。$').firstMatch(source);
    if (match != null) return '${match[1]} is an empty file.';
    match = RegExp(
      r'^将提交 (\d+) 个答案字段并结束本次 attempt。提交后不可撤回。$',
    ).firstMatch(source);
    if (match != null) {
      return '${match[1]} answer fields will be submitted and this attempt will end. Submission cannot be undone.';
    }
    match = RegExp(r'^将保存 (\d+) 个答案字段，保留本次 attempt，尚不会交卷。$').firstMatch(source);
    if (match != null) {
      return '${match[1]} answer fields will be saved. This attempt will remain open and will not be submitted.';
    }
    match = RegExp(r'^最多保存 (\d+) 个地点$').firstMatch(source);
    if (match != null) return 'You can save up to ${match[1]} places';
    match = RegExp(r'^小U没有自动识别到(.+)，请手动核对$').firstMatch(source);
    if (match != null) {
      return 'MiU could not identify ${text(match[1]!)}. Check the selection manually';
    }
    match = RegExp(r'^小U已预选(.+)，其他文件保持未选$').firstMatch(source);
    if (match != null) {
      return 'MiU selected ${text(match[1]!)}. Other files remain unselected';
    }
    match = RegExp(r'^已去重 (\d+) 个重复文件$').firstMatch(source);
    if (match != null) return '${match[1]} duplicate files removed';
    match = RegExp(r'^已忽略 (\d+) 个非同源或无效地址$').firstMatch(source);
    if (match != null) return '${match[1]} external or invalid URLs excluded';
    match = RegExp(r'^文件较多，本次仅显示前 (\d+) 个，另有 (\d+) 个未列出$').firstMatch(source);
    if (match != null) {
      return 'Showing the first ${match[1]} files; ${match[2]} more are not listed';
    }
    match = RegExp(r'^一次最多选择 (\d+) 个文件。$').firstMatch(source);
    if (match != null) return 'Select up to ${match[1]} files at a time.';
    match = RegExp(
      r'^小U按“(.+)”匹配了 (\d+) 个文件(?:，已知总大小 (.+))?。$',
    ).firstMatch(source);
    if (match != null) {
      return 'MiU matched ${match[2]} files for “${text(match[1]!)}”${match[3] == null ? '' : ', known total size ${match[3]}'}.';
    }
    match = RegExp(r'^将在本机整理 (\d+) 个课程文件(?:，已知总大小 (.+))?。$').firstMatch(source);
    if (match != null) {
      return '${match[1]} course files will be organized on this device${match[2] == null ? '' : ', known total size ${match[2]}'}.';
    }
    match = RegExp(r'^正在整理 (\d+)/(\d+)：$').firstMatch(source);
    if (match != null) return 'Organizing ${match[1]}/${match[2]}:';
    match = RegExp(r'^已生成 (.+)，并保存到小U资源库。$').firstMatch(source);
    if (match != null) {
      return '${match[1]} was created and saved to the MiU Library.';
    }
    match = RegExp(r'^已生成 (.+)，可在课程页打开或存储。$').firstMatch(source);
    if (match != null) {
      return '${match[1]} was created. Open or save it from the course page.';
    }
    match = RegExp(r'^下载完成：(.+)$').firstMatch(source);
    if (match != null) return 'Download complete: ${match[1]}';
    match = RegExp(r'^已开始下载：(.+)$').firstMatch(source);
    if (match != null) return 'Download started: ${match[1]}';
    match = RegExp(r'^(\d+) 个超过 (.+)$').firstMatch(source);
    if (match != null) return '${match[1]} exceed ${match[2]}';
    match = RegExp(r'^(\d+) 个为空文件$').firstMatch(source);
    if (match != null) return '${match[1]} are empty';
    match = RegExp(r'^(\d+) 个无法读取$').firstMatch(source);
    if (match != null) return '${match[1]} could not be read';
    match = RegExp(r'^(\d+) 个超出 (.+) 总量$').firstMatch(source);
    if (match != null) return '${match[1]} exceed the ${match[2]} total limit';
    match = RegExp(r'^未能添加附件：(.+)$').firstMatch(source);
    if (match != null) {
      return 'Could not add attachments: ${match[1]!.split('、').map(text).join(', ')}';
    }
    match = RegExp(r'^已添加 (\d+) 个附件；(.+)未添加$').firstMatch(source);
    if (match != null) {
      return '${match[1]} attachments added; not added: ${match[2]!.split('、').map(text).join(', ')}';
    }
    match = RegExp(r'^草稿保存失败：(.+)$').firstMatch(source);
    if (match != null) return 'Could not save the draft: ${text(match[1]!)}';
    match = RegExp(r'^(收件人|抄送|密送)：(.+)$').firstMatch(source);
    if (match != null) return '${text(match[1]!)}: ${match[2]}';
    match = RegExp(r'^将“(.+)”恢复到原文件夹？$').firstMatch(source);
    if (match != null) return 'Restore “${match[1]}” to its original folder?';
    match = RegExp(r'^当前(.+)，切换为(.+)$').firstMatch(source);
    if (match != null) {
      return 'Current: ${text(match[1]!)}. Switch to ${text(match[2]!)}';
    }
    match = RegExp(r'^座位 (.+)$').firstMatch(source);
    if (match != null) return 'Seat ${match[1]}';
    match = RegExp(r'^当前时间 (.+)$').firstMatch(source);
    if (match != null) return 'Current time ${match[1]}';
    match = RegExp(r'^学号二维码 (.+)$').firstMatch(source);
    if (match != null) return 'Student ID QR code ${match[1]}';
    match = RegExp(r'^(.+)，可拖动合并或拆分窗口$').firstMatch(source);
    if (match != null) return '${match[1]}, drag to merge or split windows';
    match = RegExp(r'^选择页面\s+(\d+) / (\d+)$').firstMatch(source);
    if (match != null) return 'Select Pages  ${match[1]} / ${match[2]}';
    match = RegExp(r'^课件读取失败（HTTP (\d+)）。$').firstMatch(source);
    if (match != null) return 'Could not read courseware (HTTP ${match[1]}).';
    match = RegExp(r'^共 (\d+) 条日程$').firstMatch(source);
    if (match != null) return '${match[1]} schedules';
    match = RegExp(r'^导入文件中有 (\d+) 条日程与当前配置冲突。$').firstMatch(source);
    if (match != null) {
      return '${match[1]} schedules in the import conflict with your current settings.';
    }
    match = RegExp(
      r'^将新增 (\d+) 条、更新 (\d+) 条、删除 (\d+) 条。导入会按当前版本再次校验，不会直接覆盖整表。$',
    ).firstMatch(source);
    if (match != null) {
      return '${match[1]} schedules will be added, ${match[2]} updated, and ${match[3]} deleted. The import will be checked against the current version without overwriting the entire timetable.';
    }
    match = RegExp(
      r'^已导入：新增 (\d+) 条、更新 (\d+) 条、删除 (\d+) 条$',
    ).firstMatch(source);
    if (match != null) {
      return 'Imported: ${match[1]} added, ${match[2]} updated, ${match[3]} deleted';
    }
    match = RegExp(r'^回复 (\d+)$').firstMatch(source);
    if (match != null) return '${match[1]} replies';
    match = RegExp(r'^最大文件数：(.+)，单文件大小：(.+)$').firstMatch(source);
    if (match != null) {
      return 'Maximum files: ${match[1]}, size per file: ${text(match[2]!)}';
    }
    match = RegExp(r'^学生身份，(.+)，专业 (.+)，邮箱 (.+)$').firstMatch(source);
    if (match != null) {
      return 'Student identity, ${match[1]}, programme ${match[2]}, email ${match[3]}';
    }
    match = RegExp(r'^今天强调色(.+)$').firstMatch(source);
    if (match != null) return 'Today accent color: ${text(match[1]!)}';
    match = RegExp(r'^请输入 (.+) (分钟|小时)$').firstMatch(source);
    if (match != null) {
      return 'Enter ${match[1]} ${text(match[2]!).toLowerCase()}';
    }
    match = RegExp(r'^([\d.]+(?:–[\d.]+)?) (分钟|小时)$').firstMatch(source);
    if (match != null) return '${match[1]} ${text(match[2]!).toLowerCase()}';
    match = RegExp(r'^(\d+) 小时 (\d+) 分钟$').firstMatch(source);
    if (match != null) return '${match[1]} hr ${match[2]} min';
    match = RegExp(r'^(.+)头像$').firstMatch(source);
    if (match != null) return 'Avatar for ${match[1]}';
    match = RegExp(r'^整理于 (.+)$').firstMatch(source);
    if (match != null) return 'Compiled on ${match[1]}';
    match = RegExp(r'^(\d+) 星 (\d+) 条$').firstMatch(source);
    if (match != null) return '${match[1]} stars, ${match[2]} reviews';
    match = RegExp(r'^(.+) ([\d.]+) 分$').firstMatch(source);
    if (match != null) return '${text(match[1]!)} ${match[2]} out of 5';
    match = RegExp(r'^(.+)，截止时间 (.+)，(.+)$').firstMatch(source);
    if (match != null) {
      return '${text(match[1]!)}, due ${match[2]}, ${match[3]}';
    }
    match = RegExp(r'^(\d+) 条评价$').firstMatch(source);
    if (match != null) return '${match[1]} reviews';
    match = RegExp(r'^评价功能暂停至 (.+)$').firstMatch(source);
    if (match != null) return 'Reviews are paused until ${match[1]}';

    match = RegExp(r'^共 (\d+) 门课程$').firstMatch(source);
    if (match != null) return '${match[1]} courses';
    match = RegExp(r'^第 (\d+) 节 · (\d+) 个活动$').firstMatch(source);
    if (match != null) return 'Section ${match[1]} · ${match[2]} activities';
    match = RegExp(r'^(\d+) 个附件$').firstMatch(source);
    if (match != null) return '${match[1]} attachments';
    match = RegExp(r'^(\d+) 封未读$').firstMatch(source);
    if (match != null) return '${match[1]} unread';
    match = RegExp(r'^(\d+) 封$').firstMatch(source);
    if (match != null) return '${match[1]} messages';
    match = RegExp(r'^已选 (\d+) 封$').firstMatch(source);
    if (match != null) return '${match[1]} selected';
    match = RegExp(r'^已选 (\d+)/(\d+) 个$').firstMatch(source);
    if (match != null) return '${match[1]}/${match[2]} selected';
    match = RegExp(r'^剩余 (\d+) 天$').firstMatch(source);
    if (match != null) return '${match[1]} days left';
    match = RegExp(r'^仅剩 (\d+) 小时$').firstMatch(source);
    if (match != null) return '${match[1]} hours left';
    match = RegExp(r'^仅剩 (\d+) 分钟$').firstMatch(source);
    if (match != null) return '${match[1]} minutes left';
    match = RegExp(r'^(\d+) 分钟后$').firstMatch(source);
    if (match != null) return 'In ${match[1]} minutes';
    match = RegExp(r'^提前 (\d+) 分钟$').firstMatch(source);
    if (match != null) return '${match[1]} min early';
    match = RegExp(r'^提前 (\d+) 小时$').firstMatch(source);
    if (match != null) return '${match[1]} hr early';
    match = RegExp(r'^提前 (\d+) 小时 (\d+) 分钟$').firstMatch(source);
    if (match != null) return '${match[1]} hr ${match[2]} min early';
    match = RegExp(r'^DDL 通知已开启，将在截止前 (.+)提醒。$').firstMatch(source);
    if (match != null) {
      return 'Deadline notifications enabled. You will be notified ${text(match[1]!)} before the deadline.';
    }
    match = RegExp(r'^DDL 通知已开启，将智能安排 (\d+) 次提醒。$').firstMatch(source);
    if (match != null) {
      return 'Deadline notifications enabled with ${match[1]} smart reminders.';
    }
    match = RegExp(r'^智能提醒 · (\d+) 次$').firstMatch(source);
    if (match != null) return 'Smart · ${match[1]} reminders';
    match = RegExp(r'^(\d+) 次$').firstMatch(source);
    if (match != null) return '${match[1]} reminders';
    match = RegExp(r'^课表通知已开启，将在上课前 (.+)提醒。$').firstMatch(source);
    if (match != null) {
      return 'Class notifications enabled. You will be notified ${text(match[1]!)} before class.';
    }
    match = RegExp(r'^(\d+) 天$').firstMatch(source);
    if (match != null) return '${match[1]} days';
    match = RegExp(r'^(\d+) 小时$').firstMatch(source);
    if (match != null) return '${match[1]} hours';
    match = RegExp(r'^(\d+) 分钟$').firstMatch(source);
    if (match != null) return '${match[1]} minutes';
    match = RegExp(r'^(\d+)–(\d+) 分钟$').firstMatch(source);
    if (match != null) return '${match[1]}–${match[2]} minutes';
    match = RegExp(r'^请输入 (\d+)–(\d+) 分钟$').firstMatch(source);
    if (match != null) return 'Enter ${match[1]}–${match[2]} minutes';
    match = RegExp(r'^截止时间 (.+)$').firstMatch(source);
    if (match != null) return 'Due ${match[1]}';
    match = RegExp(r'^截止 (.+)$').firstMatch(source);
    if (match != null) return 'Due ${match[1]}';
    match = RegExp(r'^(.+) 所在周$').firstMatch(source);
    if (match != null) return 'Week of ${match[1]}';
    match = RegExp(r'^已选 (\d+) 周$').firstMatch(source);
    if (match != null) return '${match[1]} weeks selected';
    match = RegExp(r'^第 (\d+) 周$').firstMatch(source);
    if (match != null) return 'Week ${match[1]}';
    match = RegExp(r'^评价功能暂停至 (.+)$').firstMatch(source);
    if (match != null) return 'Reviews are suspended until ${match[1]}';
    match = RegExp(r'^发给 (.+)$').firstMatch(source);
    if (match != null) return 'To ${match[1]}';
    match = RegExp(r'^课程：(.+)$').firstMatch(source);
    if (match != null) return 'Course: ${match[1]}';
    match = RegExp(r'^类型：(.+)$').firstMatch(source);
    if (match != null) return 'Type: ${match[1]}';
    match = RegExp(r'^打开教师档案：(.+)$').firstMatch(source);
    if (match != null) return 'Open faculty profile: ${match[1]}';
    match = RegExp(r'^永久删除选中的 (\d+) 封邮件？$').firstMatch(source);
    if (match != null) {
      return 'Permanently delete ${match[1]} selected messages?';
    }
    match = RegExp(r'^将选中的 (\d+) 封邮件移到已删除？$').firstMatch(source);
    if (match != null) return 'Move ${match[1]} selected messages to Trash?';
    match = RegExp(r'^删除已选中的 (\d+) 封邮件？$').firstMatch(source);
    if (match != null) return 'Delete ${match[1]} selected messages?';
    match = RegExp(r'^将已选 (\d+) 封邮件恢复到原文件夹？$').firstMatch(source);
    if (match != null) return 'Restore ${match[1]} selected messages?';
    match = RegExp(r'^(.+)已开启$').firstMatch(source);
    if (match != null) return '${text(match[1]!)} enabled';
    match = RegExp(r'^(.+)已关闭$').firstMatch(source);
    if (match != null) return '${text(match[1]!)} disabled';
    match = RegExp(r'^章节 (\d+) · 活动 (\d+)$').firstMatch(source);
    if (match != null) return '${match[1]} sections · ${match[2]} activities';
    match = RegExp(r'^(\d+) 个文件 · (.+)$').firstMatch(source);
    if (match != null) return '${match[1]} files · ${match[2]}';
    match = RegExp(r'^共 (\d+) 个文件$').firstMatch(source);
    if (match != null) return '${match[1]} files';
    match = RegExp(r'^另有 (\d+) 个文件$').firstMatch(source);
    if (match != null) return '${match[1]} more files';
    match = RegExp(r'^分类：(.+)$').firstMatch(source);
    if (match != null) return 'Category: ${match[1]}';
    match = RegExp(r'^进度：(\d+)%$').firstMatch(source);
    if (match != null) return 'Progress: ${match[1]}%';
    match = RegExp(r'^(.+) 页面建设中$').firstMatch(source);
    if (match != null) return '${match[1]} is under construction';
    match = RegExp(r'^确定删除「(.+)」吗？$').firstMatch(source);
    if (match != null) return 'Delete “${match[1]}”?';
    match = RegExp(r'^导入文件中有 (\d+) 条 TA 课与当前配置冲突。$').firstMatch(source);
    if (match != null) {
      return '${match[1]} TA classes in the import conflict with current settings.';
    }
    match = RegExp(r'^将新增 (\d+) 条、更新 (\d+) 条、$').firstMatch(source);
    if (match != null) return 'Add ${match[1]} and update ${match[2]},';
    match = RegExp(r'^(\d+) 位$').firstMatch(source);
    if (match != null) return '${match[1]} people';
    match = RegExp(r'^(\d+) 项$').firstMatch(source);
    if (match != null) return '${match[1]} items';
    match = RegExp(r'^记忆候选\s+(\d+)$').firstMatch(source);
    if (match != null) return 'Memory Suggestions  ${match[1]}';
    match = RegExp(r'^小U上游暂时不可用 · (\d+) 封等待重试 · 可刷新立即重试$').firstMatch(source);
    if (match != null) {
      return 'MiU is temporarily unavailable · ${match[1]} messages waiting · Refresh to retry';
    }
    match = RegExp(r'^“(.+)”会从这台设备的小U资源库中删除。$').firstMatch(source);
    if (match != null) {
      return '“${match[1]}” will be deleted from the MiU Library on this device.';
    }
    match = RegExp(r'^小U没有找到符合“(.+)”的文件，$').firstMatch(source);
    if (match != null) {
      return 'MiU found no files matching “${text(match[1]!)}”,';
    }
    match = RegExp(r'^ZIP 已生成，但加入资源库失败：(.+)$').firstMatch(source);
    if (match != null) {
      return 'The ZIP was created but could not be added to the Library: ${match[1]}';
    }
    match = RegExp(
      r'^将离开 BNBU.ME 并打开 (.+)。外部网站可能收集访问和填写的信息，请注意隐私安全，不要提交邮箱密码、验证码或其他登录凭据。$',
    ).firstMatch(source);
    if (match != null) {
      return 'You are leaving BNBU.ME for ${match[1]}. External sites may collect information you view or enter. Protect your privacy and never submit your mail password, verification codes, or other sign-in credentials.';
    }
    match = RegExp(r'^(\d{4})年(\d+)月(\d+)日$').firstMatch(source);
    if (match != null) return '${match[2]}/${match[3]}/${match[1]}';
    match = RegExp(r'^(\d+)月(\d+)日 (\d{1,2}:\d{2})$').firstMatch(source);
    if (match != null) return '${match[1]}/${match[2]} ${match[3]}';
    match = RegExp(r'^(\d+)月(\d+)日 (周[一二三四五六日])$').firstMatch(source);
    if (match != null) {
      return '${text(match[3]!)} · ${match[1]}/${match[2]}';
    }
    match = RegExp(r'^近 (\d+) 天$').firstMatch(source);
    if (match != null) return 'Last ${match[1]} Days';
    match = RegExp(r'^(.+)失败：(.+)$').firstMatch(source);
    if (match != null) return '${text(match[1]!)} failed: ${text(match[2]!)}';
    match = RegExp(r'^已逾期 (.+)$').firstMatch(source);
    if (match != null) return 'Overdue by ${text(match[1]!)}';
    match = RegExp(r'^剩余 (.+)$').firstMatch(source);
    if (match != null) return '${text(match[1]!)} remaining';
    if (source.endsWith('\n下拉即可重新读取邮箱。')) {
      return '${text(source.substring(0, source.lastIndexOf('\n')))}\nPull down to reload the mailbox.';
    }
    match = RegExp(r'^选择(.+)$').firstMatch(source);
    if (match != null) return 'Select ${match[1]}';
    return source;
  }

  static const Map<String, String> _traditionalOverrides = {
    '本次将把 eCard 的照片、中英文姓名、学号、学院与学生身份，通过加密连接临时发送至 BNBU.ME 签发服务，仅用于生成钱包卡片。钱包不包含性别，本次不会上传性别；不写入数据库或日志，不发送学校密码、Cookie 或令牌。':
        '本次將把 eCard 的照片、中英文姓名、學號、學院與學生身份，透過加密連線暫時傳送至 BNBU.ME 簽發服務，僅用於產生錢包卡片。錢包不包含性別，本次不會上傳性別；不寫入資料庫或日誌，不傳送學校密碼、Cookie 或權杖。',
    '钱包保留独立副本，可能随你的 Apple 钱包设置同步至其他 Apple 设备；退出 BNBU.ME 不会自动移除，请在钱包中手动删除。资料仅为本次快照，不自动更新，不支持 NFC、门禁或支付。\n\n点按下方按钮表示同意本次传输，随后仍需在系统钱包界面确认添加。':
        '錢包保留獨立副本，可能依你的 Apple 錢包設定同步至其他 Apple 裝置；登出 BNBU.ME 不會自動移除，請在錢包中手動刪除。資料僅為本次快照，不自動更新，不支援 NFC、門禁或付款。\n\n點按下方按鈕表示同意本次傳輸，隨後仍需在系統錢包介面確認加入。',
    '设置仅保存在本机，不修改学校资料。钱包卡片不包含性别，已有卡片不自动更新。':
        '設定僅儲存在本機，不修改學校資料。錢包卡片不包含性別，已有卡片不自動更新。',
    '钱包服务需要更新，请稍后重试': '錢包服務需要更新，請稍後重試',
    '钱包中已有这张卡。更新条码需先在钱包移除旧卡，再重新添加。': '錢包中已有這張卡。更新條碼需先在錢包移除舊卡，再重新加入。',
    '学号 Code 39 条码': '學號 Code 39 條碼',
    '添加到 Apple 钱包': '加入 Apple 錢包',
  };

  static const Map<String, String> _english = <String, String>{
    '旧副本已隔离保留；本机已有内容继续可用。':
        'Previous copies are preserved in isolation. Existing local content remains available.',
    '逐条确认旧记忆': 'Review each previous memory',
    "ME 账户": "ME account",
    "绑定 ME 账户": "Link your ME account",
    "已绑定 ME 账户": "ME account linked",
    "邮箱验证码": "Email verification code",
    "获取验证码": "Send code",
    "验证并绑定": "Verify and link",
    "为什么需要绑定？": "Why link an account?",
    "学校登录请求由本机直接发送给学校。BNBU.ME 服务端不接收您的学校密码或登录令牌，因此需要通过邮箱验证码确认邮箱归属。绑定后可使用小U、评论及多端同步；课程、课表、DDL、普通邮箱、TA和自建日程可在本机直接使用。":
        "Your device signs in directly to school services. BNBU.ME does not receive your school password or sign-in tokens. Email verification confirms that you control the mailbox and enables Small U, comments and sync. Courses, timetables, deadlines, regular email, TA and personal events remain available locally.",
    "每台设备均需验证一次。重新安装或清除应用数据后需要重新验证，日常使用与正常升级无需重复操作。":
        "Verify once on each device. Reinstalling or clearing app data requires verification again. Normal use and updates keep your authorization.",
    "开启后同步本机的小U历史、记忆、个人日程和账号设置。关闭后保留本机与已有云端内容。":
        "Sync Small U history, memories, personal events and account settings. Turning sync off keeps existing local and cloud data.",
    "查看并恢复旧云端数据": "Review and recover previous cloud data",
    "管理已授权设备": "Manage authorized devices",
    "已授权设备": "Authorized devices",
    "撤销授权": "Revoke access",
    "当前设备": "This device",
    "恢复旧云端数据": "Recover previous cloud data",
    "恢复所选副本": "Recover selected copies",
    "小U对话历史": "Small U conversations",
    "日程、TA与账号设置": "Events, TA and account settings",

    "雷达记录": "Radar records",
    "没有待恢复的旧云端数据": "No previous cloud data to recover",
    "旧云端记录会保留。恢复只补充新账户中尚不存在的副本；已有新数据不会被替换。旧记录的来源未经当时的邮箱验证，请确认后选择需要恢复的内容。":
        "Previous cloud records are retained. Recovery only adds copies that do not yet exist in your new account. Existing new data is kept. These older records were created before email verification; choose what you want to recover.",
    "本机对话已保留。绑定 ME 账户后可继续提问。":
        "Your local conversations are retained. Link your ME account to continue chatting.",
    "绑定 ME 账户，继续使用小U": "Link your ME account to use Small U",
    "登录账号已变化，请返回当前账号重新操作。":
        "The signed-in account changed. Return to the current account and try again.",
    "请先绑定 ME 账户后使用此功能": "Link your ME account to use this feature",
    "邮箱验证尚未开放，请稍后再试。":
        "Email verification is not available yet. Please try again later.",
    "验证邮件发送失败，请稍后重试。":
        "The verification email could not be sent. Please try again later.",
    "验证码错误或已过期，请重新获取。":
        "The code is incorrect or has expired. Request a new code.",
    "操作过于频繁，请稍后再试。": "Too many attempts. Please try again later.",
    "多端同步设置": "Sync settings",

    '该链接暂不支持在应用内打开。': 'This link cannot be opened in the app yet.',

    '性别显示': 'Gender display',
    '个人资料显示': 'Profile display',
    '显示性别': 'Show gender',
    '在 eCard 上显示性别': 'Show gender on eCard',
    '男性': 'Man',
    '女性': 'Woman',
    '非二元性别／性别流动': 'Non-binary / Genderfluid',
    '跨性别女性': 'Trans woman',
    '跨性别男性': 'Trans man',
    '其他／自定义': 'Self-describe',
    '不展示': 'Don’t show',
    '自定义性别': 'Describe your gender',
    '请输入1–40个字符，不含换行或控制字符':
        'Enter 1–40 characters without line breaks or control characters.',
    '设置仅保存在本机，不修改学校资料。钱包卡片不包含性别，已有卡片不自动更新。':
        'Settings stay on this device and do not change school records. Wallet passes do not include gender. Existing passes do not update automatically.',
    '性别显示设置暂不可用，请重试': 'Gender display settings are unavailable. Please retry.',
    '正在读取性别显示设置': 'Loading gender display settings',
    '钱包服务需要更新，请稍后重试':
        'The Wallet service needs to be updated. Please try again later.',
    '本次将把 eCard 的照片、中英文姓名、学号、学院与学生身份，通过加密连接临时发送至 BNBU.ME 签发服务，仅用于生成钱包卡片。钱包不包含性别，本次不会上传性别；不写入数据库或日志，不发送学校密码、Cookie 或令牌。':
        'For this request, your eCard photo, Chinese and English names, student ID, college and student identity will be sent over an encrypted connection to the BNBU.ME signing service solely to create a Wallet pass. Wallet passes do not include gender, and gender will not be uploaded. Card content is not saved in a database or logs. School passwords, cookies and tokens are never sent.',
    '钱包保留独立副本，可能随你的 Apple 钱包设置同步至其他 Apple 设备；退出 BNBU.ME 不会自动移除，请在钱包中手动删除。资料仅为本次快照，不自动更新，不支持 NFC、门禁或支付。\n\n点按下方按钮表示同意本次传输，随后仍需在系统钱包界面确认添加。':
        'Wallet keeps a separate copy and may sync it to other Apple devices according to your Wallet settings. Signing out of BNBU.ME does not remove it; remove it manually in Wallet. This is a snapshot without automatic updates, NFC, access control or payment capability.\n\nTapping the button below consents to this transfer. You must then confirm adding the pass in the system Wallet screen.',
    '添加到 Apple 钱包': 'Add to Apple Wallet',
    '已添加到 Apple 钱包': 'Added to Apple Wallet',
    '钱包中已有这张卡。更新条码需先在钱包移除旧卡，再重新添加。':
        'This pass is already in Wallet. Remove the old pass in Wallet before adding the new barcode.',
    '请等待 eCard 资料加载完成': 'Please wait for your eCard to finish loading.',
    '钱包签发服务尚未就绪，暂时无法添加':
        'Wallet issuance is not ready yet. The card cannot be added at this time.',
    '无法生成钱包卡片，请刷新 eCard 后重试':
        'Unable to create the pass. Refresh your eCard and try again.',
    '钱包请求未完成，请稍后重试':
        'The Wallet request did not complete. Please try again later.',
    '登录状态已变化，请重新打开 eCard':
        'Your sign-in session has changed. Open eCard again.',
    '钱包正在处理中': 'Processing Wallet request',
    '绩点': 'GPA',
    '累计 GPA': 'Cumulative GPA',
    '学期 GPA': 'Semester GPA',
    '修读学分': 'Units attempted',
    '获得学分': 'Units gained',
    '加权绩点': 'Weighted grade points',
    '等级': 'Grade',
    '全部学期': 'All semesters',
    '暂无成绩': 'No grades available',
    '学校成绩暂不可用': 'School grades are currently unavailable',
    '绩点读取失败，请重试': 'Unable to load grades. Please try again.',
    '登录状态已变化，请重新打开绩点': 'Your sign-in session has changed. Open GPA again.',
    '打卡查看': 'Check-in overview',
    '打卡项目': 'Projects',
    '打卡记录': 'Check-in history',
    '打卡进度': 'Check-in progress',
    '已打卡': 'Checked in',
    '要求次数': 'Required',
    '学校未提供': 'Not provided by the school',
    '主讲人': 'Speaker',
    '场次': 'Session',
    '活动时间': 'Event time',
    '签到': 'Check-in',
    '签退': 'Check-out',
    '签到时间': 'Check-in time',
    '签退时间': 'Check-out time',
    '选择项目查看打卡记录': 'Select a project to view its records',
    '暂无符合条件的打卡项目': 'No matching check-in projects',
    '暂无已统计的打卡记录': 'No finalized check-in records',
    '学校暂未提供可确认的统计状态':
        'The school has not provided a verifiable statistics status',
    '打卡系统认证未通过，请在学校系统核对账号或额外验证要求。':
        'Check-in authentication failed. Check your account or additional verification requirements in the school system.',
    '当前账号暂无打卡系统访问权限。': 'This account cannot access the school check-in system.',
    '暂时无法连接学校打卡系统，请稍后重试。':
        'The school check-in system is unavailable. Please try again later.',
    '学校打卡数据格式暂不支持，请稍后重试。':
        'The school check-in data could not be read. Please try again later.',
    '登录状态已变化，请重新打开打卡查看。':
        'Your login has changed. Please reopen the check-in overview.',
    'ME生活': 'ME Life',
    'ME评分': 'ME Rating',
    '个性化': 'Personalization',
    'iSpace头像': 'iSpace photo',
    '学校当前未开放头像修改': 'iSpace has not enabled photo updates',
    '头像读取失败': 'Unable to load photo',
    'iSpace头像已更新': 'iSpace photo updated',
    '头像更新未确认，请刷新查看后重试':
        'Photo update could not be confirmed. Refresh before retrying.',
    '裁剪头像': 'Crop photo',
    '使用': 'Use',
    '更新将同步到iSpace': 'This updates your iSpace photo',
    '暂未到可修改评分时间，请稍后重试':
        'You can change your rating after the current waiting period',
    '评分每24小时只能修改一次': 'You can change your rating once every 24 hours',
    '请升级客户端后使用ME生活': 'Update the app to use ME Life',
    '评分已保存': 'Rating saved',
    '评分保存未确认，请刷新查看': 'Rating could not be confirmed. Refresh to check.',
    '匿名身份': 'Anonymous identity',
    '匿名发布': 'Post anonymously',
    '匿名用户': 'Anonymous user',
    '公开显示iSpace姓名与头像': 'Show your iSpace name and photo publicly',
    '无法读取iSpace身份，请稍后重试':
        'Unable to read your iSpace identity. Try again later.',
    '写下你的评论': 'Write your review',
    '回复内容': 'Reply',
    '删除失败，请刷新后重试': 'Unable to delete. Refresh and try again.',
    '请输入评论内容': 'Enter your review',
    '发布未确认，内容已保留，请重试':
        'Publication could not be confirmed. Your draft is retained.',
    '正在保存': 'Saving',
    '操作失败，请重试': 'Unable to complete the action. Try again.',
    '回复加载失败': 'Unable to load replies',
    '我的评论': 'My review',
    '精选': 'Featured',
    '待审核': 'Pending review',
    '有用': 'Helpful',
    '查看回复': 'View replies',
    '立即评分': 'Rate now',
    '评论': 'Reviews',
    '最有用': 'Most helpful',
    '热评': 'Top comments',
    '全部评论': 'All comments',
    '最晚': 'Newest',
    '公开身份': 'Public identity',
    '最早': 'Oldest',
    '暂无评论': 'No reviews yet',
    '编辑我的评论': 'Edit my review',
    '写评论': 'Write a review',
    '评论暂为只读': 'Reviews are temporarily read-only',
    '分享暂不可用': 'Sharing is temporarily unavailable',
    '评论当前不可分享': 'This review cannot be shared',
    '分享生成失败，请重试': 'Unable to create the poster. Try again.',
    '分享未完成，请重试': 'Sharing did not complete. Try again.',
    '多端同步': 'Sync across devices',
    '自动同步': 'Automatic sync',

    '同意并开启': 'Agree and enable',

    '重试删除': 'Retry deletion',
    "习惯设置读取失败，请重试。": "Could not load account preferences. Please retry.",
    "习惯设置尚未保存，请重试。": "Account preferences have not been saved. Please retry.",
    "本机已停止，账号停用等待联网同步。":
        "Stopped on this device. Account-wide disable is waiting for a connection.",
    "本机已停止，其他设备更新过雷达设置，请再次选择不使用以确认账号停用。":
        "Stopped on this device. Another device changed radar settings. Select Do not use again to confirm account-wide disable.",
    "服务端尚未支持可靠删除同步，本机删除已保留。":
        "The server does not yet support reliable deletion sync. Your local deletion is preserved.",
    "历史删除记录已达上限，请联系维护者。":
        "History deletion records have reached the limit. Please contact the maintainer.",
    '同步设置读取失败，请重试。': 'Could not load sync settings. Please try again.',
    '同步暂未完成，稍后自动重试。': 'Sync is incomplete. It will retry automatically.',
    '管理课程': 'Manage courses',
    '保存中': 'Saving',
    '课程显示名称': 'Course display name',
    '已保存到本机': 'Saved on this device',
    '课程名称最多150个字符，不能包含换行或控制字符':
        'Use up to 150 characters, without line breaks or control characters.',
    '课程名称自动保存；顺序和隐藏状态点击保存后同步。隐藏不会关闭 DDL 提醒。':
        'Course names save automatically. Save order and visibility changes separately. Hiding does not turn off deadline reminders.',
    '更改显示名称': 'Rename for me',
    '恢复原名': 'Restore original name',
    '隐藏课程': 'Hide course',
    '恢复显示': 'Show course',
    '已隐藏': 'Hidden',
    '课程选项': 'Course options',
    '拖动排序': 'Drag to reorder',
    '上移': 'Move up',
    '下移': 'Move down',
    '未能保存，请重试': 'Could not save. Please retry.',
    '本机保存失败，请重试': 'Local save failed. Please retry.',
    '已保存在本机，等待同步': 'Saved on this device; sync pending',
    '暂时无法同步': 'Sync temporarily unavailable',
    '保存后将课程标识、显示名、顺序及隐藏状态同步到同账号设备。隐藏不会关闭 DDL 提醒。':
        'Saving syncs course IDs, display names, order and visibility across your devices. Hiding a course does not turn off deadline reminders.',
    '接入学校邮箱': 'Connect school mail',
    '邮箱密码': 'Mail password',
    'iSpace 已登录。邮箱密码可以不同，也可以稍后在邮箱页接入。':
        'You are signed in to iSpace. Your mail password may be different. You can connect later in Mail.',
    '验证并接入': 'Verify and connect',
    '暂不接入邮箱': 'Skip mail for now',
    '重试连接': 'Retry connection',
    '邮箱验证失败，请输入邮箱密码；也请确认学校邮箱已开通。':
        'Mail sign-in was rejected. Enter your mail password and check that your school mailbox is activated.',
    '暂时无法连接邮箱，请检查网络后重试。iSpace 登录不受影响。':
        'Mail is temporarily unreachable. Check your connection and retry. Your iSpace sign-in is unaffected.',
    '邮箱设置仅在本次会话生效，安全存储失败，请稍后重试。':
        'Mail settings are active for this session only. Secure storage failed; please try again later.',
    '邮箱服务暂时不可用，请稍后重试。':
        'Mail is temporarily unavailable. Please try again later.',
    '此平台暂时无法验证邮箱。': 'Mail verification is unavailable on this platform.',
    '本次隐私确认包含使用与提醒统计：同意并登录后默认开启，可在“通知与同步”关闭；此前关闭的选择保持不变。':
        'This privacy agreement includes app usage and reminder statistics. These are enabled after you agree and sign in, and can be turned off in Notifications & Sync. A previous choice to turn them off is preserved.',
    '统计隐私说明': 'Statistics privacy details',
    '隐私说明更新': 'Privacy notice update',
    '登录已恢复，请确认新增的使用与提醒统计说明。':
        'Your sign-in has been restored. Please review the new app usage and reminder statistics notice.',
    '暂不开启，继续': 'Continue without statistics',
    '同意并继续': 'Agree and continue',
    '使用与提醒统计': 'App Usage & Reminder Statistics',
    '统计上报暂不可用，待报数据已保留，请更新客户端':
        'Reporting unavailable. Pending data is retained; please update the app.',
    '已同意，仅统计已接入的功能': 'Enabled for integrated features only',
    '已同意，等待服务端启用': 'Consented; waiting for server activation',
    '未同意，不采集统计事件': 'Off; no statistics events collected',
    '统计设置保存失败，请重试。': 'Could not save statistics preferences. Please retry.',
    '同意后记录实际进入 App 的次数，以及系统能够确认已发出的课表和 DDL 提醒。仅上报随机事件标识、类型、时间、平台、版本与状态，不上传课程名、作业标题或通知正文。\n\n离线事件最多补报31天，明细去重记录保留90天，按日累计保留至账号或设备删除。Apple 提醒统计可能遗漏已清除的通知，不代表送达或已读。可随时关闭，关闭后停止采集并清除本机待报数据。':
        'With your consent, we record actual app entries and timetable and deadline notifications whose issuance the system can confirm. Only random event identifiers, type, time, platform, version and status are reported, never course names, assignment titles or notification text.\n\nOffline events can be reported for up to 31 days; raw deduplication records are kept for 90 days. Daily totals remain until the account or device is deleted. Apple statistics may miss cleared notifications and do not indicate receipt or reading. You can turn this off at any time to stop collection and clear pending local events.',
    '移除': 'Remove',
    '确认后会按“章节 / 活动 / 文件名”生成 ZIP 并保存到小U资源库。登录 Cookie 只会发送到 iSpace 同源地址，文件正文不会交给小U服务端。':
        'After confirmation, a ZIP organized by section, activity, and filename will be saved to the MiU Library. Sign-in cookies are sent only to the same iSpace origin. File contents are not sent to the MiU server.',
    '已加入下载任务': 'Download Queued',
    '下载完成': 'Download Complete',
    '下载未完成，请重试': 'Download incomplete. Try again.',
    '章节说明': 'Section Details',
    '下载本组': 'Download Group',
    '下载本页文件': 'Download Page Files',
    '查看原页面': 'View Original Page',
    '下载全部课件': 'Download courseware',
    '下载并生成 ZIP': 'Download ZIP',
    '保存 ZIP': 'Save ZIP',
    'iSpace 单个下载位置': 'iSpace file download location',
    '全部下载位置': 'Courseware download location',
    '请选择下载文件夹': 'Choose a download folder',
    '恢复系统下载目录': 'Reset to system Downloads',
    '下载位置不可用，请重新选择文件夹。':
        'Download location unavailable. Choose a folder again.',
    '文件已保存到下载位置': 'File saved to the download location',
    '正在下载文件…': 'Downloading file…',
    '文件下载失败，请检查网络和下载位置后重试。':
        'Download failed. Check the network and download location, then retry.',
    '下载此文件': 'Download this file',
    '取消下载': 'Cancel download',
    '全选': 'Select all',
    '重新读取': 'Reload',
    '正在读取课件清单…': 'Loading courseware…',
    '正在保存…': 'Saving…',
    '正在下载并打包…': 'Downloading and creating ZIP…',
    'ZIP 已生成': 'ZIP is ready',
    'ZIP 已保存到所选位置': 'ZIP saved to the selected location',
    '已保存到本机小U资源库': 'Saved to the local MiU library',
    '登录状态已变化，请重新打开课程页面。': 'Your session changed. Reopen the course.',
    '无法读取课件清单，请重试。': 'Could not load courseware. Try again.',
    '课件清单已变化，请重新选择。': 'Courseware has changed. Review your selection.',
    '下载会话无效。': 'The download session is invalid.',
    'ZIP 已生成，但保存到资源库失败。':
        'ZIP is ready, but could not be added to the library.',
    '课件下载未完成，请重试。': 'The download did not finish. Try again.',
    'ZIP 保存失败，请重试。': 'Could not save ZIP. Try again.',
    '无法打开 ZIP，请先保存到本机。': 'Could not open ZIP. Save it to your device first.',
    '部分课程页面读取失败，清单可能不完整。':
        'Some course pages could not be read. This list may be incomplete.',
    '非同源或不安全的文件链接已排除。': 'External or unsafe file links were excluded.',
    '当前课程没有可下载的课件。': 'No downloadable courseware was found.',
    '按章节生成 ZIP，仅保存到本机，单次最多 512 MB。':
        'ZIP organized by section. Stored locally, up to 512 MB per download.',
    '课件超过单次 100 个文件上限，请使用单文件下载。':
        'This course exceeds the 100-file limit. Download files individually.',
    '文件链接返回了网页，无法作为课件下载。':
        'This link returned a web page instead of a course file.',
    '文件下载暂时失败，请重试。': 'The file download failed temporarily. Try again.',
    '文件访问被拒绝，请检查登录状态或课程权限。':
        'File access was denied. Check your session or course permissions.',
    '文件暂时不可用，请稍后重试。': 'This file is unavailable. Try again later.',
    '课程文件的下载地址不安全。': 'The course file URL is unsafe.',
    '没有文件下载成功，请重试失败项。': 'No files were downloaded. Retry failed files.',
    '重试失败项': 'Retry failed files',
    '部分课件已打包': 'Partial ZIP is ready',
    '未下载的文件': 'Files not downloaded',
    '已下载': 'Downloaded',
    '课程文件总大小超过 512 MB。': 'Course files exceed the 512 MB limit.',
    '课程文件打包失败，请稍后重试。': 'Could not create the course ZIP. Try again later.',
    '课程文件内容为空。': 'The downloaded file is empty.',
    '下载跳转离开了 iSpace，已阻止。': 'A redirect outside iSpace was blocked.',
    '课程文件下载跳转无效。': 'The file redirect is invalid.',
    '课程文件下载跳转过多。': 'Too many file redirects.',
    'iSpace 登录状态已失效，请重新登录。': 'Your iSpace session expired. Sign in again.',
    '登录状态已变化，已停止打包。': 'Your session changed. ZIP creation stopped.',
    '登录状态已变化，已停止下载。': 'Your session changed. The download stopped.',
    '下载已取消。': 'Download cancelled.',
    '雷达同步容量已满，新增记录保留在本机。':
        'Radar sync capacity is full. New records remain on this device.',
    '操作未保存，请重试。': 'Changes were not saved. Try again.',
    '请选择未来时间。': 'Choose a future time.',
    '立即处理': 'Act now',
    '北京时间': 'Beijing time',
    '主题相关': 'Related subject',
    '同一邮件往来': 'Same thread',
    '移回待处理': 'Move to to-do',
    '标记完成': 'Mark complete',
    '邮件已由你确认发送，邮件服务器已接受发送请求。':
        'You confirmed sending the email and the mail server accepted it.',
    '草稿已保存，尚未发送。': 'The draft is saved and has not been sent.',
    '你已关闭此次操作。': 'You closed this operation.',
    '此次操作未完成，请检查后重试。':
        'The operation did not complete. Review it before retrying.',
    '提醒已登记到本机通知。': 'The reminder is registered on this device.',
    '附件已下载，设备没有可打开此类型文件的应用。':
        'Attachment downloaded. No app is available to open this file type.',
    '附件已下载，请先关闭当前文件或分享菜单后重试。':
        'Attachment downloaded. Close the current file or share menu and try again.',
    '附件已下载，暂时无法打开。请回到邮件页面后重试。':
        'Attachment downloaded but could not open. Return to the email and try again.',
    '附件下载失败，请稍后重试。': 'Attachment download failed. Please try again later.',
    '文件超过当前下载大小上限。': 'The file exceeds the download size limit.',
    '查看原始样式': 'View original appearance',
    '适应当前主题': 'Use app appearance',
    '文件读取失败，重试': 'Could not load file. Try again.',
    '本机文件不可用，请返回重新下载。': 'File unavailable. Go back and download it again.',
    '无法打开这个文件。': 'Could not open this file.',
    '用其他应用打开': 'Open in another app',
    '此文件暂不支持内嵌预览': 'An inline preview is unavailable for this file.',
    '文件操作未完成，请重试。': 'The file action could not complete. Please try again.',
    '保存文件': 'Save file',
    '保存或分享': 'Save or share',
    '文件已下载到本机。': 'The file is downloaded to this device.',
    '已打开目标页面。': 'The requested page was opened.',
    '作业已最终提交并核对状态。':
        'The assignment was submitted and its final status was verified.',
    '作业草稿已保存，尚未最终提交。':
        'The assignment draft is saved but has not been submitted.',
    'iSpace已接受作业更新。': 'iSpace accepted the assignment update.',
    '处理状态': 'Task status',
    '等待回复': 'Waiting for reply',
    '稍后处理': 'Snoozed',
    '已取消': 'Cancelled',
    '待处理': 'To do',
    '读取范围': 'Read coverage',
    '完整读取': 'Fully read',
    '部分读取': 'Partially read',
    '未读取': 'Not read',
    '覆盖范围未知': 'Coverage unknown',
    '时间原文': 'Deadline source',
    '分类规则': 'Category rules',
    '暂无分类规则': 'No category rules',
    '应用范围': 'Apply to',
    '只改这封': 'This message only',
    '同一发件人的新邮件': 'New messages from this sender',
    '后续更新': 'Later update',
    '查看最新往来': 'Open latest message',

    'BNBU.ME': 'BNBU.ME',
    '首页': 'Home',
    '邮箱': 'Mail',
    '课表': 'Timetable',
    '我的': 'Me',
    '连接你的校园生活': 'Your campus life, connected',
    '非官方客户端': 'Unofficial client',
    '我已阅读并接受 ': 'I have read and accept ',
    '隐私政策': 'Privacy Policy',
    '接受隐私政策': 'Accept the Privacy Policy',
    '请先阅读并接受隐私政策': 'Please read and accept the Privacy Policy first',
    '是否同意隐私政策并继续登录？':
        'Do you agree to the Privacy Policy and continue signing in?',
    '阅读隐私政策': 'Read the Privacy Policy',
    '同意并登录': 'Agree & Sign In',
    '北京师范大学-香港浸会大学联合国际学院': 'Beijing Normal-Hong Kong Baptist University',
    '收起侧边栏': 'Collapse sidebar',
    '展开侧边栏': 'Expand sidebar',
    '刷新': 'Refresh',
    '重试': 'Retry',
    '取消': 'Cancel',
    '确定': 'Confirm',
    '确认': 'Confirm',
    '关闭': 'Close',
    '显示密码': 'Show password',
    '隐藏密码': 'Hide password',
    '保存': 'Save',
    '编辑': 'Edit',
    '删除': 'Delete',
    '恢复': 'Restore',
    '清空': 'Clear',
    '返回': 'Back',
    '继续': 'Continue',
    '下一步': 'Next',
    '完成': 'Done',
    '打开': 'Open',
    '复制': 'Copy',
    '已复制': 'Copied',
    '发送': 'Send',
    '预览': 'Preview',
    '加载更多': 'Load more',
    '搜索失败': 'Search failed',
    '同步中': 'Syncing',
    '重试加载': 'Retry loading',
    '打开 ZIP': 'Open ZIP',
    '课程内容为空': 'No course content',
    '当前课程没有可安全批量下载的文件。':
        'This course has no files available for safe batch download.',
    '选择课程文件': 'Select Course Files',
    '确认后会按“章节 / 活动 / 文件名”生成 ZIP 并保存到小U资源库。':
        'After confirmation, a ZIP will be organized by section, activity, and file name, then saved to the MiU Library.',
    '生成 ZIP': 'Create ZIP',
    '登录状态已失效，请重新登录后下载。': 'Your session has expired. Sign in again to download.',
    '批量下载准备失败，请稍后重试。': 'Could not prepare the batch download. Try again later.',
    '该活动类型的完整原生交互正在搬运中，当前优先支持 Assignment。':
        'Full native interaction for this activity type is still in progress. Assignment is currently supported first.',
    '小程序码暂时无法处理，请刷新后重试。':
        'The mini-program code could not be processed. Refresh and try again.',
    '清除朵朵登录数据？': 'Clear Duoduo Sign-in Data?',
    '这只会清除朵朵校园墙在本机保存的网页登录状态，不影响学校账号。':
        'This only clears Duoduo web sign-in data stored on this device. Your school account is not affected.',
    '清除': 'Clear',
    '朵朵隐私政策': 'Duoduo Privacy Policy',
    '清除朵朵登录数据': 'Clear Duoduo Sign-in Data',
    '微信授权登录': 'Sign in with WeChat',
    '先保存小程序码并打开微信，在扫一扫中从相册识别；授权后返回即可继续登录。':
        'Save the mini-program code and open WeChat. Scan it from Photos, authorize, then return to continue.',
    '保存并打开微信': 'Save & Open WeChat',
    '课件无法预览': 'Course material cannot be previewed',
    '学业窗口暂时无法打开，请重试。': 'The study window could not open. Try again.',
    '当前资源没有可用的下载地址。': 'This resource has no available download URL.',
    '正在准备下载，请稍候…': 'Preparing download…',
    '分享文件失败，请稍后重试。': 'Could not share the file. Try again later.',
    '正在同步课表…': 'Syncing schedule…',
    '暂无后续课程': 'No upcoming classes',
    '登录后查看下一门课': 'Sign in to view your next class',
    '同步失败': 'Sync failed',
    '教室待确认': 'Room to be confirmed',
    '下一门课': 'Next class',
    '下一节课': 'Next class',
    '打开完整课表': 'Open full schedule',
    '正在同步 DDL…': 'Syncing deadlines…',
    '暂无待办 DDL': 'No upcoming deadlines',
    '登录后查看下一个 DDL': 'Sign in to view your next deadline',
    '下一个 DDL': 'Next deadline',
    '打开作业详情和提交入口': 'Open assignment details',
    '政教信息': 'Campus Directory',
    '统一门户': 'Student Portal',
    '校园地标': 'Campus Landmarks',
    '查看位置': 'View location',
    '校园导航': 'Campus Map',
    '官方地图': 'Official Map',
    '官方校园地图': 'Official Campus Map',
    'MIS 教务': 'MIS',
    'MIS 教务系统': 'MIS Academic System',
    '公开目录': 'Public Directory',
    '学校公开目录': 'BNBU Public Directory',
    '校历': 'Academic Calendar',
    '请假申请': 'Leave Request',
    '其他时段课程': 'Other course times',
    '选课尚未确认，请重新读取。': 'Selection pending. Check again.',
    '课程已加入，请重新读取。': 'Course added. Check again to continue.',
    '课程读取失败，请重试。': 'Could not load courses. Try again.',
    '重叠课程': 'Overlapping classes',
    '门课': 'classes',
    '返回课表': 'Back to timetable',
    '已选': 'Selected',
    '课程已加入，请返回表单后继续选择。':
        'Course added. Return to the form to continue selecting.',
    '学期': 'Semester',
    '学号': 'Student ID',
    '开始日期': 'Start date',
    '结束日期': 'End date',
    '选择': 'Select',
    '放弃': 'Discard',
    '学校原表': 'School form',
    '返回表单': 'Back to form',
    '申请人资料': 'Applicant',
    '申请开放时间': 'Applications open',
    '申请截止时间': 'Applications close',
    '中文姓名': 'Chinese name',
    '英文姓名': 'English name',
    '手机号码': 'Mobile phone number',
    '家人联系电话': 'Family contact number',
    '请假详情': 'Leave details',
    '请假类型': 'Reason',
    '请假原因（英文）': 'Reason details (in English)',
    '学校核算天数': 'Days calculated by school',
    '待学校核算': 'Pending school calculation',
    '涉及课程与教师': 'Courses and teachers',
    '选择课程与教师': 'Select courses and teachers',
    '移除此课程？': 'Remove this course?',
    '移除课程': 'Remove course',
    '更换课程': 'Change course',
    '重新读取课程': 'Reload courses',
    '暂时无法读取学校课程，请重试。': 'School courses are unavailable. Please try again.',
    '学校尚未确认课程操作，请重新读取；不会重复添加、移除或提交。':
        'The school has not confirmed the course change. Reload to check; additions, removals and submissions will not be repeated.',
    '请先完成或关闭学校的课程选择窗口。':
        'Finish or close the school course selection window first.',
    '上一页': 'Previous page',
    '下一页': 'Next page',
    '暂无数据': 'No data',
    '本页课程均已选择': 'All courses on this page are selected',
    '证明材料': 'Supporting documents',
    '已上传至学校': 'Uploaded to school',
    '正在上传附件': 'Uploading attachment',
    '所选文件未能读取，尚未上传。请重新选择附件。':
        'The file could not be read and was not uploaded. Please select it again.',
    '核对并提交': 'Review and submit',
    '请先填写学校要求的必填内容。':
        'Please complete the fields required by the school first.',
    '核对请假申请': 'Review leave application',
    '申请须知': 'School application notes',
    '返回修改': 'Back to edit',
    '确认提交给学校': 'Confirm and submit to school',
    '选择附件并上传至学校': 'Choose a file and upload to school',
    '移除附件': 'Remove attachment',
    '移除此申请中的附件？': 'Remove attachment from this application?',
    '重新读取附件状态': 'Check attachment status',
    '学校原表仅用于核对或恢复，请勿重复提交申请。':
        'Use the school form to verify or recover. Do not submit the application again.',
    '学校须知、附件或提交控件尚未确认，暂不能提交。':
        'School notes, attachments or submission controls could not be verified. Submission is unavailable.',
    '已触发学校提交校验，尚未确认申请成功。请核对学校结果，不要重复提交。':
        'School submission validation was triggered; success is not yet confirmed. Check the school result and do not submit again.',
    '学校未确认提交结果。为避免重复申请，已停止重试，请核对学校原表。':
        'Submission is unconfirmed. Retries are blocked to avoid duplicates; check the school form.',
    '暂时无法确认学校附件控件，请重新读取。':
        'School attachment controls are unverified. Please reload.',
    '附件为空或超过学校允许的大小。': 'The file is empty or exceeds the school size limit.',
    '附件上传尚未得到学校确认，请核对状态；不会自动重传。':
        'Upload is unconfirmed. Check its status; it will not be uploaded again automatically.',
    '无法读取或上传所选附件，请核对状态。':
        'The selected file could not be read or uploaded. Check its status.',
    '学校未确认附件移除，请核对状态；不会自动重试。':
        'Attachment removal is unconfirmed. Check its status; no automatic retry will occur.',
    '添加或管理附件': 'Add or manage attachments',
    '到学校确认并提交': 'Review and submit at school',
    '正在同步学校表单': 'Updating school form',
    '正在提交至学校': 'Submitting to the school',
    '提交结果待确认': 'Submission outcome unconfirmed',
    '申请已提交': 'Application submitted',
    '申请提交成功': 'Application submitted successfully',
    '请等待审批。': 'Please wait for approval.',
    '学校已确认申请提交成功，请等待审批。':
        'The school confirmed submission. Your application is awaiting approval.',
    '学校返回提交失败，申请未确认成功。请核对填写内容；不会自动重复提交。':
        'The school returned a submission failure. Check your entries; the application will not be resubmitted automatically.',
    '学校返回了后续处理要求，当前尚不能确认申请成功。为避免重复申请，已停止重试。':
        'The school requires further processing. Submission is unconfirmed; retries are blocked to avoid duplicates.',
    '已取消学校提交确认，可以继续修改。':
        'School submission confirmation cancelled. You can continue editing.',
    '学校提交回执暂不可用，本次未触发提交，请稍后重试。':
        'School submission receipts are unavailable. Nothing was submitted; try again later.',
    '请先核对学校表单': 'Check the school form first',
    '请先重新读取课程，核对学校状态后再提交。':
        'Reload courses and check the school state before submitting.',
    '正在读取学校表单': 'Loading school form',
    '正在连接学校系统': 'Connecting to the school system',
    '重新读取表单': 'Reload form',
    '重新读取申请资料': 'Reload application',
    '查询学校提交结果': 'Check school submission result',
    '暂时无法读取申请资料，请检查网络后重新读取。':
        'Application data is unavailable. Check your connection and reload.',
    '学校尚未确认更改，请重新读取表单核对；不会自动重试或提交。':
        'Changes are unconfirmed. Reload the form to check; no automatic retry or submission will occur.',
    '此操作暂不可用，请重新读取表单。': 'This action is unavailable. Please reload the form.',
    '连接已中断，当前填写已保留。请重新打开请假申请后核对学校状态。':
        'The connection was interrupted. Your entries have been kept. Reopen the leave application to check the school state.',
    '课程操作仍待学校确认，请稍后重新读取；不会重复操作。':
        'The course change is still unconfirmed. Reload later; the action will not be repeated.',
    '学校未确认提交结果。为避免重复申请，已停止重试；当前不能确认申请成功。':
        'Submission is unconfirmed. Retries are blocked to avoid duplicate applications; success cannot be confirmed.',
    '放弃未同步的填写？': 'Discard unsynced changes?',
    '尚未写入学校表单的内容将被清除。':
        'Changes not yet written to the school form will be cleared.',
    '暂时无法读取原生表单，请在学校原表继续。':
        'The native form is unavailable. Continue in the school form.',
    '学校表单未确认更改，请查看原表核对；不会自动重试或提交。':
        'The school has not confirmed these changes. Check the original form; no automatic retry or submission will occur.',
    '登录状态已变化，请重新打开请假申请。': 'Your session has changed. Reopen Leave Request.',
    '课程、附件和最终确认由学校处理，完成后可返回表单。':
        'Use the school controls for courses, attachments and final confirmation, then return to the form.',
    '查看原版': 'Original layout',
    '手机排版': 'Mobile layout',
    '朵朵校园墙': 'Duoduo Campus Wall',
    '学业模式': 'Study Mode',
    '最近文件': 'Recent Files',
    '暂无学业记录': 'No study records',
    '最近动态': 'Recent Activity',
    '暂无动态': 'No recent activity',
    '正在上课': 'In class now',
    '今天稍后': 'Later today',
    '明天': 'Tomorrow',
    '周一': 'Monday',
    '周二': 'Tuesday',
    '周三': 'Wednesday',
    '周四': 'Thursday',
    '周五': 'Friday',
    '周六': 'Saturday',
    '周日': 'Sunday',
    'iSpace 待办事项': 'iSpace task',
    '写邮件': 'Compose',
    '邮件雷达': 'Mail Radar',
    '收件箱': 'Inbox',
    '草稿箱': 'Drafts',
    '已发送': 'Sent',
    '已删除': 'Deleted',
    '未读': 'Unread',
    '多选': 'Select',
    '仅看未读': 'Unread only',
    '仅主题': 'Subject only',
    '按发件人': 'By sender',
    '按收件人': 'By recipient',
    '清除搜索': 'Clear search',
    '搜索邮件': 'Search mail',
    '没有匹配的邮件': 'No matching messages',
    '正在加载邮件': 'Loading mail',
    '加载失败': 'Loading failed',
    '暂无邮件': 'No messages',
    '邮件预览': 'Mail preview',
    '邮件暂时无法读取': 'This message is temporarily unavailable',
    '当前版本无法连接小U邮件分析服务。':
        'This version cannot connect to the MiU mail analysis service.',
    '附件需小于 10 MB，总大小不能超过 20 MB':
        'Each attachment must be under 10 MB and the total under 20 MB',
    '小U 草稿 · 请核对': 'MiU Draft · Please Review',
    '附件已变化，请重新打开邮件后再试。':
        'Attachments have changed. Reopen the message and try again.',
    '请先登录后再读取邮箱。': 'Please sign in before opening mail.',
    '确认删除': 'Confirm deletion',
    '确认恢复': 'Confirm restore',
    '确认删除邮件': 'Delete message?',
    '确认恢复邮件': 'Restore message?',
    '邮件已恢复。': 'Message restored.',
    '邮件已删除。': 'Message deleted.',
    '请填写收件人': 'Enter at least one recipient',
    '邮件已发送': 'Message sent',
    '插入链接': 'Insert link',
    '插入': 'Insert',
    '保存草稿？': 'Save draft?',
    '不保存': 'Discard',
    '继续编辑': 'Keep editing',
    '保存并关闭': 'Save and close',
    '存草稿': 'Save draft',
    '抄送': 'Cc',
    '抄送／密送': 'Cc/Bcc',
    '输入联系人／部门': 'Contact or department',
    '格式': 'Formatting',
    '密送': 'Bcc',
    '主题': 'Subject',
    '正文': 'Message',
    '附件': 'Attachments',
    '添加附件': 'Add attachment',
    '图片': 'Image',
    '添加图片': 'Add image',
    '项目列表': 'Bulleted list',
    '编号列表': 'Numbered list',
    '引用': 'Quote',
    '分隔线': 'Divider',
    '表情': 'Emoji',
    '搜索联系人': 'Search contacts',
    '收件人': 'Recipient',
    '发件人': 'Sender',
    '时间': 'Time',
    '转发': 'Forward',
    '回复': 'Reply',
    '询问小U': 'Ask MiU',
    '回复邮件': 'Reply',
    '查看原始邮件': 'View original message',
    '外部': 'External',
    '返回邮箱': 'Back to mail',
    '上一封': 'Previous',
    '下一封': 'Next',
    '无主题': 'No subject',
    '无主题邮件': 'No subject',
    '小U当前不可用。': 'MiU is currently unavailable.',
    'iSpace 导航': 'iSpace navigation',
    '请先登录 iSpace': 'Sign in to iSpace',
    '去我的登录': 'Go to Me to sign in',
    '我的课程': 'My Courses',
    '暂无课程数据': 'No course data',
    '下拉刷新或稍后重试': 'Pull to refresh or try again later',
    '站点课程': 'Site Courses',
    '站点公告': 'Site Announcements',
    '暂无进行中的课程': 'No active courses',
    '当前筛选条件下没有数据': 'No results for the current filter',
    '未提供简称': 'No short name',
    '该课程暂无内容': 'No content in this course',
    '该章节暂无活动': 'No activities in this section',
    '作业': 'Assignment',
    '论坛': 'Forum',
    '视频': 'Video',
    '测验': 'Quiz',
    '投票': 'Choice',
    '资源': 'Resource',
    '演示文稿': 'Presentations',
    'PDF 课件/文档': 'PDF Slides & Documents',
    '文档': 'Documents',
    '音视频': 'Audio & Video',
    '压缩包/安装文件': 'Archives & Installers',
    '其他文件': 'Other Files',
    '全部课程文件': 'All Course Files',
    '演示文稿与 PDF 课件': 'Presentations & PDF Slides',
    '压缩包': 'Archives',
    '文件夹': 'Folder',
    '页面': 'Page',
    '链接': 'Link',
    '活动': 'Activity',
    '时间线': 'Timeline',
    '待办': 'To do',
    '课程': 'Courses',
    '更多': 'More',
    '动态': 'Updates',
    '章节': 'Sections',
    '公告': 'Announcements',
    '成绩': 'Grades',
    '暂无内容': 'No content',
    '暂无课程动态': 'No course updates',
    '部分课程动态暂时无法读取': 'Some course updates are unavailable',
    '成绩暂不可用，重试': 'Grades unavailable. Retry',
    '暂无可见成绩': 'No visible grades',
    '内容暂不可用，重试': 'Content unavailable. Retry',
    '站点页面': 'Site Pages',
    '站点博客': 'Site Blog',
    '站点徽章': 'Site Badges',
    '标签': 'Tags',
    '作业截止': 'Assignment due',
    '站点新闻与公告': 'Site News and Announcements',
    '已接入': 'Available',
    '打开论坛详情': 'Open Forum Details',
    '未知课程': 'Unknown course',
    '无日期': 'No date',
    '已逾期': 'Overdue',
    '全部': 'All',
    '未来 7 天': 'Next 7 days',
    '未来 30 天': 'Next 30 days',
    '未来 3 个月': 'Next 3 months',
    '未来 6 个月': 'Next 6 months',
    '按日期排序': 'Sort by date',
    '由新到旧': 'Newest first',
    '由旧到新': 'Oldest first',
    '筛选与排序': 'Filter and sort',
    '搜索字体': 'Search fonts',
    'Low，简单问题': 'Low, simple questions',
    'High，复杂问题': 'High, complex questions',
    '按课程排序': 'Sort by course',
    '上一周': 'Previous week',
    '下一周': 'Next week',
    '管理TA课': 'Manage TA classes',
    '横表': 'Grid',
    '竖表': 'List',
    '切换课表视图': 'Switch schedule view',
    '回到当前': 'Return to now',
    '选择所在周': 'Select week',
    '选择适用周': 'Select weeks',
    '添加其他周': 'Add other weeks',
    '恢复教学周': 'Reset to teaching weeks',
    '教学开始周': 'First teaching week',
    '教学结束周': 'Last teaching week',
    '教学期外': 'Outside teaching term',
    '每周（未限定）': 'Every week (unrestricted)',
    '未选周将不显示、不提醒': 'Unselected weeks are hidden and have no reminders',
    '当前学期校历不可用，请手动选择周':
        'Calendar unavailable for this semester. Select weeks manually.',
    '固定日程': 'Fixed schedules',
    '重复': 'Repeat',
    '固定日程配置保存失败，请稍后重试。': 'Unable to save schedules. Try again later.',
    '本机固定日程暂时无法读取，请稍后重试。': 'Local schedules are unavailable. Try again later.',
    '固定日程配置已变化，请重新打开后再操作。': 'Schedules changed. Reopen before continuing.',
    '这条日程已被更新，请重新打开后再保存。': 'This schedule changed. Reopen before saving.',
    '这条日程已不存在，请刷新后再操作。':
        'This schedule no longer exists. Refresh before continuing.',
    '导入内容包含重复日程，请检查文件后重试。': 'The import contains duplicate schedules.',
    '导入内容与当前固定日程配置冲突，请先处理冲突。': 'Resolve schedule conflicts before importing.',
    '所属课程已变化，请重新选择课程。': 'The course changed. Select it again.',
    '导入的 TA 与所属课程不一致。': 'The imported TA does not match its course.',
    '已新增日程': 'Schedule added',
    '已保存日程': 'Schedule saved',
    '已删除日程': 'Schedule deleted',
    '删除日程': 'Delete schedule',
    '正在加载日程': 'Loading schedules',
    '日程已变化，请重新询问小U。': 'Schedules changed. Ask MiU again.',
    '日程已变化，请重新预览后再保存。': 'Schedules changed. Review them again before saving.',

    '新建固定日程': 'New fixed schedule',
    '编辑固定日程': 'Edit fixed schedule',
    '新建日程': 'New schedule',
    '日程': 'Schedule',
    '所属课程': 'Course',
    '请选择所属课程': 'Select a course',
    '暂无可关联课程': 'No courses available',
    '暂无固定日程': 'No fixed schedules',
    '所属课程暂不可用': 'Course unavailable',
    '请输入日程名称': 'Enter a schedule name',
    '请输入有效时间': 'Enter a valid time',

    '打开日期选择器切换课表周次': 'Choose a date to change week',
    'DDL显示开关': 'Deadline visibility',
    '开': 'On',
    '关': 'Off',
    '隐藏 DDL': 'Hide deadlines',
    '显示 DDL': 'Show deadlines',
    '课表加载失败': 'Schedule failed to load',
    '还没有加载到课表': 'Schedule has not loaded yet',
    '下拉刷新后，会自动从 MIS 拉取当前学期课表。':
        'Pull to refresh the current semester schedule from MIS.',
    '考试安排': 'Exams',
    '无安排': 'No events',
    '课程详情': 'Course details',
    'DDL详情': 'Deadline details',
    '今日': 'Today',
    '当前时间': 'Current time',
    'TA课': 'TA class',
    '选择教师': 'Select instructor',
    '本次时间': 'Time',
    '重复方式': 'Repeat',
    '课程类型': 'Course type',
    '未提供': 'Not provided',
    '学分': 'Credits',
    '节次': 'Period',
    '本周全部上课时间': 'All class times this week',
    '备注': 'Notes',
    '名称': 'Name',
    '地点': 'Location',
    '星期': 'Weekday',
    '开始时间': 'Start Time',
    '结束时间': 'End Time',
    '在线文本': 'Online Text',
    '消息': 'Message',
    '提示词': 'Prompt',
    '评价内容': 'Review',
    '记忆内容': 'Memory',
    '输入你的作业文本内容': 'Enter your assignment text',
    '输入邮箱地址...': 'Enter an email address…',
    '问问小U': 'Ask MiU',
    '截止时间': 'Due time',
    '状态': 'Status',
    '说明': 'Details',
    'Reading Week 假期': 'Reading Week',
    '无时间信息': 'No time information',
    '每周重复': 'Weekly',
    '单独一周': 'One week only',
    '该作业当前不支持文件提交。':
        'This assignment does not currently support file submissions.',
    '暂不支持原生详情': 'Native Details Unavailable',
    '该事件当前没有可用的原生详情数据。': 'Native details are not available for this activity.',
    '当前作业未开放文件提交。': 'File submissions are not open for this assignment.',
    '在线文本提交': 'Online Text Submission',
    '最新讨论': 'Latest Discussions',
    '暂无可见讨论帖子。': 'No visible discussion posts.',
    '复制 Mediasite 链接': 'Copy Mediasite Link',
    '说明附件': 'Description Attachments',
    '选择文件': 'Choose File',
    '点击选择或拖入文件': 'Click to choose or drop files',
    '松手上传': 'Release to upload',
    '拖动文件到这里': 'Drop files here',
    '松开以添加文件': 'Release to add files',
    '移除文件': 'Remove file',
    '请添加文件，不支持文件夹或快捷方式。':
        'Add files only. Folders and shortcuts are not supported.',
    '存在同名文件，请先移除旧文件或重命名后添加。':
        'A file with this name is already selected. Remove it or rename the new file.',
    '所选文件数量超过该作业允许的上限。':
        'The selected files exceed the assignment file count limit.',
    '所选文件大小超过该作业允许的上限。': 'A selected file exceeds the assignment size limit.',
    '提交文件': 'Submit File',
    '已提交文件': 'Submitted Files',
    '选择的文件不可读取，请重试。': 'The selected file cannot be read. Try again.',
    '文件提交请求已发送，请稍后刷新查看状态。':
        'The file submission was sent. Refresh shortly to check its status.',
    '提交失败，请稍后重试。': 'Submission failed. Try again later.',
    '提交': 'Submit',
    '提交请求已发送，请稍后刷新查看状态。':
        'The submission was sent. Refresh shortly to check its status.',
    '暂无帖子内容': 'No post content',
    '当前 Folder 暂无可展示文件。': 'This folder has no files to display.',
    '正在准备文件夹压缩包，请稍候…': 'Preparing the folder archive…',
    '系统下载不可用，已切换到网页下载。':
        'System download is unavailable. Switched to web download.',
    '当前版本优先完成 iSpace Timeline 功能。\n后续会在此页补齐完整业务能力。':
        'This version currently focuses on iSpace Timeline.\nMore features will be added here.',
    '通知与同步': 'Notifications & Sync',
    '外观与语言': 'Appearance & Language',
    '语言': 'Language',
    '简体中文': '简体中文',
    '繁體中文': '繁體中文',
    'English': 'English',
    '跟随系统': 'Follow System',
    '中文': '中文',
    '关于应用': 'About',
    '开发者联系方式': 'Developer contacts',
    '暂时无法打开，请重试': 'Unable to open. Try again.',
    '账户与安全': 'Account & Security',
    'Face ID 保护': 'Face ID Protection',
    'Touch ID 保护': 'Touch ID Protection',
    '生物识别保护': 'Biometric Protection',
    '使用 Face ID 解锁': 'Unlock with Face ID',
    '使用 Touch ID 解锁': 'Unlock with Touch ID',
    '使用生物识别解锁': 'Unlock with Biometrics',
    '验证身份': 'Authenticate',
    '验证身份以解锁 BNBU.ME': 'Authenticate to unlock BNBU.ME',
    '身份验证未完成，设置未更改。':
        'Authentication was not completed. Settings were not changed.',
    '此设备尚未设置 Face ID 或 Touch ID。':
        'Face ID or Touch ID is not set up on this device.',
    '未完成身份验证。': 'Authentication was not completed.',
    '未完成身份验证，设置未更改。':
        'Authentication was not completed. Settings were not changed.',
    'Face ID 或 Touch ID 当前不可用。':
        'Face ID or Touch ID is currently unavailable.',
    'Face ID 或 Touch ID 当前不可用，设置未更改。':
        'Face ID or Touch ID is currently unavailable. Settings were not changed.',
    '身份验证失败，请重试。': 'Authentication failed. Try again.',
    '身份验证失败，请重试，设置未更改。':
        'Authentication failed. Try again. Settings were not changed.',
    '停用小U': 'Disable MiU',
    '退出登录': 'Sign Out',
    '停用小U？': 'Disable MiU?',
    '停用': 'Disable',
    '版本信息': 'Version Information',
    '应用名称': 'App Name',
    '不可用': 'Unavailable',
    '包名': 'Package ID',
    '版本': 'Version',
    '显示主题': 'Theme',
    '浅色': 'Light',
    '深色': 'Dark',
    '学生': 'Student',
    '专业': 'Major',
    '检查更新': 'Check for Updates',
    '当前已是最新版本': 'You are up to date',
    '检查更新失败': 'Update check failed',
    '当前平台不支持官网更新检查': 'Updates are not available on this platform',
    '液态玻璃': 'Liquid Glass',
    '系统暂不支持液态玻璃': 'Liquid Glass is not supported by this system',
    '突出显示今天': 'Highlight Today',
    '蓝色': 'Blue',
    '青绿': 'Teal',
    '琥珀': 'Amber',
    '紫色': 'Violet',
    '灵动岛与锁屏提醒': 'Dynamic Island & Lock Screen',
    '课表上岛': 'Classes on Dynamic Island',
    '上课提前时间': 'Class Lead Time',
    '上课后关闭': 'Dismiss After Class Starts',
    'DDL 上岛': 'Deadlines on Dynamic Island',
    'DDL 提前时间': 'Deadline Lead Time',
    '自定义上课提前时间': 'Custom Class Lead Time',
    '自定义 DDL 提前时间': 'Custom Deadline Lead Time',
    '小时': 'Hours',
    '分钟': 'Minutes',
    '不提醒': 'Off',
    '自定义': 'Custom',
    '请输入 30 分钟至 48 小时': 'Enter a time from 30 minutes to 48 hours',
    'DDL 通知': 'Deadline Notifications',
    '课表通知': 'Class Notifications',
    'DDL 通知时间': 'Deadline Notification Time',
    'DDL 通知设置': 'Deadline Notification Settings',
    'DDL 提醒': 'Deadline Reminders',
    '暂无待发送提醒': 'No pending reminders',
    '智能提醒': 'Smart',
    '固定提醒': 'Fixed',
    '提醒次数': 'Reminder Count',
    '提醒时间': 'Reminder Times',
    '自定义时间': 'Custom Time',
    '免打扰': 'Quiet Hours',
    '约提前 2 小时': 'About 2 hours before',
    '约提前 24 小时、2 小时': 'About 24 and 2 hours before',
    '约提前 24 小时、8 小时、2 小时': 'About 24, 8, and 2 hours before',
    '了解提醒逻辑': 'How Smart Reminders Work',
    '智能提醒如何工作': 'How Smart Reminders Work',
    '默认三次提醒': 'Three Reminders by Default',
    '通常在截止前约 24 小时、8 小时和 2 小时提醒，也可以改为 1—3 次。':
        'Usually about 24, 8, and 2 hours before the deadline. You can choose 1–3 reminders.',
    '自动避开免打扰': 'Respects Quiet Hours',
    '默认免打扰为 00:00—06:00。落在这段时间的提醒会提前到免打扰开始前 10 分钟。':
        'Quiet hours default to 00:00–06:00. A reminder in this period moves to 10 minutes before quiet hours begin.',
    '睡前统一提醒': 'Pre-sleep Summary',
    '免打扰期间至结束后 1 小时内到期的 DDL，会在免打扰前统一提醒；多项会合成一条。':
        'Deadlines due during quiet hours or within one hour after they end are summarized before quiet hours. Multiple deadlines share one notification.',
    '避免连续打扰': 'Avoids Back-to-back Alerts',
    '调整后相距不足 2 小时的提醒会合并，汇总不会额外增加提醒次数。':
        'Adjusted reminders less than two hours apart are merged. A summary never adds another reminder.',
    '30 分钟—48 小时': '30 minutes–48 hours',
    '每个 DDL 最多提醒 3 次': 'Up to 3 reminders per deadline',
    '这个提醒时间已经添加': 'This reminder time is already selected',
    '免打扰开始和结束时间不能相同': 'Quiet hours must have different start and end times',
    '请至少选择一个提醒时间': 'Select at least one reminder time',
    'DDL 通知设置保存失败，请稍后重试。':
        'Could not save deadline notification settings. Try again later.',
    '课表通知时间': 'Class Notification Time',
    '自定义 DDL 通知时间': 'Custom Deadline Notification Time',
    '自定义课表通知时间': 'Custom Class Notification Time',
    'DDL 通知时间保存失败，请稍后重试。':
        'Could not save the deadline notification time. Try again later.',
    '课表通知时间保存失败，请稍后重试。':
        'Could not save the class notification time. Try again later.',
    '校历加载失败': 'Calendar failed to load',
    '正在加载校历': 'Loading calendar',
    '请检查网络后重试。': 'Check your connection and try again.',
    '本学期校历': 'Current Semester Calendar',
    '课程计划': 'Class Schedule',
    '刷新校历': 'Refresh calendar',
    '目录加载失败': 'Directory failed to load',
    '师资目录已更新，请重新加载': 'Faculty directory changed. Reload to continue',
    '沿用上次资料': 'Using previous data',
    '尚未核验': 'Not yet verified',
    '最近核验': 'Last verified',
    '没有匹配的政教信息': 'No matching directory entries',
    '没有匹配的机构': 'No matching organizations',
    '学院': 'Schools',
    '高研院': 'Graduate School',
    '政务': 'Administration',
    '搜索全部政教信息': 'Search the campus directory',
    '职责': 'Responsibilities',
    '部门与联系人': 'Departments & Contacts',
    '打开官网': 'Open Website',
    '师资队伍': 'Faculty',
    '师资与人员': 'Faculty and staff',
    '人员': 'Staff',
    '办事分工': 'Services and responsibilities',
    '官方来源': 'Official sources',
    '补充资料核验': 'Supplement verified',
    '来源页面': 'Source pages',
    '访问受限': 'Restricted access',
    '历史资料': 'Historical information',
    '师资目录加载失败': 'Faculty directory failed to load',
    '暂无师资数据': 'No faculty data',
    '研究领域': 'Research Areas',
    '教育经历': 'Education',
    '时间表': 'Schedule',
    '主要任职': 'Primary Appointment',
    '交叉任职': 'Joint Appointments',
    '个人主页': 'Profile',
    '该教师可能未被学校收录': 'This instructor may not be listed in the school directory',
    '我的地点': 'My Places',
    '高德校园地图': 'Amap Campus Map',
    '查看最新官方地图': 'View Latest Official Map',
    '没有找到对应楼宇。可尝试输入楼号、中文名、英文名或房间前缀。':
        'No building found. Try a building number, Chinese or English name, or room prefix.',
    '地点已保存': 'Place saved',
    '地点已更新': 'Place updated',
    '地点已删除': 'Place deleted',
    '编辑地点': 'Edit Place',
    '删除地点': 'Delete Place',
    '地点名称': 'Place Name',
    '请输入地点名称': 'Enter a place name',
    '登录后查看 eCard': 'Sign in to view eCard',
    '学号暂不可用': 'Student ID is unavailable',
    '学号 Code 39 条码': 'Student ID Code 39 barcode',
    '重新加载照片': 'Reload photo',
    '宿舍信息暂不可用': 'Residence information is unavailable',
    '隐藏宿舍位置': 'Hide residence',
    '显示宿舍位置': 'Show residence',
    '男': 'Male',
    '女': 'Female',
    '本科生': 'Undergraduate',
    '研究生': 'Postgraduate',
    '博士': 'Doctoral Student',
    'TA 课程': 'TA Classes',
    '课程安排': 'Class Schedule',
    '新增课程': 'Add Class',
    '删除 TA 课': 'Delete TA Class',
    '导入配置': 'Import',
    '导出配置': 'Export',
    '每周': 'Weekly',
    '导入': 'Import',
    '导入存在冲突': 'Import Conflicts',
    '知道了': 'Got It',
    '确认导入 TA 课': 'Confirm TA Class Import',
    '资源库': 'Library',
    '对话': 'Chats',
    '新对话': 'New Chat',
    '记忆': 'Memory',
    '剩余额度': 'Remaining quota',
    '选择思考强度': 'Select thinking effort',
    '清空小U历史': 'Clear MiU History',
    '清空小U历史？': 'Clear MiU History?',
    '本机与已同步的小U问答都会被清空。':
        'MiU conversations on this device and in the synced snapshot will '
        'both be cleared.',
    '添加到对话': 'Add to Chat',
    '删除资源？': 'Delete Resource?',
    '删除记忆？': 'Delete Memory?',
    '小U': 'MiU',
    '正在读取': 'Loading',
    '今天想做什么？': 'What would you like to do?',
    '确认操作': 'Confirm Action',
    '确认设置提醒': 'Confirm Reminder',
    '确认后将由这台设备创建本地通知。':
        'After confirmation, this device will create a local notification.',
    '设置提醒': 'Set Reminder',
    '确认邮件草稿': 'Confirm Email Draft',
    '打开写邮件': 'Open Composer',
    '确认在线文本草稿': 'Confirm Online Text Draft',
    '打开作业页': 'Open Assignment',
    '仅一周': 'One Week Only',
    '适用周': 'Applicable Week',
    '结束时间必须晚于开始时间': 'End time must be later than start time',
    '请选择 TA 课适用周': 'Select an applicable week for the TA class',
    '打开原生编辑器': 'Open Native Editor',
    '确认删除 TA 课': 'Confirm TA Class Deletion',
    '打开 TA 课管理页后还会再次要求确认。':
        'You will be asked to confirm again in TA Class Management.',
    '编辑消息': 'Edit Message',
    '从这里发送': 'Send from Here',
    '删除对话': 'Delete Chat',
    '重新生成这轮回复': 'Regenerate response',
    '记忆建议': 'Memory Suggestions',
    '重新加载': 'Reload',
    '稍后': 'Later',
    '前往官网下载': 'Open Official Download',
    '本页整理': 'Page Notes',
    '点击右上角按钮后开始整理': 'Use the top-right action to organize this page',
    '学业问答': 'Study Q&A',
    '暂无问答记录': 'No Q&A history',
    '问答记录': 'Q&A History',
    '重新整理本页': 'Reorganize This Page',
    '现有整理内容将被新结果替换。': 'The current notes will be replaced.',
    '25度评价': '25doer review',
    'BNBU.ME评分分布': 'BNBU.ME rating distribution',
    '评价数据已更新，请刷新后继续。': 'Reviews have changed. Refresh to continue.',
    '商家回复': 'Merchant reply',
    '条评分': 'ratings',
    '评分': 'Rating',
    '我的评价': 'My Review',
    '匿名同学': 'Anonymous Student',
    '暂无同学评价': 'No student reviews yet',
    '请选择评分': 'Choose a rating',
    '评价加载失败': 'Could not load reviews',
    '评价最多2000字': 'Reviews can contain up to 2,000 characters',
    '评价保存失败，请重试': 'Could not save the review. Try again.',
    '地标已下架或不存在': 'This landmark is no longer available',
    '评价服务暂不可用': 'Reviews are temporarily unavailable',
    '登录状态已失效，请重试': 'Your session has expired. Try again.',
    '上一张': 'Previous image',
    '下一张': 'Next image',
    '发表评价': 'Write a Review',
    '编辑评价': 'Edit Review',
    '评价功能当前不可用。': 'Reviews are currently unavailable.',
    '认真度': 'Teaching',
    '给分': 'Grading',
    '点名': 'Attendance',
    '负担': 'Workload',
    '评价': 'Review',
    '同学评价': 'Student Reviews',
    '历史选课参考': 'Past Course Insights',
    '历史匿名经验，内容主观且样本有限，仅供选课参考；不计入同学评价评分与数量。':
        'Anonymous past experiences are subjective and based on limited samples. They are for course selection reference only and are not included in student review ratings or counts.',
    '教学风格与课程体验': 'Teaching style & course experience',
    '课堂要求': 'Expectations',
    '灵活自主': 'Flexible',
    '两者兼有': 'A mix of both',
    '规范细致': 'Structured',
    '交流风格': 'Interaction',
    '沉稳克制': 'Reserved',
    '热情亲和': 'Warm',
    '授课方式': 'Teaching approach',
    '系统讲授': 'Lecture-led',
    '讲授与讨论': 'A mix of both',
    '互动讨论': 'Discussion-led',
    '课程节奏': 'Course pace',
    '循序渐进': 'Gradual',
    '节奏适中': 'Moderate',
    '紧凑推进': 'Brisk',
    '作业投入': 'Workload',
    '较少': 'Light',
    '适中': 'Moderate',
    '较多': 'Substantial',
    '未选择': 'Unselected',
    '清除选择': 'Clear selection',
    '请选择至少一项课堂体验': 'Choose at least one course experience',
    '历史评价': 'Earlier review',
    '综合评分': 'Overall Rating',
    '保存评价': 'Save Review',
    '教学认真度': 'Teaching Quality',
    '给分宽松度': 'Grading Leniency',
    '点名频率': 'Attendance Frequency',
    '课程负担': 'Course Workload',
    '课表匹配': 'Schedule Match',
    '管理员已隐藏': 'Hidden by Moderator',
    '总体评分': 'Overall Rating',
    '分项评分': 'Category Ratings',
    '话题': 'Conversations',
    '星标邮件': 'Starred',
    '恢复到原文件夹': 'Restore to Original Folder',
    '垃圾邮件': 'Junk',
    '不使用': 'Off',
    '选择邮件': 'Select Messages',
    '取消全选': 'Deselect All',
    '标记': 'Mark',
    '移动': 'Move',
    '标为已读': 'Mark Read',
    '标为未读': 'Mark Unread',
    '添加星标': 'Add Star',
    '取消星标': 'Remove Star',
    '加入雷达': 'Add to Radar',
    '暂无雷达邮件': 'No radar messages',
    '等待重试': 'Waiting to Retry',
    '小U将分析所选范围内的邮件正文与允许的附件，并同步加密后的分析结果。范围设置会同步到同一账号的其他设备。':
        'MiU will analyze message bodies and supported attachments in this range and sync encrypted results. Your range setting syncs across devices on the same account.',
    '邮件雷达最多分析近60天。': 'Mail Radar supports up to 60 days.',
    '请先选择邮件雷达的分析天数。': 'Choose a Mail Radar range first.',
    '只能加入近60天且身份有效的邮件。':
        'Only messages from the last 60 days with a valid mailbox identity can be added.',
    '当前邮箱不允许修改该标记。': 'This mailbox does not allow changing this flag.',
    '新草稿已保存，旧草稿暂时保留在草稿箱。':
        'The new draft is saved. The previous draft is still in Drafts.',
    '暂时无法加载全部邮件，请刷新后重试。':
        'Could not load every message. Refresh and try again.',
    '当前邮箱连接不支持移动。': 'This mail connection does not support moving messages.',
    '当前邮箱连接不支持星标。': 'This mail connection does not support stars.',
    '当前邮箱连接不支持修改未读状态。': 'This mail connection cannot change unread state.',
    '邮箱服务器暂不支持安全移动。': 'The mail server does not support safe message moves.',
    '邮箱服务器暂不支持安全永久删除。':
        'The mail server does not support safe permanent deletion.',
    '启用邮件雷达': 'Enable Mail Radar',
    '小U会分析所选时间范围内的邮件主题、正文和安全附件，生成摘要、优先级、截止时间与下一步行动；与当前界面语言不同的邮件会翻译为当前界面语言，已包含完整当前语言内容的邮件不会重复翻译。':
        'MiU analyzes subjects, message bodies, and safe attachments in the selected range to produce summaries, priorities, due dates, and next steps. Messages in another language are translated into the selected app language, while messages already containing complete content in that language are not translated again.',
    '图片和二维码会在邮件详情中直接展示；PDF、Word、PPT、Excel 和常见文本可交给小U分析，单个源附件上限 20 MB。压缩包、程序、脚本及未知格式不会发送，二维码链接不会自动打开。':
        'Images and QR codes appear directly in message details. PDF, Word, PowerPoint, Excel, and common text files can be analyzed, up to 20 MB per source attachment. Archives, apps, scripts, and unknown formats are not sent, and QR links never open automatically.',
    '不会发送邮箱密码、Cookie、Token 或其他登录凭据。分析结果仅在本机按当前账号保存。':
        'Mail passwords, cookies, tokens, and other sign-in credentials are never sent. Results are stored on this device for the current account.',
    '同意并开始分析': 'Agree & Start Analysis',
    '近 7 天': 'Last 7 Days',
    '近 30 天': 'Last 30 Days',
    '近 90 天': 'Last 90 Days',
    '近 180 天': 'Last 180 Days',
    '近 365 天': 'Last 365 Days',
    '纠正分类': 'Correct Category',
    '撤回邮件雷达同意？': 'Withdraw Mail Radar Consent?',
    '后台分析将停止，已有雷达记录保留在本机。':
        'Background analysis will stop. Existing Mail Radar records will remain on this device.',
    '撤回同意': 'Withdraw Consent',
    '发件人已撤回': 'Recalled by Sender',
    '保存图片': 'Save Image',
    '保存附件': 'Save Attachment',
    '附件保存失败，请稍后重试。': 'Could not save the attachment. Try again later.',
    '即将打开外部链接': 'Open External Link',
    '该外部链接无效，无法打开。': 'This external link is invalid.',
    '邮件中的外部链接已变化，请刷新后重试。':
        'The external link has changed. Refresh the message and try again.',
    '系统无法打开这个外部链接。': 'The system could not open this link.',
    '确认打开': 'Open Link',
    '紧急': 'Urgent',
    '重要': 'Important',
    '普通': 'Normal',
    '低优先级': 'Low priority',
    '截止事项': 'Deadlines',
    '待办事项': 'Action required',
    '活动安排': 'Events',
    '校园通知': 'Campus notices',
    '系统邮件': 'System mail',
    '个人来信': 'Personal mail',
    '校内部门': 'Campus department',
    '暂停邮件雷达': 'Pause Mail Radar',
    '有邮件材料校验未通过，其他邮件继续处理。':
        'Some mail content failed validation. Other messages will continue processing.',
    '邮件采集等待平台预算恢复，已分析结果仍可领取。':
        'Collection is waiting for the platform budget to reset. Existing results remain available.',
    '邮件分析结果待后台核验。': 'The mail analysis result requires review.',
    '开启邮件雷达': 'Enable Mail Radar',
    '直接来信': 'Direct Messages',
    '近期关注': 'Recent Priority',
    '等待小U': 'Waiting for MiU',
    '稍后阅读': 'Read Later',
    '已完成': 'Completed',
    '撤回通知': 'Recall Notice',
    '等待分析': 'Waiting for Analysis',
    '小U分析待重试': 'Analysis Will Retry',
    '邮件雷达详情': 'Mail Radar Details',
    '小U摘要': 'MiU Summary',
    '调用记录': 'Analysis Log',
    '翻译': 'Translation',
    '关联邮件': 'Related Messages',
    '分析时间范围': 'Analysis Range',
    '小U状态': 'MiU Status',
    '软件更新': 'Software Update',
    '必须更新': 'Update Required',
    '必须更新生效时间': 'Update required from',
    '请前往商店更新': 'Please update from the store',
    '前往商店更新': 'Update in Store',
    '重新检查': 'Check Again',
    '虚拟形象': 'Avatar',
    '正在检查更新': 'Checking for updates',
    '正在下载更新': 'Downloading update',
    '正在校验安装包': 'Verifying update',
    '正在准备安装': 'Preparing installation',
    '等待安装': 'Waiting for installation',
    '更新下载失败': 'Update download failed',
    '安装未完成': 'Installation incomplete',
    '下载并安装': 'Download and install',
    '允许安装': 'Allow installation',
    '重新安装': 'Retry installation',
    '下载完成后将打开系统安装器，请确认安装':
        'After downloading, confirm the update in the system installer.',
    '请允许 BNBU.ME 安装应用，返回后将继续安装':
        'Allow BNBU.ME to install apps. Installation will continue when you return.',
    '请在系统页面确认安装，取消后可重新安装':
        'Confirm installation on the system screen. If cancelled, you can retry.',
    '更新下载或校验失败，请重试': 'Could not download or verify the update. Please retry.',
    '无法完成安装，请重试': 'Could not complete installation. Please retry.',
    '新版本将通过系统浏览器从官网下载安装':
        'The new version will be downloaded from the official website in your browser',
    '失败': 'Failed',
    '错误': 'Error',
    '关闭通知': 'Dismiss notification',

    "通用设置": "General Settings",
    "DDL 通知已关闭，已排程的 DDL 通知已清除。":
        "Deadline notifications are off. Scheduled deadline notifications have been cleared.",
    "课表通知已关闭，已排程的课程通知已清除。":
        "Class notifications are off. Scheduled class notifications have been cleared.",
    "暂时无法确认邮件雷达权限，请稍后重试。":
        "Could not check Mail Radar access. Try again later.",
    "管理员暂未开放此权限": "This feature has not been enabled by the administrator",
    "邮件雷达暂时无法准备，请稍后重试。":
        "Mail Radar is temporarily unavailable. Try again later.",
    "邮件雷达设置保存失败，请稍后重试。": "Could not save Mail Radar settings. Try again later.",
    "同意": "Agree",
    "正在加载": "Loading",
    "重新检查权限": "Check Access Again",
    "开启": "Enable",
    "添加": "Add",
    "相机": "Camera",
    "照片": "Photos",
    "文件": "Files",
    "照片恢复失败。": "Could not restore the photo.",
    "一次最多添加 3 个附件。": "You can add up to 3 attachments at a time.",
    "附件总大小不能超过 50 MB。": "Attachments must not exceed 50 MB in total.",
    "单个附件大小需在 50 MB 以内。": "Each attachment must be between 1 byte and 50 MB.",
    "待提交作业文件总大小不能超过 150 MB。":
        "Assignment files must not exceed 150 MB in total.",
    "小U资源库暂不可用。": "The MiU Library is temporarily unavailable.",
    "无法打开这个资源。": "Could not open this resource.",
    "小U记忆": "MiU Memory",
    "添加记忆": "Add Memory",
    "编辑记忆": "Edit Memory",
    "编辑记忆建议": "Edit Memory Suggestion",
    "正在唤醒小U": "Starting MiU",
    "对话与资源": "Chats & Resources",
    "小U正在处理": "MiU is working",
    "上一个分支": "Previous Branch",
    "下一个分支": "Next Branch",
    "安排我今天的课程和 DDL": "Plan my classes and deadlines for today",
    "帮我写一封课程邮件": "Help me write an email about a course",
    "查看 iSpace 最近作业": "Check recent iSpace assignments",
    "我现在在哪里？": "Where am I now?",
    "添加内容": "Add Content",
    "无法读取所选附件，请重新选择。":
        "Could not read the selected attachment. Select it again.",
    "小U返回了未声明确认要求的操作，已阻止执行。":
        "MiU returned an action without the required confirmation flag. The action was blocked.",
    "确认开始 Quiz": "Confirm Starting Quiz",
    "确认最终交卷": "Confirm Final Submission",
    "确认保存答案": "Confirm Saving Answers",
    "将创建新的作答 attempt。开始后，小U需要重新读取题目。":
        "A new quiz attempt will be created. MiU will need to read the questions again after it starts.",
    "最终交卷": "Submit Attempt",
    "开始": "Start",
    "保存答案": "Save Answers",
    "确认附件下载": "Confirm Attachment Download",
    "小U会打开原生邮件详情，重新校验附件后才开始下载。":
        "MiU will open the message in the app and verify the attachment before downloading it.",
    "打开邮件并下载": "Open Message & Download",
    "邮件 UID": "Message UID",
    "确认打包课程资料": "Confirm Course Archive",
    "小U会重新读取原生课程文件清单，按要求预选并分类显示文件；显示实际数量与大小供你确认后，App 会自动下载并在本机生成 ZIP。":
        "MiU will reload the course file list, select and group the requested files, and show their actual count and size for confirmation. The app will then download them and create a ZIP on this device.",
    "读取并打包": "Load & Create ZIP",
    "课程 ID": "Course ID",
    "确认作业文件上传": "Confirm Assignment File Upload",
    "小U只会打开原生作业页和文件选择器，不会自动提交文件。":
        "MiU will open the assignment page and file picker. Files will only be submitted after your confirmation.",
    "打开文件选择器": "Open File Picker",
    "作业 ID": "Assignment ID",
    "小U会前往原生邮箱重新读取邮件；删除前仍需在邮箱页面最终确认。":
        "MiU will reload the message in the mailbox. You must confirm deletion there.",
    "前往邮箱确认删除": "Confirm Deletion in Mailbox",
    "小U会前往原生邮箱重新读取邮件；恢复前仍需在邮箱页面最终确认。":
        "MiU will reload the message in the mailbox. You must confirm restoration there.",
    "前往邮箱确认恢复": "Confirm Restoration in Mailbox",
    "时间缺失": "Time Missing",
    "确认新增 TA 课": "Confirm Adding TA Class",
    "确认编辑 TA 课": "Confirm Editing TA Class",
    "请输入 TA 课名称": "Enter a TA class name",
    "请输入 00:00–23:59": "Enter a time from 00:00 to 23:59",
    "请输入 00:01–24:00": "Enter a time from 00:01 to 24:00",
    "请选择该周任意一天": "Choose any day in that week",
    "星期一": "Monday",
    "星期二": "Tuesday",
    "星期三": "Wednesday",
    "星期四": "Thursday",
    "星期五": "Friday",
    "星期六": "Saturday",
    "星期日": "Sunday",
    "更多操作": "More Actions",
    "其他，自行输入": "Other, type your own response",
    "资源操作": "Resource Actions",
    "资源库为空": "The Library is empty",
    "已附加邮件": "Message Attached",
    "已附加邮件草稿": "Email Draft Attached",
    "资源库引用": "Library Reference",
    "编辑并创建分支": "Edit & Create Branch",
    "重新生成并创建分支": "Regenerate & Create Branch",
    "赞": "Helpful",
    "踩": "Not Helpful",
    "忽略": "Dismiss",
    "仅本机": "On This Device",
    "等待同步": "Waiting to Sync",
    "已同步": "Synced",
    "可拖动调整位置": "Drag to reposition",
    "展开": "Expand",
    "展开全文": "Read more",
    "展开标签": "Show all tags",
    "收起标签": "Collapse tags",
    "收起回复": "Collapse replies",
    "已编辑": "Edited",
    "收起": "Collapse",
    "请先登录后再写邮件": "Sign in before composing an email",
    "教师档案加载失败": "Could not load the faculty profile",
    "其他师资": "Other Faculty",
    "打开官方校园地图": "Open Official Campus Map",
    "搜索 T3、格物楼、图书馆或 T3-602": "Search T3, Gewu Building, Library, or T3-602",
    "高德地图加载失败": "Could not load the Amap map",
    "请检查网络后重新加载。": "Check your connection and reload.",
    "取消选点": "Cancel Location Selection",
    "标记地点": "Mark Location",
    "重置地图": "Reset Map",
    "我的地点加载失败": "Could not load your places",
    "地点保存失败": "Could not save the location",
    "课程内容加载失败，请稍后重试。": "Could not load course content. Try again later.",
    "正在批量下载": "Downloading Course Files",
    "批量下载课程文件": "Download Course Files",
    "请回到对话补充要打包的类型。":
        "Return to the chat and specify the file types to include.",
    "已知文件总大小不能超过 512 MB。": "The known total file size must not exceed 512 MB.",
    "小U已选好打包内容": "MiU Has Selected the Files",
    "确认生成 ZIP": "Confirm ZIP Creation",
    "登录 Cookie 只会发送到 iSpace 同源地址，文件正文不会交给小U服务端。":
        "Sign-in cookies are sent only to the same iSpace origin. File contents are not sent to the MiU server.",
    "正在核对课件列表…": "Checking course files…",
    "课件列表已变化，请重新选择后下载。":
        "The course file list has changed. Select the files again before downloading.",
    "未能建立安全下载会话，请稍后重试。":
        "Could not establish a secure download session. Try again later.",
    "无法访问本机文件目录。": "Could not access the local file directory.",
    "无法打开 ZIP 文件。": "Could not open the ZIP file.",
    "小程序码已保存到相册，但未能打开微信。":
        "The mini program code was saved to Photos, but WeChat could not be opened.",
    "未能保存小程序码或打开微信，请重试。":
        "Could not save the mini program code or open WeChat. Try again.",
    "小程序码已保存。请在微信扫一扫中选择相册，授权后返回 BNBU.ME。":
        "The mini program code was saved. Open Scan in WeChat, choose Photos, and return to BNBU.ME after authorization.",
    "微信已打开，但小程序码未能保存，请返回后重试。":
        "WeChat opened, but the mini program code could not be saved. Return and try again.",
    "朵朵校园墙加载失败": "Could not load Duoduo Campus Wall",
    "Folder 内容加载失败，请稍后重试。": "Could not load the folder. Try again later.",
    "正在下载文件夹": "Downloading Folder",
    "下载文件夹": "Download Folder",
    "正在准备下载…": "Preparing download…",
    "下载整个文件夹": "Download Entire Folder",
    "点击预览": "Tap to Preview",
    "文件夹下载完成。": "Folder download complete.",
    "在课表中定位并打开课程详情": "Find this class in the timetable and open its details",
    "与 iSpace 站点课程保持一致": "Matches your courses on iSpace",
    "内容暂不可用": "Content is temporarily unavailable",
    "下载": "Download",
    "无法读取所选图片": "Could not read the selected image",
    "所选图片为空文件": "The selected image file is empty",
    "内嵌图片不能超过 2 MB": "Inline images must not exceed 2 MB",
    "无法打开或读取所选附件，请重新选择":
        "Could not open or read the selected attachment. Select it again",
    "草稿已保存": "Draft Saved",
    "编辑草稿": "Edit Draft",
    "新建邮件": "New Message",
    "撤销": "Undo",
    "重做": "Redo",
    "清除格式": "Clear Formatting",
    "粗体": "Bold",
    "斜体": "Italic",
    "下划线": "Underline",
    "插入 2 × 2 表格": "Insert 2 × 2 Table",
    "插入 3 × 3 表格": "Insert 3 × 3 Table",
    "字体": "Font",
    "默认字体": "Default Font",
    "苹方": "PingFang",
    "宋体": "Songti",
    "楷体": "Kaiti",
    "字号": "Font Size",
    "文字颜色与高亮": "Text Color & Highlight",
    "签名": "Signature",
    "不使用签名": "No Signature",
    "使用 BNBU.ME 签名": "Use BNBU.ME Signature",
    "小U智能": "MiU Tools",
    "智能翻译暂未开放。": "AI translation is not yet available.",
    "智能翻译": "AI Translation",
    "草稿内容过长，暂时无法作为小U附件。": "This draft is too long to attach to a MiU chat.",
    "暂时无法创建小U对话。": "Could not create a MiU chat. Try again later.",
    "时　间": "Date",
    "主　题": "Subject",
    "文字颜色": "Text Color",
    "文字高亮": "Text Highlight",
    "文字": "Text",
    "高亮": "Highlight",
    "删除线": "Strikethrough",
    "清除高亮": "Clear Highlight",
    "对齐": "Alignment",
    "左对齐": "Align Left",
    "居中": "Center",
    "右对齐": "Align Right",
    "两端对齐": "Justify",
    "列表": "Lists",
    "增加缩进": "Increase Indent",
    "减少缩进": "Decrease Indent",
    "行距": "Line Spacing",
    "紧凑行距": "Compact Spacing",
    "标准行距": "Normal Spacing",
    "宽松行距": "Loose Spacing",
    "表格编辑": "Edit Table",
    "表格前插入行": "Insert Row Above",
    "表格后插入行": "Insert Row Below",
    "删除当前行": "Delete Row",
    "表格前插入列": "Insert Column Before",
    "表格后插入列": "Insert Column After",
    "删除当前列": "Delete Column",
    "合并或拆分单元格": "Merge or Split Cells",
    "切换表头行": "Toggle Header Row",
    "删除表格": "Delete Table",
    "发给": "To",
    "大小": "Size",
    "邮件操作引用无效，请重新询问小U。":
        "The message action reference is invalid. Ask MiU again.",
    "邮箱内容已更新，请重新询问小U。": "The mailbox has changed. Ask MiU again.",
    "请先登录后再操作邮箱。": "Sign in before using the mailbox.",
    "邮件引用已失效，请刷新邮箱后重试。":
        "The message reference has expired. Refresh the mailbox and try again.",
    "邮箱内容已更新，请刷新后重试。": "The mailbox has changed. Refresh and try again.",
    "未知时间": "Unknown Time",
    "收取": "Check Mail",
    "回复全部": "Reply All",
    "换个关键词试试。": "Try a different keyword.",
    "当前没有未读邮件。": "There are no unread messages.",
    "该文件夹没有邮件。": "This folder has no messages.",
    "选择一封邮件": "Select a Message",
    "请稍后重试。": "Try again later.",
    "登录状态已变化。": "Your sign-in session has changed.",
    "发件人邮箱：": "Sender address:",
    "收件人邮箱：": "Recipient address:",
    "清除邮箱地址": "Clear Email Address",
    "下拉即可重新读取邮箱。": "Pull down to reload the mailbox.",
    "隐藏": "Hide",
    "详情": "Details",
    "这封邮件没有可解析的正文内容。": "No readable message body was found.",
    "HTML 邮件，点开查看完整内容": "HTML message. Open to view the full content",
    "邮件引用已失效，请返回邮箱刷新后重试。":
        "The message reference has expired. Return to the mailbox, refresh, and try again.",
    "这封邮件缺少稳定引用，请返回邮箱刷新后重试。":
        "This message has no stable reference. Return to the mailbox, refresh, and try again.",
    "恢复邮件": "Restore Message",
    "删除邮件": "Delete Message",
    "邮件": "Email",
    "邮箱内容已变化，请刷新后重试。": "The mailbox has changed. Refresh and try again.",
    "永久删除": "Delete Permanently",
    "请先登录后再打开 Portal 或 MIS。": "Sign in before opening Portal or MIS.",
    "正在加载学校页面": "Loading School Page",
    "学校页面加载失败，请检查网络后重试。":
        "Could not load the school page. Check your connection and try again.",
    "学校页面加载失败": "Could not load the school page",
    '页面地址无法加载。': 'This page address cannot be loaded.',
    '网页登录会话准备失败，请重试。': 'Could not prepare the web session. Please retry.',
    '网页内容规则初始化失败，请重试。': 'Could not initialize the content rules. Please retry.',
    '页面内容无法加载。': 'This document cannot be loaded.',
    "课表横表视图": "Timetable Grid View",
    "课表竖表视图": "Timetable List View",
    "待完成": "To Do",
    "打开 iSpace": "Open iSpace",
    "Reading Week\n假期": "Reading Week\nHoliday",
    "学业整理": "Study Notes",
    "请先在 BNBU.ME 完成登录": "Sign in to BNBU.ME first",
    "关闭文件": "Close File",
    "学业记录": "Study History",
    "正在同步学业文件": "Syncing Study Files",
    "学业文件无法读取": "Could not read the study file",
    "整理设置": "Notes Settings",
    "整理本页": "Summarize This Page",
    "问答历史": "Q&A History",
    "询问本页": "Ask About This Page",
    "选择多页提问": "Select Pages to Ask About",
    "询问全文件": "Ask About the Entire File",
    "返回问答": "Back to Q&A",
    "新建问答": "New Q&A",
    "确认重新整理": "Confirm Regenerating Notes",
    "整理失败": "Could not generate notes",
    "整理失败，请重试。": "Could not generate notes. Try again.",
    "选择页面": "Select Pages",
    "学业文件超过 64 MB。": "The study file exceeds 64 MB.",
    "同步学业文件超时。": "Study file sync timed out.",
    "学业模式目前只支持 PDF 与 PPTX。":
        "Study Mode currently supports PDF and PPTX files only.",
    "整理提示词": "Notes Prompt",
    "恢复预设": "Restore Default",
    "日程已变化，请重新预览后再删除。":
        "The schedule has changed. Review it again before deleting.",
    "课程操作": "Class Actions",
    "导出日程配置": "Export Schedule Settings",
    "已导出日程配置": "Schedule settings exported",
    "导出失败，请稍后重试": "Export failed. Try again later",
    "导入日程配置": "Import Schedule Settings",
    "未能读取导入文件": "Could not read the import file",
    "导入文件格式不正确": "The import file format is invalid",
    "导入失败，请确认文件格式正确": "Import failed. Check the file format",
    "新增日程": "Add Schedule",
    "编辑日程": "Edit Schedule",
    "请先导出最新配置并合并后再导入。":
        "Export the latest settings and merge your changes before importing.",
    "确认导入日程": "Confirm Schedule Import",
    "不会直接覆盖整表。": "The entire timetable will not be overwritten.",
    "没有需要导入的变化": "No changes to import",
    "单独周": "Single Week",
    "详情加载失败，请稍后重试。": "Could not load the details. Try again later.",
    "作业名": "Assignment Name",
    "已关闭": "Closed",
    "最晚提交": "Cut-off Date",
    "评分截止": "Grading Due",
    "保存在线文本草稿": "Save Online Text Draft",
    "最终提交作业": "Submit Assignment",
    "当前作业允许编辑提交": "This assignment allows submission edits",
    "当前作业可能不允许编辑提交": "This assignment may not allow submission edits",
    "简介": "Overview",
    "讨论权限": "Discussion Permissions",
    "可发起讨论": "You Can Start a Discussion",
    "当前不可发起讨论": "You Cannot Start a Discussion Currently",
    "活动名": "Activity Name",
    "模块类型": "Module Type",
    "入口 URL": "Entry URL",
    "Mediasite 链接已复制": "Mediasite link copied",
    "提交状态": "Submission Status",
    "评分状态": "Grading Status",
    "反馈": "Feedback",
    "暂无": "None Yet",
    "未知": "Unknown",
    "未提交": "Not Submitted",
    "已提交": "Submitted",
    "草稿": "Draft",
    "已重新开启": "Reopened",
    "未评分": "Not Graded",
    "已评分": "Graded",
    "评分中": "Grading in Progress",
    "文件提交": "File Submission",
    "未限制": "No Limit",
    "保存文件草稿": "Save File Draft",
    "保存草稿": "Save Draft",
    "作业已提交": "Assignment Submitted",
    "草稿已保存，尚未最终提交": "Draft saved. Final submission is still required",
    "iSpace 已接受作业更新": "iSpace accepted the assignment update",
    "提交后将进入评分流程": "Your submission will enter the grading process",
    "接受 iSpace 作业提交声明": "Accept the iSpace Submission Statement",
    "最终提交": "Submit",
    "最终提交失败，请稍后重试。": "Final submission failed. Try again later.",
    "资源详情": "Resource Details",
    "讨论内容加载失败，请稍后重试。": "Could not load the discussion. Try again later.",
    "（无正文）": "(No Message Body)",
    "正在下载": "Downloading",
    "分享": "Share",
    "下载完成。": "Download complete.",
    "已加入下载任务。": "Download queued.",
    "下载失败，请稍后重试。": "Download failed. Try again later.",
    "官网页面加载失败": "Could not load the official page",
    "检查更新失败，请重试": "Could not check for updates. Try again",
    "无法打开官网，请重试": "Could not open the official website. Try again",
    "操作状态已更新": "Action status updated",
    "搜索": "Search",
    "选择课程": "Select Course",
    "请选择适用周": "Choose an applicable week",
    "上个月": "Previous Month",
    "下个月": "Next Month",
    "登录后可评价": "Sign in to leave a review",
    "页面已变化，请重试": "The page has changed. Try again",
    "评价已保存": "Review saved",
    "编辑记忆候选": "Edit Suggested Memory",
    "小U记忆暂不可用": "MiU Memory is temporarily unavailable",
    "已保存到小U记忆": "Saved to MiU Memory",
    "分析尚未完成，将在后台自动重试。":
        "Analysis is incomplete and will retry automatically in the background.",
    "正在准备邮件翻译…": "Preparing message translation…",
    "暂时无法生成翻译，请稍后重新打开。":
        "Could not generate a translation. Reopen this message later.",
    "无法准备回复邮件": "Could not prepare the reply",
    "保存邮件附件": "Save Email Attachment",
    "提醒已设置": "Reminder Set",
    "已批准记忆": "Approved Memory",
    "已使用": "Used",
    "无匹配": "No Match",
    "暂不可用": "Temporarily Unavailable",
    "请检查网络后重新建立登录会话。": "Check your connection and sign in again.",
    "不支持的内嵌图片格式": "Unsupported inline image format",
    "邮件正文": "Message Body",
    "重置": "Reset",
    "体态": "Posture",
    "肤色": "Skin Tone",
    "发型": "Hairstyle",
    "发色": "Hair Color",
    "上装": "Top",
    "下装": "Bottom",
    "鞋": "Shoes",
    "配饰": "Accessories",
    "自然": "Natural",
    "松弛": "Relaxed",
    "活力": "Energetic",
    "瓷白": "Porcelain",
    "暖色": "Warm",
    "小麦": "Tan",
    "短发": "Short",
    "微卷": "Wavy",
    "层次": "Layered",
    "齐肩": "Shoulder Length",
    "束发": "Tied Back",
    "墨黑": "Jet Black",
    "深棕": "Dark Brown",
    "栗色": "Chestnut",
    "灰棕": "Ash Brown",
    "蓝黑": "Blue Black",
    "校园卫衣": "Campus Hoodie",
    "棒球夹克": "Varsity Jacket",
    "通勤衬衫": "Casual Shirt",
    "冬季外套": "Winter Coat",
    "灰色束脚裤": "Gray Joggers",
    "黑色工装裤": "Black Cargo Pants",
    "蓝色牛仔裤": "Blue Jeans",
    "运动鞋": "Sneakers",
    "高帮鞋": "High Tops",
    "休闲鞋": "Casual Shoes",
    "无": "None",
    "斜挎包": "Crossbody Bag",
    "耳机": "Headphones",
    "双肩包": "Backpack",
    "围巾": "Scarf",
    "待机": "Idle",
    "开心": "Happy",
    "专注": "Focused",
    "思考": "Thinking",
    "学生虚拟形象": "Student Avatar",
    "编辑虚拟形象": "Edit Avatar",
    "PPTX 文件超过 64 MB，无法在学业模式中展开":
        "This PPTX file exceeds 64 MB and cannot be opened in Study Mode",
    "PPTX 无法读取": "Could not read the PPTX file",
    "历史选课参考暂时无法读取": "Past course insights are temporarily unavailable",
    "发表教师评价": "Write a Faculty Review",
    "编辑教师评价": "Edit Faculty Review",
    "教师评价加载失败": "Could not load faculty reviews",
    "暂无课表匹配评价": "No reviews match your timetable",
    "查看全部": "View All",
    "较随意": "Less Rigorous",
    "很认真": "Very Rigorous",
    "严格": "Strict",
    "宽松": "Lenient",
    "很少": "Rarely",
    "经常": "Often",
    "较轻": "Light",
    "较重": "Heavy",
    "请完成全部评分": "Complete all ratings",
    "未匹配课表": "No Timetable Match",
    "图书": "Book",
    "互动课程": "Interactive Lesson",
    "工作坊": "Workshop",
    "调查": "Survey",
    "协作页面": "Wiki",
    "词汇表": "Glossary",
    "学习包": "Learning Package",
    "内容包": "Content Package",
    "数据库": "Database",
    "外部工具": "External Tool",
    "文本与媒体": "Text & Media",
    "打开 iSpace 活动详情": "Open iSpace Activity Details",
  };

  static const Map<String, String> _chinese = <String, String>{
    'User Id': '用户名',
    'Enter your BNBU account': '输入 BNBU 账号',
    'Please enter your user ID': '请输入用户名',
    'Password': '密码',
    'Enter your iSpace password': '输入 iSpace 密码',
    'Please enter your password': '请输入密码',
    'Sign In': '登录',
    'Restoring previous session': '正在恢复登录状态',
  };
}

class _BnbuLocalizationsDelegate
    extends LocalizationsDelegate<BnbuLocalizations> {
  const _BnbuLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => BnbuLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<BnbuLocalizations> load(Locale locale) =>
      SynchronousFuture<BnbuLocalizations>(BnbuLocalizations(locale));

  @override
  bool shouldReload(_BnbuLocalizationsDelegate old) => false;
}

extension BnbuLocalizedBuildContext on BuildContext {
  BnbuLocalizations get l10n => BnbuLocalizations.of(this);
}

class BnbuText extends StatelessWidget {
  const BnbuText(
    this.data, {
    Key? key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.locale,
    this.softWrap,
    this.overflow,
    this.textScaler,
    this.maxLines,
    this.semanticsLabel,
    this.textWidthBasis,
    this.textHeightBehavior,
    this.selectionColor,
  }) : _textKey = key,
       super(key: null);

  final String data;
  final Key? _textKey;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final Locale? locale;
  final bool? softWrap;
  final TextOverflow? overflow;
  final TextScaler? textScaler;
  final int? maxLines;
  final String? semanticsLabel;
  final TextWidthBasis? textWidthBasis;
  final TextHeightBehavior? textHeightBehavior;
  final Color? selectionColor;

  @override
  Widget build(BuildContext context) {
    return Text(
      BnbuLocalizations.of(context).text(data),
      key: _textKey,
      style: style,
      strutStyle: strutStyle,
      textAlign: textAlign,
      textDirection: textDirection,
      locale: locale,
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      semanticsLabel: semanticsLabel == null
          ? null
          : BnbuLocalizations.of(context).text(semanticsLabel!),
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      selectionColor: selectionColor,
    );
  }
}
