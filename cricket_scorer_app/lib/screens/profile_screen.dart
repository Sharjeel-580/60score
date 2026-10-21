// My Profile (v1.3.1 batch, feature #3): every signed-in account has
// its own profile — name, account contact, a unique user ID — plus a
// "My Stats" summary computed ONLY from that account's own data (the
// active identity scope of the store). Guests get a simple log-in
// prompt instead of a fake profile.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account_profile.dart';
import '../auth_service.dart';
import '../store.dart';
import '../theme.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  final Store store;
  const ProfileScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: AnimatedBuilder(
        animation: Listenable.merge([store, AuthService()]),
        builder: (context, _) {
          final auth = AuthService();
          final profile = store.profile;
          if (!auth.isLoggedIn || profile == null) {
            return _guestPrompt(context);
          }
          return _profileBody(context, auth, profile);
        },
      ),
    );
  }

  Widget _guestPrompt(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 24),
        const EmptyState(
          icon: Icons.account_circle_outlined,
          title: 'You are browsing as a guest',
          subtitle: 'Log in to get your own profile, a unique 60Score '
              'ID, and stats that stay separate from everyone else.',
        ),
        const SizedBox(height: 8),
        ScoreButton(
          label: 'Log in / Sign up',
          icon: Icons.login,
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => LoginScreen(store: store)),
            );
          },
        ),
      ],
    );
  }

  Widget _profileBody(
      BuildContext context, AuthService auth, AccountProfile profile) {
    final user = auth.currentUser;
    final totals = AccountTotals.fromStore(store);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        ScoreCard(
          child: Column(
            children: [
              _avatar(user?.photoURL, profile.displayName),
              const SizedBox(height: 12),
              Text(
                profile.displayName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (profile.contact.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  profile.contact,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13),
                ),
              ],
              const SizedBox(height: 14),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () async {
                  await Clipboard.setData(
                      ClipboardData(text: profile.userCode));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User ID copied')),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: kGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: kGold.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.badge, color: kGold, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        profile.userCode,
                        style: const TextStyle(
                          color: kGold,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.copy, color: kGold, size: 14),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tap to copy your 60Score ID',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
        const SectionTitle(icon: Icons.bar_chart, title: 'My Stats'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.1,
          children: [
            _statCard(Icons.emoji_events, 'Tournaments',
                '${totals.tournaments}'),
            _statCard(
                Icons.sports_cricket, 'Matches', '${totals.matches}'),
            _statCard(Icons.groups, 'Teams', '${totals.teams}'),
            _statCard(Icons.person, 'Players', '${totals.players}'),
            _statCard(Icons.trending_up, 'Total Runs',
                '${totals.totalRuns}'),
            _statCard(Icons.sports_baseball, 'Total Wickets',
                '${totals.totalWickets}'),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Stats are from your own tournaments and matches only — '
          'runs and wickets count completed matches.',
          style: TextStyle(color: Colors.white38, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _avatar(String? photoUrl, String name) {
    final initial =
        name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'P';
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 38,
        backgroundColor: kPanel2,
        backgroundImage: NetworkImage(photoUrl),
        onBackgroundImageError: (_, _) {},
        child: null,
      );
    }
    return CircleAvatar(
      radius: 38,
      backgroundColor: kCyan.withValues(alpha: 0.18),
      child: Text(
        initial,
        style: const TextStyle(
          color: kCyan,
          fontSize: 30,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _statCard(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: kOceanCardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCyan.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: kGold, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: kWhite,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
