import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/moodle_activity_icon.dart';
import 'package:bnbu_me/widgets/timeline_summary_card.dart';

import 'card_catalog/card_samples.dart';
import 'card_catalog/catalog_data.dart';

/// Independent Flutter review page. No production main, session or settings.
void main() => runApp(const CardCatalogPreview());

class CardCatalogPreview extends StatefulWidget {
  const CardCatalogPreview({super.key});
  @override
  State<CardCatalogPreview> createState() => _CardCatalogPreviewState();
}

class _CardCatalogPreviewState extends State<CardCatalogPreview> {
  bool dark = false;
  bool missingFields = false;
  String language = 'zh-Hans';
  String filter = '全部';
  String mode = '对照';
  String activity = 'assign';
  String courseStatus = '今天稍后';
  String emptyState = '无数据';
  double cardWidth = 358;
  double textScale = 1;
  double bottomInset = 12;
  int titleLines = 2;
  CatalogTextCase textCase = CatalogTextCase.normal;
  CatalogDueCase dueCase = CatalogDueCase.urgent;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BNBU.ME · 卡片设计预览',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    locale: switch (language) {
      'en' => const Locale('en'),
      'zh-Hant' => const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      ),
      _ => const Locale('zh', 'CN'),
    },
    supportedLocales: BnbuLocalizations.supportedLocales,
    localizationsDelegates: const [
      BnbuLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(builder: _page),
  );

  Widget _page(BuildContext context) {
    final tokens = context.bnbuTheme;
    final entries = catalogEntries
        .where((e) => filter == '全部' || e.page == filter)
        .toList();
    final fixture = CatalogFixture(
      textCase: textCase,
      dueCase: dueCase,
      english: language == 'en',
      activity: activity,
      missingFields: missingFields,
      courseStatus: courseStatus,
      emptyState: emptyState,
    );
    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '卡片设计预览',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('catalog-theme'),
                    tooltip: '切换明暗',
                    onPressed: () => setState(() => dark = !dark),
                    icon: Icon(dark ? LucideIcons.sun300 : LucideIcons.moon300),
                  ),
                  PopupMenuButton<String>(
                    tooltip: '语言',
                    initialValue: language,
                    onSelected: (value) => setState(() => language = value),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'zh-Hans', child: Text('简体中文')),
                      PopupMenuItem(value: 'zh-Hant', child: Text('繁體中文')),
                      PopupMenuItem(value: 'en', child: Text('English')),
                    ],
                    icon: const Icon(LucideIcons.languages300),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _select('范围', filter, [
                    '全部',
                    '首页',
                    'iSpace',
                    '课表',
                    '横表',
                    '考试',
                    '管理',
                  ], (v) => filter = v),
                  _select('显示', mode, ['对照', '现状', '拟调整'], (v) => mode = v),
                  _select(
                    '宽度',
                    cardWidth,
                    [288.0, 358.0, 600.0],
                    (v) => cardWidth = v,
                    labels: {
                      288.0: '320px 手机',
                      358.0: '390px 手机',
                      600.0: '宽屏卡片',
                    },
                  ),
                  _select(
                    '文字',
                    textCase,
                    CatalogTextCase.values,
                    (v) => textCase = v,
                    labels: const {
                      CatalogTextCase.short: '一行标题',
                      CatalogTextCase.normal: '常规',
                      CatalogTextCase.long: '长标题',
                      CatalogTextCase.extreme: '极长标题',
                    },
                  ),
                  _select('字号', textScale, [
                    1.0,
                    1.3,
                    1.6,
                    2.0,
                  ], (v) => textScale = v),
                  _select(
                    '截止',
                    dueCase,
                    CatalogDueCase.values,
                    (v) => dueCase = v,
                    labels: const {
                      CatalogDueCase.future: '3天6小时',
                      CatalogDueCase.boundary: '恰好24小时',
                      CatalogDueCase.urgent: '5小时30分钟',
                      CatalogDueCase.minute: '不足1分钟',
                      CatalogDueCase.overdue: '已逾期',
                      CatalogDueCase.missing: '无日期',
                    },
                  ),
                  _select('活动', activity, [
                    'assign',
                    'quiz',
                    'forum',
                    'resource',
                    'folder',
                    'feedback',
                    'choice',
                    'page',
                    'url',
                    'mediasite',
                    'unknown',
                  ], (v) => activity = v),
                  _select('课程状态', courseStatus, [
                    '今天稍后',
                    '正在上课',
                    '20 分钟后',
                    '明天',
                  ], (v) => courseStatus = v),
                  _select('空态', emptyState, [
                    '无数据',
                    '同步中',
                    '未登录',
                    '失败',
                  ], (v) => emptyState = v),
                  FilterChip(
                    label: const Text('缺少字段'),
                    selected: missingFields,
                    onSelected: (v) => setState(() => missingFields = v),
                  ),
                  _select(
                    '方案标题',
                    titleLines,
                    [2, 3],
                    (v) => titleLines = v,
                    labels: const {2: '预留两行', 3: '预留三行'},
                  ),
                  _select('方案底距', bottomInset, [
                    8.0,
                    12.0,
                    16.0,
                    20.0,
                  ], (v) => bottomInset = v),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                key: const ValueKey('catalog-list'),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                itemCount: entries.length + 1,
                itemBuilder: (context, index) {
                  if (index == entries.length) return _elements(context);
                  final entry = entries[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Column(
                      key: ValueKey('catalog-entry-${entry.id}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                entry.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _rules(context, entry),
                              child: const Text('设计规则'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final width = cardWidth.clamp(
                              0.0,
                              constraints.maxWidth,
                            );
                            Widget sample(bool proposed) => SizedBox(
                              width: width,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      proposed ? '拟调整' : '现状',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(color: tokens.textMuted),
                                    ),
                                  ),
                                  MediaQuery(
                                    data: MediaQuery.of(context).copyWith(
                                      textScaler: TextScaler.linear(textScale),
                                      size: Size(cardWidth + 32, 800),
                                    ),
                                    child: CatalogCardSample(
                                      entry: entry,
                                      fixture: fixture,
                                      proposed: proposed,
                                      titleLines: titleLines,
                                      bottomInset: bottomInset,
                                      onOpen: () =>
                                          _sampleAction(context, entry),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (mode != '对照') return sample(mode == '拟调整');
                            if (constraints.maxWidth >= width * 2 + 24) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  sample(false),
                                  const SizedBox(width: 24),
                                  sample(true),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                sample(false),
                                const SizedBox(height: 16),
                                sample(true),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _select<T>(
    String label,
    T value,
    List<T> values,
    void Function(T) update, {
    Map<T, String> labels = const {},
  }) => PopupMenuButton<T>(
    tooltip: label,
    initialValue: value,
    onSelected: (v) => setState(() => update(v)),
    itemBuilder: (_) => values
        .map((v) => PopupMenuItem<T>(value: v, child: Text(labels[v] ?? '$v')))
        .toList(),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label · ${labels[value] ?? value}'),
          const SizedBox(width: 4),
          const Icon(LucideIcons.chevronDown300, size: 14),
        ],
      ),
    ),
  );

  void _rules(BuildContext context, CatalogEntry entry) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(entry.name),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final section in [
                ('现状', entry.current),
                ('高度与溢出', entry.expansion),
                ('拟调整', entry.proposal),
                ('来源', entry.source),
              ]) ...[
                Text(
                  section.$1,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                SelectableText(section.$2),
                const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  void _sampleAction(BuildContext context, CatalogEntry entry) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(entry.name),
          content: Text(previewText(context, '预览操作', 'Preview action')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );

  Widget _elements(BuildContext context) {
    final tokens = context.bnbuTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('共享元素', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Wrap(
          spacing: 20,
          runSpacing: 16,
          children: [
            for (final type in [
              ...moodleActivityAssetTypes.toList()..sort(),
              'mediasite',
              'unknown',
            ])
              SizedBox(
                width: 92,
                child: Column(
                  children: [
                    MoodleActivityIcon(
                      moduleName: type,
                      size: 24,
                      color: tokens.brandBlue,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timelineActivityVisualFor(
                        moduleName: type,
                        activityType: type,
                      ).label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            for (final element in [
              ('品牌蓝', tokens.brandBlue),
              ('DDL红', tokens.danger),
              ('表面', tokens.surface),
              ('主文字', tokens.textPrimary),
              ('次文字', tokens.textSecondary),
              ('边框', tokens.border),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 16, height: 16, color: element.$2),
                  const SizedBox(width: 8),
                  Text(element.$1),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
