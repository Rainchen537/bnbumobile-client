import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/portal_account_profile.dart';

void main() {
  test('organization is not a programme name', () {
    final profile = PortalAccountProfile.fromPortalJson({
      'subcompanyname': 'University',
      'deptname': '',
    });
    expect(profile.majorName, isEmpty);
  });

  test('Portal account profile reads explicit gender and dorm fields', () {
    final profile = PortalAccountProfile.fromPortalJson({
      'username': '测试学生',
      'jobs': 'BNBU Student UG/STUDENT',
      'subcompanyname': 'FST',
      'deptname': 'Data Science',
      'icon': '/student/photo.jpg',
      'sex': '男',
      'dormitory': 'V24-101',
    });

    expect(profile.organization, 'FST');
    expect(profile.department, 'Data Science');
    expect(profile.gender, '男');
    expect(profile.residence, 'V24-101');
  });

  test('Portal resource card reads the nested school gender field', () {
    final profile =
        PortalAccountProfile.fromPortalJson({
          'username': '测试学生',
          'jobs': 'BNBU Student UG/STUDENT',
          'subcompanyname': 'FST',
          'deptname': 'Data Science',
          'userid': 2099000001,
        }).mergeResourceCardJson({
          'result': [
            {
              'id': 'item2',
              'items': [
                {'name': 'workcode', 'value': '2099000001'},
                {'name': 'sex', 'label': '性别', 'value': '0', 'showName': '男'},
              ],
            },
          ],
        });

    expect(profile.organization, 'FST');
    expect(profile.department, 'Data Science');
    expect(profile.gender, '男');
  });

  test('Portal resource card accepts school Chinese field names', () {
    final profile =
        PortalAccountProfile.fromPortalJson({
          'username': '测试学生',
          'jobs': 'BNBU Student UG/STUDENT',
          'subcompanyname': 'FST',
          'deptname': 'Data Science',
        }).mergeResourceCardJson({
          'result': {
            'conditions': [
              {
                'domkey': ['xbmc'],
                'label': '性别',
                'value': '女',
              },
            ],
          },
        });

    expect(profile.gender, '女');
  });

  test(
    'Portal resource card reads college separately from student and major',
    () {
      final profile =
          PortalAccountProfile.fromPortalJson({
            'username': '测试学生',
            'jobs': 'BNBU Student UG/STUDENT',
            'subcompanyname': 'Student',
            'deptname': 'Data Science',
          }).mergeResourceCardJson({
            'result': {
              'conditions': [
                {
                  'domkey': ['ssxy'],
                  'label': '所属学院',
                  'showName': 'FST',
                },
              ],
            },
          });

      expect(profile.organization, 'Student');
      expect(profile.department, 'Data Science');
      expect(profile.college, 'FST');
    },
  );

  test('Portal resource card reads the student level independently', () {
    final profile =
        PortalAccountProfile.fromPortalJson({
          'username': '测试学生',
          'jobs': 'Student',
        }).mergeResourceCardJson({
          'result': {
            'conditions': [
              {
                'domkey': ['xslb'],
                'label': '学生类别',
                'showName': 'Taught Postgraduate',
              },
            ],
          },
        });

    expect(profile.identity, 'Student');
    expect(profile.studentLevel, 'Taught Postgraduate');
  });
}
