// Shareable match summary image (Stumps SUMMARY-card style).
//
// Renders a branded card off-screen, captures it as PNG and opens the
// system share sheet. ASCII-safe, offline, no extra packages needed.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'models.dart';
import 'scoring.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/player_avatar.dart';

Future<void> shareMatchSummaryImage(
  BuildContext context,
  Store store,
  Match match,
) async {
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -6000,
      top: 0,
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: RepaintBoundary(
            key: key,
            child: _SummaryCard(store: store, match: match),
          ),
        ),
      ),
    ),
  );
  Overlay.of(context).insert(entry);
  // Let the card lay out and paint before capturing.
  await Future.delayed(const Duration(milliseconds: 400));
  try {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 2.5);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null) {
      await shareBytes(
        'summary_${match.id}.png',
        bytes.buffer.asUint8List(),
        text: '60Score match summary',
      );
    }
  } finally {
    entry.remove();
  }
}

class _SummaryCard extends StatelessWidget {
  final Store store;
  final Match match;
  const _SummaryCard({required this.store, required this.match});

  Player? _playerOf(String pid) => store.findPlayer(pid);

  /// Aggregate batting + bowling figures for the POTM across all innings.
  Map<String, int> _potmStats(String pid) {
    var runs = 0, balls = 0, fours = 0, sixes = 0, wkts = 0, bowlRuns = 0;
    for (final inn in match.innings) {
      final bf = inn.batting[pid];
      if (bf != null && bf.batted) {
        runs += bf.runs;
        balls += bf.balls;
        fours += bf.fours;
        sixes += bf.sixes;
      }
      final wf = inn.bowling[pid];
      if (wf != null && wf.legalBalls > 0) {
        wkts += wf.wickets;
        bowlRuns += wf.runs;
      }
    }
    return {
      'runs': runs,
      'balls': balls,
      'fours': fours,
      'sixes': sixes,
      'wkts': wkts,
      'bowlRuns': bowlRuns,
    };
  }

  String _potmQuote(Map<String, int> s) {
    if (s['runs']! >= 50) return 'A magnificent knock — pure class!';
    if (s['runs']! >= 30) return 'Brilliant knock and led his team to victory!';
    if (s['wkts']! >= 3) return 'Unplayable spell — tore through the lineup!';
    if (s['runs']! > 0) return 'A fine all-round contribution!';
    return 'Star performer of the match!';
  }

