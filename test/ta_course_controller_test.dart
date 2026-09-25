import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/ta_course_entry.dart';
import 'package:bnbu_me/models/timetable_data.dart';
import 'package:bnbu_me/services/ta_course_repository.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/ta_course_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('switching accounts and logout do not leak entries', () async {
    final session = _SessionController('student01');
    final taCourses = TaCourseController(
      sessionController: session,
      repository: TaCourseRepository(store: _MemoryTaCourseStore()),
    );
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });
    await taCourses.reload();
    await taCourses.addEntry(_entry(id: 'first'), expectedRevision: 0);

    session.switchOwner('student02');
    await taCourses.reload();

    expect(taCourses.entries, isEmpty);
    await taCourses.addEntry(_entry(id: 'second'), expectedRevision: 0);

    session.switchOwner(null);
    expect(taCourses.entries, isEmpty);

    session.switchOwner('student01');
    await taCourses.reload();

    expect(taCourses.entries.single.id, 'first');
  });

  test('save errors are observable', () async {
    final session = _SessionController('student01');
    final taCourses = TaCourseController(
      sessionController: session,
      repository: TaCourseRepository(
        store: _MemoryTaCourseStore(failSetString: true),
      ),
    );
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });
    await taCourses.reload();

    final result = await taCourses.addEntry(_entry(), expectedRevision: 0);

    expect(result.isSuccess, isFalse);
    expect(taCourses.lastSaveError, isA<TaCourseStorageException>());
    expect(taCourses.errorMessage, '无法保存 TA 课配置。');
  });

  test('conflicts are typed and observable', () async {
    final session = _SessionController('student01');
    final taCourses = TaCourseController(
      sessionController: session,
      repository: TaCourseRepository(store: _MemoryTaCourseStore()),
    );
    addTearDown(() {
      taCourses.dispose();
      session.dispose();
    });
    await taCourses.reload();
    await taCourses.addEntry(_entry(id: 'a'), expectedRevision: 0);

    final result = await taCourses.updateEntry(
      taCourses.entries.single.copyWith(title: 'late'),
      expectedRevision: 0,
    );

    expect(result.conflict?.type, TaCourseConflictType.entryRevisionMismatch);
    expect(
      taCourses.lastConflict?.type,
      TaCourseConflictType.entryRevisionMismatch,
    );
    expect(taCourses.errorMessage, contains('已被更新'));
  });
}

TaCourseEntry _entry({String id = 'course'}) {
  return TaCourseEntry(
    id: id,
    title: 'Course',
    location: 'B201',
    weekday: DateTime.monday,
    startMinutes: 9 * 60,
    endMinutes: 9 * 60 + 50,
    repeatType: TaCourseRepeatType.weekly,
  );
}

class _SessionController extends AppSessionController {
  _SessionController(this._owner);

  String? _owner;

  @override
  bool get isLoggedIn => _owner != null;

  @override
  String? get username => _owner;

  @override
  TimetableData? get timetable => null;

  void switchOwner(String? owner) {
    _owner = owner;
    notifyListeners();
  }
}

class _MemoryTaCourseStore implements TaCoursePreferencesStore {
  _MemoryTaCourseStore({this.failSetString = false});

  final bool failSetString;
  final Map<String, String> _values = {};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<bool> setString(String key, String value) async {
    if (failSetString) {
      return false;
    }
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }
}
