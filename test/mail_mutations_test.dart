import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/mail_mutations.dart';

void main() {
  test('failed trash copy never deletes the source', () async {
    final transport = _Transport()..failCopy = true;
    await expectLater(
      moveMailSafely(transport, [3], 'Trash'),
      throwsStateError,
    );
    expect(transport.calls, ['copy:3:Trash']);
  });
  test('ambiguous MOVE is not repeated as COPY', () async {
    final transport = _Transport()
      ..supportsMove = true
      ..failMove = true;
    await expectLater(
      moveMailSafely(transport, [3], 'Trash'),
      throwsStateError,
    );
    expect(transport.calls, ['move:3:Trash']);
  });
  test('fallback expunges only explicitly selected UIDs', () async {
    final transport = _Transport();
    await moveMailSafely(transport, [3, 8, 3], 'Trash');
    expect(transport.calls, ['copy:3,8:Trash', 'deleted:3,8', 'expunge:3,8']);
  });
  test(
    'missing UID expunge support fails before copying or deleting',
    () async {
      final transport = _Transport()..supportsUidExpunge = false;
      await expectLater(
        moveMailSafely(transport, [3], 'Trash'),
        throwsStateError,
      );
      await expectLater(
        deleteMailPermanentlySafely(transport, [3]),
        throwsStateError,
      );
      expect(transport.calls, isEmpty);
    },
  );
}

class _Transport implements MailMutationTransport {
  @override
  bool supportsMove = false;
  @override
  bool supportsUidExpunge = true;
  bool failCopy = false;
  bool failMove = false;
  final calls = <String>[];
  @override
  Future<void> copy(List<int> uids, String target) async {
    calls.add('copy:${uids.join(',')}:$target');
    if (failCopy) throw StateError('copy failed');
  }

  @override
  Future<void> move(List<int> uids, String target) async {
    calls.add('move:${uids.join(',')}:$target');
    if (failMove) throw StateError('connection interrupted');
  }

  @override
  Future<void> markDeleted(List<int> uids) async =>
      calls.add('deleted:${uids.join(',')}');
  @override
  Future<void> expungeUids(List<int> uids) async =>
      calls.add('expunge:${uids.join(',')}');
}
