// Shareable match summary image — poster-style rebuild (v1.4.5).
//
// Matches the Super Sixty League 2026 Match Summary poster template
// (reference: user files 411179_3_xu1v.png) as closely as Flutter
// widgets allow, driven by the REAL match being shared — teams,
// scores, overs, figures, POTM, result, date, venue, tournament.
// Nothing is invented: fewer table rows when the match has fewer
// performers, no padded fake rows.
//
// Layout (top to bottom, same as the poster):
//   1. top band: left league-count badge, centre 60-mark + league
//      name, right slogan badge, venue chip
//   2. MATCH SUMMARY title + date banner
//   3. score row: team card + VS + team card
//   4. body: LEFT (wider) team batting/bowling tables stacked,
//      RIGHT (narrower) Player of the Match panel
//   5. result banner
//   6. footer: date | venue | league name
//
// Widget approximations (noted, not hidden): the night-stadium photo,
// floodlights, batsman silhouette and lion artwork cannot be drawn
// with widgets — the look is approximated with dark gradients plus
// blue/red/gold glows. Metallic title text is flat silver/gold.
// Team shield logos come from the bundled assets (same map as the
// poster summary); any other team gets a gold-ring monogram badge.
//
// Renders off-screen, captures as PNG and opens the system share
// sheet. Fully offline, no extra packages.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'models.dart';
import 'poster_summary.dart';
import 'scoring.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/player_avatar.dart';
import 'widgets/share_preview.dart';

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
      final png = bytes.buffer.asUint8List();
      // v1.2.2: fit-to-screen preview inside the SafeArea before
      // sharing, so the tall card can be checked whole (its top no
      // longer runs under the camera/notch). The captured image
      // itself is unchanged.
      if (!context.mounted) return;
      final ok = await showSharePreview(
        context,
        title: 'Match Summary',
        images: [png],
      );
      if (ok) {
        await shareBytes(
          'summary_${match.id}.png',
          png,
          text: '60Score match summary',
        );
      }
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

  /// Aggregate batting figures for the POTM across all innings.
  Map<String, int> _potmStats(String pid) {
    var runs = 0, balls = 0, fours = 0, sixes = 0;
    for (final inn in match.innings) {
      final bf = inn.batting[pid];
      if (bf != null && bf.batted) {
        runs += bf.runs;
        balls += bf.balls;
        fours += bf.fours;
        sixes += bf.sixes;
      }
    }
    return {
      'runs': runs,
      'balls': balls,
      'fours': fours,
      'sixes': sixes,
    };
  }

  DateTime? _matchDate() {
    if (match.dateIso.isEmpty) return null;
    return DateTime.tryParse(match.dateIso.split('T').first);
  }

  static const _longMonths = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];
  static const _shortMonths = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  /// '24 OCTOBER 2026' for the date banner, or '' when undated.
  String _longDate() {
    final d = _matchDate();
    if (d == null) return '';
    return '${d.day} ${_longMonths[d.month - 1]} ${d.year}';
  }

  /// '24 OCT 2026' for the footer, or '' when undated.
  String _shortDate() {
    final d = _matchDate();
    if (d == null) return '';
    return '${d.day} ${_shortMonths[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final tournament = match.tournamentId == null
        ? null
        : store.tournamentById(match.tournamentId!);
    final result = match.resultText.isNotEmpty
        ? match.resultText
        : computeResult(match, store.teamName);
    final longDate = _longDate();

    return Container(
      width: 680,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1B33), Color(0xFF05080F)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: kGold.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            // Night-stadium glow approximation: blue floodlight wash
            // top-left, red/gold wash top-right (no photo available).
            Positioned(
              top: -90,
              left: -90,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF0284C7).withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -90,
              right: -90,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      kRed.withValues(alpha: 0.28),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ---- 1. Top band ----
                  _topBand(tournament),
                  if (match.venue.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [_venueChip(match.venue)],
                    ),
                  ],
                  const SizedBox(height: 10),
                  // ---- 2. Title + date banner ----
                  RichText(
                    textAlign: TextAlign.center,
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 46,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
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
                  if (longDate.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Transform.rotate(
                      angle: -0.008,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          longDate,
                          style: const TextStyle(
                            color: Colors.black,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // ---- 3. Score row ----
                  Row(
                    children: [
                      Expanded(
                        child: _scoreCard(match.teamAId, kCyan),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                            ),
                            children: [
                              TextSpan(
                                text: 'V',
                                style: TextStyle(color: Colors.white),
                              ),
                              TextSpan(
                                text: 'S',
                                style: TextStyle(color: kGold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: _scoreCard(match.teamBId, kGold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ---- 4. Body: tables (left) + POTM (right) ----
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            for (final inn in match.innings)
                              _teamTableCard(inn),
                          ],
                        ),
                      ),
                      if (match.manOfMatchId.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: _potmPanel(),
                        ),
                      ],
                    ],
                  ),
                  // ---- 5. Result banner ----
                  if (result.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0B0B),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kGold, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: kGold.withValues(alpha: 0.20),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.emoji_events,
                            color: kGold,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                result.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: kGold,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // ---- 6. Footer ----
                  _footer(tournament),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Top band: league-count badge (left), 60-mark + league name
  /// (centre), slogan badge (right). Counts are real: tournament
  /// teams and tournament fixtures. Without a tournament there is no
  /// league to count — the left badge is omitted, not invented.
  Widget _topBand(Tournament? tournament) {
    Widget badge(List<String> lines, bool alignRight) {
      return Column(
        crossAxisAlignment:
            alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(
              line,
              style: const TextStyle(
                color: Colors.white,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                height: 1.3,
              ),
            ),
          const SizedBox(height: 4),
          Container(
            width: 64,
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: alignRight
                    ? [
                        kRed.withValues(alpha: 0.2),
                        kRed,
                      ]
                    : [
                        kRed,
                        kRed.withValues(alpha: 0.2),
                      ],
              ),
            ),
          ),
        ],
      );
    }

    final leagueFixtures = tournament == null
        ? 0
        : store.matches.where((m) => m.tournamentId == tournament.id).length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (tournament != null)
          badge(
            [
              '${tournament.teamIds.length} TEAMS',
              '$leagueFixtures MATCHES',
              'ONE CHAMPION',
            ],
            false,
          ),
        Expanded(
          child: Column(
            children: [
              // 60-mark approximation: cyan 6 + tennis-ball 0 + gold II
              // (the poster's batsman silhouette is not reproducible
              // with widgets and is omitted, not faked).
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    '6',
                    style: TextStyle(
                      color: kCyan,
                      fontStyle: FontStyle.italic,
                      fontWeight: FontWeight.w900,
                      fontSize: 54,
                      height: 1,
                    ),
                  ),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        center: Alignment(-0.3, -0.3),
                        colors: [
                          Colors.white,
                          Color(0xFF7DD3FC),
                          Color(0xFF0284C7),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const Text(
                    'II',
                    style: TextStyle(
                      color: kGold,
                      fontWeight: FontWeight.w900,
                      fontSize: 54,
                      height: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                (tournament?.name ?? '60SCORE').toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kCyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        badge(
          const ['CRICKET', 'PASSION', 'FRIENDSHIP', 'GLORY'],
          true,
        ),
      ],
    );
  }

  Widget _venueChip(String venue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGold.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, color: kGold, size: 14),
          const SizedBox(width: 4),
          Text(
            venue.toUpperCase(),
            style: const TextStyle(
              color: kGold,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Team shield logo from the bundled assets, or a gold-ring
  /// monogram badge for teams without bundled artwork.
  Widget _teamLogo(String teamName) {
    final asset = teamLogoAssetFor(teamName);
    if (asset != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.asset(
          asset,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _monogramBadge(teamName),
        ),
      );
    }
    return _monogramBadge(teamName);
  }

  Widget _monogramBadge(String teamName) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: kGold.withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        teamMonogram(teamName),
        style: const TextStyle(
          color: kGold,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
    );
  }

  /// Score card: logo + name + big score + overs, accent-glow border.
  Widget _scoreCard(String teamId, Color accent) {
    final inn = match.innings.cast<InningsState?>().firstWhere(
          (i) => i!.battingTeamId == teamId,
          orElse: () => null,
        );
    final score =
        inn == null ? '-' : '${inn.totalRuns}-${inn.wickets}';
    final overs = inn == null
        ? ''
        : 'OVERS ${oversText(inn.legalBalls, inn.ballsPerOver)}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF10222F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: 0.55),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.22),
            blurRadius: 18,
          ),
        ],
      ),
      child: Row(
        children: [
          _teamLogo(store.teamName(teamId)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  store.teamName(teamId).toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    score,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w900,
                      fontSize: 30,
                    ),
                  ),
                ),
                if (overs.isNotEmpty)
                  Text(
                    overs,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Batting + bowling mini-tables for one innings, poster shape:
  /// top 4 batters by runs, top 3 bowlers by wickets desc then runs
  /// asc. Fewer rows when the match has fewer performers — never
  /// padded.
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
    final accent = inn.battingTeamId == match.teamAId ? kCyan : kGold;

    Widget tableHead(List<String> cols) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: Text(
                  cols[0],
                  style: const TextStyle(
                    color: Colors.white60,
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
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        );

    Widget batRow(String pid, BatFig f) {
      final sr =
          f.balls == 0 ? '-' : (f.runs * 100 / f.balls).toStringAsFixed(1);
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
                  fontSize: 12,
                ),
              ),
            ),
            for (final v in [
              '${f.runs}',
              '${f.balls}',
              '${f.fours}',
              '${f.sixes}',
              sr,
            ])
              Expanded(
                child: Text(
                  v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
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
                  fontSize: 12,
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
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF10222F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.12),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            store.teamName(inn.battingTeamId).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'BATTING',
            style: TextStyle(
              color: kGold,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1,
            ),
          ),
          tableHead(const ['BATSMAN', 'R', 'B', '4s', '6s', 'SR']),
          for (final e in batters.take(4)) batRow(e.key, e.value),
          const Divider(height: 12, color: Colors.white10),
          const Text(
            'BOWLING',
            style: TextStyle(
              color: kGold,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 1,
            ),
          ),
          tableHead(const ['BOWLER', 'O', 'R', 'W', 'ECON']),
          for (final e in bowlers.take(3)) bowlRow(e.key, e.value),
        ],
      ),
    );
  }

  /// Player of the Match panel (RIGHT column): header, photo, name
  /// banner, stat rows. Photo from the player's app record; role-icon
  /// fallback when no photo exists (never another player's photo).
  Widget _potmPanel() {
    final pid = match.manOfMatchId;
    final pl = _playerOf(pid);
    final name = store.playerName(pid);
    final potmPhoto = store.photoForPlayer(pid);
    final s = _potmStats(pid);
    final sr = s['balls']! == 0
        ? '-'
        : (s['runs']! * 100 / s['balls']!).toStringAsFixed(1);

    final statRows = <List<String>>[
      ['${s['runs']}', 'RUNS'],
      ['${s['balls']}', 'BALLS'],
      ['${s['fours']}', 'FOURS'],
      ['${s['sixes']}', 'SIXES'],
      [sr, 'STRIKE RATE'],
    ];

    return Container(
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
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: 0.15),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.emoji_events, color: kGold, size: 24),
              SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PLAYER',
                    style: TextStyle(
                      color: kGold,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  Text(
                    'OF THE MATCH',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          PlayerAvatar(
            photoBase64: potmPhoto.isEmpty ? null : potmPhoto,
            role: pl?.role ?? 'Batter',
            name: name,
            radius: 78,
            fallbackIcon: Icons.person,
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: kGold.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kGold,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final row in statRows)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(
                vertical: 9,
                horizontal: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: kGold.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    row[0],
                    style: const TextStyle(
                      color: kGold,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    row[1],
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _footer(Tournament? tournament) {
    final segments = <Widget>[];
    Widget segment(IconData icon, String text) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kGold, size: 14),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    final shortDate = _shortDate();
    if (shortDate.isNotEmpty) {
      segments.add(segment(Icons.calendar_month, shortDate));
    }
    if (match.venue.isNotEmpty) {
      segments.add(segment(Icons.location_on, match.venue.toUpperCase()));
    }
    if (tournament != null) {
      segments.add(
        segment(Icons.emoji_events, tournament.name.toUpperCase()),
      );
    }
    if (segments.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (var i = 0; i < segments.length; i++) {
      if (i > 0) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('|', style: TextStyle(color: Colors.white38)),
          ),
        );
      }
      children.add(segments[i]);
    }
    return Container(
      padding: const EdgeInsets.only(top: 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 0,
        runSpacing: 6,
        children: children,
      ),
    );
  }
}
