import 'dart:async';

import 'package:bnbu_me/models/cis_checkin.dart';
import 'package:bnbu_me/state/app_session_controller.dart';

Map<String, dynamic> checkinProjectJson({
  int checked = 9,
  int required = 10,
  bool completed = false,
}) => {
  'id': 'assignment-1',
  'project': {
    'id': 'project-1',
    'nameEn': 'Synthetic lecture programme',
    'timeRang': {'begin': '2026-09-01 08:00:00', 'end': '2027-01-01 18:00:00'},
  },
  'minCheckinTimes': required,
  'studentCheckinTimes': checked,
  'studentFinishCheckin': completed,
};

Map<String, dynamic> checkinRecordJson({
  String id = 'record-1',
  Object? counting = false,
  bool completed = true,
}) => {
  'id': id,
  'projectItem': {
    'id': 'event-1',
    'nameEn': 'Synthetic event — science, society and student life',
    'nameCn': '合成活动：科学与校园生活',
    'counting': counting,
    'speaker': 'Synthetic speaker',
    'location': 'Synthetic room',
    'timeRang': {'begin': '2026-09-16 14:00:00', 'end': '2026-09-16 16:00:00'},
    'plusCount': 0,
  },
  'mainCheckinFinish': true,
  'mainCheckoutFinish': completed,
  'finish': completed,
  'checkinFinish': true,
  'checkoutFinish': completed,
  'checkinTime': '2026-09-16 13:55:00',
  'checkoutTime': completed ? '2026-09-16 16:02:00' : null,
};

Map<String, dynamic> checkinEnvelope(
  List<Map<String, dynamic>> rows, {
  int page = 1,
  int? total,
}) => {
  'success': true,
  'code': 200,
  'result': {'data': rows, 'pageNo': page, 'totalCount': total ?? rows.length},
};

class CheckinFixtureLease implements AppSessionLease {
  bool active = true;
  @override
  String get owner => 'synthetic-checkin';
  @override
  bool get isActive => active;
}

/// Used only by tests and the explicitly synthetic preview, never production.
class CheckinFixtureController extends AppSessionController {
  final lease = CheckinFixtureLease();
  Object? projectFailure;
  Object? recordFailure;
  Completer<void>? recordGate;
  int recordCalls = 0;
  int blankRecordPages = 0;
  bool unknownRecordStatistics = false;
  int projectCalls = 0;
  bool hasCachedProjects = false;
  @override
  CisCheckinPageData<CisCheckinProject>? cachedCheckinProjects() =>
      hasCachedProjects && lease.active
      ? CisCheckinPageData(items: projects, page: 1, hasMore: false)
      : null;
  List<CisCheckinProject> projects = [
    CisCheckinProject.fromJson(checkinProjectJson()),
    const CisCheckinProject(
      id: 'project-2',
      name: 'Synthetic AI literacy',
      requiredCount: 9,
      checkedCount: 12,
      completed: true,
    ),
    const CisCheckinProject(
      id: 'project-3',
      name: 'Synthetic zero requirement',
      requiredCount: 0,
      checkedCount: 0,
      completed: true,
    ),
  ];
  @override
  bool get isLoggedIn => lease.active;
  @override
  String get username => lease.owner;
  @override
  AppSessionLease? captureSessionLease() => lease.active ? lease : null;
  @override
  Future<CisCheckinPageData<CisCheckinProject>> loadCheckinProjects({
    int page = 1,
    bool forceRefresh = false,
  }) async {
    projectCalls++;
    if (projectFailure != null) throw projectFailure!;
    return CisCheckinPageData(items: projects, page: page, hasMore: false);
  }

  @override
  Future<CisCheckinPageData<CisCheckinRecord>> loadCheckinRecords({
    String? projectId,
    int page = 1,
    bool forceRefresh = false,
  }) async {
    recordCalls++;
    await recordGate?.future;
    if (recordFailure != null) throw recordFailure!;
    if (unknownRecordStatistics) {
      return CisCheckinPageData(
        items: const [],
        page: page,
        hasMore: false,
        hasUnknownStatistics: true,
      );
    }
    if (page <= blankRecordPages) {
      return CisCheckinPageData(items: const [], page: page, hasMore: true);
    }
    return CisCheckinPageData(
      items: [
        CisCheckinRecord.fromJson(
          checkinRecordJson(id: '${projectId ?? 'all'}-$page'),
        ),
        CisCheckinRecord.fromJson(
          checkinRecordJson(
            id: '${projectId ?? 'all'}-incomplete',
            completed: false,
          ),
        ),
      ],
      page: page,
      hasMore: false,
    );
  }

  void expire() {
    lease.active = false;
    notifyListeners();
  }
}