  @override
  Widget build(BuildContext context) {
    final tournament = match.tournamentId == null
        ? null
        : store.tournamentById(match.tournamentId!);
    final result = match.resultText.isNotEmpty
        ? match.resultText
        : computeResult(match, store.teamName);
    final dateLine = [
      if (match.dateIso.isNotEmpty) match.dateIso,
      if (match.venue.isNotEmpty) match.venue,
    ].join('  |  ');

    return Container(
      width: 460,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1B2E), Color(0xFF060D18)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: kGold.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- Header ----
          const Text(
            '60SCORE',
            style: TextStyle(
              color: kCyan,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 2),
          RichText(
            textAlign: TextAlign.center,
            text: const TextSpan(
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
              children: [
                TextSpan(
                  text: 'MATCH ',
                  style: TextStyle(color: Colors.white),
                ),
                TextSpan(
                  text: 'SUMMARY',
                  style: TextStyle(color: kGold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (dateLine.isNotEmpty)
            Text(
              dateLine,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
          if (tournament != null) ...[
            const SizedBox(height: 6),
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
              child: Text(
                tournament.name,
                style: const TextStyle(
                  color: kGold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          // ---- Team VS cards ----
          _vsCards(),
          const SizedBox(height: 12),
          // ---- Per-team batting/bowling tables ----
          for (final inn in match.innings) _teamTableCard(inn),
          // ---- Player of the Match ----
          if (match.manOfMatchId.isNotEmpty) ...[
            const SizedBox(height: 4),
            _potmCard(),
          ],
          // ---- Result banner ----
          if (result.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    kGold.withValues(alpha: 0.35),
                    kGold.withValues(alpha: 0.12),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kGold),
              ),
              child: Text(
                result.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: kGold,
                  fontWeight: FontWeight.w900,
                  fontSize: 19,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text(
            'Made by Sharjeel',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '60Score${tournament != null ? ' • ${tournament.name}' : ''}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  /// Two team cards with a VS in the middle.
  Widget _vsCards() {
    Widget teamCard(String teamId, Color accent) {
      final inn = match.innings.cast<InningsState?>().firstWhere(
            (i) => i!.battingTeamId == teamId,
            orElse: () => null,
          );
      final score = inn == null
          ? '-'
          : '${inn.totalRuns}-${inn.wickets}';
      final overs = inn == null
          ? ''
          : 'Overs ${oversText(inn.legalBalls, inn.ballsPerOver)}';
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF10222F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: accent.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              CaptainAvatar(store: store, teamId: teamId),
              const SizedBox(height: 6),
              Text(
                store.teamName(teamId).toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              if (overs.isNotEmpty)
                Text(
                  overs,
                  style: const TextStyle(
                    color: kCyan,
                    fontSize: 11,
                  ),
                ),
              Text(
                score,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 28,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        teamCard(match.teamAId, kCyan),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'VS',
            style: TextStyle(
              color: kGold,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        teamCard(match.teamBId, kGold),
      ],
    );
  }

  /// Batting + bowling mini-table for one innings.
  Widget _teamTableCard(InningsState inn) {
    final batters = inn.batting.entries.where((e) => e.value.batted).toList()
      ..sort((a, b) => b.value.runs.compareTo(a.value.runs));
    final bowlers =
        inn.bowling.entries.where((e) => e.value.legalBalls > 0).toList()
          ..sort((a, b) {
            if (b.value.wickets != a.value.wickets) {
              return b.value.wickets.compareTo(a.value.wickets);
            }
            return a.value.runs.compareTo(b.value.runs);
          });
    final accent =
        inn.battingTeamId == match.teamAId ? kCyan : kGold;

    Widget tableHead(List<String> cols) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  cols[0],
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              for (var i = 1; i < cols.length; i++)
                Expanded(
                  child: Text(
                    cols[i],
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        );

    Widget batRow(String pid, BatFig f) {
      final sr = f.balls == 0
          ? '-'
          : (f.runs * 100 / f.balls).toStringAsFixed(1);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                '${store.playerName(pid)}${f.out ? '' : ' *'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
              ),
            ),
            for (final v in [
              '${f.runs}',
              '${f.balls}',
              '${f.fours}',
              '${f.sixes}',
              sr
            ])
              Expanded(
                child: Text(
                  v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    Widget bowlRow(String pid, BowlFig f) {
      final econ = f.legalBalls == 0
          ? '-'
          : (f.runs * inn.ballsPerOver / f.legalBalls).toStringAsFixed(1);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                store.playerName(pid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
              ),
            ),
            for (final v in [
              oversText(f.legalBalls, inn.ballsPerOver),
              '${f.runs}',
              '${f.wickets}',
              econ,
            ])
              Expanded(
                child: Text(
                  v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF10222F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.teamName(inn.battingTeamId).toUpperCase(),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          tableHead(const ['BATTING', 'R', 'B', '4s', '6s', 'SR']),
          for (final e in batters.take(4)) batRow(e.key, e.value),
          const SizedBox(height: 6),
          tableHead(const ['BOWLING', 'O', 'R', 'W', 'ECON']),
          for (final e in bowlers.take(3)) bowlRow(e.key, e.value),
        ],
      ),
    );
  }

  /// Player of the Match showcase card.
  Widget _potmCard() {
    final pid = match.manOfMatchId;
    final pl = _playerOf(pid);
    final name = store.playerName(pid);
    // v1.1.6: POTM photo via the shared player record; default person
    // icon when no photo exists (never dummy/another player's photo).
    final potmPhoto = store.photoForPlayer(pid);
    final team = pl != null ? (store.teamById(_teamOfPlayer(pid))?.name ?? '') : '';
    final s = _potmStats(pid);
    final sr = s['balls']! == 0
        ? '-'
        : (s['runs']! * 100 / s['balls']!).toStringAsFixed(1);

    final tiles = <List<String>>[
      ['${s['runs']}', 'Runs'],
      ['${s['balls']}', 'Balls'],
      ['${s['fours']}', 'Fours'],
      ['${s['sixes']}', 'Sixes'],
      [sr, 'Strike Rate'],
    ];
    if (s['wkts']! > 0) {
      tiles.insert(1, ['${s['wkts']}/${s['bowlRuns']}', 'Wickets']);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kGold.withValues(alpha: 0.25),
            kGold.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kGold, width: 1.5),
      ),
      child: Column(
        children: [
          // v1.1.7: POTM photo prominent on the LEFT (large), name/team on
          // the right — mirrors the on-screen summary layout.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PlayerAvatar(
                photoBase64: potmPhoto.isEmpty ? null : potmPhoto,
                role: pl?.role ?? 'Batter',
                name: name,
                radius: 52,
                fallbackIcon: Icons.person,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.emoji_events, color: kGold, size: 20),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'PLAYER OF THE MATCH',
                            style: TextStyle(
                              color: kGold,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                    if (team.isNotEmpty)
                      Text(
                        team,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: kGold.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          tiles[i][0],
                          style: const TextStyle(
                            color: kGold,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          tiles[i][1],
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (i < tiles.length - 1) const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '"${_potmQuote(s)}"',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _teamOfPlayer(String pid) {
    for (final t in store.teams) {
      if (t.players.any((p) => p.id == pid)) return t.id;
    }
    return '';
  }
}
