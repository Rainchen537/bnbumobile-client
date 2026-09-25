import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_theme.dart';
import 'package:simple_icons/simple_icons.dart';

import '../services/mail_sender_avatar_service.dart';

@immutable
class MailSenderAvatarAppearance {
  const MailSenderAvatarAppearance({
    required this.accentColor,
    required this.initials,
    this.icon,
    this.badge,
    this.brand,
  });

  final Color accentColor;
  final String initials;
  final IconData? icon;
  final String? badge;
  final String? brand;
}

class MailSenderAvatar extends StatefulWidget {
  const MailSenderAvatar({
    super.key,
    required this.sender,
    required this.diameter,
    this.senderAvatarService,
  });

  final String sender;
  final double diameter;
  final MailSenderAvatarService? senderAvatarService;

  @override
  State<MailSenderAvatar> createState() => _MailSenderAvatarState();
}

class _MailSenderAvatarState extends State<MailSenderAvatar> {
  Future<Uint8List?>? _thumbnailFuture;

  @override
  void initState() {
    super.initState();
    _refreshThumbnail();
  }

  @override
  void didUpdateWidget(covariant MailSenderAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sender != widget.sender ||
        !identical(oldWidget.senderAvatarService, widget.senderAvatarService)) {
      _refreshThumbnail();
    }
  }

  void _refreshThumbnail() {
    _thumbnailFuture = widget.senderAvatarService?.loadThumbnail(widget.sender);
  }

  @override
  Widget build(BuildContext context) {
    final senderName = _senderParts(widget.sender).$1;
    return Semantics(
      image: true,
      label: context.l10n.text(
        '${senderName.isEmpty ? widget.sender : senderName}头像',
      ),
      child: SizedBox.square(
        dimension: widget.diameter,
        child: _thumbnailFuture == null
            ? _fallback(context)
            : FutureBuilder<Uint8List?>(
                future: _thumbnailFuture,
                builder: (context, snapshot) {
                  final bytes = snapshot.data;
                  final child = bytes == null || bytes.isEmpty
                      ? KeyedSubtree(
                          key: const ValueKey('mail-avatar-fallback'),
                          child: _fallback(context),
                        )
                      : ClipOval(
                          key: const ValueKey('mail-avatar-thumbnail'),
                          child: Image.memory(
                            bytes,
                            width: widget.diameter,
                            height: widget.diameter,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.low,
                            gaplessPlayback: true,
                            excludeFromSemantics: true,
                            errorBuilder: (_, _, _) => _fallback(context),
                          ),
                        );
                  return AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    child: child,
                  );
                },
              ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    return SenderAvatarSymbol(
      appearance: resolveMailSenderAvatarAppearance(widget.sender),
      diameter: widget.diameter,
    );
  }
}

/// Shared local symbol for mail senders and public directory organizations.
class SenderAvatarSymbol extends StatelessWidget {
  const SenderAvatarSymbol({
    super.key,
    required this.appearance,
    required this.diameter,
  });

  final MailSenderAvatarAppearance appearance;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final surface = Theme.of(context).colorScheme.surface;
    final baseAccent =
        brightness == Brightness.dark &&
            appearance.accentColor.computeLuminance() < 0.04
        ? const Color(0xFFF8FAFC)
        : appearance.accentColor;
    final accent = brightness == Brightness.dark && appearance.badge != null
        ? Color.lerp(baseAccent, Colors.white, 0.42)!
        : baseAccent;
    final background = Color.alphaBlend(
      accent.withValues(alpha: brightness == Brightness.dark ? 0.20 : 0.12),
      surface,
    );
    final badge = appearance.badge;

    return SizedBox.square(
      dimension: diameter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
                border: Border.all(color: accent.withValues(alpha: 0.28)),
              ),
              child: Center(
                child: appearance.icon == null
                    ? BnbuText(
                        appearance.initials,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w700,
                          fontSize: diameter * 0.34,
                        ),
                      )
                    : Icon(
                        appearance.icon,
                        key: appearance.brand == null
                            ? null
                            : ValueKey('mail-brand-${appearance.brand}'),
                        size: diameter * 0.49,
                        color: accent,
                      ),
              ),
            ),
          ),
          if (badge != null && diameter >= 28)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                key: ValueKey('mail-organization-$badge'),
                constraints: BoxConstraints(
                  minWidth: diameter * 0.34,
                  minHeight: diameter * 0.34,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: badge.length > 2 ? 3 : 2,
                ),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(diameter),
                  border: Border.all(color: surface, width: 1.5),
                ),
                alignment: Alignment.center,
                child: BnbuText(
                  badge,
                  maxLines: 1,
                  style: TextStyle(
                    color: _bestOnColor(accent),
                    fontSize: diameter * (badge.length > 3 ? 0.16 : 0.19),
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

MailSenderAvatarAppearance resolveMailSenderAvatarAppearance(String sender) {
  final senderParts = _senderParts(sender);
  final name = senderParts.$1.toLowerCase();
  final email = senderParts.$2;
  final atIndex = email.lastIndexOf('@');
  final local = atIndex < 0 ? '' : email.substring(0, atIndex);
  final domain = atIndex < 0 ? '' : email.substring(atIndex + 1);

  if (_matchesDomain(domain, const {'github.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.github,
      initials: 'GH',
      icon: SimpleIcons.github,
      brand: 'github',
    );
  }
  if (_matchesDomain(domain, const {'anthropic.com', 'claude.ai'})) {
    final isClaudeCode =
        name.contains('claude code') ||
        local.contains('claude-code') ||
        local.contains('claudecode');
    return MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.claudecode,
      initials: isClaudeCode ? 'CC' : 'CL',
      icon: isClaudeCode ? SimpleIcons.claudecode : SimpleIcons.claude,
      brand: isClaudeCode ? 'claude-code' : 'claude',
    );
  }
  if (_matchesDomain(domain, const {'openai.com', 'chatgpt.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: Color(0xFF0B6B57),
      initials: 'AI',
      icon: LucideIcons.sparkles300,
      brand: 'openai',
    );
  }
  if (_matchesDomain(domain, const {'google.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.google,
      initials: 'G',
      icon: SimpleIcons.google,
      brand: 'google',
    );
  }

  final commonBrand = _commonBrandForDomain(domain);
  if (commonBrand != null) {
    return commonBrand;
  }

  if (domain != 'mail.bnbu.edu.cn' &&
      _matchesDomain(domain, const {'bnbu.edu.cn'})) {
    return resolveOfficialOrganizationAppearance(local);
  }

  final normalized = sender.trim().toLowerCase();
  if (normalized == 'ar' || normalized == 'ugss') {
    final badge = normalized.toUpperCase();
    return MailSenderAvatarAppearance(
      accentColor: _officialAccentFor(badge),
      initials: badge,
      icon: _officialIconFor(normalized),
      badge: badge,
    );
  }

  final initials = _initials(sender);
  return MailSenderAvatarAppearance(
    accentColor: _genericAccentFor(normalized),
    initials: initials,
  );
}

MailSenderAvatarAppearance? _commonBrandForDomain(String domain) {
  if (_matchesDomain(domain, const {'apple.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.apple,
      initials: 'AP',
      icon: SimpleIcons.apple,
      brand: 'apple',
    );
  }
  if (_matchesDomain(domain, const {'notion.so', 'makenotion.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.notion,
      initials: 'N',
      icon: SimpleIcons.notion,
      brand: 'notion',
    );
  }
  if (_matchesDomain(domain, const {'figma.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.figma,
      initials: 'F',
      icon: SimpleIcons.figma,
      brand: 'figma',
    );
  }
  if (_matchesDomain(domain, const {'zoom.us'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.zoom,
      initials: 'Z',
      icon: SimpleIcons.zoom,
      brand: 'zoom',
    );
  }
  if (_matchesDomain(domain, const {'dropbox.com', 'dropboxmail.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.dropbox,
      initials: 'DB',
      icon: SimpleIcons.dropbox,
      brand: 'dropbox',
    );
  }
  if (_matchesDomain(domain, const {'discord.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.discord,
      initials: 'DC',
      icon: SimpleIcons.discord,
      brand: 'discord',
    );
  }
  if (_matchesDomain(domain, const {'stripe.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.stripe,
      initials: 'ST',
      icon: SimpleIcons.stripe,
      brand: 'stripe',
    );
  }
  if (_matchesDomain(domain, const {'vercel.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.vercel,
      initials: 'V',
      icon: SimpleIcons.vercel,
      brand: 'vercel',
    );
  }
  if (_matchesDomain(domain, const {'cloudflare.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.cloudflare,
      initials: 'CF',
      icon: SimpleIcons.cloudflare,
      brand: 'cloudflare',
    );
  }
  if (_matchesDomain(domain, const {'atlassian.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: SimpleIconColors.atlassian,
      initials: 'AT',
      icon: SimpleIcons.atlassian,
      brand: 'atlassian',
    );
  }
  if (_matchesDomain(domain, const {'microsoft.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: Color(0xFF0067B8),
      initials: 'MS',
      icon: LucideIcons.panelsTopLeft300,
      brand: 'microsoft',
    );
  }
  if (_matchesDomain(domain, const {'amazon.com', 'amazonaws.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: Color(0xFFB45309),
      initials: 'AWS',
      icon: LucideIcons.package300,
      brand: 'amazon',
    );
  }
  if (_matchesDomain(domain, const {'slack.com'})) {
    return const MailSenderAvatarAppearance(
      accentColor: Color(0xFF4A154B),
      initials: 'SL',
      icon: LucideIcons.messageSquare300,
      brand: 'slack',
    );
  }
  return null;
}

/// Uses the same functional icon, stable color and abbreviation in both views.
MailSenderAvatarAppearance resolveOfficialOrganizationAppearance(String local) {
  final normalized = local.trim().toLowerCase();
  final badge = _officialAbbreviation(normalized);
  return MailSenderAvatarAppearance(
    accentColor: _officialAccentFor(badge),
    initials: badge,
    icon: _officialIconFor(normalized),
    badge: badge,
  );
}

const Map<String, String> _officialAbbreviations = {
  'aco': 'ACO',
  'caso': 'CASO',
  'ctl': 'CTL',
  'ic': 'IC',
  'ar': 'AR',
  'academicsuccess': 'AS',
  'ugcourse': 'UGC',
  'ugrecord': 'UGR',
  'ugexam': 'EX',
  'qa': 'QA',
  'edoc': 'ED',
  'edocument': 'ED',
  'hkbusp': 'BP',
  'summer': 'SUM',
  'sdc': 'SDC',
  'sdac': 'SDA',
  'ugss': 'UGS',
  'sao': 'SAO',
  'sdo': 'SDO',
  'fbm': 'FBM',
  'fhss': 'FHS',
  'fst': 'FST',
  'scc': 'SCC',
  'sai': 'SAI',
  'sge': 'SGE',
  'uicsge': 'SGE',
  'shc': 'SHC',
  'gs': 'GS',
  'gstpg': 'GTP',
  'gs_rpg': 'GRP',
  'library': 'LIB',
  'admission': 'ADM',
  'emo': 'EMO',
  'ias': 'IAS',
  'rdkto': 'RDK',
  'mpro': 'MPR',
  'itsc_support': 'ITS',
  'uicbc': 'BC',
  'cyl': 'CYL',
  'pco': 'PCO',
  'puo': 'PUO',
  'pur': 'PUR',
  'fotuition': 'FOT',
  'fpo': 'FPO',
  'bnbuef': 'EF',
  'hr': 'HR',
  'alumni': 'ALU',
  'international': 'INT',
  'ccdo': 'CCD',
  'londoncenter': 'LON',
};

IconData _officialIconFor(String local) {
  if (local == 'aco') return LucideIcons.shieldCheck300;
  if (local == 'caso') return LucideIcons.leaf300;
  const academicAdministration = {
    'ar',
    'academicsuccess',
    'ugcourse',
    'ugrecord',
    'ugexam',
    'qa',
    'edoc',
    'edocument',
    'hkbusp',
    'summer',
    'ctl',
  };
  const studentServices = {
    'ugss',
    'sdc',
    'sdac',
    'sao',
    'sdo',
    'fpo',
    'alumni',
  };
  const graduateAndResearch = {'gs', 'gstpg', 'gs_rpg', 'ias', 'rdkto', 'ic'};
  const campusOperations = {'emo', 'itsc_support', 'ccdo'};
  const financeAndBusiness = {'fotuition', 'bnbuef', 'pur'};
  const globalEngagement = {'international', 'uicbc', 'londoncenter'};
  if (academicAdministration.contains(local)) {
    return LucideIcons.clipboardCheck300;
  }
  if (studentServices.contains(local)) {
    return LucideIcons.graduationCap300;
  }
  if (_isCollegeLocal(local)) {
    return LucideIcons.landmark300;
  }
  if (graduateAndResearch.contains(local)) {
    return LucideIcons.microscope300;
  }
  if (local == 'library') {
    return LucideIcons.bookOpen300;
  }
  if (local == 'admission') {
    return LucideIcons.badgeCheck300;
  }
  if (campusOperations.contains(local)) {
    return LucideIcons.wrench300;
  }
  if (financeAndBusiness.contains(local)) {
    return LucideIcons.briefcaseBusiness300;
  }
  if (local == 'hr') {
    return LucideIcons.usersRound300;
  }
  if (globalEngagement.contains(local)) {
    return LucideIcons.globe2300;
  }
  if (local == 'doctor') {
    return LucideIcons.heartPulse300;
  }
  if (local == 'mpro') {
    return LucideIcons.megaphone300;
  }
  return LucideIcons.building2300;
}

bool _isCollegeLocal(String local) {
  const colleges = {'fbm', 'fhss', 'fst', 'scc', 'sai', 'sge', 'uicsge', 'shc'};
  return colleges.contains(local) ||
      colleges.any(
        (college) =>
            local.startsWith('$college-') || local.startsWith('${college}_'),
      );
}

String _officialAbbreviation(String local) {
  final exact = _officialAbbreviations[local];
  if (exact != null) {
    return exact;
  }
  for (final entry in _officialAbbreviations.entries) {
    if (local.startsWith('${entry.key}-') ||
        local.startsWith('${entry.key}_')) {
      return entry.value;
    }
  }
  final parts = local
      .toUpperCase()
      .split(RegExp(r'[^A-Z0-9]+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.length >= 2) {
    return parts.take(3).map((part) => part[0]).join();
  }
  final cleaned = parts.isEmpty ? 'BNB' : parts.first;
  return cleaned.characters.take(3).toString();
}

const List<Color> _officialAccents = [
  Color(0xFF1D4ED8),
  Color(0xFF6D28D9),
  Color(0xFF0F766E),
  Color(0xFFB45309),
  Color(0xFFBE123C),
  Color(0xFF0E7490),
  Color(0xFF166534),
  Color(0xFF9D174D),
  Color(0xFF334155),
  Color(0xFF7C2D12),
  Color(0xFF5B21B6),
  Color(0xFF1E3A8A),
];

const List<Color> _genericAccents = [
  Color(0xFF6D28D9),
  Color(0xFF15803D),
  Color(0xFFBE185D),
  Color(0xFFB45309),
  Color(0xFF0E7490),
  Color(0xFF4338CA),
];

Color _officialAccentFor(String badge) {
  return _officialAccents[_stableHash(badge) % _officialAccents.length];
}

Color _genericAccentFor(String sender) {
  return _genericAccents[_stableHash(sender) % _genericAccents.length];
}

int _stableHash(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7fffffff;
  }
  return hash;
}

bool _matchesDomain(String domain, Set<String> allowedDomains) {
  for (final allowed in allowedDomains) {
    if (domain == allowed || domain.endsWith('.$allowed')) {
      return true;
    }
  }
  return false;
}

(String, String) _senderParts(String value) {
  final normalized = value.trim();
  final bracketMatch = RegExp(
    r'^(.*?)\s*<([^<>]+@[^<>]+)>$',
  ).firstMatch(normalized);
  if (bracketMatch != null) {
    return (
      bracketMatch.group(1)?.trim() ?? '',
      bracketMatch.group(2)?.trim().toLowerCase() ?? '',
    );
  }
  final emailMatch = RegExp(
    r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+',
  ).firstMatch(normalized);
  if (emailMatch == null) {
    return (normalized, '');
  }
  final email = emailMatch.group(0)!.toLowerCase();
  final name = normalized.replaceFirst(emailMatch.group(0)!, '').trim();
  return (name, email);
}

String _initials(String input) {
  final cleaned = input.trim();
  if (cleaned.isEmpty) return '邮';
  final upper = cleaned.toUpperCase();
  if (upper.length == 1) return upper;
  final words = upper
      .split(RegExp(r'[^A-Z0-9\u4E00-\u9FFF]+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (words.length >= 2) return '${words.first[0]}${words[1][0]}';
  return upper.characters.take(2).toString();
}

Color _bestOnColor(Color background) {
  final luminance = background.computeLuminance();
  final whiteContrast = 1.05 / (luminance + 0.05);
  final blackContrast = (luminance + 0.05) / 0.05;
  return whiteContrast >= blackContrast
      ? Colors.white
      : const Color(0xFF0F172A);
}
