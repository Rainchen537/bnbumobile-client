import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_directory.dart';
import 'package:bnbu_me/services/directory_search.dart';

void main() {
  test('whole query cannot collapse to a domain or one shared name token', () {
    expect(DirectorySearch.isExactPersonName('李鸣', '李明'), isFalse);
    expect(DirectorySearch.isExactPersonName('李明', 'liming'), isTrue);
    expect(
      DirectorySearch.score(
        'missing@bnbu.edu.cn',
        values: ['other@bnbu.edu.cn'],
      ),
      DirectorySearch.noMatch,
    );
    expect(
      DirectorySearch.score(
        'Xiaodong Xu',
        values: ['Xiaodong Li'],
        personNames: ['Xiaodong Li'],
      ),
      DirectorySearch.noMatch,
    );
    expect(
      DirectorySearch.score('陈东龙', values: ['陈小明'], personNames: ['陈小明']),
      DirectorySearch.noMatch,
    );
    expect(
      DirectorySearch.score(
        'Alice Physics',
        values: ['Alice Li', 'Physics'],
        personNames: ['Alice Li'],
      ),
      lessThan(DirectorySearch.noMatch),
    );
    expect(
      DirectorySearch.score(
        'Alice Physics',
        values: ['Alice Li', 'Business'],
        personNames: ['Alice Li'],
      ),
      DirectorySearch.noMatch,
    );
  });
  test(
    'matches Chinese names by full pinyin, initials and either name order',
    () {
      const values = ['徐晓冬', 'Xiaodong Xu', 'xiaodongxu@bnbu.edu.cn'];

      for (final query in ['徐晓冬', 'xiaodongxu', 'xuxiaodong', 'xxd']) {
        expect(
          DirectorySearch.score(
            query,
            values: values,
            personNames: const ['徐晓冬', 'Xiaodong Xu'],
          ),
          lessThan(DirectorySearch.noMatch),
          reason: 'query=$query',
        );
      }
    },
  );

  test('keeps one-edit fuzzy matching for directory content', () {
    expect(
      DirectorySearch.score('admisions', values: const ['Admissions Office']),
      lessThan(DirectorySearch.noMatch),
    );
  });

  test(
    'recognizes an exact Chinese teacher name independently of fuzzy hits',
    () {
      const exact = OfficialTeacherProfile(
        name: '陈东龙',
        nameEn: 'Donglong Chen',
        email: 'donglongchen@bnbu.edu.cn',
        title: '副教授',
        titleEn: 'Associate Professor',
        position: '',
        office: '',
        telephone: '',
        academicCn: '',
        academicEn: '',
        educationCn: '',
        educationEn: '',
        unitNames: [],
        photoUrl: '',
        profileUrl: '',
        sourceUpdatedAt: null,
      );
      const fuzzy = OfficialTeacherProfile(
        name: '陈龙',
        nameEn: 'Long Chen',
        email: 'longchen@bnbu.edu.cn',
        title: '副教授',
        titleEn: 'Associate Professor',
        position: '',
        office: '',
        telephone: '',
        academicCn: '',
        academicEn: '',
        educationCn: '',
        educationEn: '',
        unitNames: [],
        photoUrl: '',
        profileUrl: '',
        sourceUpdatedAt: null,
      );

      expect(DirectorySearch.isExactTeacherName(exact, '陈东龙'), isTrue);
      expect(
        DirectorySearch.isExactTeacherName(exact, 'Dr. Donglong CHEN'),
        isTrue,
      );
      expect(DirectorySearch.isExactTeacherName(fuzzy, '陈东龙'), isFalse);
    },
  );

  test(
    'organization search covers contact details and staff profile content',
    () {
      final organization = CampusDirectoryOrganization(
        id: 'example',
        category: CampusDirectoryCategory.administration,
        nameCn: '示例部门',
        nameEn: 'Example Office',
        shortName: '',
        websiteUrl: '',
        facultyUrl: '',
        teacherUnit: '',
        office: '',
        phones: const [],
        emails: const [],
        responsibilities: const [],
        contacts: const [
          CampusDirectoryContact(
            nameCn: '徐晓冬',
            nameEn: 'Xiaodong Xu',
            office: 'T3-602',
            phones: ['0756-3620000'],
            emails: ['xiaodongxu@bnbu.edu.cn'],
            responsibilities: ['课程注册'],
          ),
        ],
        embeddedStaff: const [],
        sourceUrls: const [],
      );

      expect(
        DirectorySearch.matchesOrganization(organization, 'xuxiaodong'),
        isTrue,
      );
      expect(
        DirectorySearch.matchesOrganization(organization, 'kechengzhuce'),
        isTrue,
      );
      expect(
        DirectorySearch.matchesOrganization(organization, '3620000'),
        isTrue,
      );
      final faculty = CampusDirectoryOrganization(
        id: 'college-sge',
        category: CampusDirectoryCategory.college,
        nameCn: '通识教育学院',
        nameEn: 'School of General Education',
        shortName: 'SGE',
        websiteUrl: '',
        facultyUrl: '',
        teacherUnit: '通识教育学院',
        office: '',
        phones: const [],
        emails: const [],
        responsibilities: const [],
        contacts: const [
          CampusDirectoryContact(
            nameCn: '外国语言中心',
            nameEn: 'Centre for Foreign Languages',
            office: '',
            phones: [],
            emails: [],
            responsibilities: [],
          ),
        ],
        embeddedStaff: const [],
        sourceUrls: const [],
      );
      const teacher = OfficialTeacherProfile(
        name: '语言教师',
        nameEn: 'Language Teacher',
        email: '',
        title: '',
        titleEn: '',
        position: '',
        office: '',
        telephone: '',
        academicCn: '',
        academicEn: '',
        educationCn: '',
        educationEn: '',
        unitNames: ['外国语言中心'],
        photoUrl: '',
        profileUrl: '',
        sourceUpdatedAt: null,
      );
      expect(
        DirectorySearch.teacherBelongsToOrganization(teacher, faculty),
        isTrue,
      );
    },
  );
}
