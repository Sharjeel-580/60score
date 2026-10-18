// About screen (§27): branding, tagline, description, version, credit
// and developer contact details. No invented addresses, websites or links.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../widgets/app_logo.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const _kPhoneDisplay = '03096571271';
  static const _kPhoneIntl = '923096571271';
  static const _kVersion = '1.1.3';

  static const _kFeatures = <String>[
    'Match creation',
    'Live scoring',
    'Tournaments',
    'Teams & players',
    'Drafting',
    'Statistics',
    'Fixtures',
    'Scorecards',
    'Data export',
  ];

  Future<void> _openLink(
    BuildContext context,
    Uri uri, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) async {
    var ok = false;
    try {
      if (await canLaunchUrl(uri)) {
        ok = await launchUrl(uri, mode: mode);
      }
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open that link on this device'),
        ),
      );
    }
  }

  Widget _infoRow(String label, String value, {bool last = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(color: kSilver, fontSize: 14),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: kWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (!last) const Divider(height: 1),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About 60Score')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          children: [
            const AppLogo(height: 110),
            const SizedBox(height: 16),
            const Text(
              '60Score',
              style: TextStyle(
                color: kWhite,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Cricket Scoring, Simplified.',
              style: TextStyle(
                color: kCyan,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'MADE BY SHARJEEL',
              style: TextStyle(
                color: kGold,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Offline-first cricket scoring for the Super Sixty League. '
              'Score ball-by-ball, track points tables and NRR, and run '
              'playoffs — no account, no internet needed.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kSilver, fontSize: 14, height: 1.5),
            ),
            const SectionTitle(icon: Icons.info_outline, title: 'App Info'),
            ScoreCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  _infoRow('Developer', 'Sharjeel'),
                  _infoRow('Contact', _kPhoneDisplay),
                  _infoRow('Version', _kVersion, last: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScoreButton(
                  label: 'Call Developer',
                  icon: Icons.call,
                  kind: ScoreButtonKind.primary,
                  onPressed: () => _openLink(
                    context,
                    Uri.parse('tel:$_kPhoneDisplay'),
                  ),
                ),
                const SizedBox(height: 12),
                ScoreButton(
                  label: 'WhatsApp',
                  icon: Icons.chat,
                  kind: ScoreButtonKind.gold,
                  onPressed: () => _openLink(
                    context,
                    Uri.parse('https://wa.me/$_kPhoneIntl'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
            const SectionTitle(icon: Icons.star_outline, title: 'Features'),
            ScoreCard(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              child: Column(
                children: _kFeatures
                    .map(
                      (f) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: kCyan,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                f,
                                style: const TextStyle(
                                  color: kWhite,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
