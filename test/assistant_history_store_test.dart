import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/assistant_history_store.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const account = 'student01';
  final key = SecretKey(List<int>.generate(32, (index) => index));
  final differentKey = SecretKey(List<int>.filled(32, 7));

  SharedPreferencesAssistantHistoryStore store({
    Future<SecretKey> Function()? encryptionKey,
  }) => SharedPreferencesAssistantHistoryStore(
    key: encryptionKey ?? () async => key,
  );

  String digestFor(String username) =>
      sha256.convert(utf8.encode(username.trim().toLowerCase())).toString();
  String encryptedKeyFor(String username) =>
      'bnbu.ai_assistant.history.v2.${digestFor(username)}';
  String legacyKeyFor(String username) =>
      'bnbu.ai_assistant.history.v1.${digestFor(username)}';

  final conversation = AssistantConversation(
    id: 'history-1',
    title: '本地加密',
    createdAt: DateTime.utc(2026, 9, 7),
    updatedAt: DateTime.utc(2026, 9, 7, 1),
    messages: [
      AssistantStoredMessage(
        role: 'user',
        content: '只应存在于加密记录中的内容',
        createdAt: DateTime.utc(2026, 9, 7),
      ),
    ],
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'history is encrypted, account-bound and restorable with its key',
    () async {
      await store().save(account, [conversation]);

      final preferences = await SharedPreferences.getInstance();
      final encryptedKey = encryptedKeyFor(account);
      final encrypted = preferences.getString(encryptedKey);
      expect(encrypted, isNotNull);
      expect(encrypted, isNot(contains(conversation.messages.single.content)));
      expect(preferences.containsKey(legacyKeyFor(account)), isFalse);

      final restored = await store().load(account.toUpperCase());
      expect(restored.single.id, conversation.id);
      expect(
        restored.single.messages.single.content,
        conversation.messages.single.content,
      );
      expect(await store().load('other-account'), isEmpty);
    },
  );

  test('a valid plaintext v1 record migrates once and is deleted', () async {
    final preferences = await SharedPreferences.getInstance();
    final legacyKey = legacyKeyFor(account);
    await preferences.setString(legacyKey, jsonEncode([conversation.toJson()]));

    final restored = await store().load(account);

    expect(restored.single.title, conversation.title);
    expect(preferences.containsKey(legacyKey), isFalse);
    final encrypted = preferences.getString(encryptedKeyFor(account));
    expect(encrypted, isNotNull);
    expect(encrypted, isNot(contains(conversation.messages.single.content)));
  });

  test('wrong or malformed ciphertext is a safe cache miss', () async {
    await store().save(account, [conversation]);
    expect(
      await store(encryptionKey: () async => differentKey).load(account),
      isEmpty,
    );

    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(encryptedKeyFor(account), 'not-a-secret-box');
    await preferences.setString(
      legacyKeyFor(account),
      jsonEncode([conversation.toJson()]),
    );
    expect(await store().load(account), isEmpty);
  });

  test(
    'attachment metadata round trips without runtime bytes or paths',
    () async {
      final attachment = AssistantInputAttachment(
        name: 'campus.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      final withAttachment = AssistantConversation(
        id: 'history-attachment',
        title: 'campus.png',
        createdAt: DateTime.utc(2026, 9, 8),
        updatedAt: DateTime.utc(2026, 9, 8),
        messages: [
          AssistantStoredMessage(
            role: 'user',
            content: '',
            createdAt: DateTime.utc(2026, 9, 8),
            runtimeAttachments: [attachment],
            attachmentReferences: [
              AssistantAttachmentReference.fromInputAttachment(attachment),
            ],
          ),
        ],
      );

      await store().save(account, [withAttachment]);
      final restored = (await store().load(account)).single.messages.single;

      expect(restored.content, isEmpty);
      expect(restored.attachmentReferences.single.name, 'campus.png');
      expect(
        restored.attachmentReferences.single.kind,
        AssistantAttachmentReferenceKind.image,
      );
      expect(restored.runtimeAttachments, isEmpty);
      final encoded = jsonEncode(restored.toJson());
      expect(encoded, isNot(contains('data_base64')));
      expect(encoded, isNot(contains('local_file_path')));
    },
  );

  test('only an exact legacy typed-mail attachment suffix is migrated', () {
    final base = {
      'role': 'user',
      'created_at': '2026-09-08T00:00:00Z',
      'mail_references': [
        {
          'kind': 'message',
          'folder': 'inbox',
          'uid': 8,
          'mailbox_uid_validity': 9,
          'sender': 'sender@example.test',
          'subject': 'Synthetic subject',
          'received_at': '2026-09-07T16:00:00Z',
        },
      ],
    };
    final migrated = AssistantStoredMessage.fromJson({
      ...base,
      'content': '请总结。\n\n附件：Synthetic subject',
    });
    final untouched = AssistantStoredMessage.fromJson({
      ...base,
      'content': '我自己写的附件说明：Synthetic subject',
    });

    expect(migrated.content, '请总结。');
    expect(untouched.content, '我自己写的附件说明：Synthetic subject');
  });

  test(
    'one incompatible legacy conversation is normalized without blocking history',
    () {
      final invalid = AssistantConversation(
        id: 'bad:id',
        title: '旧记录',
        createdAt: DateTime.utc(2026, 9, 8),
        updatedAt: DateTime.utc(2026, 9, 8),
        messages: conversation.messages,
      );

      final normalized = normalizeAssistantHistorySnapshot([
        invalid,
        conversation,
      ]);

      expect(normalized, hasLength(2));
      expect(normalized.map((item) => item.id), contains(conversation.id));
      expect(normalized.any((item) => item.id.startsWith('legacy-')), isTrue);
    },
  );

  test(
    'an unavailable key never writes or restores plaintext history',
    () async {
      final unavailable = store(
        encryptionKey: () async =>
            throw StateError('synthetic keychain failure'),
      );
      await expectLater(
        unavailable.save(account, [conversation]),
        throwsA(isA<AssistantHistoryException>()),
      );

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(encryptedKeyFor(account)), isFalse);
      await preferences.setString(
        legacyKeyFor(account),
        jsonEncode([conversation.toJson()]),
      );
      expect(await unavailable.load(account), isEmpty);
    },
  );
}
