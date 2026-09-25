import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/services/ai_assistant_service.dart';
import 'package:bnbu_me/services/mail_radar_analyzer.dart';
import 'package:bnbu_me/services/mail_radar_attachment_processor.dart';
import 'package:bnbu_me/services/mail_service.dart';

const _credentials = MailAccessCredentials(
  userId: 'fixture',
  emailAddress: 'fixture@example.edu',
  password: 'test-only',
);
final _date = DateTime.utc(2026, 9, 8, 8);

MailMessageDetail _mail(
  String body, {
  List<MailAttachment> attachments = const [],
}) => MailMessageDetail(
  uid: 7,
  mailboxUidValidity: 91,
  folder: MailFolder.sent,
  subject: 'Fixture notice',
  sender: 'Office <office@example.edu>',
  recipients: 'all_students@example.edu',
  cc: null,
  date: _date,
  body: body,
  htmlBody: null,
  isSeen: false,
  attachments: attachments,
);

MailMessageSummary _summary(MailMessageDetail mail) => MailMessageSummary(
  uid: mail.uid,
  mailboxUidValidity: mail.mailboxUidValidity,
  folder: mail.folder,
  subject: mail.subject,
  sender: mail.sender,
  preview: '',
  hasHtmlBody: false,
  date: mail.date,
  isSeen: mail.isSeen,
  hasAttachments: mail.attachments.isNotEmpty,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MailRadarItem> analyze(
    _Remote remote,
    MailMessageDetail mail, {
    _Processor? processor,
    bool Function()? active,
  }) =>
      LightMailRadarAnalyzer(
        assistantService: remote,
        radarService: remote,
        attachmentProcessor: processor ?? _Processor(),
      ).analyze(
        clientRequestId: '11111111-1111-4111-8111-111111111111',
        username: 'fixture',
        credentials: _credentials,
        summary: _summary(mail),
        detail: mail,
        mailService: _MailService(),
        isOperationActive: active,
      );

  test('充分正文只请求标签，不取附件且保留原信身份和纸夹', () async {
    final remote = _Remote();
    final processor = _Processor();
    final mail = _mail(
      '图书馆开放安排已在本邮件中完整列明。${'正文说明开放位置与可用设施。' * 20}',
      attachments: const [
        MailAttachment(
          name: 'poster.pdf',
          size: 42,
          mimeType: 'application/pdf',
        ),
      ],
    );
    final item = await analyze(remote, mail, processor: processor);
    expect(processor.calls, 0);
    expect(remote.requests.single.lightweight, isTrue);
    expect(remote.requests.single.sourceFolder, MailFolder.sent);
    expect(
      remote.requests.single.bodySha256,
      matches(RegExp(r'^[a-f0-9]{64}$')),
    );
    expect(remote.requests.single.attachments, isEmpty);
    expect(remote.requests.single.sourceLinks, isEmpty);
    expect(item.toSummary().hasAttachments, isTrue);
    expect(item.toSummary().isSeen, isFalse);
    expect(item.translationZh, isEmpty);
    expect(item.actionZh, isEmpty);
    expect(item.memorySuggestions, isEmpty);
    expect(item.toolUses, isEmpty);
  });

  test('仅附件提供截止证据时限量取文本并核对真实发送的证据', () async {
    const evidence = '2026年9月11日14:00前提交';
    final remote = _Remote(
      result: {
        'category': 'deadline',
        'priority': 'high',
        'summary_zh': '提交材料。',
        'deadline_at': '2026-09-11T14:00:00+08:00',
        'deadline_text': '9/11 14:00',
        'deadline_evidence': evidence,
        'deadline_precision': 'datetime',
      },
    );
    final processor = _Processor(text: evidence);
    final mail = _mail(
      '具体截止要求见附件。',
      attachments: [
        for (var i = 0; i < 5; i++)
          MailAttachment(
            name: 'fixture-$i.pdf',
            size: 42,
            mimeType: 'application/pdf',
          ),
        const MailAttachment(
          name: 'photo.jpg',
          size: 42,
          mimeType: 'image/jpeg',
        ),
      ],
    );
    final item = await analyze(remote, mail, processor: processor);
    expect(processor.calls, 3);
    expect(remote.requests.single.attachments, hasLength(1));
    expect(
      utf8.decode(remote.requests.single.attachments.single.bytes),
      contains(evidence),
    );
    expect(item.deadlineAt, DateTime.parse('2026-09-11T14:00:00+08:00'));
    expect(item.deadlinePrecision, 'datetime');
    expect(item.attachmentNotes, isEmpty);
  });

  test('日期精度和真实午夜精度跨快照及状态修改保持区分', () async {
    for (final precision in ['date', 'datetime']) {
      final evidence = precision == 'date' ? '9月11日截止' : '9月11日00:00截止';
      final remote = _Remote(
        result: {
          'category': 'deadline',
          'priority': 'normal',
          'summary_zh': '提交材料。',
          'deadline_at': '2026-09-11T00:00:00+08:00',
          'deadline_text': evidence,
          'deadline_evidence': evidence,
          'deadline_precision': precision,
        },
      );
      final item = await analyze(remote, _mail(evidence));
      final restored = MailRadarItem.fromJson(
        item.copyWith(originalIsSeen: true).toJson(),
      );
      expect(restored.deadlinePrecision, precision);
      expect(restored.deadlineAt, item.deadlineAt);
    }
  });

  test('不存在于已提供正文和附件中的截止时间不进入列表数据', () async {
    final remote = _Remote(
      result: {
        'category': 'deadline',
        'priority': 'normal',
        'summary_zh': '截止时间需要确认。',
        'deadline_at': '2026-09-30T12:00:00+08:00',
        'deadline_text': '9/30 12:00',
        'deadline_evidence': '9月30日12:00截止',
        'deadline_precision': 'datetime',
      },
    );
    final item = await analyze(remote, _mail('请等待后续通知。'));
    expect(item.deadlineAt, isNull);
    expect(item.deadlinePrecision, 'none');
    expect(item.deadlineText, isEmpty);
  });

  test('已失效运行不进入远端或附件处理', () async {
    final remote = _Remote();
    final processor = _Processor();
    await expectLater(
      analyze(remote, _mail('见附件。'), processor: processor, active: () => false),
      throwsA(isA<AiAssistantOperationCancelledException>()),
    );
    expect(remote.requests, isEmpty);
    expect(processor.calls, 0);
  });

  test('轻量附件限制中文载荷且不把未发送的页图声明为已读取', () async {
    final remote = _Remote();
    final documents = [
      for (var i = 0; i < 3; i++)
        MailAttachment(
          name: '材料-$i.pdf',
          size: 42,
          mimeType: 'application/pdf',
        ),
    ];
    final item = await analyze(
      remote,
      _mail('见附件。', attachments: documents),
      processor: _Processor(text: '附件中的具体要求。' * 4000),
    );
    expect(
      remote.requests.single.attachments.single.bytes.length,
      lessThan(64 * 1024),
    );
    expect(item.attachmentCoverage.values, everyElement('partial'));

    final imageOnlyRemote = _Remote();
    final imageOnly = await analyze(
      imageOnlyRemote,
      _mail('见附件。', attachments: documents.take(1).toList()),
      processor: _Processor(
        text: '',
        visuals: [
          AssistantInputAttachment(
            name: '扫描页.jpg',
            mimeType: 'image/jpeg',
            bytes: Uint8List.fromList([1]),
          ),
        ],
      ),
    );
    expect(imageOnlyRemote.requests.single.attachments, isEmpty);
    expect(imageOnly.attachmentCoverage.values, everyElement('unread'));
  });

  test('附加材料不会让有明确正文截止的长邮件额外读取文档', () {
    final body = '${'课程说明。' * 40}截止日期为9月11日14:00，补充材料请参阅附件。';
    expect(LightMailRadarAnalyzer.needsAttachmentEvidence(body), isFalse);
    expect(
      LightMailRadarAnalyzer.needsAttachmentEvidence(
        '${'背景说明。' * 40}截止信息详见附件。',
      ),
      isTrue,
    );
  });
}

