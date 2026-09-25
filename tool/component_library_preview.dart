import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/bnbu_component_library.dart';

/// Offline component workbench: no account, settings persistence or network.
void main() => runApp(const ComponentLibraryPreview());

class ComponentLibraryPreview extends StatefulWidget {
  const ComponentLibraryPreview({super.key});

  @override
  State<ComponentLibraryPreview> createState() =>
      _ComponentLibraryPreviewState();
}

class _ComponentLibraryPreviewState extends State<ComponentLibraryPreview> {
  bool _dark = false;
  bool _wide = false;
  bool _reduced = false;
  double _width = 358;
  double _textScale = 1;
  Locale _locale = const Locale('zh', 'CN');
  final _hidden = TextEditingController();
  final _persistent = TextEditingController();
  String _folder = '收件箱';

  @override
  void dispose() {
    _hidden.dispose();
    _persistent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BNBU.ME · 组件库',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
    locale: _locale,
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
    final english = _locale.languageCode == 'en';
    String text(String zh, String en) => english ? en : context.l10n.text(zh);
    return Scaffold(
      backgroundColor: tokens.canvas,
      appBar: AppBar(
        title: Text(text('组件库', 'Component library')),
        actions: [
          IconButton(
            key: const ValueKey('library-theme'),
            tooltip: text('切换明暗', 'Toggle theme'),
            onPressed: () => setState(() => _dark = !_dark),
            icon: Icon(_dark ? LucideIcons.sun300 : LucideIcons.moon300),
          ),
          BnbuMenuButton<Locale>(
            tooltip: text('语言', 'Language'),
            initialValue: _locale,
            icon: const Icon(LucideIcons.languages300),
            onSelected: (value) => setState(() => _locale = value),
            itemBuilder: (_) => [
              BnbuMenuItem(
                value: const Locale('zh', 'CN'),
                child: const Text('简体中文'),
              ),
              BnbuMenuItem(
                value: const Locale.fromSubtags(
                  languageCode: 'zh',
                  scriptCode: 'Hant',
                ),
                child: const Text('繁體中文'),
              ),
              BnbuMenuItem(
                value: const Locale('en'),
                child: const Text('English'),
              ),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = math.max(200.0, constraints.maxWidth - 40);
          final actualWidth = math.min(_width, maxWidth);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    child: SegmentedButton<bool>(
                      key: const ValueKey('library-layout'),
                      segments: [
                        ButtonSegment(
                          value: false,
                          label: Text(text('窄屏', 'Compact')),
                        ),
                        ButtonSegment(
                          value: true,
                          label: Text(text('宽屏', 'Wide')),
                        ),
                      ],
                      selected: {_wide},
                      onSelectionChanged: (value) => setState(() {
                        _wide = value.single;
                        _width = _wide ? 760 : 358;
                      }),
                    ),
                  ),
                  Text('${actualWidth.round()} px'),
                  SizedBox(
                    width: math.min(220, maxWidth),
                    child: Slider(
                      key: const ValueKey('library-width'),
                      label: '${actualWidth.round()} px',
                      value: actualWidth.clamp(200, maxWidth),
                      min: 200,
                      max: math.max(201, maxWidth),
                      onChanged: (value) => setState(() => _width = value),
                    ),
                  ),
                  FilterChip(
                    label: Text(text('大字号', 'Large text')),
                    selected: _textScale > 1,
                    onSelected: (value) =>
                        setState(() => _textScale = value ? 1.6 : 1),
                  ),
                  FilterChip(
                    label: Text(text('减少动态效果', 'Reduced motion')),
                    selected: _reduced,
                    onSelected: (value) => setState(() => _reduced = value),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(_textScale),
                  disableAnimations: _reduced,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: actualWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _section(
                          context,
                          text('隐藏式搜索框', 'Hidden search'),
                          BnbuRevealSearch.hidden(
                            controller: _hidden,
                            onChanged: (_) {},
                            mode: _wide
                                ? BnbuRevealSearchMode.local
                                : BnbuRevealSearchMode.pageCentered,
                            softMode: !_wide,
                            preserveQueryOnDismiss: true,
                            controlKey: const ValueKey('library-hidden-search'),
                            closeKey: const ValueKey('library-hidden-close'),
                          ),
                        ),
                        _section(
                          context,
                          text('常显式搜索框', 'Persistent search'),
                          BnbuRevealSearch.persistent(
                            controller: _persistent,
                            onChanged: (_) {},
                            preserveQueryOnDismiss: true,
                            controlKey: const ValueKey(
                              'library-persistent-search',
                            ),
                            closeKey: const ValueKey(
                              'library-persistent-close',
                            ),
                          ),
                        ),
                        _section(
                          context,
                          text('标准下拉菜单', 'Standard menu'),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: BnbuMenuButton<String>(
                              key: const ValueKey('library-menu'),
                              initialValue: _folder,
                              constraints: BoxConstraints.tightFor(
                                width: math.min(actualWidth, _wide ? 360 : 280),
                              ),
                              onSelected: (value) =>
                                  setState(() => _folder = value),
                              itemBuilder: (_) => [
                                for (final folder in const [
                                  '收件箱',
                                  '星标邮件',
                                  '草稿箱',
                                  '已发送',
                                  '已删除',
                                  '垃圾邮件',
                                ])
                                  BnbuMenuItem(
                                    value: folder,
                                    selected: _folder == folder,
                                    child: BnbuText(folder),
                                  ),
                              ],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 14,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    BnbuText(_folder),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      LucideIcons.chevronDown300,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(BuildContext context, String title, Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}
