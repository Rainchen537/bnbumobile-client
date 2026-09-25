import '../state/account_habits.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/campus_time.dart';
import '../models/ta_course_entry.dart';
import '../models/timeline_item.dart';
import '../models/timetable_data.dart';
import '../models/widget_snapshot.dart';
import 'app_statistics_service.dart';

enum DeadlineReminderMode { smart, fixed }

@immutable
class DeadlineReminderPreferences {
  const DeadlineReminderPreferences({
    this.mode = DeadlineReminderMode.smart,
    this.reminderCount = 3,
    this.fixedLeadMinutes = const <int>[1440, 480, 120],
    this.quietStartMinutes = 0,
    this.quietEndMinutes = 360,
  });

  final DeadlineReminderMode mode;
  final int reminderCount;
  final List<int> fixedLeadMinutes;
  final int quietStartMinutes;
  final int quietEndMinutes;

  List<int> get effectiveLeadMinutes {
    if (mode == DeadlineReminderMode.fixed) {
      return List<int>.unmodifiable(fixedLeadMinutes);
    }
    return switch (reminderCount) {
      1 => const <int>[120],
      2 => const <int>[1440, 120],
      _ => const <int>[1440, 480, 120],
    };
  }

  DeadlineReminderPreferences copyWith({
    DeadlineReminderMode? mode,
    int? reminderCount,
    List<int>? fixedLeadMinutes,
    int? quietStartMinutes,
    int? quietEndMinutes,
  }) {
    return DeadlineReminderPreferences(
      mode: mode ?? this.mode,
      reminderCount: reminderCount ?? this.reminderCount,
      fixedLeadMinutes: fixedLeadMinutes ?? this.fixedLeadMinutes,
      quietStartMinutes: quietStartMinutes ?? this.quietStartMinutes,
      quietEndMinutes: quietEndMinutes ?? this.quietEndMinutes,
    );
  }
}

class DeadlineReminderService {
  DeadlineReminderService({
    FlutterLocalNotificationsPlugin? notificationsPlugin,
  }) : _notificationsPlugin =
           notificationsPlugin ?? FlutterLocalNotificationsPlugin();

  static const String _enabledPreferenceKey = 'deadline_reminders.enabled';
  static const String _courseEnabledPreferenceKey = 'course_reminders.enabled';
  static const String _deadlineLeadMinutesPreferenceKey =
      'deadline_reminders.lead_minutes';
  static const String _deadlineModePreferenceKey = 'deadline_reminders.mode_v2';
  static const String _deadlineReminderCountPreferenceKey =
      'deadline_reminders.count_v2';
  static const String _deadlineFixedLeadMinutesPreferenceKey =
      'deadline_reminders.fixed_lead_minutes_v2';
  static const String _deadlineQuietStartPreferenceKey =
      'deadline_reminders.quiet_start_minutes_v2';
  static const String _deadlineQuietEndPreferenceKey =
      'deadline_reminders.quiet_end_minutes_v2';
  static const String _courseLeadMinutesPreferenceKey =
      'course_reminders.lead_minutes';
  static const String _typedNotificationIdsMigratedPreferenceKey =
      'local_notifications.typed_ids_v1';
  static const String _channelId = 'ddl_reminders';
  static const String _channelName = 'DDL reminders';
  static const String _channelDescription =
      'Upcoming iSpace deadline reminders';
  static const String _assistantChannelId = 'small_u_reminders';
  static const String _assistantChannelName = '小U提醒';
  static const String _assistantChannelDescription = '由你确认后创建的小U本地提醒';
  static const String _courseChannelId = 'course_reminders';
  static const String _courseChannelName = '课程提醒';
  static const String _courseChannelDescription = '即将开始的课程提醒';
  static const int _iosPendingNotificationLimit = 64;
  static const int _iosDeadlineReminderBudget = 48;
  static const int _iosCourseReminderBudget = 16;
  static const int _notificationTypeMask = 0x60000000;
  static const int _notificationHashMask = 0x1fffffff;
  static const int _courseNotificationIdFlag = 0x20000000;
  static const int _assistantNotificationIdFlag = 0x40000000;
  static const int defaultCourseLeadMinutes = 15;
  static const int defaultDeadlineLeadMinutes = 1440;
  static const int minimumCourseLeadMinutes = 5;
  static const int maximumCourseLeadMinutes = 120;
  static const int minimumDeadlineLeadMinutes = 30;
  static const int maximumDeadlineLeadMinutes = 2880;
  static const List<int> courseLeadMinuteOptions = <int>[
    5,
    10,
    15,
    30,
    60,
    120,
  ];
  static const List<int> deadlineLeadMinuteOptions = <int>[
    30,
    60,
    120,
    360,
    480,
    720,
    1440,
    2880,
  ];