class _Remote implements AiAssistantService, AiAssistantMailRadarService {
  _Remote({Map<String, dynamic>? result})
    : result =
          result ??
          {
            'category': 'notice',
            'priority': 'normal',
            'summary_zh': '图书馆开放时间调整。',
            'deadline_at': null,
            'deadline_text': '',
            'deadline_evidence': '',
            'deadline_precision': 'none',
          };
  final Map<String, dynamic> result;
  final requests = <MailRadarRemoteRequest>[];
  @override
  Future<bool> isEnabled(String username) async => true;
  @override
  Future<MailRadarRemoteAnalysis> analyzeMailRadar({
    required String username,
    required MailRadarRemoteRequest request,
    bool Function()? isOperationActive,
    void Function(AiAssistantRemoteProgress progress)? onProgress,
  }) async {
    requests.add(request);
    return MailRadarRemoteAnalysis(
      clientRequestId: request.clientRequestId,
      result: result,
      toolUses: const [],
      memorySuggestions: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MailService implements MailService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Processor extends MailRadarAttachmentProcessor {
  _Processor({this.text = '附加资料。', this.visuals = const []});
  final String text;
  final List<AssistantInputAttachment> visuals;
  int calls = 0;
  @override
  Future<MailRadarPreparedAttachment> prepare({
    required MailAccessCredentials credentials,
    required MailMessageDetail message,
    required MailAttachment attachment,
    required MailService mailService,
    bool Function()? isOperationActive,
  }) async {
    calls++;
    return MailRadarPreparedAttachment(
      name: attachment.name,
      text: text,
      visuals: visuals,
    );
  }
}
