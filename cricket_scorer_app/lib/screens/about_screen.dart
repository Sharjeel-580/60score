// About screen (§27): branding, tagline, description, version, credit.
// No contact information, website or email — nothing invented.
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/app_logo.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const AppLogo(height: 120),
              const SizedBox(height: 20),
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
              const SizedBox(height: 16),
              const Text(
                'Offline-first cricket scoring for the Super Sixty League. '
                'Score ball-by-ball, track points tables and NRR, and run '
                'playoffs — no account, no internet needed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: kSilver, fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              ScoreCard(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      'Version',
                      style: TextStyle(color: kSilver, fontSize: 14),
                    ),
                    Text(
                      '1.0.0',
                      style: TextStyle(
                        color: kWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Made by Sharjeel',
                style: TextStyle(
                  color: kGold,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
