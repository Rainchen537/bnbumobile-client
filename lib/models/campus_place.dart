class CampusPlace {
  const CampusPlace({
    required this.id,
    required this.code,
    required this.chineseName,
    required this.englishName,
    required this.mapX,
    required this.mapY,
    required this.areaHint,
    this.aliases = const [],
  });

  final String id;
  final String code;
  final String chineseName;
  final String englishName;
  final double mapX;
  final double mapY;
  final String areaHint;
  final List<String> aliases;

  String get displayName {
    if (code.isEmpty) {
      return chineseName;
    }
    return '$code · $chineseName';
  }

  bool matches(String rawQuery) {
    final query = _normalized(rawQuery);
    if (query.isEmpty) {
      return true;
    }
    final normalizedCode = _normalized(code);
    if (normalizedCode.isNotEmpty && query.startsWith(normalizedCode)) {
      return true;
    }
    final candidates = <String>[code, chineseName, englishName, ...aliases];
    return candidates.any(
      (candidate) => _normalized(candidate).contains(query),
    );
  }

  static String _normalized(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  }
}

const campusPlaces = <CampusPlace>[
  CampusPlace(
    id: 't1',
    code: 'T1',
    chineseName: '师雅楼',
    englishName: 'Business and Management Building',
    mapX: 0.72,
    mapY: 0.56,
    areaHint: '位于教学区东南侧，靠近大学会堂和行政楼一侧。',
    aliases: ['工商管理楼', 'business', 'management'],
  ),
  CampusPlace(
    id: 't2',
    code: 'T2',
    chineseName: '人文楼',
    englishName: 'Humanities Building',
    mapX: 0.65,
    mapY: 0.57,
    areaHint: '位于 T1 西侧、T3 东侧，教学区南侧道路附近。',
    aliases: ['humanities'],
  ),
  CampusPlace(
    id: 't3',
    code: 'T3',
    chineseName: '格物楼',
    englishName: 'Science Building',
    mapX: 0.59,
    mapY: 0.55,
    areaHint: '位于教学区南侧，T2 西侧、V25 东侧。',
    aliases: ['科学楼', 'science'],
  ),
  CampusPlace(
    id: 't4',
    code: 'T4',
    chineseName: '教学楼',
    englishName: 'Teaching Building',
    mapX: 0.735,
    mapY: 0.345,
    areaHint: '位于学习资源中心北侧、校园湖西北侧。',
    aliases: ['teaching building'],
  ),
  CampusPlace(
    id: 't5',
    code: 'T5',
    chineseName: '教学楼',
    englishName: 'Teaching Building',
    mapX: 0.695,
    mapY: 0.37,
    areaHint: '位于 T4 西侧、学习资源中心北侧。',
    aliases: ['teaching building'],
  ),
  CampusPlace(
    id: 't6',
    code: 'T6',
    chineseName: '教学楼',
    englishName: 'Teaching Building',
    mapX: 0.645,
    mapY: 0.40,
    areaHint: '位于 T5 西南侧、T7 东侧，靠近学习资源中心。',
    aliases: ['teaching building'],
  ),
  CampusPlace(
    id: 't7',
    code: 'T7',
    chineseName: '教学楼',
    englishName: 'Teaching Building',
    mapX: 0.592,
    mapY: 0.414,
    areaHint: '位于 T6 西侧、T8 东侧。',
    aliases: ['teaching building'],
  ),
  CampusPlace(
    id: 't8',
    code: 'T8',
    chineseName: '博简楼',
    englishName: 'CEFC Building',
    mapX: 0.53,
    mapY: 0.435,
    areaHint: '位于 T7 西侧、T29 东北侧。',
    aliases: ['cefc'],
  ),
  CampusPlace(
    id: 't29',
    code: 'T29',
    chineseName: '教学楼',
    englishName: 'Teaching Building',
    mapX: 0.48,
    mapY: 0.47,
    areaHint: '位于 T8 西南侧、V24 东侧。',
    aliases: ['teaching building'],
  ),
  CampusPlace(
    id: 'lrc',
    code: 'LRC',
    chineseName: '学习资源中心',
    englishName: 'Learning Resource Centre',
    mapX: 0.70,
    mapY: 0.44,
    areaHint: '位于教学区东侧，T4–T7 南侧、校园湖西侧。',
    aliases: ['图书馆', 'library', 'learning resource center'],
  ),
  CampusPlace(
    id: 'administration',
    code: '',
    chineseName: '行政楼',
    englishName: 'Administration Building',
    mapX: 0.865,
    mapY: 0.575,
    areaHint: '位于校园东南侧，大学会堂东侧。',
    aliases: ['administration'],
  ),
  CampusPlace(
    id: 'university-hall',
    code: '',
    chineseName: '大学会堂',
    englishName: 'University Hall',
    mapX: 0.82,
    mapY: 0.60,
    areaHint: '位于行政楼西侧、体育馆东北侧。',
    aliases: ['university hall'],
  ),
  CampusPlace(
    id: 'sports-complex',
    code: '',
    chineseName: '体育馆',
    englishName: 'Sports Complex',
    mapX: 0.72,
    mapY: 0.66,
    areaHint: '位于教学区南侧、大学会堂西南侧，靠近金同路。',
    aliases: ['gym', 'gymnasium', 'sports complex'],
  ),
  CampusPlace(
    id: 'performance-theatre',
    code: '',
    chineseName: '演艺厅',
    englishName: 'Performance Theatre',
    mapX: 0.825,
    mapY: 0.49,
    areaHint: '位于校园湖东南侧、大学会堂北侧。',
    aliases: ['theatre', 'theater'],
  ),
  CampusPlace(
    id: 'arts-hall',
    code: '',
    chineseName: '艺馨厅',
    englishName: 'Arts Hall',
    mapX: 0.76,
    mapY: 0.20,
    areaHint: '位于校园东北侧，V16 东北方向。',
    aliases: ['arts hall'],
  ),
  CampusPlace(
    id: 'creative-clusters',
    code: '',
    chineseName: '文化创意群落',
    englishName: 'Cultural Creativity Clusters',
    mapX: 0.865,
    mapY: 0.39,
    areaHint: '位于校园湖东侧、演艺厅东北方向。',
    aliases: ['cultural creativity clusters'],
  ),
  CampusPlace(
    id: 'sports-park',
    code: '',
    chineseName: '体育公园',
    englishName: 'Sports Park',
    mapX: 0.34,
    mapY: 0.22,
    areaHint: '位于校园西北区域、一期宿舍区东侧。',
    aliases: ['操场', '运动场', 'sports park'],
  ),
  CampusPlace(
    id: 'ias',
    code: '',
    chineseName: '高等研究院',
    englishName: 'Institute for Advanced Study',
    mapX: 0.15,
    mapY: 0.07,
    areaHint: '位于校园最西北侧、一期宿舍区北侧。',
    aliases: ['ias', 'institute for advanced study'],
  ),
  CampusPlace(
    id: 'dorm-d1-d6',
    code: 'D1–D6',
    chineseName: '一期宿舍区',
    englishName: 'Phase 1 Residential Area',
    mapX: 0.15,
    mapY: 0.26,
    areaHint: '位于校园西北侧环形住宿区，体育公园西侧。',
    aliases: ['d1', 'd2', 'd3', 'd4', 'd5', 'd6', '宿舍'],
  ),
  CampusPlace(
    id: 'dorm-v15-v23',
    code: 'V15–V23',
    chineseName: '宿舍区',
    englishName: 'Residential Area',
    mapX: 0.56,
    mapY: 0.34,
    areaHint: '位于教学楼 T4–T8 北侧和西侧。',
    aliases: [
      'v15',
      'v16',
      'v17',
      'v18',
      'v19',
      'v20',
      'v21',
      'v22',
      'v23',
      '宿舍',
    ],
  ),
  CampusPlace(
    id: 'dorm-v24-v29',
    code: 'V24–V29',
    chineseName: '宿舍区',
    englishName: 'Residential Area',
    mapX: 0.46,
    mapY: 0.60,
    areaHint: '位于教学区西南侧、金同路北侧。',
    aliases: ['v24', 'v25', 'v26', 'v27', 'v28', 'v29', '宿舍'],
  ),
];
