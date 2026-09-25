/// A failed copy must never fall through to deleting the only remaining copy.
/// UID EXPUNGE is required so unrelated messages marked deleted by another
/// client are never swept up by this operation.
abstract interface class MailMutationTransport {
  bool get supportsMove;
  bool get supportsUidExpunge;
  Future<void> move(List<int> uids, String target);
  Future<void> copy(List<int> uids, String target);
  Future<void> markDeleted(List<int> uids);
  Future<void> expungeUids(List<int> uids);
}

Future<void> moveMailSafely(
  MailMutationTransport transport,
  List<int> uids,
  String target,
) async {
  if (uids.isEmpty) return;
  final selected = List<int>.unmodifiable(uids.toSet());
  if (transport.supportsMove) {
    // An interrupted MOVE can have an unknown outcome. Do not retry it as COPY.
    await transport.move(selected, target);
    return;
  }
  if (!transport.supportsUidExpunge) {
    throw StateError('邮箱服务器暂不支持安全移动。');
  }
  await transport.copy(selected, target);
  await transport.markDeleted(selected);
  await transport.expungeUids(selected);
}

Future<void> deleteMailPermanentlySafely(
  MailMutationTransport transport,
  List<int> uids,
) async {
  if (uids.isEmpty) return;
  if (!transport.supportsUidExpunge) {
    throw StateError('邮箱服务器暂不支持安全永久删除。');
  }
  final selected = List<int>.unmodifiable(uids.toSet());
  await transport.markDeleted(selected);
  await transport.expungeUids(selected);
}
