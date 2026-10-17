// 60Score home dashboard.
// Built only from real persisted store data — nothing hardcoded.
import 'package:flutter/material.dart';

import '../models.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import '../tournament_engine.dart';
import 'match_setup_screen.dart';
import 'registration_screen.dart';
import 'scorer_home_screen.dart';
import 'scorecard_screen.dart';
import 'scoring_screen.dart';
import 'settings_screen.dart';
import 'fixture_detail_screen.dart';
import 'teams_screen.dart';

/// Formats a stored dateIso like '2026-10-22T14:00:00' as
/// '22 Oct 2026, 02:00 PM'. Manual parse — never a toIso8601String round-trip.
String formatFixtureDate(String iso) {
  try {
    final parts = iso.split('T');
    if (parts.length != 2) return iso;
    final d = parts[0].split('-');
    final t = parts[1].split(':');
    if (d.length != 3 || t.length < 2) return iso;
    final day = int.parse(d[2]);
    final month = int.parse(d[1]);
    final year = int.parse(d[0]);
    final hour = int.parse(t[0]);
    final minute = t[1].padLeft(2, '0');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    if (month < 1 || month > 12) return iso;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    var h12 = hour % 12;
    if (h12 == 0) h12 = 12;
    return '${day.toString().padLeft(2, '0')} ${months[month - 1]} $year, '
        '${h12.toString().padLeft(2, '0')}:$minute $ampm';
  } catch (_) {
    return iso;
  }
}

class HomeScreen extends StatelessWidget {
  final Store store;
  final VoidCallback onOpenDrawer;
  final ValueChanged<int> onSelectTab;

  const HomeScreen({
    super.key,
    required this.store,
    required this.onOpenDrawer,
    required this.onSelectTab,
  });

