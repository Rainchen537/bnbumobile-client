import 'dart:async';

import 'package:flutter/material.dart' hide ScaffoldMessenger;
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_about_service.dart';
import '../theme/app_theme.dart';
import 'bnbu_notice.dart';

class AppAboutContent extends StatefulWidget {
  const AppAboutContent({super.key, required this.versionLabel, this.service});
  final String versionLabel;
  final AppAboutService? service;
  @override
  State<AppAboutContent> createState() => _AppAboutContentState();
}

class _AppAboutContentState extends State<AppAboutContent>
    with WidgetsBindingObserver {
  late final AppAboutService _service = widget.service ?? AppAboutService();
  AppAboutConfiguration _configuration = const AppAboutConfiguration();
  bool _refreshing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() async {
    final cached = await _service.loadCached();
    if (!mounted) return;
    setState(() => _configuration = cached);
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    final next = await _service.refresh(_configuration);
    if (mounted) setState(() => _configuration = next);
    _refreshing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  Future<void> _open(DeveloperContact contact) async {
    try {
      if (contact.target != null &&
          await launchUrl(
            contact.target!,
            mode: LaunchMode.externalApplication,
          )) {
        return;
      }
      await Clipboard.setData(ClipboardData(text: contact.value));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: BnbuText('已复制')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: BnbuText('暂时无法打开，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset(
                'assets/branding/app_logo.png',
                width: 88,
                height: 88,
                semanticLabel: 'BNBU.ME',
              ),
            ),
            const SizedBox(height: 16),
            Text('BNBU.ME', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              widget.versionLabel,
              style: TextStyle(color: context.bnbuTheme.textSecondary),
            ),
          ],
        ),
      ),
      if (_configuration.contacts.isNotEmpty) ...[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: BnbuText('开发者联系方式'),
        ),
        for (final contact in _configuration.contacts)
          ListTile(
            title: Text(contact.label),
            subtitle: Text(contact.value),
            trailing: Icon(
              contact.target == null
                  ? LucideIcons.copy300
                  : LucideIcons.externalLink300,
              size: 18,
            ),
            onTap: () => _open(contact),
          ),
      ],
    ],
  );
}
