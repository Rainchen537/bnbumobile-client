import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/services/campus_directory_service.dart';
import 'package:bnbu_me/services/mail_recipient_directory.dart';

void main() {
  test(
    'full address preserves punctuation and unknown complete addresses stay unmatched',
    () async {
      final directory = MailRecipientDirectory(
        directoryService: _FakeCampusDirectoryService(),
      );
      addTearDown(directory.dispose);
      expect(await directory.search('missing@bnbu.edu.cn'), isEmpty);
      expect(await directory.search('alice-li@bnbu.edu.cn'), isEmpty);
      expect(await directory.search('alice.li@bnbu.edu.cn'), hasLength(1));
      expect(await directory.search('Alice Xu'), isEmpty);
      expect(await directory.search(''), isEmpty);
    },
  );

  test(
    'searches organization, contact and staff names from official snapshot',
    () async {
      final directory = MailRecipientDirectory(
        directoryService: _FakeCampusDirectoryService(),
      );
      addTearDown(directory.dispose);

      final organization = await directory.search('教务');
      expect(
        organization.map((item) => item.email),
        containsAll(['registry@bnbu.edu.cn', 'records@bnbu.edu.cn']),
      );

      final contact = await directory.search('陈老师');
      expect(contact.first.email, 'records@bnbu.edu.cn');
      expect(contact.first.kind, MailRecipientKind.person);

      final staff = await directory.search('王静');
      expect(staff.first.email, 'jing.wang@bnbu.edu.cn');

      final westernOrder = await directory.search('xiaodongxu');
      expect(westernOrder.first.email, 'xiaodongxu@bnbu.edu.cn');

      final chineseOrder = await directory.search('xuxiaodong');
      expect(chineseOrder.first.email, 'xiaodongxu@bnbu.edu.cn');
    },
  );

  test(
    'merges remote teacher results and supports a one-edit fuzzy match',
    () async {
      final service = _FakeCampusDirectoryService();
      final directory = MailRecipientDirectory(directoryService: service);
      addTearDown(directory.dispose);

      final teacher = await directory.search('Alice');
      expect(teacher.single.email, 'alice.li@bnbu.edu.cn');
      expect(service.teacherQueries, contains('Alice'));

      final fuzzy = await directory.search('admisions');
      expect(
        fuzzy.map((item) => item.email),
        contains('admissions@bnbu.edu.cn'),
      );
    },
  );

  test(
    'prioritizes exact email local-part matches over names and metadata',
    () async {
      final directory = MailRecipientDirectory(
        directoryService: _FakeCampusDirectoryService(),
      );
      addTearDown(directory.dispose);

      final results = await directory.search('ar');

      expect(results.first.email, 'ar@bnbu.edu.cn');
    },
  );
}

class _FakeCampusDirectoryService implements CampusDirectoryService {
  final List<String> teacherQueries = [];

  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() async {
    return [
      CampusDirectoryOrganization(
        id: 'registry',
        category: CampusDirectoryCategory.administration,
        nameCn: '教务部',
        nameEn: 'Registry',
        shortName: 'AR',
        websiteUrl: '',
        facultyUrl: '',
        teacherUnit: '',
        office: '行政楼',
        phones: const [],
        emails: const ['registry@bnbu.edu.cn'],
        responsibilities: const ['Admissions'],
        contacts: const [
          CampusDirectoryContact(
            nameCn: '陈老师',
            nameEn: 'Chen',
            office: '成绩与学籍',
            phones: [],
            emails: ['records@bnbu.edu.cn'],
            responsibilities: ['成绩单'],
          ),
        ],
        embeddedStaff: [
          _teacher(name: '王静', email: 'jing.wang@bnbu.edu.cn'),
          _teacher(
            name: '徐晓冬',
            nameEn: 'Xiaodong Xu',
            email: 'xiaodongxu@bnbu.edu.cn',
          ),
        ],
        sourceUrls: const [],
      ),
      const CampusDirectoryOrganization(
        id: 'ar',
        category: CampusDirectoryCategory.administration,
        nameCn: '学术注册部',
        nameEn: 'Academic Registry',
        shortName: 'AR',
        websiteUrl: '',
        facultyUrl: '',
        teacherUnit: '',
        office: '',
        phones: [],
        emails: ['ar@bnbu.edu.cn'],
        responsibilities: ['Registry'],
        contacts: [],
        embeddedStaff: [],
        sourceUrls: [],
      ),
      const CampusDirectoryOrganization(
        id: 'admissions',
        category: CampusDirectoryCategory.administration,
        nameCn: '招生办公室',
        nameEn: 'Admissions Office',
        shortName: 'Admissions',
        websiteUrl: '',
        facultyUrl: '',
        teacherUnit: '',
        office: '',
        phones: [],
        emails: ['admissions@bnbu.edu.cn'],
        responsibilities: ['Admissions'],
        contacts: [],
        embeddedStaff: [],
        sourceUrls: [],
      ),
    ];
  }

  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) async {
    teacherQueries.add(query);
    final items = query.toLowerCase().contains('alice')
        ? [
            _teacher(
              name: '李爱丽',
              nameEn: 'Alice Li',
              email: 'alice.li@bnbu.edu.cn',
            ),
          ]
        : const <OfficialTeacherProfile>[];
    return OfficialTeacherPage(
      items: items,
      total: items.length,
      offset: offset,
      limit: limit,
      units: const ['商学院'],
    );
  }

  @override
  void dispose() {}
}

OfficialTeacherProfile _teacher({
  required String name,
  String nameEn = '',
  required String email,
}) {
  return OfficialTeacherProfile(
    name: name,
    nameEn: nameEn,
    email: email,
    title: '讲师',
    titleEn: 'Lecturer',
    position: '',
    office: '',
    telephone: '',
    academicCn: '',
    academicEn: '',
    educationCn: '',
    educationEn: '',
    unitNames: const ['商学院'],
    photoUrl: '',
    profileUrl: '',
    sourceUpdatedAt: null,
  );
}
