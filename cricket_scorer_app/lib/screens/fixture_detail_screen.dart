import 'package:flutter/material.dart';

import '../models.dart';
import '../nav_memory.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import '../fixture_poster.dart';
import '../widgets/player_avatar.dart';
import 'fixture_edit_screen.dart';
import 'match_setup_screen.dart';
import 'scorecard_screen.dart';
import 'scorer_home_screen.dart';
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

  @override
  void initState() {
    super.initState();
    // Recents resume (v1.4.5): see NavMemory's contract.
    NavMemory.save('fixture', widget.matchId);
  }

  @override
  void dispose() {
    NavMemory.clear('fixture', widget.matchId);
    super.dispose();
  }

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

  /// Full fixture edit (v1.3.7): date, time, venue, teams, overs,
  /// title, round — see FixtureEditScreen for the guard rails
  /// (upcoming fixtures only, so no scoring data can be harmed).
  Future<void> _editFixture(Match m) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FixtureEditScreen(store: store, matchId: m.id),
      ),
    );
    if (changed == true && mounted) setState(() {});
  }

  /// Delete this fixture outright (v1.3.7), with the standard
  /// confirm. Offered for every non-live status that lands on this
  /// screen — until now a fixture could only be cancelled, never
  /// removed. Live matches are never routed here, and completed
  /// matches keep their own delete actions (scorecard / lists).
  Future<void> _deleteFixture(Match m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete fixture?'),
        content: Text(
          'Delete ${store.teamName(m.teamAId)} vs '
          '${store.teamName(m.teamBId)}? This removes the fixture '
          'permanently.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: kRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await store.deleteMatch(m.id);
    if (mounted) Navigator.pop(context, true);
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

    final tournamentName = m.tournamentId == null
        ? ''
        : (store.tournamentById(m.tournamentId!)?.name ?? '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Match Fixture'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share poster',
            onPressed: () => shareFixturePoster(context, store, m),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _fixtureHero(m, tournamentName),
          const SizedBox(height: 12),
          _infoCards(m),
          const SizedBox(height: 12),
          _actionGrid(m),
          const SizedBox(height: 12),
          _previousMeetings(m),
          const SizedBox(height: 10),
          _headToHeadCard(m),
          const SizedBox(height: 10),
          _standingCard(m),
          const SizedBox(height: 12),
          ..._statusActions(m),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ---------- Hero: MATCH FIXTURE + VS with captains ----------

  Player? _captain(String teamId) {
    final t = store.teamById(teamId);
    if (t == null) return null;
    for (final p in t.players) {
      if (p.isCaptain) return p;
    }
    return null;
  }

  Widget _fixtureHero(Match m, String tournamentName) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1B2E), Color(0xFF060D18)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: kGold.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          const Text(
            '60SCORE',
            style: TextStyle(
              color: kCyan,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 2),
          RichText(
            textAlign: TextAlign.center,
            text: const TextSpan(
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
              children: [
                TextSpan(
                  text: 'MATCH ',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: 'FIXTURE',
                  style: TextStyle(color: kGold),
                ),
              ],
            ),
          ),
          if (tournamentName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: kGold.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.emoji_events,
                    size: 14,
                    color: kGold,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      tournamentName,
                      style: const TextStyle(
                        color: kGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            stageLabel(m.stage).toUpperCase(),
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _captainBlock(m.teamAId, kCyan)),
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: kGold,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              Expanded(child: _captainBlock(m.teamBId, kOrangeRed)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _captainBlock(String teamId, Color accent) {
    final name = store.teamName(teamId);
    final cap = _captain(teamId);
    // v1.1.6: captain's photo via the shared player record, so a photo
    // added in Registered Players / Team Management shows up here without
    // any re-import. Never another player's photo.
    final capPhoto = cap == null ? '' : store.photoForPlayer(cap.id);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 12,
              ),
            ],
          ),
          child: PlayerAvatar(
            photoBase64: capPhoto.isEmpty ? null : capPhoto,
            role: cap?.role ?? 'Batter',
            name: cap?.name ?? name,
            radius: 38,
            // v1.1.5: captains without a photo get a clean default person
            // icon — never a role icon, never another player's photo.
            fallbackIcon: Icons.person_outline,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.6)),
          ),
          child: Column(
            children: [
              Text(
                name.isEmpty ? 'TBD' : name.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                cap != null ? 'Captain: ${cap.name}' : 'Captain: unassigned',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Date / Time / Venue cards ----------

  Widget _infoCards(Match m) {
    final parts = _splitDateTime(m.dateIso);
    Widget card(IconData icon, String top, String bottom, Color accent) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accent.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: kCyan, size: 22),
                const SizedBox(height: 8),
                Text(
                  top,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  bottom,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        card(
          Icons.calendar_month,
          parts[0],
          'Match Date',
          kCyan,
        ),
        const SizedBox(width: 10),
        card(
          Icons.access_time,
          parts[1],
          'Match Time',
          kTeal,
        ),
        const SizedBox(width: 10),
        card(
          Icons.location_on_outlined,
          m.venue.isNotEmpty ? m.venue : 'TBD',
          'Venue',
          kGold,
        ),
      ],
    );
  }

  /// Split "06 Nov 2026, 03:00 PM" into [date, time].
  List<String> _splitDateTime(String dateIso) {
    final full = formatFixtureDate(dateIso);
    if (full == 'Date TBD') return ['Date TBD', '--:--'];
    final idx = full.indexOf(',');
    if (idx < 0) return [full, '--:--'];
    return [full.substring(0, idx).trim(), full.substring(idx + 1).trim()];
  }

  /// v1.1.6: mirrors the New Match screen's _canStart gate — teams set and
  /// different, at least 2 players per XI, toss recorded. Below this the
  /// user is guided through the existing setup flow instead of scoring.
  bool _fixtureReadyForScoring(Match m) =>
      m.teamAId.isNotEmpty &&
      m.teamBId.isNotEmpty &&
      m.teamAId != m.teamBId &&
      m.xiA.length >= 2 &&
      m.xiB.length >= 2 &&
      m.tossWinnerId.isNotEmpty;

  // ---------- 2x2 action grid ----------

  Widget _actionGrid(Match m) {
    Widget btn({
      required IconData icon,
      required String label,
      required Color color,
      required VoidCallback? onTap,
    }) =>
        Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 10,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: color.withValues(alpha: onTap == null ? 0.25 : 0.6),
                  width: 1.5,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: onTap == null ? 0.06 : 0.22),
                    color.withValues(alpha: onTap == null ? 0.02 : 0.08),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: onTap == null
                        ? Colors.white24
                        : color,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: onTap == null
                            ? Colors.white24
                            : Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

    VoidCallback? liveTap;
    if (m.status == 'live') {
      liveTap = () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScoringScreen(store: store, match: m),
            ),
          ).then((_) {
            if (mounted) setState(() {});
          });
    } else if (m.status == 'upcoming') {
      // v1.1.6 "Do Scoring": one tap per fixture, no duplicates.
      // Setup complete -> flip this fixture to live and go to scoring.
      // Setup missing -> open the existing setup screen on this fixture
      // (in-place update, the fixture is preserved and never duplicated).
      liveTap = () async {
        if (_fixtureReadyForScoring(m)) {
          m.status = 'live';
          await store.upsertMatch(m);
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScoringScreen(store: store, match: m),
            ),
          ).then((_) {
            if (mounted) setState(() {});
          });
        } else {
          Navigator.push(
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
          });
        }
      };
    }

    VoidCallback? scorecardTap;
    if (m.status == 'completed' || m.innings.isNotEmpty) {
      scorecardTap = () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScorecardScreen(store: store, match: m),
            ),
          );
    }

    return Column(
      children: [
        Row(
          children: [
            btn(
              icon: Icons.info_outline,
              label: 'Match Details',
              color: kCyan,
              onTap: () => _showDetailsSheet(m),
            ),
            const SizedBox(width: 10),
            btn(
              icon: Icons.group_outlined,
              label: 'Playing XI',
              color: kTeal,
              onTap: () => _showPlayingXiSheet(m),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            btn(
              icon: Icons.sports_cricket,
              // v1.1.6: "Do Scoring" on a saved fixture (was "Start Scoring").
              label: m.status == 'live' ? 'Live Scoring' : 'Do Scoring',
              color: const Color(0xFFB388FF),
              onTap: liveTap,
            ),
            const SizedBox(width: 10),
            btn(
              icon: Icons.receipt_long,
              label: 'View Scorecard',
              color: kGold,
              onTap: scorecardTap,
            ),
          ],
        ),
      ],
    );
  }

  void _showDetailsSheet(Match m) {
    final tid = m.tournamentId;
    final tname = tid == null
        ? 'Friendly'
        : (store.tournamentById(tid)?.name ?? 'Friendly');
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Match Details',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              _infoRow(
                Icons.emoji_events_outlined,
                'Tournament',
                tname,
              ),
              const Divider(height: 20),
              _infoRow(
                Icons.timer_outlined,
                'Format',
                '${m.oversLimit} overs',
              ),
              const Divider(height: 20),
              _infoRow(
                Icons.sports_baseball,
                'Ball Type',
                m.ballType,
              ),
              if (m.tossWinnerId.isNotEmpty) ...[
                const Divider(height: 20),
                _infoRow(
                  Icons.casino_outlined,
                  'Toss',
                  '${store.teamName(m.tossWinnerId)} chose to ${m.tossDecision}',
                ),
              ],
              if (m.resultText.isNotEmpty) ...[
                const Divider(height: 20),
                _infoRow(
                  Icons.emoji_events,
                  'Result',
                  m.resultText,
                ),
              ],
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlayingXiSheet(Match m) {
    Widget xiList(String label, List<String> xi) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: kCopper,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            if (xi.isEmpty)
              const Text(
                'Not announced yet.',
                style: TextStyle(color: Colors.white54),
              ),
            for (var i = 0; i < xi.length; i++)
              Builder(builder: (_) {
                final pid = xi[i];
                final pl = store.findPlayer(pid);
                final t = store.teamById(
                    label == store.teamName(m.teamAId)
                        ? m.teamAId
                        : m.teamBId);
                final tp = t?.playerById(pid);
                // v1.1.6: photo via the shared player record.
                final xiPhoto = store.photoForPlayer(pid);
                return ListTile(
                  dense: true,
                  leading: PlayerAvatar(
                    photoBase64: xiPhoto.isEmpty ? null : xiPhoto,
                    role: tp?.role ?? pl?.role ?? 'Batter',
                    name: store.playerName(pid),
                    radius: 16,
                  ),
                  title: Text(store.playerName(pid)),
                  trailing: tp?.isCaptain == true
                      ? const Text(
                          'C',
                          style: TextStyle(
                            color: kGold,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                );
              }),
            const SizedBox(height: 8),
          ],
        );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Playing XI',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      xiList(store.teamName(m.teamAId), m.xiA),
                      xiList(store.teamName(m.teamBId), m.xiB),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Previous meetings / H2H / Standing ----------

  List<Match> _pastMeetings(Match m) {
    return store.matches
        .where((x) =>
            x.id != m.id &&
            x.tournamentId == m.tournamentId &&
            ((x.teamAId == m.teamAId && x.teamBId == m.teamBId) ||
                (x.teamAId == m.teamBId && x.teamBId == m.teamAId)) &&
            (x.status == 'completed'))
        .toList();
  }

  Widget _previousMeetings(Match m) {
    final past = _pastMeetings(m);
    return ScoreCard(
      child: ExpansionTile(
        leading: const Icon(Icons.history, color: kCyan),
        title: Text(
          'Previous Meetings (${past.length})',
          style: const TextStyle(
            color: kWhite,
            fontWeight: FontWeight.w700,
          ),
        ),
        children: [
          if (past.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'No previous meetings in this tournament.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          for (final p in past.take(5))
            ListTile(
              dense: true,
              title: Text(
                '${store.teamName(p.teamAId)} vs ${store.teamName(p.teamBId)}',
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                p.resultText.isEmpty ? formatFixtureDate(p.dateIso) : p.resultText,
                style: const TextStyle(fontSize: 11),
                maxLines: 2,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ScorecardScreen(store: store, match: p),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _headToHeadCard(Match m) {
    final h = headToHead(store.matches, m.teamAId, m.teamBId);
    return ScoreCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.bar_chart, color: kCyan, size: 20),
                SizedBox(width: 8),
                Text(
                  'Head to Head',
                  style: TextStyle(
                    color: kWhite,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _h2hStat(
                    '${h.aWins}',
                    '${store.teamName(m.teamAId)} wins',
                    kCyan,
                  ),
                ),
                Expanded(
                  child: _h2hStat(
                    '${h.played}',
                    'Played',
                    kWhite,
                  ),
                ),
                Expanded(
                  child: _h2hStat(
                    '${h.bWins}',
                    '${store.teamName(m.teamBId)} wins',
                    kGold,
                  ),
                ),
              ],
            ),
            if (h.tied > 0 || h.noResult > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Tied: ${h.tied}  •  No result: ${h.noResult}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _h2hStat(String value, String label, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _standingCard(Match m) {
    final tid = m.tournamentId ?? '';
    final t = tid.isEmpty ? null : store.tournamentById(tid);
    final teamIds = t?.teamIds ?? [m.teamAId, m.teamBId];
    final entries = computePointsTable(
      tid,
      teamIds,
      store.matches,
      pointsAdjustments: t?.pointsAdjustments ?? const {},
      pointsTableOverrides: t?.pointsTableOverrides ?? const {},
    );
    return ScoreCard(
      child: InkWell(
        // v1.1.5: opens the tournament's existing points-table screen.
        onTap: () {
          final tid = m.tournamentId;
          final t = tid == null ? null : store.tournamentById(tid);
          if (t == null) {
            _snack('No tournament linked to this fixture.');
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TournamentDetailScreen(
                store: store,
                tournament: t,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.emoji_events_outlined,
                      color: kGold, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tournament Standing',
                          style: TextStyle(
                            color: kWhite,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'View points table and team position',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.white38),
                ],
              ),
              if (entries.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (var i = 0; i < entries.take(4).length; i++)
                  Builder(builder: (_) {
                    final e = entries[i];
                    final isMine =
                        e.teamId == m.teamAId || e.teamId == m.teamBId;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: isMine ? kGold : Colors.white54,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              store.teamName(e.teamId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isMine ? kWhite : Colors.white70,
                                fontWeight: isMine
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            '${e.points} pts',
                            style: const TextStyle(
                              color: kCyan,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------- Status-based actions (existing logic, preserved) ----------

  List<Widget> _statusActions(Match m) {
    switch (m.status) {
      case 'upcoming':
        return [
          Row(
            children: [
              Expanded(
                child: ScoreButton(
                  label: 'Edit fixture',
                  kind: ScoreButtonKind.ghost,
                  icon: Icons.edit_outlined,
                  onPressed: () => _editFixture(m),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ScoreButton(
                  label: 'Cancel fixture',
                  kind: ScoreButtonKind.danger,
                  icon: Icons.cancel_outlined,
                  onPressed: () => _cancelFixture(m),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ScoreButton(
            label: 'Delete fixture',
            kind: ScoreButtonKind.ghost,
            icon: Icons.delete_outline,
            onPressed: () => _deleteFixture(m),
          ),
        ];
      case 'cancelled':
        return [
          const EmptyState(
            icon: Icons.cancel_outlined,
            title: 'Fixture cancelled',
            subtitle: 'This fixture counts as finalized for the points table.',
          ),
          const SizedBox(height: 10),
          ScoreButton(
            label: 'Reopen as upcoming',
            kind: ScoreButtonKind.gold,
            icon: Icons.restore,
            onPressed: () => _reopenFixture(m),
          ),
          const SizedBox(height: 10),
          ScoreButton(
            label: 'Delete fixture',
            kind: ScoreButtonKind.ghost,
            icon: Icons.delete_outline,
            onPressed: () => _deleteFixture(m),
          ),
        ];
      default:
        // noResult lands here. Live and completed matches have
        // their own screens (and completed has its own delete
        // actions there) — they are never offered a delete here,
        // so scoring data can never be removed from this screen.
        return [
          ScoreButton(
            label: 'Share Poster',
            kind: ScoreButtonKind.ghost,
            icon: Icons.share_outlined,
            onPressed: () => shareFixturePoster(context, store, m),
          ),
          if (m.status == 'noResult') ...[
            const SizedBox(height: 10),
            ScoreButton(
              label: 'Delete fixture',
              kind: ScoreButtonKind.ghost,
              icon: Icons.delete_outline,
              onPressed: () => _deleteFixture(m),
            ),
          ],
        ];
    }
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

}