  void _openTournament(BuildContext context, Tournament t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TournamentDetailScreen(store: store, tournament: t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final defaultT = store.tournamentById(Store.defaultTournamentId);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const SizedBox(height: 12),
            _tournamentCard(context, defaultT),
            _upcomingSection(context),
            _liveSection(context),
            _recentSection(context),
            _pointsSection(context, defaultT),
            _quickActions(context, defaultT),
          ],
        ),
      ),
    );
  }

  // ---------- branded header ----------
  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Menu',
          icon: const Icon(Icons.menu, color: kWhite),
          onPressed: onOpenDrawer,
        ),
        Image.asset('assets/60score_logo.png', height: 40),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '60Score',
                style: TextStyle(
                  color: kWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Cricket Scoring, Simplified.',
                style: TextStyle(color: kSilver, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          icon: const Icon(Icons.settings_outlined, color: kSilver),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsScreen(store: store),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- featured default tournament ----------
  Widget _tournamentCard(BuildContext context, Tournament? t) {
    if (t == null) {
      return const EmptyState(
        icon: Icons.emoji_events_outlined,
        title: 'No tournament yet',
        subtitle: 'The default tournament will appear here after setup.',
      );
    }
    final fixtureCount =
        store.matches.where((m) => m.tournamentId == t.id).length;
    return ScoreCard(
      highlight: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events, color: kGold, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t.name,
                  style: const TextStyle(
                    color: kWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (t.venue.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    color: kSilver, size: 14),
                const SizedBox(width: 4),
                Text(t.venue,
                    style:
                        const TextStyle(color: kSilver, fontSize: 13)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              StatChip('Teams', '${t.teamIds.length}'),
              const SizedBox(width: 10),
              StatChip('Fixtures', '$fixtureCount'),
            ],
          ),
          const SizedBox(height: 14),
          ScoreButton(
            label: 'View Tournament',
            icon: Icons.arrow_forward,
            onPressed: () => _openTournament(context, t),
          ),
        ],
      ),
    );
  }

  // ---------- upcoming fixtures ----------
  Widget _upcomingSection(BuildContext context) {
    final upcoming = store.matches
        .where((m) => m.status == 'upcoming')
        .toList()
      ..sort((a, b) => a.dateIso.compareTo(b.dateIso));
    final show = upcoming.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Upcoming Fixtures',
          action: TextButton(
            onPressed: () => onSelectTab(1),
            child: const Text('View all',
                style: TextStyle(color: kCyan, fontSize: 13)),
          ),
        ),
        if (show.isEmpty)
          const EmptyState(
            icon: Icons.event_outlined,
            title: 'No upcoming fixtures',
            subtitle: 'Create a match or tournament fixture to see it here.',
          )
        else
          ...show.map((m) => _fixtureTile(context, m)),
      ],
    );
  }

  Widget _fixtureTile(BuildContext context, Match m) {
    final a = store.teamName(m.teamAId);
    final b = store.teamName(m.teamBId);
    final isPlayoff = m.stage != 'league';
    final title = isPlayoff && m.matchTitle.isNotEmpty ? m.matchTitle : '$a vs $b';
    final subtitle = isPlayoff
        ? '$a vs $b  •  ${formatFixtureDate(m.dateIso)}'
        : '${formatFixtureDate(m.dateIso)}${m.venue.isNotEmpty ? '  •  ${m.venue}' : ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ScoreCard(
        padding: const EdgeInsets.all(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FixtureDetailScreen(
              store: store,
              matchId: m.id,
            ),
          ),
        ),
        child: Row(
          children: [
            TeamAvatar(a, radius: 18),
            const SizedBox(width: 4),
            TeamAvatar(b, radius: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: kWhite,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const StatusPill('upcoming'),
          ],
        ),
      ),
    );
  }

  // ---------- live matches ----------
  Widget _liveSection(BuildContext context) {
    final live =
        store.matches.where((m) => m.status == 'live').toList();
    if (live.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Live Matches'),
        ...live.map((m) {
          final a = store.teamName(m.teamAId);
          final b = store.teamName(m.teamBId);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ScoreCard(
              highlight: true,
              padding: const EdgeInsets.all(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScoringScreen(store: store, match: m),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$a vs $b',
                            style: const TextStyle(
                                color: kWhite,
                                fontWeight: FontWeight.w700,
                                fontSize: 14)),
                        const SizedBox(height: 3),
                        Text(_liveSummary(m),
                            style: const TextStyle(
                                color: kSilver, fontSize: 12)),
                      ],
                    ),
                  ),
                  const StatusPill('live'),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  String _liveSummary(Match m) {
    if (m.innings.isEmpty) return 'Match in progress';
    final inn = m.innings.last;
    final bat = store.teamName(inn.battingTeamId);
    return '$bat ${inn.totalRuns}/${inn.wickets} '
        '(${oversText(inn.legalBalls, inn.ballsPerOver)})';
  }

  // ---------- recent results ----------
  Widget _recentSection(BuildContext context) {
    final done = store.matches
        .where((m) => m.status == 'completed')
        .toList()
      ..sort((a, b) => b.dateIso.compareTo(a.dateIso));
    final show = done.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Recent Results',
          action: TextButton(
            onPressed: () => onSelectTab(1),
            child: const Text('View all',
                style: TextStyle(color: kCyan, fontSize: 13)),
          ),
        ),
        if (show.isEmpty)
          const EmptyState(
            icon: Icons.scoreboard_outlined,
            title: 'No completed matches',
            subtitle: 'Finished matches and their scorecards appear here.',
          )
        else
          ...show.map((m) {
            final a = store.teamName(m.teamAId);
            final b = store.teamName(m.teamBId);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ScoreCard(
                padding: const EdgeInsets.all(12),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ScorecardScreen(store: store, match: m),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$a vs $b',
                              style: const TextStyle(
                                  color: kWhite,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14)),
                          if (m.resultText.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(m.resultText,
                                style: const TextStyle(
                                    color: kSilver, fontSize: 12)),
                          ],
                        ],
                      ),
                    ),
                    const StatusPill('completed'),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  // ---------- points-table summary ----------
  Widget _pointsSection(BuildContext context, Tournament? t) {
    if (t == null) return const SizedBox.shrink();
    final table = leaguePointsTable(t, store.matches);
    final show = table.take(4).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Points Table',
          action: TextButton(
            onPressed: () => _openTournament(context, t),
            child: const Text('Full table',
                style: TextStyle(color: kCyan, fontSize: 13)),
          ),
        ),
        if (show.isEmpty)
          const EmptyState(
            icon: Icons.table_chart_outlined,
            title: 'No standings yet',
            subtitle: 'Complete a league match to build the table.',
          )
        else
          ScoreCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              children: [
                _pointsHeaderRow(),
                const Divider(height: 8),
                ...show.asMap().entries.map(
                      (e) => _pointsRow(e.key + 1, e.value),
                    ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pointsHeaderRow() {
    const style = TextStyle(
        color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700);
    return const Row(
      children: [
        SizedBox(width: 26, child: Text('#', style: style)),
        Expanded(child: Text('Team', style: style)),
        SizedBox(width: 30, child: Text('P', style: style)),
        SizedBox(width: 30, child: Text('W', style: style)),
        SizedBox(width: 30, child: Text('L', style: style)),
        SizedBox(width: 36, child: Text('Pts', style: style)),
        SizedBox(width: 64, child: Text('NRR', style: style)),
      ],
    );
  }

  Widget _pointsRow(int pos, PointsRow row) {
    final name = store.teamName(row.teamId);
    TextStyle cell(bool head) => TextStyle(
          color: head ? kWhite : kSilver,
          fontSize: 12,
          fontWeight: head ? FontWeight.w700 : FontWeight.w400,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$pos',
                style: const TextStyle(
                    color: kCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: Text(name,
                overflow: TextOverflow.ellipsis, style: cell(true)),
          ),
          SizedBox(width: 30, child: Text('${row.played}', style: cell(false))),
          SizedBox(width: 30, child: Text('${row.won}', style: cell(false))),
          SizedBox(width: 30, child: Text('${row.lost}', style: cell(false))),
          SizedBox(width: 36, child: Text('${row.points}', style: cell(true))),
          SizedBox(
            width: 64,
            child: Text(row.nrr.toStringAsFixed(3), style: cell(false)),
          ),
        ],
      ),
    );
  }

  // ---------- quick actions ----------
  Widget _quickActions(BuildContext context, Tournament? t) {
    void push(Widget page) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => page),
        );
    final actions = <_QuickAction>[
      _QuickAction('New Match', Icons.add_circle_outline, kCyan,
          () => push(MatchSetupScreen(store: store))),
      _QuickAction('Tournaments', Icons.emoji_events_outlined, kGold, () {
        if (t != null) {
          _openTournament(context, t);
        } else {
          onSelectTab(1);
        }
      }),
      _QuickAction('Teams', Icons.group_outlined, kTeal,
          () => push(TeamsScreen(store: store))),
      _QuickAction('Players', Icons.how_to_reg_outlined, kCyan,
          () => push(RegistrationScreen(store: store))),
      _QuickAction('Scorecards', Icons.scoreboard_outlined, kSilver,
          () => onSelectTab(1)),
      _QuickAction('Statistics', Icons.bar_chart_outlined, kGold,
          () => onSelectTab(3)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Quick Actions'),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.15,
          ),
          itemCount: actions.length,
          itemBuilder: (_, i) {
            final a = actions[i];
            return ScoreCard(
              padding: const EdgeInsets.all(10),
              onTap: a.onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(a.icon, color: a.color, size: 26),
                  const SizedBox(height: 8),
                  Text(
                    a.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: kWhite,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  _QuickAction(this.label, this.icon, this.color, this.onTap);
}
