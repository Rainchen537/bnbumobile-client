import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:simple_icons/simple_icons.dart';

import 'package:bnbu_me/widgets/mail_sender_avatar.dart';

void main() {
  group('mail sender avatar appearance', () {
    test('official senders use functional icon groups and badges', () {
      final registry = resolveMailSenderAvatarAppearance(
        'Academic Registry <ar@bnbu.edu.cn>',
      );
      final studentServices = resolveMailSenderAvatarAppearance(
        'Student Services <ugss@bnbu.edu.cn>',
      );
      final faculty = resolveMailSenderAvatarAppearance(
        'Faculty <fbm-events@bnbu.edu.cn>',
      );
      final graduate = resolveMailSenderAvatarAppearance(
        'Graduate School <gs@bnbu.edu.cn>',
      );
      final library = resolveMailSenderAvatarAppearance(
        'Library <library@bnbu.edu.cn>',
      );
      final admission = resolveMailSenderAvatarAppearance(
        'Admission <admission@bnbu.edu.cn>',
      );
      final operations = resolveMailSenderAvatarAppearance(
        'ITSC <itsc_support@bnbu.edu.cn>',
      );
      final finance = resolveMailSenderAvatarAppearance(
        'Finance <fotuition@bnbu.edu.cn>',
      );
      final community = resolveMailSenderAvatarAppearance(
        'HR <hr@bnbu.edu.cn>',
      );
      final global = resolveMailSenderAvatarAppearance(
        'International <international@bnbu.edu.cn>',
      );
      final health = resolveMailSenderAvatarAppearance(
        'Health <doctor@bnbu.edu.cn>',
      );
      final communications = resolveMailSenderAvatarAppearance(
        'Communications <mpro@bnbu.edu.cn>',
      );
      final generic = resolveMailSenderAvatarAppearance(
        'Office <office@bnbu.edu.cn>',
      );

      expect(registry.icon, LucideIcons.clipboardCheck300);
      expect(studentServices.icon, LucideIcons.graduationCap300);
      expect(faculty.icon, LucideIcons.landmark300);
      expect(graduate.icon, LucideIcons.microscope300);
      expect(library.icon, LucideIcons.bookOpen300);
      expect(admission.icon, LucideIcons.badgeCheck300);
      expect(operations.icon, LucideIcons.wrench300);
      expect(finance.icon, LucideIcons.briefcaseBusiness300);
      expect(community.icon, LucideIcons.usersRound300);
      expect(global.icon, LucideIcons.globe2300);
      expect(health.icon, LucideIcons.heartPulse300);
      expect(communications.icon, LucideIcons.megaphone300);
      expect(generic.icon, LucideIcons.building2300);
      expect(registry.badge, 'AR');
      expect(studentServices.badge, 'UGS');
      expect(faculty.badge, 'FBM');
      expect(graduate.badge, 'GS');
      expect(operations.badge, 'ITS');
      expect(registry.accentColor, isNot(studentServices.accentColor));
    });

    test('requested technology companies use dedicated brand appearances', () {
      final github = resolveMailSenderAvatarAppearance(
        'GitHub <notifications@mail.github.com>',
      );
      final claudeCode = resolveMailSenderAvatarAppearance(
        'Claude Code <updates@anthropic.com>',
      );
      final openAi = resolveMailSenderAvatarAppearance(
        'OpenAI <updates@email.openai.com>',
      );
      final google = resolveMailSenderAvatarAppearance(
        'Google <no-reply@google.com>',
      );

      expect(github.brand, 'github');
      expect(github.icon, SimpleIcons.github);
      expect(github.accentColor, SimpleIconColors.github);
      expect(claudeCode.brand, 'claude-code');
      expect(claudeCode.icon, SimpleIcons.claudecode);
      expect(claudeCode.accentColor, SimpleIconColors.claudecode);
      expect(openAi.brand, 'openai');
      expect(openAi.icon, LucideIcons.sparkles300);
      expect(google.brand, 'google');
      expect(google.icon, SimpleIcons.google);
      expect(google.accentColor, SimpleIconColors.google);
    });

    test('common company coverage keeps strict domain boundaries', () {
      final brands = <String, String>{
        'notice@apple.com': 'apple',
        'team@makenotion.com': 'notion',
        'invite@figma.com': 'figma',
        'meeting@zoom.us': 'zoom',
        'share@dropboxmail.com': 'dropbox',
        'alert@discord.com': 'discord',
        'receipt@stripe.com': 'stripe',
        'deploy@vercel.com': 'vercel',
        'security@cloudflare.com': 'cloudflare',
        'update@atlassian.com': 'atlassian',
        'service@microsoft.com': 'microsoft',
        'notice@amazonaws.com': 'amazon',
        'message@slack.com': 'slack',
      };

      for (final entry in brands.entries) {
        expect(
          resolveMailSenderAvatarAppearance(entry.key).brand,
          entry.value,
          reason: entry.key,
        );
      }
      expect(
        resolveMailSenderAvatarAppearance(
          'attacker@github.com.example.org',
        ).brand,
        isNull,
      );
      expect(
        resolveMailSenderAvatarAppearance('person@gmail.com').brand,
        isNull,
      );
    });
  });
}
