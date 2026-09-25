import 'dart:convert';
import 'dart:typed_data';

// Exercise the parser used by the pinned transport against real FETCH framing.
// ignore: implementation_imports
import 'package:enough_mail/src/private/imap/fetch_parser.dart';
// ignore: implementation_imports
import 'package:enough_mail/src/private/imap/imap_response.dart';
// ignore: implementation_imports
import 'package:enough_mail/src/private/imap/imap_response_line.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/mail_service_io.dart';

void main() {
  test('list FETCH preserves headers and RFC822 message size', () {
    final headers = <String, String>{
      'SUBJECT': '=?UTF-8?B?6K++56iL6YCa55+l?=',
      'FROM': 'Teacher <teacher@example.test>',
      'TO': 'Student <student@example.test>',
      'CC': 'Office <office@example.test>',
      'DATE': 'Mon, 07 Sep 2026 10:30:00 +0800',
      'MESSAGE-ID': '<notice@example.test>',
      'IN-REPLY-TO': '<original@example.test>',
      'REFERENCES': '<original@example.test>',
    };
    final requested = RegExp(
      r'HEADER\.FIELDS \(([^)]+)\)',
    ).firstMatch(mailListHeaderFetchCriteria)![1]!.split(' ');
    final literal =
        '${headers.entries.where((h) => requested.contains(h.key)).map((h) => '${h.key}: ${h.value}\r\n').join()}\r\n';
    final response = ImapResponse()
      ..add(
        ImapResponseLine(
          '* 1 FETCH (UID 12 FLAGS () RFC822.SIZE 263168 ENVELOPE ("Mon, 07 Sep 2026 10:30:00 +0800" "=?UTF-8?B?6K++56iL6YCa55+l?=" (("Teacher" NIL "teacher" "example.test")) NIL NIL (("Student" NIL "student" "example.test")) NIL NIL "<original@example.test>" "<notice@example.test>") BODY[HEADER.FIELDS (${requested.join(' ')})] {${utf8.encode(literal).length}}',
        ),
      )
      ..add(ImapResponseLine.raw(Uint8List.fromList(utf8.encode(literal))))
      ..add(ImapResponseLine(')'));
    final parser = FetchParser(isUidFetch: true);
    expect(parser.parseUntagged(response, null), isTrue);
    final message = parser.lastParsedMessage!;
    expect(message.decodeSubject(), '课程通知');
    expect(message.from!.single.email, 'teacher@example.test');
    expect(message.to!.single.email, 'student@example.test');
    expect(message.cc!.single.email, 'office@example.test');
    expect(message.decodeDate()!.toUtc(), DateTime.utc(2026, 9, 7, 2, 30));
    expect(message.getHeaderValue('References'), '<original@example.test>');
    expect(message.size, 263168);
  });
}