  final FlutterLocalNotificationsPlugin _notificationsPlugin;
  AppStatisticsService? statistics;
  Future<String?> _statisticsPayload(
    String kind,
    int id,
    DateTime triggerAt,
    String? payload,
  ) async {
    try {
      return await statistics?.notificationPayload(
            kind: kind,
            id: id,
            triggerAt: triggerAt,
            payload: payload,
          ) ??
          payload;
    } catch (_) {
      return payload; // Telemetry/storage failure must never suppress the reminder.
    }
  }

  Future<void>? _initializationFuture;
  Future<void> _notificationMutation = Future<void>.value();

  Future<bool> loadEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_enabledPreferenceKey) ?? true;
  }

  Future<bool> loadCourseEnabled() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(_courseEnabledPreferenceKey) ?? true;
  }

  Future<int> loadDeadlineLeadMinutes() async {
    final preferences = await SharedPreferences.getInstance();
    return _validatedDeadlineLeadMinutes(
      preferences.getInt(_deadlineLeadMinutesPreferenceKey),
    );
  }

  Future<DeadlineReminderPreferences> loadDeadlineReminderPreferences() async {
    if (AccountHabits.shared.managed) {
      final p = AccountHabits.shared.read<Map?>(
        'deadline_reminders.policy',
        null,
      );
      if (p == null) return const DeadlineReminderPreferences();
      return DeadlineReminderPreferences(
        mode: p['mode'] == 'fixed'
            ? DeadlineReminderMode.fixed
            : DeadlineReminderMode.smart,
        reminderCount: p['count'] as int,
        fixedLeadMinutes: (p['leads'] as List).cast<int>(),
        quietStartMinutes: p['quietStart'] as int,
        quietEndMinutes: p['quietEnd'] as int,
      );
    }
    final preferences = await SharedPreferences.getInstance();
    final storedMode = preferences.getString(_deadlineModePreferenceKey);
    if (storedMode == null) {
      final legacyLead = preferences.getInt(_deadlineLeadMinutesPreferenceKey);
      if (legacyLead != null) {
        return _validatedDeadlinePreferences(
          DeadlineReminderPreferences(
            mode: DeadlineReminderMode.fixed,
            reminderCount: 1,
            fixedLeadMinutes: <int>[
              legacyLead.clamp(
                minimumDeadlineLeadMinutes,
                maximumDeadlineLeadMinutes,
              ),
            ],
          ),
        );
      }
      return const DeadlineReminderPreferences();
    }

    final fixedLeads = preferences
        .getStringList(_deadlineFixedLeadMinutesPreferenceKey)
        ?.map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
    return _validatedDeadlinePreferences(
      DeadlineReminderPreferences(
        mode: storedMode == DeadlineReminderMode.fixed.name
            ? DeadlineReminderMode.fixed
            : DeadlineReminderMode.smart,
        reminderCount:
            preferences.getInt(_deadlineReminderCountPreferenceKey) ?? 3,
        fixedLeadMinutes:
            fixedLeads ?? const DeadlineReminderPreferences().fixedLeadMinutes,
        quietStartMinutes:
            preferences.getInt(_deadlineQuietStartPreferenceKey) ?? 0,
        quietEndMinutes:
            preferences.getInt(_deadlineQuietEndPreferenceKey) ?? 360,
      ),
    );
  }

  Future<int> loadCourseLeadMinutes() async {
    if (AccountHabits.shared.managed) {
      return AccountHabits.shared.read(
        'course_reminders.lead_minutes',
        defaultCourseLeadMinutes,
      );
    }
    final preferences = await SharedPreferences.getInstance();
    return _validatedCourseLeadMinutes(
      preferences.getInt(_courseLeadMinutesPreferenceKey),
    );
  }

  Future<int> setDeadlineLeadMinutes(int value) async {
    final validated = _validatedDeadlineLeadMinutes(value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_deadlineLeadMinutesPreferenceKey, validated);
    await setDeadlineReminderPreferences(
      DeadlineReminderPreferences(
        mode: DeadlineReminderMode.fixed,
        reminderCount: 1,
        fixedLeadMinutes: <int>[validated],
      ),
    );
    return validated;
  }

  Future<DeadlineReminderPreferences> setDeadlineReminderPreferences(
    DeadlineReminderPreferences value,
  ) async {
    final validated = _validatedDeadlinePreferences(value);
    if (AccountHabits.shared.managed) {
      await AccountHabits.shared.set('deadline_reminders.policy', {
        'mode': validated.mode.name,
        'count': validated.reminderCount,
        'leads': validated.fixedLeadMinutes,
        'quietStart': validated.quietStartMinutes,
        'quietEnd': validated.quietEndMinutes,
      });
      return validated;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _deadlineModePreferenceKey,
      validated.mode.name,
    );
    await preferences.setInt(
      _deadlineReminderCountPreferenceKey,
      validated.reminderCount,
    );
    await preferences.setStringList(
      _deadlineFixedLeadMinutesPreferenceKey,
      validated.fixedLeadMinutes.map((value) => '$value').toList(),
    );
    await preferences.setInt(
      _deadlineQuietStartPreferenceKey,
      validated.quietStartMinutes,
    );
    await preferences.setInt(
      _deadlineQuietEndPreferenceKey,
      validated.quietEndMinutes,
    );
    return validated;
  }

  Future<int> setCourseLeadMinutes(int value) async {
    final validated = _validatedCourseLeadMinutes(value);
    if (AccountHabits.shared.managed) {
      await AccountHabits.shared.set(
        'course_reminders.lead_minutes',
        validated,
      );
      return validated;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_courseLeadMinutesPreferenceKey, validated);
    return validated;
  }

  Future<String?> enable() {
    return _withNotificationMutation(() async {
      if (kIsWeb) {
        return '当前平台暂不支持 DDL 提醒。';
      }
      await _ensureInitialized();
      final permissionError = await _requestPermissions();
      if (permissionError != null) {
        await _setEnabled(false);
        await _cancelDeadlineReminders();
        return permissionError;
      }
      await _setEnabled(true);
      return null;
    });
  }

  Future<void> disable() {
    return _withNotificationMutation(() async {
      await _setEnabled(false);
      await _ensureInitialized();
      await _cancelDeadlineReminders();
    });
  }

  Future<String?> enableCourseNotifications() {
    return _withNotificationMutation(() async {
      if (kIsWeb) {
        return '当前平台暂不支持课表通知。';
      }
      await _ensureInitialized();
      final permissionError = await _requestPermissions(label: '课表通知');
      if (permissionError != null) {
        await _setCourseEnabled(false);
        await _migrateNotificationIdsIfNeeded();
        await _cancelCourseReminders();
        return permissionError;
      }
      await _setCourseEnabled(true);
      return null;
    });
  }

  Future<void> disableCourseNotifications() {
    return _withNotificationMutation(() async {
      await _setCourseEnabled(false);
      await _ensureInitialized();
      await _migrateNotificationIdsIfNeeded();
      await _cancelCourseReminders();
    });
  }

  Future<void> synchronize(List<TimelineItem> items) {
    return _withNotificationMutation(() async {
      if (!await loadEnabled()) {
        return;
      }
      await _ensureInitialized();
      await _migrateNotificationIdsIfNeeded();
      await _cancelDeadlineReminders();

      final preferences = await loadDeadlineReminderPreferences();
      final reminders = _buildPendingReminders(items, preferences: preferences);
      final pendingCount = Platform.isIOS
          ? (await _notificationsPlugin.pendingNotificationRequests()).length
          : 0;
      final limit = Platform.isIOS
          ? reminders.length.clamp(
              0,
              (_iosPendingNotificationLimit - pendingCount)
                  .clamp(0, _iosPendingNotificationLimit)
                  .clamp(0, _iosDeadlineReminderBudget),
            )
          : reminders.length;

      final details = NotificationDetails(
        android: const AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification_status',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
        windows: const WindowsNotificationDetails(),
      );

      for (final reminder in reminders.take(limit)) {
        await _notificationsPlugin.zonedSchedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          scheduledDate: tz.TZDateTime.from(reminder.triggerAt, tz.local),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: await _statisticsPayload(
            'ddl',
            reminder.id,
            reminder.triggerAt,
            reminder.payload,
          ),
        );
      }
    });
  }

  Future<void> synchronizeCourses(
    TimetableData timetable, {
    List<TaCourseEntry> fixedSchedules = const [],
  }) {
    return _withNotificationMutation(() async {
      if (!await loadCourseEnabled()) {
        return;
      }
      await _ensureInitialized();
      await _migrateNotificationIdsIfNeeded();
      await _cancelCourseReminders();

      final leadMinutes = await loadCourseLeadMinutes();
      final reminders = _buildPendingCourseReminders(
        timetable,
        fixedSchedules: fixedSchedules,
        leadMinutes: leadMinutes,
      );
      final pendingCount = Platform.isIOS
          ? (await _notificationsPlugin.pendingNotificationRequests()).length
          : 0;
      final limit = Platform.isIOS
          ? reminders.length.clamp(
              0,
              (_iosPendingNotificationLimit - pendingCount)
                  .clamp(0, _iosPendingNotificationLimit)
                  .clamp(0, _iosCourseReminderBudget),
            )
          : reminders.length;

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _courseChannelId,
          _courseChannelName,
          channelDescription: _courseChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification_status',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
        windows: WindowsNotificationDetails(),
      );

      for (final reminder in reminders.take(limit)) {
        await _notificationsPlugin.zonedSchedule(
          id: reminder.id,
          title: reminder.title,
          body: reminder.body,
          scheduledDate: tz.TZDateTime.from(reminder.triggerAt, tz.local),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: await _statisticsPayload(
            'schedule',
            reminder.id,
            reminder.triggerAt,
            reminder.payload,
          ),
        );
      }
    });
  }

  @visibleForTesting
  List<Map<String, Object?>> buildCourseNotificationPlanForTesting(
    TimetableData timetable, {
    required DateTime now,
    int leadMinutes = defaultCourseLeadMinutes,
    List<TaCourseEntry> fixedSchedules = const [],
  }) {
    return _buildPendingCourseReminders(
          timetable,
          fixedSchedules: fixedSchedules,
          now: now,
          leadMinutes: _validatedCourseLeadMinutes(leadMinutes),
        )
        .map(
          (reminder) => <String, Object?>{
            'title': reminder.title,
            'body': reminder.body,
            'triggerAt': reminder.triggerAt,
            'payload': reminder.payload,
          },
        )
        .toList(growable: false);
  }

  @visibleForTesting
  List<Map<String, Object?>> buildDeadlineNotificationPlanForTesting(
    List<TimelineItem> items, {
    required DateTime now,
    DeadlineReminderPreferences preferences =
        const DeadlineReminderPreferences(),
  }) {
    return _buildPendingReminders(
          items,
          now: now,
          preferences: _validatedDeadlinePreferences(preferences),
        )
        .map(
          (reminder) => <String, Object?>{
            'title': reminder.title,
            'body': reminder.body,
            'triggerAt': reminder.triggerAt,
            'payload': reminder.payload,
          },
        )
        .toList(growable: false);
  }

  List<DateTime> previewDeadlineReminderTimes(
    TimelineItem item, {
    required DeadlineReminderPreferences preferences,
    DateTime? now,
  }) {
    return _buildPendingReminders(
      <TimelineItem>[item],
      preferences: _validatedDeadlinePreferences(preferences),
      now: now,
    ).map((reminder) => reminder.triggerAt).toList(growable: false);
  }

  Future<void> cancelAll() {
    return _withNotificationMutation(_cancelAll);
  }

  Future<String?> scheduleAssistantReminder({
    required String title,
    required String body,
    required DateTime scheduledAt,
  }) {
    return _withNotificationMutation(() async {
      if (kIsWeb) {
        return '当前平台暂不支持本地提醒。';
      }
      final now = DateTime.now();
      final localScheduledAt = scheduledAt.toLocal();
      if (!localScheduledAt.isAfter(now.add(const Duration(minutes: 1)))) {
        return '提醒时间必须至少晚于现在 1 分钟。';
      }
      if (localScheduledAt.isAfter(now.add(const Duration(days: 366)))) {
        return '提醒时间不能超过未来 366 天。';
      }
      await _ensureInitialized();
      final permissionError = await _requestPermissions();
      if (permissionError != null) {
        return permissionError.replaceFirst('DDL 提醒', '本地提醒');
      }
      if (Platform.isIOS) {
        final pending = await _notificationsPlugin
            .pendingNotificationRequests();
        if (pending.length >= _iosPendingNotificationLimit) {
          return '系统待处理提醒已达到上限，请先删除部分提醒。';
        }
      }

      final notificationId = _assistantNotificationId(
        title: title,
        scheduledAt: localScheduledAt,
      );
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          _assistantChannelId,
          _assistantChannelName,
          channelDescription: _assistantChannelDescription,
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification_status',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
        windows: WindowsNotificationDetails(),
      );
      await _notificationsPlugin.zonedSchedule(
        id: notificationId,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(localScheduledAt, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'assistant-reminder:$notificationId',
      );
      return null;
    });
  }

  Future<void> _cancelAll() async {
    try {
      await statistics?.observeReminders();
    } catch (_) {
      /* evidence unavailable */
    }
    await _ensureInitialized();
    await _notificationsPlugin.cancelAll();
  }

  Future<void> _cancelDeadlineReminders() async {
    try {
      await statistics?.observeReminders();
    } catch (_) {
      /* evidence unavailable */
    }
    await _migrateNotificationIdsIfNeeded();
    final pending = await _notificationsPlugin.pendingNotificationRequests();
    for (final request in pending) {
      if (_isDeadlineNotificationId(request.id)) {
        await _notificationsPlugin.cancel(id: request.id);
      }
    }
  }

  Future<void> _cancelCourseReminders() async {
    try {
      await statistics?.observeReminders();
    } catch (_) {
      /* evidence unavailable */
    }
    final pending = await _notificationsPlugin.pendingNotificationRequests();
    for (final request in pending) {
      if (_isCourseNotificationId(request.id)) {
        await _notificationsPlugin.cancel(id: request.id);
      }
    }
  }

  Future<void> _migrateNotificationIdsIfNeeded() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_typedNotificationIdsMigratedPreferenceKey) ==
        true) {
      return;
    }
    final pending = await _notificationsPlugin.pendingNotificationRequests();
    for (final request in pending) {
      if (!_isAssistantNotificationId(request.id)) {
        await _notificationsPlugin.cancel(id: request.id);
      }
    }
    await preferences.setBool(_typedNotificationIdsMigratedPreferenceKey, true);
  }

  Future<T> _withNotificationMutation<T>(Future<T> Function() operation) async {
    final previous = _notificationMutation;
    final completer = Completer<void>();
    _notificationMutation = completer.future;
    await previous;
    try {
      return await operation();
    } finally {
      completer.complete();
    }
  }

  Future<void> _ensureInitialized() {
    return _initializationFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    tz.initializeTimeZones();
    if (!kIsWeb) {
      try {
        final timezone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(timezone.identifier));
      } catch (_) {
        // Keep the default timezone if lookup fails.
      }
    }

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification_status'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      windows: WindowsInitializationSettings(
        appName: 'BNBU.ME',
        appUserModelId: 'BNBUME.HandsBNBU',
        guid: '857e820f-2934-4ea3-b17a-2ce4d6c37779',
      ),
    );

    await _notificationsPlugin.initialize(settings: settings);

    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.max,
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    const assistantChannel = AndroidNotificationChannel(
      _assistantChannelId,
      _assistantChannelName,
      description: _assistantChannelDescription,
      importance: Importance.max,
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(assistantChannel);
    const courseChannel = AndroidNotificationChannel(
      _courseChannelId,
      _courseChannelName,
      description: _courseChannelDescription,
      importance: Importance.max,
    );
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(courseChannel);
  }

  Future<void> _setEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledPreferenceKey, value);
  }

  Future<void> _setCourseEnabled(bool value) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_courseEnabledPreferenceKey, value);
  }

  Future<String?> _requestPermissions({String label = 'DDL 提醒'}) async {
    if (Platform.isAndroid) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notificationsGranted = await androidPlugin
          ?.requestNotificationsPermission();
      if (notificationsGranted == false) {
        return '未授予系统通知权限，$label未开启。';
      }
      final exactAlarmGranted = await androidPlugin
          ?.requestExactAlarmsPermission();
      if (exactAlarmGranted == false) {
        return '未授予精确提醒权限，$label未开启。';
      }
      return null;
    }

    if (Platform.isIOS || Platform.isMacOS) {
      final granted = Platform.isIOS
          ? await _notificationsPlugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: false, sound: true)
          : await _notificationsPlugin
                .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: false, sound: true);
      if (granted == false) {
        return '未授予系统通知权限，$label未开启。';
      }
    }

    return null;
  }

  List<_ScheduledReminder> _buildPendingReminders(
    List<TimelineItem> items, {
    required DeadlineReminderPreferences preferences,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final drafts = <_DeadlineReminderDraft>[];

    for (final item in items) {
      final due = item.sortTime?.toLocal();
      if (due == null || !due.isAfter(effectiveNow)) {
        continue;
      }

      final itemDrafts = <_DeadlineReminderDraft>[];
      for (final leadMinutes in preferences.effectiveLeadMinutes) {
        var triggerAt = due.subtract(Duration(minutes: leadMinutes));
        if (preferences.mode == DeadlineReminderMode.smart) {
          triggerAt = _adjustLateSmartReminder(
            triggerAt,
            preferences: preferences,
          );
        }
        final quietWindow = _quietWindowContaining(
          triggerAt,
          preferences: preferences,
        );
        final isSleepDigest = quietWindow != null;
        if (quietWindow != null) {
          triggerAt = quietWindow.start.subtract(const Duration(minutes: 10));
        }
        if (!triggerAt.isAfter(effectiveNow)) {
          continue;
        }
        itemDrafts.add(
          _DeadlineReminderDraft(
            item: item,
            due: due,
            triggerAt: triggerAt,
            isSleepDigest: isSleepDigest,
          ),
        );
      }

      final dueQuietWindow = _quietWindowCoveringDue(
        due,
        preferences: preferences,
      );
      if (dueQuietWindow != null) {
        final digestAt = dueQuietWindow.start.subtract(
          const Duration(minutes: 10),
        );
        if (digestAt.isAfter(effectiveNow) &&
            !itemDrafts.any((draft) => draft.triggerAt == digestAt)) {
          final digestDraft = _DeadlineReminderDraft(
            item: item,
            due: due,
            triggerAt: digestAt,
            isSleepDigest: true,
          );
          if (itemDrafts.length >= preferences.effectiveLeadMinutes.length &&
              itemDrafts.isNotEmpty) {
            itemDrafts.sort(
              (left, right) => left.triggerAt.compareTo(right.triggerAt),
            );
            itemDrafts[itemDrafts.length - 1] = digestDraft;
          } else {
            itemDrafts.add(digestDraft);
          }
        }
      }

      final uniqueByTrigger = <DateTime, _DeadlineReminderDraft>{};
      for (final draft in itemDrafts) {
        final existing = uniqueByTrigger[draft.triggerAt];
        uniqueByTrigger[draft.triggerAt] = existing == null
            ? draft
            : draft.copyWith(
                isSleepDigest: existing.isSleepDigest || draft.isSleepDigest,
              );
      }
      drafts.addAll(_mergeCrowdedDeadlineDrafts(uniqueByTrigger.values));
    }

    final reminders = <_ScheduledReminder>[];
    final sleepGroups = <DateTime, List<_DeadlineReminderDraft>>{};
    for (final draft in drafts) {
      if (draft.isSleepDigest) {
        sleepGroups.putIfAbsent(draft.triggerAt, () => []).add(draft);
        continue;
      }
      reminders.add(_scheduledDeadlineReminder(draft));
    }
    for (final entry in sleepGroups.entries) {
      final uniqueItems = <String, _DeadlineReminderDraft>{};
      for (final draft in entry.value) {
        uniqueItems[_deadlineIdentity(draft.item)] = draft;
      }
      final group = uniqueItems.values.toList()
        ..sort((left, right) => left.due.compareTo(right.due));
      if (group.length == 1) {
        reminders.add(_scheduledDeadlineReminder(group.single));
      } else {
        reminders.add(_scheduledDeadlineDigest(group, entry.key));
      }
    }
    reminders.sort((left, right) => left.triggerAt.compareTo(right.triggerAt));
    return reminders;
  }

  _ScheduledReminder _scheduledDeadlineReminder(_DeadlineReminderDraft draft) {
    final remaining = draft.due.difference(draft.triggerAt);
    final title = draft.item.title.trim().isEmpty
        ? 'DDL 即将截止'
        : draft.item.title.trim();
    return _ScheduledReminder(
      id: _notificationIdFor(draft.item, triggerAt: draft.triggerAt),
      title: title,
      body:
          '${_courseLabel(draft.item.courseName)} · 距截止还有 ${_formatDuration(remaining)}\n${_formatDue(draft.due)}',
      triggerAt: draft.triggerAt,
      payload: draft.item.url,
    );
  }

  List<_DeadlineReminderDraft> _mergeCrowdedDeadlineDrafts(
    Iterable<_DeadlineReminderDraft> drafts,
  ) {
    final sorted = drafts.toList()
      ..sort((left, right) => left.triggerAt.compareTo(right.triggerAt));
    final merged = <_DeadlineReminderDraft>[];
    for (final draft in sorted) {
      if (merged.isNotEmpty &&
          draft.triggerAt.difference(merged.last.triggerAt) <
              const Duration(hours: 2)) {
        final previous = merged.removeLast();
        merged.add(
          draft.copyWith(
            isSleepDigest: previous.isSleepDigest || draft.isSleepDigest,
          ),
        );
      } else {
        merged.add(draft);
      }
    }
    return merged;
  }

  _ScheduledReminder _scheduledDeadlineDigest(
    List<_DeadlineReminderDraft> drafts,
    DateTime triggerAt,
  ) {
    final body = drafts
        .take(3)
        .map((draft) => '${_formatClock(draft.due)} ${draft.item.title.trim()}')
        .join('\n');
    final remaining = drafts.length - 3;
    final suffix = remaining > 0 ? '\n另有 $remaining 项' : '';
    return _ScheduledReminder(
      id: _digestNotificationId(drafts, triggerAt),
      title: '免打扰前：${drafts.length} 项 DDL',
      body: '$body$suffix',
      triggerAt: triggerAt,
      payload: 'bnbume://ispace',
    );
  }

  List<_ScheduledReminder> _buildPendingCourseReminders(
    TimetableData timetable, {
    List<TaCourseEntry> fixedSchedules = const [],
    required int leadMinutes,
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now();
    final snapshot = buildBnbuWidgetSnapshot(
      timetable: timetable,
      timelineItems: const <TimelineItem>[],
      taCourses: fixedSchedules,
      now: effectiveNow,
    );
    final reminders = <_ScheduledReminder>[];
    final seen = <int>{};
    for (final course in snapshot.courses) {
      final triggerAt = course.startsAt.toLocal().subtract(
        Duration(minutes: leadMinutes),
      );
      if (!triggerAt.isAfter(effectiveNow)) {
        continue;
      }
      final id = _courseNotificationId(course);
      if (!seen.add(id)) {
        continue;
      }
      final room = course.room.trim().isEmpty ? '教室待定' : course.room.trim();
      reminders.add(
        _ScheduledReminder(
          id: id,
          title: course.title.trim().isEmpty ? '课程即将开始' : course.title.trim(),
          body: '$room · ${_formatCourseRange(course.startsAt, course.endsAt)}',
          triggerAt: triggerAt,
          payload: 'bnbume://schedule',
        ),
      );
    }
    reminders.sort((left, right) => left.triggerAt.compareTo(right.triggerAt));
    return reminders;
  }

  int _notificationIdFor(TimelineItem item, {required DateTime triggerAt}) {
    final source =
        '${_deadlineIdentity(item)}:${triggerAt.toUtc().microsecondsSinceEpoch}';
    return _deadlineNotificationHash(source);
  }

  int _digestNotificationId(
    List<_DeadlineReminderDraft> drafts,
    DateTime triggerAt,
  ) {
    final identities = drafts
        .map((draft) => _deadlineIdentity(draft.item))
        .join('|');
    return _deadlineNotificationHash(
      'digest:${triggerAt.toUtc().microsecondsSinceEpoch}:$identities',
    );
  }

  int _deadlineNotificationHash(String source) {
    var hash = 0;
    for (final codeUnit in source.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }
    return hash & _notificationHashMask;
  }

  int _courseNotificationId(BnbuWidgetCourseOccurrence course) {
    final source =
        '${course.code}:${course.title}:${course.room}:${course.startsAt.toUtc().microsecondsSinceEpoch}';
    var hash = 0;
    for (final codeUnit in source.codeUnits) {
      hash = ((hash * 31) + codeUnit) & _notificationHashMask;
    }
    return _courseNotificationIdFlag | hash;
  }

  int _assistantNotificationId({
    required String title,
    required DateTime scheduledAt,
  }) {
    final source = '$title:${scheduledAt.toUtc().microsecondsSinceEpoch}';
    var hash = 0;
    for (final codeUnit in source.codeUnits) {
      hash = ((hash * 31) + codeUnit) & _notificationHashMask;
    }
    return _assistantNotificationIdFlag | hash;
  }

  bool _isAssistantNotificationId(int id) =>
      (id & _assistantNotificationIdFlag) != 0;

  bool _isCourseNotificationId(int id) =>
      (id & _notificationTypeMask) == _courseNotificationIdFlag;

  bool _isDeadlineNotificationId(int id) => (id & _notificationTypeMask) == 0;

  String _deadlineIdentity(TimelineItem item) =>
      '${item.id}:${item.courseId}:${item.instanceId}:${item.sortTime?.millisecondsSinceEpoch ?? 0}';

  String _courseLabel(String courseName) {
    final normalized = courseName.trim();
    return normalized.isEmpty ? 'iSpace' : normalized;
  }

  String _formatDuration(Duration duration) {
    final totalMinutes = duration.inMinutes;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '$minutes 分钟';
    if (minutes == 0) return '$hours 小时';
    return '$hours 小时 $minutes 分钟';
  }

  int _validatedCourseLeadMinutes(int? value) {
    if (value != null && value > 0 && value < minimumCourseLeadMinutes) {
      return minimumCourseLeadMinutes;
    }
    if (value != null &&
        value >= minimumCourseLeadMinutes &&
        value <= maximumCourseLeadMinutes) {
      return value;
    }
    return defaultCourseLeadMinutes;
  }

  int _validatedDeadlineLeadMinutes(int? value) {
    if (value != null &&
        value >= minimumDeadlineLeadMinutes &&
        value <= maximumDeadlineLeadMinutes) {
      return value;
    }
    return defaultDeadlineLeadMinutes;
  }

  DeadlineReminderPreferences _validatedDeadlinePreferences(
    DeadlineReminderPreferences value,
  ) {
    final reminderCount = value.reminderCount.clamp(1, 3);
    final fixedLeadMinutes =
        value.fixedLeadMinutes
            .where(
              (lead) =>
                  lead >= minimumDeadlineLeadMinutes &&
                  lead <= maximumDeadlineLeadMinutes,
            )
            .toSet()
            .toList()
          ..sort((left, right) => right.compareTo(left));
    final safeFixedLeads = fixedLeadMinutes.take(3).toList(growable: false);
    final quietStart = value.quietStartMinutes.clamp(0, 1439);
    var quietEnd = value.quietEndMinutes.clamp(0, 1439);
    if (quietEnd == quietStart) {
      quietEnd = (quietStart + 360) % 1440;
    }
    return DeadlineReminderPreferences(
      mode: value.mode,
      reminderCount: reminderCount,
      fixedLeadMinutes: safeFixedLeads.isEmpty
          ? const <int>[1440, 480, 120]
          : safeFixedLeads,
      quietStartMinutes: quietStart,
      quietEndMinutes: quietEnd,
    );
  }

  DateTime _adjustLateSmartReminder(
    DateTime triggerAt, {
    required DeadlineReminderPreferences preferences,
  }) {
    final quietStart = _dateAtMinutes(triggerAt, preferences.quietStartMinutes);
    final nextQuietStart = quietStart.isAfter(triggerAt)
        ? quietStart
        : quietStart.add(const Duration(days: 1));
    final comfortableEvening = nextQuietStart.subtract(
      const Duration(hours: 2),
    );
    if (triggerAt.isAfter(comfortableEvening) &&
        triggerAt.isBefore(nextQuietStart)) {
      return comfortableEvening;
    }
    return triggerAt;
  }

  _QuietWindow? _quietWindowContaining(
    DateTime moment, {
    required DeadlineReminderPreferences preferences,
  }) {
    for (final dayOffset in const <int>[-1, 0]) {
      final anchor = moment.add(Duration(days: dayOffset));
      final start = _dateAtMinutes(anchor, preferences.quietStartMinutes);
      var end = _dateAtMinutes(anchor, preferences.quietEndMinutes);
      if (!end.isAfter(start)) {
        end = end.add(const Duration(days: 1));
      }
      if (!moment.isBefore(start) && moment.isBefore(end)) {
        return _QuietWindow(start: start, end: end);
      }
    }
    return null;
  }

  _QuietWindow? _quietWindowCoveringDue(
    DateTime due, {
    required DeadlineReminderPreferences preferences,
  }) {
    for (final dayOffset in const <int>[-1, 0]) {
      final anchor = due.add(Duration(days: dayOffset));
      final start = _dateAtMinutes(anchor, preferences.quietStartMinutes);
      var end = _dateAtMinutes(anchor, preferences.quietEndMinutes);
      if (!end.isAfter(start)) {
        end = end.add(const Duration(days: 1));
      }
      final coveredEnd = end.add(const Duration(hours: 1));
      if (!due.isBefore(start) && !due.isAfter(coveredEnd)) {
        return _QuietWindow(start: start, end: end);
      }
    }
    return null;
  }

  DateTime _dateAtMinutes(DateTime date, int minutes) =>
      DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);

  String _formatClock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  String _formatDue(DateTime due) {
    final month = due.month.toString().padLeft(2, '0');
    final day = due.day.toString().padLeft(2, '0');
    final hour = due.hour.toString().padLeft(2, '0');
    final minute = due.minute.toString().padLeft(2, '0');
    return '截止时间 $month-$day $hour:$minute';
  }

  String _formatCourseRange(DateTime startsAt, DateTime endsAt) {
    final starts = toBnbuCampusClock(startsAt);
    final ends = toBnbuCampusClock(endsAt);
    String clock(DateTime value) =>
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '北京时间 ${clock(starts)}–${clock(ends)}';
  }
}

class _ScheduledReminder {
  const _ScheduledReminder({
    required this.id,
    required this.title,
    required this.body,
    required this.triggerAt,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final DateTime triggerAt;
  final String payload;
}

class _DeadlineReminderDraft {
  const _DeadlineReminderDraft({
    required this.item,
    required this.due,
    required this.triggerAt,
    required this.isSleepDigest,
  });

  final TimelineItem item;
  final DateTime due;
  final DateTime triggerAt;
  final bool isSleepDigest;

  _DeadlineReminderDraft copyWith({bool? isSleepDigest}) {
    return _DeadlineReminderDraft(
      item: item,
      due: due,
      triggerAt: triggerAt,
      isSleepDigest: isSleepDigest ?? this.isSleepDigest,
    );
  }
}

class _QuietWindow {
  const _QuietWindow({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}
