import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/ispace_page_content.dart';
import 'package:bnbu_me/models/portal_account_profile.dart';
import 'package:bnbu_me/pages/student_ecard_page.dart';

void main() {
  const base = 'https://school.example';
  test('Teaching Materials retains week and nested lab downloads', () {
    final page = IspacePageContent.parse('''<p><span>Week 01</span></p><ul>
      <li><a href="/pluginfile.php/1/mod_page/content/2/Lecture.pptx?time=42">Lecture 01 - Introduction</a></li>
      <li><a href="/pluginfile.php/1/mod_page/content/2/Lab.pptx">Lab 01 - Digital</a><ul>
        <li><a href="/pluginfile.php/1/mod_page/content/2/Digital.zip">Digital.zip</a></li>
        <li><a href="/pluginfile.php/1/mod_page/content/2/Material.zip">Lab Material</a></li>
      </ul></li></ul>''', base);
    expect(page.isFileDirectory, isTrue);
    expect(page.links.length, 4);
    expect(page.links.every((l) => l.isFile), isTrue);
    expect(page.links.first.group, 'Week 01');
    expect(page.links.last.group, 'Week 01 / Lab 01 - Digital');
    expect(page.links.first.title, 'Lecture 01 - Introduction');
    expect(page.links.first.fileName, 'Lecture.pptx');
    expect(page.links.first.url, endsWith('?forcedownload=1'));
  });
  test('rich WAP page keeps HTML while exposing its policy attachment', () {
    final page = IspacePageContent.parse(
      '<img src="banner.png"><p>Appointments</p><a href="/pluginfile.php/1/policy.pdf">Policy</a>',
      base,
    );
    expect(page.isFileDirectory, isFalse);
    expect(page.links.single.isFile, isTrue);
  });
  test('tables, booking forms and embedded video are never flattened', () {
    for (final content in [
      '<table><tr><td>Update</td></tr></table>',
      '<form><input></form>',
      '<iframe src="https://video.example/player"></iframe>',
      '<p>${'Long prose ' * 80}</p>',
    ]) {
      expect(
        IspacePageContent.parse(
          '$content<a href="/pluginfile.php/1/a.pdf">File</a>',
          base,
        ).isFileDirectory,
        isFalse,
      );
    }
  });
  test('Lab websites remain links and unsafe links force original page', () {
    final page = IspacePageContent.parse(
      '<h3>Lab 1</h3><a href="/pluginfile.php/1/a.sql">Material</a><a href="https://tools.example">Install</a>',
      base,
    );
    expect(page.isFileDirectory, isTrue);
    expect(page.links.last.isFile, isFalse);
    expect(
      IspacePageContent.parse(
        '<a href="javascript:alert(1)">Action</a><a href="/pluginfile.php/1/a.pdf">File</a>',
        base,
      ).isFileDirectory,
      isFalse,
    );
  });
  test('mixed Chinese and English names are separated without translation', () {
    final data = StudentEcardData.fromSources(
      portal: const PortalAccountProfile(
        fullName: '张三 ZHANG San',
        identity: 'Student',
        organization: '',
        department: '',
        avatarPath: '',
      ),
    );
    expect(data.chineseName, '张三');
    expect(data.englishName, 'ZHANG San');
    final onlyEnglish = StudentEcardData.fromSources(
      sessionName: 'Example Student',
    );
    expect(onlyEnglish.chineseName, isEmpty);
    expect(onlyEnglish.englishName, 'Example Student');
  });
}
