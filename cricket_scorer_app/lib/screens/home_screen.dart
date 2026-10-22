// 60Score home dashboard — v1.1.2 redesign.
// Built only from real persisted store data — nothing hardcoded.
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/player_avatar.dart';
import 'completed_matches_screen.dart';
import 'registration_screen.dart';
import 'scorer_home_screen.dart';
import 'settings_screen.dart';
import 'teams_screen.dart';
import 'tournaments_screen.dart';

/// Short fixture date range, e.g. '2026-10-22T14:00:00' -> '22 Oct 2026'.
String _shortDate(String iso) {
  try {
    final d = iso.split('T').first.split('-');
    if (d.length != 3) return '';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final month = int.parse(d[1]);
    if (month < 1 || month > 12) return '';
    return '${d[2].trim().padLeft(2, '0')} ${months[month - 1]} ${d[0]}';
  } catch (_) {
    return '';
  }
}

class HomeScreen extends StatefulWidget {
  final Store store;
  final VoidCallback onOpenDrawer;
  final ValueChanged<int> onSelectTab;
  const HomeScreen({super.key, required this.store, required this.onOpenDrawer, required this.onSelectTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _QuickItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickItem(this.icon, this.title, this.subtitle, this.onTap);
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Store get store => widget.store;

  void _openTournament(BuildContext context, Tournament t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentDetailScreen(store: store, tournament: t),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    // Hero features the most recently created tournament (the list is in
    // creation order); with no tournaments the hero hides into an empty
    // state — there is no seeded/default tournament anymore.
    final featuredT =
        store.tournaments.isEmpty ? null : store.tournaments.last;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kOceanBlack, kSunsetNavyDeep],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Branded header
              BrandedHeader(
                onMenu: widget.onOpenDrawer,
                onSettings: () =>
                    _push(context, SettingsScreen(store: store)),
              ),
              const SizedBox(height: 16),
              // 2. HERO — featured tournament
              _heroCard(context, featuredT),
              const SizedBox(height: 20),
              // 3. Quick actions (2x2 premium grid)
              _sectionTitle('Quick Actions', Icons.flash_on),
              const SizedBox(height: 10),
              _quickGrid(context),
              const SizedBox(height: 20),
              // 4. Recent matches
              // Recent Matches opens the completed-matches list
              // (v1.3.5) — never the general Matches screen.
              _sectionTitle('Recent Matches', Icons.history,
                  trailing: ViewAllLink(
                      onTap: () => _push(
                          context,
                          CompletedMatchesScreen(store: store)))),
              const SizedBox(height: 10),
              _recentMatches(context),
            ],
          ),
        ),
      ),
    );
  }

  /// Small premium section heading — orange accent bar.
  Widget _sectionTitle(String title, IconData icon, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              gradient: kSunsetGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: kSunsetOrange, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: kWhite,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (trailing != null) ...[trailing],
        ],
      ),
    );
  }

  // ---------- 2. HERO card — sunset gradient, big tournament name ----------
  Widget _heroCard(BuildContext context, Tournament? t) {
    if (t == null) {
      return const EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No tournament yet',
        subtitle: 'Create a tournament and it will be featured here.',
      );
    }
    final fixtures =
        store.matches.where((m) => m.tournamentId == t.id).toList();
    final dateRange = _fixtureDateRange(fixtures);
    final teamCount = t.teamIds.length;
    return GestureDetector(
      onTap: () => _openTournament(context, t),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [kSunsetOrange, kSunsetNavy],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: kSunsetOrangeSoft.withValues(alpha: 0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: kSunsetOrange.withValues(alpha: 0.35),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                ),
              ),
              child: const Text(
                '★ FEATURED TOURNAMENT',
                style: TextStyle(
                  color: kWhite,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              t.name,
              style: const TextStyle(
                color: kWhite,
                fontSize: 27,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _heroChip(Icons.groups, '$teamCount Teams'),
                if (dateRange.isNotEmpty)
                  _heroChip(Icons.calendar_month, dateRange),
                _heroChip(Icons.sports_cricket,
                    '${fixtures.length} Matches'),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: kWhite,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'View Tournament →',
                style: TextStyle(
                  color: kSunsetOrangeDeep,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kWhite, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: kWhite,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 3. Quick actions — 2x2 ocean grid with sunset icons ----------
  Widget _quickGrid(BuildContext context) {
    void push(Widget page) => _push(context, page);
    final items = [
      _QuickItem(Icons.sports_cricket, 'New Match', 'Quick / Custom',
          () => widget.onSelectTab(2)),
      _QuickItem(Icons.emoji_events, 'Tournaments', 'View & Manage',
          () => push(TournamentsScreen(store: store))),
      _QuickItem(Icons.groups, 'Teams', 'Add / Manage',
          () => push(TeamsScreen(store: store))),
      _QuickItem(Icons.person, 'Players', 'Registered',
          () => push(RegistrationScreen(store: store))),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemCount: items.length,
      itemBuilder: (c, i) => _quickCard(items[i]),
    );
  }

  Widget _quickCard(_QuickItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: item.onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: kOceanCardGradient,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: kOceanSteel.withValues(alpha: 0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          // v1.2.2: scale the content down to fit the card instead of
          // clipping title/subtitle on narrow (~360dp) phones.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: kSunsetGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: kSunsetOrange.withValues(alpha: 0.4),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(item.icon, color: kWhite, size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kOceanFaint,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // (Old 5-card action row removed — replaced by _quickGrid 2x2.)

  // ---------- 3. Featured tournament card ----------
  // (Old _tournamentCard/_metaChip removed — replaced by _heroCard.)

  /// Date range label from real fixture dates, e.g. '22 Oct - 08 Nov 2026'.
  String _fixtureDateRange(List<Match> fixtures) {
    final dates =
        fixtures.map((m) => m.dateIso).where((d) => d.isNotEmpty).toList()
          ..sort();
    if (dates.isEmpty) return '';
    final first = dates.first;
    final last = dates.last;
    if (first.split('T').first == last.split('T').first) {
      return _shortDate(first);
    }
    return '${_shortDate(first)} - ${_shortDate(last)}';
  }

  // ---------- 4. Quick actions grid (2 rows x 4) ----------
  // ---------- 5. Recent matches ----------
  Widget _recentMatches(BuildContext context) {
    final done = store.matches
        .where((m) => m.status == 'completed')
        .toList()
      ..sort((a, b) => b.dateIso.compareTo(a.dateIso));
    final show = done.take(3).toList();
    if (show.isEmpty) {
      return ScoreCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const EmptyState(
              icon: Icons.scoreboard_outlined,
              title: 'No matches yet',
              subtitle:
                  'Start a new match or open a tournament to view match history.',
            ),
            ScoreButton(
              label: 'New Match',
              icon: Icons.add_circle_outline,
              kind: ScoreButtonKind.ghost,
              onPressed: () => widget.onSelectTab(2),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < show.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _recentMatchCard(context, show[i]),
        ],
      ],
    );
  }

  Widget _recentMatchCard(BuildContext context, Match m) {
    final a = store.teamName(m.teamAId);
    final b = store.teamName(m.teamBId);
    return ScoreCard(
      padding: const EdgeInsets.all(12),
      // Tapping Recent Matches opens the list of ALL completed
      // matches (v1.3.5); the user opens the one they want there.
      onTap: () =>
          _push(context, CompletedMatchesScreen(store: store)),
      child: Row(
        children: [
          CaptainAvatar(store: store, teamId: m.teamAId, radius: 18),
          const SizedBox(width: 4),
          CaptainAvatar(store: store, teamId: m.teamBId, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$a vs $b',
                  style: const TextStyle(
                    color: kWhite,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                ..._scoreLines(m).map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: Text(
                      line,
                      style: const TextStyle(
                          color: kSilver, fontSize: 12),
                    ),
                  ),
                ),
                if (m.resultText.isNotEmpty)
                  Text(
                    m.resultText,
                    style: const TextStyle(
                      color: kCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          const StatusPill('completed'),
        ],
      ),
    );
  }

  List<String> _scoreLines(Match m) {
    final lines = <String>[];
    for (final inn in m.innings) {
      final bat = store.teamName(inn.battingTeamId);
      final overs = inn.ballsPerOver > 0
          ? '${inn.legalBalls ~/ inn.ballsPerOver}.${inn.legalBalls % inn.ballsPerOver}'
          : '${inn.legalBalls}';
      lines.add('$bat ${inn.totalRuns}/${inn.wickets} ($overs ov)');
    }
    return lines.take(2).toList();
  }
}

