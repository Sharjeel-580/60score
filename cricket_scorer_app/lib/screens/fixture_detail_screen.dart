import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import 'match_setup_screen.dart';
import 'scorecard_screen.dart';
import 'scoring_screen.dart';

/// "2026-11-06T15:00:00" -> "06 Nov 2026, 03:00 PM".
/// "2026-11-06"          -> "06 Nov 2026".
/// Anything unparseable is returned as-is.
String formatFixtureDate(String dateIso) {
  if (dateIso.isEmpty) return 'Date TBD';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  try {
    final datePart = dateIso.split('T').first;
    final dp = datePart.split('-');
    if (dp.length != 3) return dateIso;
    final y = int.parse(dp[0]);
    final mo = int.parse(dp[1]);
    final d = int.parse(dp[2]);
    if (mo < 1 || mo > 12) return dateIso;
    final dateStr = '${d.toString().padLeft(2, '0')} ${months[mo - 1]} $y';
    if (!dateIso.contains('T')) return dateStr;
    final timePart = dateIso.split('T')[1].split(':');
    if (timePart.length < 2) return dateStr;
    final h24 = int.parse(timePart[0]);
    final min = timePart[1].padLeft(2, '0').substring(0, 2);
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    var h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    return '$dateStr, ${h12.toString().padLeft(2, '0')}:$min $ampm';
  } catch (_) {
    return dateIso;
  }
}

/// Human label for a tournament stage.
String stageLabel(String stage) {
  switch (stage) {
    case 'semifinal1':
      return 'Semi Final 1';
    case 'semifinal2':
      return 'Semi Final 2';
    case 'final':
      return 'Grand Final';
    default:
      return 'League Fixture';
  }
}

/// Detail screen for a single fixture/match.
///
/// Routing hub: upcoming and cancelled/no-result fixtures land here (never
/// on the scorecard — that was the red-screen bug). Returns `true` from
/// Navigator.pop when the fixture was changed, so callers can refresh.
class FixtureDetailScreen extends StatefulWidget {
  final Store store;
  final String matchId;
  const FixtureDetailScreen({
    super.key,
    required this.store,
    required this.matchId,
  });

  @override
  State<FixtureDetailScreen> createState() => _FixtureDetailScreenState();
}

class _FixtureDetailScreenState extends State<FixtureDetailScreen> {
  Store get store => widget.store;
  Match? get match => store.matchById(widget.matchId);

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _cancelFixture(Match m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel fixture?'),
        content: const Text(
          'This fixture will be marked as cancelled. '
          'A cancelled fixture counts as finalized for the points table.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: kRed),
            child: const Text('Cancel fixture'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    m.status = 'cancelled';
    await store.upsertMatch(m);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _reopenFixture(Match m) async {
    m.status = 'upcoming';
    await store.upsertMatch(m);
    _snack('Fixture reopened as upcoming');
    if (mounted) Navigator.pop(context, true);
  }

  Widget _teamRow(String teamId) {
    final name = store.teamName(teamId); // 'TBD' when unassigned
    return Row(
      children: [
        TeamAvatar(name),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: TextStyle(
              color: teamId.isEmpty ? Colors.white38 : kWhite,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = match;
    if (m == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const EmptyState(
                icon: Icons.event_busy,
                title: 'Fixture not found',
                subtitle: 'This fixture may have been deleted.',
              ),
              const SizedBox(height: 8),
              ScoreButton(
                label: 'Go back',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    }

    final title = m.matchTitle.isNotEmpty ? m.matchTitle : stageLabel(m.stage);
    final oversLabel = '${m.oversLimit} overs';

    return Scaffold(
      appBar: AppBar(title: const Text('Fixture')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ScoreCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: kWhite,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    StatusPill(m.status),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  stageLabel(m.stage),
                  style: const TextStyle(color: kCyan, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _teamRow(m.teamAId),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(child: Divider()),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'VS',
                          style: TextStyle(
                            color: kGold,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      Expanded(child: Divider()),
                    ],
                  ),
                ),
                _teamRow(m.teamBId),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ScoreCard(
            child: Column(
              children: [
                _infoRow(
                  Icons.calendar_month,
                  'Date',
                  formatFixtureDate(m.dateIso),
                ),
                const Divider(height: 20),
                _infoRow(
                  Icons.location_on_outlined,
                  'Venue',
                  m.venue.isNotEmpty ? m.venue : 'TBD',
                ),
                const Divider(height: 20),
                _infoRow(Icons.timer_outlined, 'Format', oversLabel),
                if (m.resultText.isNotEmpty) ...[
                  const Divider(height: 20),
                  _infoRow(Icons.emoji_events_outlined, 'Result', m.resultText),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          ..._actions(m),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: kTeal),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: kWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _actions(Match m) {
    switch (m.status) {
      case 'upcoming':
        return [
          ScoreButton(
            label: 'Start Setup',
            icon: Icons.play_arrow,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MatchSetupScreen(
                  store: store,
                  tournamentId: m.tournamentId,
                  existingMatch: m,
                ),
              ),
            ).then((_) {
              if (mounted) setState(() {});
            }),
          ),
          const SizedBox(height: 10),
          ScoreButton(
            label: 'Edit fixture',
            kind: ScoreButtonKind.ghost,
            icon: Icons.edit_outlined,
            onPressed: () => _snack(
              'Fixture editing is not available yet — cancel and recreate if needed.',
            ),
          ),
          const SizedBox(height: 10),
          ScoreButton(
            label: 'Cancel fixture',
            kind: ScoreButtonKind.danger,
            icon: Icons.cancel_outlined,
            onPressed: () => _cancelFixture(m),
          ),
        ];
      case 'live':
        return [
          ScoreButton(
            label: 'Continue scoring',
            icon: Icons.sports_cricket,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ScoringScreen(store: store, match: m),
              ),
            ).then((_) {
              if (mounted) setState(() {});
            }),
          ),
        ];
      case 'completed':
        return [
          ScoreButton(
            label: 'View scorecard',
            icon: Icons.receipt_long,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ScorecardScreen(store: store, match: m),
              ),
            ),
          ),
        ];
      case 'cancelled':
        return [
          const EmptyState(
            icon: Icons.cancel_outlined,
            title: 'Fixture cancelled',
            subtitle: 'This fixture counts as finalized for the points table.',
          ),
          ScoreButton(
            label: 'Reopen as upcoming',
            kind: ScoreButtonKind.gold,
            icon: Icons.restore,
            onPressed: () => _reopenFixture(m),
          ),
        ];
      default: // noResult and anything unexpected
        return [
          EmptyState(
            icon: Icons.info_outline,
            title: m.status == 'noResult' ? 'No result' : m.status,
            subtitle: m.resultText.isNotEmpty
                ? m.resultText
                : 'This fixture is finalized.',
          ),
        ];
    }
  }
}
