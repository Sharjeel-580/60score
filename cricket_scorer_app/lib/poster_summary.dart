// Poster-style Match Summary share image (v1.3.8).
//
// Renders the owner-approved poster design (sample v3, approved
// 2026-10-23) inside the app for completed matches: dark navy poster,
// team-logo badges, big score panels, per-team top batting/bowling
// tables, a Player of the Match panel and a gold result banner.
//
// The card is built off-screen at 540x675 logical px and captured at
// pixelRatio 2.0, so the shared PNG is exactly 1080x1350. This is an
// ADDITIONAL share option on the scorecard Summary tab — the existing
// Summary and Share layouts are untouched.
//
// Data comes from the match record's figures (the source of truth).
// POTM photo follows the owner's photo rule: the player's photo when
// one exists, the standard person icon otherwise.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'models.dart';
import 'scoring.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/player_avatar.dart';
import 'widgets/share_preview.dart';

// ---- Design constants (approved sample v3) ----
const _kPosterGold = Color(0xFFF5B921);
const _kPosterGoldDeep = Color(0xFFC78F0E);
const _kPosterBgTop = Color(0xFF0C1E42);
const _kPosterBgBottom = Color(0xFF050B1F);
const _kPosterPanel = Color(0xFF051632);
const _kPosterPanelDark = Color(0xFF081226);
const _kPosterChip = Color(0xFF020918);
const _kAccentA = Color(0xFFA9D2FF);
const _kAccentB = Color(0xFF8FE3F2);

// ---------------------------------------------------------------------------
// Team logos: bundled artwork for the six Super Sixty League teams,
// matched by normalized team name. Any other team gets a monogram
// badge in the same gold-ring frame (the app is generic).
// ---------------------------------------------------------------------------

String _squashTeamName(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

const _kTeamLogoAssets = <String, String>{
  'shazihawks': 'assets/team_logos/shazi-hawks.png',
  'adidolphins': 'assets/team_logos/adi-dolphins.png',
  'uslions': 'assets/team_logos/us-lions.png',
  'makings': 'assets/team_logos/ma-kings.png',
  'alipanthers': 'assets/team_logos/ali-panthers.png',
  'abknights': 'assets/team_logos/ab-knights.png',
};

/// Bundled logo asset for [teamName], or null when the team has no
/// bundled artwork (monogram fallback). Punctuation/spacing variants
/// ("M.A. Kings", "U.S. Lions") resolve to the same team.
String? teamLogoAssetFor(String teamName) =>
    _kTeamLogoAssets[_squashTeamName(teamName)];

/// Two-letter monogram for a team without bundled artwork.
String teamMonogram(String teamName) {
  final words = teamName
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  String clean(String w) => w.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  if (words.length == 1) {
    final w = clean(words.first);
    if (w.isEmpty) return '?';
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  final a = clean(words[0]);
  final b = clean(words[1]);
  final m = '${a.isEmpty ? '' : a[0]}${b.isEmpty ? '' : b[0]}';
  return m.isEmpty ? '?' : m.toUpperCase();
}

// ---------------------------------------------------------------------------
// Data shaping (pure logic over the match figures — unit-tested).
// ---------------------------------------------------------------------------

class PosterChip {
  final String value;
  final String label;
  const PosterChip(this.value, this.label);
}

class PosterBatLine {
  final String name; // includes '*' when not out
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final String strikeRateText;
  const PosterBatLine({
    required this.name,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.strikeRateText,
  });
}

class PosterBowlLine {
  final String name;
  final String oversText;
  final int runs;
  final int wickets;
  final String economyText;
  const PosterBowlLine({
    required this.name,
    required this.oversText,
    required this.runs,
    required this.wickets,
    required this.economyText,
  });
}

class PosterTeamSection {
  final String teamId;
  final String name;
  final bool hasInnings;
  final String scoreText; // e.g. '117-8'
  final String oversText; // e.g. '8.0'
  final List<PosterBatLine> batting; // top 4
  final List<PosterBowlLine> bowling; // top 3
  const PosterTeamSection({
    required this.teamId,
    required this.name,
    required this.hasInnings,
    required this.scoreText,
    required this.oversText,
    required this.batting,
    required this.bowling,
  });
}

class PosterPotm {
  final String playerId;
  final String name;
  final String role;
  final String photoBase64; // '' when the player has no photo
  final List<PosterChip> chips;
  const PosterPotm({
    required this.playerId,
    required this.name,
    required this.role,
    required this.photoBase64,
    required this.chips,
  });
}

class PosterSummaryData {
  final String tournamentName;
  final String seasonLabel; // e.g. 'SEASON 2K26', '' when unset
  final String venue;
  final String dateLabel; // e.g. '22 OCT 2026'
  final String resultText;
  final List<PosterTeamSection> teams; // display order, 2 entries
  final PosterPotm potm;
  const PosterSummaryData({
    required this.tournamentName,
    required this.seasonLabel,
    required this.venue,
    required this.dateLabel,
    required this.resultText,
    required this.teams,
    required this.potm,
  });
}

/// True when the match record carries any figure at all (someone
/// batted or bowled). The poster is only offered then.
bool matchHasPosterFigures(Match match) {
  for (final inn in match.innings) {
    for (final f in inn.batting.values) {
      if (f.batted) return true;
    }
    for (final f in inn.bowling.values) {
      if (f.legalBalls > 0) return true;
    }
  }
  return false;
}

/// '2026-10-22' -> '22 OCT 2026'. Anything unparsable is returned
/// upper-cased as stored.
String posterDateLabel(String dateIso) {
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(dateIso.trim());
  if (m == null) return dateIso.toUpperCase();
  const months = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];
  final month = int.tryParse(m.group(2)!);
  final day = int.tryParse(m.group(3)!);
  if (month == null || day == null || month < 1 || month > 12) {
    return dateIso.toUpperCase();
  }
  return '$day ${months[month - 1]} ${m.group(1)}';
}

String _strikeRateText(int runs, int balls) =>
    balls == 0 ? '0.0' : (runs * 100 / balls).toStringAsFixed(1);

String _economyText(int runs, int legalBalls, int ballsPerOver) =>
    legalBalls == 0
        ? '0.0'
        : (runs * ballsPerOver / legalBalls).toStringAsFixed(1);

PosterTeamSection _sectionFor(
  Store store,
  String teamId,
  InningsState? inn,
) {
  final name = store.teamName(teamId);
  if (inn == null) {
    return PosterTeamSection(
      teamId: teamId,
      name: name,
      hasInnings: false,
      scoreText: '-',
      oversText: '',
      batting: const [],
      bowling: const [],
    );
  }
  final batEntries = inn.batting.entries.where((e) => e.value.batted).toList()
    ..sort((a, b) {
      if (b.value.runs != a.value.runs) {
        return b.value.runs.compareTo(a.value.runs);
      }
      if (a.value.balls != b.value.balls) {
        return a.value.balls.compareTo(b.value.balls);
      }
      return store.playerName(a.key).compareTo(store.playerName(b.key));
    });
  final bowlEntries =
      inn.bowling.entries.where((e) => e.value.legalBalls > 0).toList()
        ..sort((a, b) {
          if (b.value.wickets != a.value.wickets) {
            return b.value.wickets.compareTo(a.value.wickets);
          }
          final ea = a.value.runs * inn.ballsPerOver / a.value.legalBalls;
          final eb = b.value.runs * inn.ballsPerOver / b.value.legalBalls;
          if (ea != eb) return ea.compareTo(eb);
          return store.playerName(a.key).compareTo(store.playerName(b.key));
        });
  return PosterTeamSection(
    teamId: teamId,
    name: name,
    hasInnings: true,
    scoreText: '${inn.totalRuns}-${inn.wickets}',
    oversText: oversText(inn.legalBalls, inn.ballsPerOver),
    batting: [
      for (final e in batEntries.take(4))
        PosterBatLine(
          name: '${store.playerName(e.key)}${e.value.out ? '' : ' *'}',
          runs: e.value.runs,
          balls: e.value.balls,
          fours: e.value.fours,
          sixes: e.value.sixes,
          strikeRateText: _strikeRateText(e.value.runs, e.value.balls),
        ),
    ],
    bowling: [
      for (final e in bowlEntries.take(3))
        PosterBowlLine(
          name: store.playerName(e.key),
          oversText: oversText(e.value.legalBalls, inn.ballsPerOver),
          runs: e.value.runs,
          wickets: e.value.wickets,
          economyText:
              _economyText(e.value.runs, e.value.legalBalls, inn.ballsPerOver),
        ),
    ],
  );
}

class _Agg {
  bool batted = false;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  int bowlBalls = 0;
  int bowlRuns = 0;
  int wickets = 0;
}

Map<String, _Agg> _aggregateFigures(Match match) {
  final aggs = <String, _Agg>{};
  for (final inn in match.innings) {
    inn.batting.forEach((pid, f) {
      if (!f.batted) return;
      final a = aggs.putIfAbsent(pid, _Agg.new);
      a.batted = true;
      a.runs += f.runs;
      a.balls += f.balls;
      a.fours += f.fours;
      a.sixes += f.sixes;
    });
    inn.bowling.forEach((pid, f) {
      if (f.legalBalls <= 0) return;
      final a = aggs.putIfAbsent(pid, _Agg.new);
      a.bowlBalls += f.legalBalls;
      a.bowlRuns += f.runs;
      a.wickets += f.wickets;
    });
  }
  return aggs;
}

PosterPotm _posterPotm(Store store, Match match, Map<String, _Agg> aggs) {
  String? pid;
  if (match.manOfMatchId.isNotEmpty && aggs.containsKey(match.manOfMatchId)) {
    pid = match.manOfMatchId;
  }
  if (pid == null) {
    // Fallback: the match's top run-scorer; if nobody batted, the
    // top wicket-taker.
    final batters = aggs.entries.where((e) => e.value.batted).toList()
      ..sort((a, b) {
        if (b.value.runs != a.value.runs) {
          return b.value.runs.compareTo(a.value.runs);
        }
        if (a.value.balls != b.value.balls) {
          return a.value.balls.compareTo(b.value.balls);
        }
        return store.playerName(a.key).compareTo(store.playerName(b.key));
      });
    if (batters.isNotEmpty) {
      pid = batters.first.key;
    } else {
      final bowlers = aggs.entries.where((e) => e.value.bowlBalls > 0).toList()
        ..sort((a, b) {
          if (b.value.wickets != a.value.wickets) {
            return b.value.wickets.compareTo(a.value.wickets);
          }
          if (a.value.bowlRuns != b.value.bowlRuns) {
            return a.value.bowlRuns.compareTo(b.value.bowlRuns);
          }
          return store.playerName(a.key).compareTo(store.playerName(b.key));
        });
      if (bowlers.isNotEmpty) pid = bowlers.first.key;
    }
  }
  final id = pid ?? '';
  final a = aggs[id] ?? _Agg();
  final bpo = match.ballsPerOver;
  // Bowling-led performance: he bowled and either never batted or
  // scored nothing with the bat — his chips come from the bowling
  // figures. Otherwise the batting chips of the sample.
  final bowlingLed = a.bowlBalls > 0 && (!a.batted || a.runs == 0);
  final chips = bowlingLed
      ? <PosterChip>[
          PosterChip('${a.wickets}', 'WICKETS'),
          PosterChip(oversText(a.bowlBalls, bpo), 'OVERS'),
          PosterChip('${a.bowlRuns}', 'RUNS'),
          PosterChip(_economyText(a.bowlRuns, a.bowlBalls, bpo), 'ECONOMY'),
        ]
      : <PosterChip>[
          PosterChip('${a.runs}', 'RUNS'),
          PosterChip('${a.balls}', 'BALLS'),
          PosterChip('${a.fours}', 'FOURS'),
          PosterChip('${a.sixes}', 'SIXES'),
          PosterChip(_strikeRateText(a.runs, a.balls), 'STRIKE RATE'),
        ];
  return PosterPotm(
    playerId: id,
    name: store.playerName(id),
    role: store.findPlayer(id)?.role ?? 'Batter',
    photoBase64: store.photoForPlayer(id),
    chips: chips,
  );
}

/// Builds the poster's data from the match record, or null when the
/// match has no figures at all (the poster is not offered then).
PosterSummaryData? buildPosterSummaryData(Store store, Match match) {
  if (!matchHasPosterFigures(match)) return null;
  final tournament = match.tournamentId == null
      ? null
      : store.tournamentById(match.tournamentId!);
  final venue =
      match.venue.isNotEmpty ? match.venue : (tournament?.venue ?? '');

  // Display order: first-innings team first (as in the sample), then
  // any team without an innings in A/B order.
  final order = <String>[];
  for (final inn in match.innings) {
    if (!order.contains(inn.battingTeamId)) order.add(inn.battingTeamId);
  }
  for (final id in [match.teamAId, match.teamBId]) {
    if (!order.contains(id)) order.add(id);
  }
  InningsState? inningsOf(String teamId) {
    for (final inn in match.innings) {
      if (inn.battingTeamId == teamId) return inn;
    }
    return null;
  }

  final result = match.resultText.isNotEmpty
      ? match.resultText
      : computeResult(match, store.teamName);
  return PosterSummaryData(
    tournamentName: tournament?.name ?? '',
    seasonLabel:
        match.season.isEmpty ? '' : 'SEASON ${match.season.toUpperCase()}',
    venue: venue,
    dateLabel: posterDateLabel(match.dateIso),
    resultText: result,
    teams: [
      for (final teamId in order)
        _sectionFor(store, teamId, inningsOf(teamId)),
    ],
    potm: _posterPotm(store, match, _aggregateFigures(match)),
  );
}

// ---------------------------------------------------------------------------
// Capture + share (same off-screen pattern as summary_share.dart).
// ---------------------------------------------------------------------------

Future<void> shareMatchPosterImage(
  BuildContext context,
  Store store,
  Match match,
) async {
  final data = buildPosterSummaryData(store, match);
  if (data == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Poster needs a played match with figures'),
        ),
      );
    }
    return;
  }
  // Decode the bundled team logos up front so they are painted by
  // the time the off-screen card is captured.
  for (final t in data.teams) {
    final asset = teamLogoAssetFor(t.name);
    if (asset != null) {
      try {
        await precacheImage(AssetImage(asset), context);
      } catch (_) {
        // Missing/broken artwork falls back to the monogram badge.
      }
    }
  }
  if (!context.mounted) return;
  final key = GlobalKey();
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -6000,
      top: 0,
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          // The poster is a fixed 540x675 design: pin the text scale
          // so the user's system font-size setting cannot distort it.
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.noScaling),
            child: RepaintBoundary(
              key: key,
              child: MatchPosterCard(data: data),
            ),
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
    // 540x675 logical at pixelRatio 2.0 -> exactly 1080x1350.
    final img = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes != null) {
      final png = bytes.buffer.asUint8List();
      if (!context.mounted) return;
      final ok = await showSharePreview(
        context,
        title: 'Match Summary Poster',
        images: [png],
      );
      if (ok) {
        await shareBytes(
          'summary_poster_${match.id}.png',
          png,
          text: '60Score match summary poster',
        );
      }
    }
  } finally {
    entry.remove();
  }
}

// ---------------------------------------------------------------------------
// The poster card (540x675 logical). Public so widget tests can pump
// it directly.
// ---------------------------------------------------------------------------

class MatchPosterCard extends StatelessWidget {
  final PosterSummaryData data;
  const MatchPosterCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 540,
      height: 675,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_kPosterBgTop, _kPosterBgBottom],
        ),
      ),
      child: Column(
        children: [
          _header(),
          const SizedBox(height: 6),
          _title(),
          const SizedBox(height: 2),
          _vsRow(),
          const SizedBox(height: 8),
          _scorePanels(),
          const SizedBox(height: 7),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _tablesColumn()),
                const SizedBox(width: 10),
                SizedBox(width: 188, child: _potmPanel()),
              ],
            ),
          ),
          const SizedBox(height: 7),
          _resultBanner(),
          const SizedBox(height: 6),
          _footer(),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // '60 SCORE' mark.
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '60',
              style: TextStyle(
                color: _kPosterGold,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                height: 1.0,
              ),
            ),
            Text(
              'SCORE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
        // Tournament name + season.
        Expanded(
          child: Column(
            children: [
              if (data.tournamentName.isNotEmpty)
                Text(
                  data.tournamentName.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              if (data.seasonLabel.isNotEmpty)
                Text(
                  data.seasonLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _kPosterGold,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
            ],
          ),
        ),
        // Venue.
        if (data.venue.isNotEmpty)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, color: _kPosterGold, size: 13),
              const SizedBox(width: 3),
              Text(
                data.venue.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          )
        else
          const SizedBox(width: 60),
      ],
    );
  }

  Widget _title() {
    return RichText(
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: const TextSpan(
        style: TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
        children: [
          TextSpan(text: 'MATCH ', style: TextStyle(color: Colors.white)),
          TextSpan(text: 'SUMMARY', style: TextStyle(color: _kPosterGold)),
        ],
      ),
    );
  }

  Widget _teamBadge(PosterTeamSection t, double size) {
    final asset = teamLogoAssetFor(t.name);
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: _kPosterGold,
      ),
      padding: const EdgeInsets.all(2.5),
      child: ClipOval(
        child: asset != null
            ? Image.asset(
                asset,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _monogramBadge(t.name, size),
              )
            : _monogramBadge(t.name, size),
      ),
    );
  }

  Widget _monogramBadge(String teamName, double size) {
    return Container(
      color: const Color(0xFF12275A),
      alignment: Alignment.center,
      child: Text(
        teamMonogram(teamName),
        style: TextStyle(
          color: _kPosterGold,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _vsSide(PosterTeamSection t) {
    return Expanded(
      child: Column(
        children: [
          _teamBadge(t, 60),
          const SizedBox(height: 5),
          Text(
            t.name.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            width: 56,
            height: 2.5,
            decoration: BoxDecoration(
              color: _kPosterGold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vsRow() {
    if (data.teams.length < 2) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _vsSide(data.teams[0]),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'VS',
            style: TextStyle(
              color: _kPosterGold,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
        _vsSide(data.teams[1]),
      ],
    );
  }

  Widget _scorePanel(PosterTeamSection t, List<Color> gradient) {
    return Expanded(
      child: Container(
        height: 77,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              t.name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            Text(
              t.scoreText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 39,
                fontWeight: FontWeight.w900,
                height: 1.05,
              ),
            ),
            Text(
              t.hasInnings ? 'OVERS ${t.oversText}' : '',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _scorePanels() {
    if (data.teams.length < 2) return const SizedBox.shrink();
    return Row(
      children: [
        _scorePanel(
          data.teams[0],
          const [Color(0xFF0D47A1), Color(0xFF062659)],
        ),
        const SizedBox(width: 10),
        _scorePanel(
          data.teams[1],
          const [Color(0xFF0B6D8C), Color(0xFF04384F)],
        ),
      ],
    );
  }

  Widget _tablesColumn() {
    final cards = <Widget>[];
    for (var i = 0; i < data.teams.length; i++) {
      final t = data.teams[i];
      if (!t.hasInnings) continue;
      if (cards.isNotEmpty) cards.add(const SizedBox(height: 8));
      cards.add(
        Expanded(child: _teamTableCard(t, i == 0 ? _kAccentA : _kAccentB)),
      );
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(children: cards);
  }

  Widget _tableHeader(List<String> labels, List<int> flexes) {
    // Sample rhythm: the header texts sit in a 10px band under the
    // section label, with a hairline under them.
    return Container(
      height: 11,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              flex: flexes[i],
              child: Text(
                labels[i],
                textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                style: const TextStyle(color: Colors.white38, fontSize: 8),
              ),
            ),
        ],
      ),
    );
  }

  // Data rows flex inside their section (see _teamTableCard), so a
  // row is a plain centered Row; the section gives it its height.
  Widget _batRow(PosterBatLine l) {
    const flexes = [44, 10, 10, 9, 9, 14];
    final values = [
      l.name,
      '${l.runs}',
      '${l.balls}',
      '${l.fours}',
      '${l.sixes}',
      l.strikeRateText,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            flex: flexes[i],
            child: Text(
              values[i],
              textAlign: i == 0 ? TextAlign.left : TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: i == 0 ? Colors.white : Colors.white70,
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }

  Widget _bowlRow(PosterBowlLine l) {
    const flexes = [44, 12, 10, 10, 14];
    final values = [
      l.name,
      l.oversText,
      '${l.runs}',
      '${l.wickets}',
      l.economyText,
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            flex: flexes[i],
            child: Text(
              values[i],
              textAlign: i == 0 ? TextAlign.left : TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: i == 0 ? Colors.white : Colors.white70,
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }

  Widget _teamTableCard(PosterTeamSection t, Color accent) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      decoration: BoxDecoration(
        color: _kPosterPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
            ),
          ),
          const Text(
            'BATTING',
            style: TextStyle(
              color: _kPosterGold,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          _tableHeader(
            const ['BATSMAN', 'R', 'B', '4s', '6s', 'SR'],
            const [44, 10, 10, 9, 9, 14],
          ),
          // Rows flex to the card's height (4 batting / 3 bowling
          // shares), so the card can never overflow vertically.
          Expanded(
            flex: 4,
            child: Column(
              children: [
                for (final l in t.batting) Expanded(child: _batRow(l)),
              ],
            ),
          ),
          const SizedBox(height: 1),
          const Text(
            'BOWLING',
            style: TextStyle(
              color: _kPosterGold,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          _tableHeader(
            const ['BOWLER', 'O', 'R', 'W', 'ECON'],
            const [44, 12, 10, 10, 14],
          ),
          Expanded(
            flex: 3,
            child: Column(
              children: [
                for (final l in t.bowling) Expanded(child: _bowlRow(l)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _potmPanel() {
    final p = data.potm;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1B38), _kPosterPanelDark],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kPosterGold, width: 1.5),
      ),
      child: Column(
        children: [
          const Icon(Icons.emoji_events, color: _kPosterGold, size: 16),
          const SizedBox(height: 3),
          const Text(
            'PLAYER',
            style: TextStyle(
              color: _kPosterGold,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              height: 1.0,
            ),
          ),
          const Text(
            'OF THE MATCH',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _kPosterGold,
            ),
            padding: const EdgeInsets.all(2.5),
            child: PlayerAvatar(
              photoBase64: p.photoBase64.isEmpty ? null : p.photoBase64,
              role: p.role,
              name: p.name,
              radius: 41,
              fallbackIcon: Icons.person,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            p.name,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _kPosterGold,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < p.chips.length; i++)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(top: i == 0 ? 0 : 5),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _kPosterChip,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: _kPosterGold.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            p.chips[i].value,
                            style: const TextStyle(
                              color: _kPosterGold,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              p.chips[i].label,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultBanner() {
    if (data.resultText.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF07162E),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _kPosterGold, width: 1.5),
      ),
      child: Text(
        data.resultText.toUpperCase(),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: _kPosterGold,
          fontSize: 16.5,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _footer() {
    final parts = <Widget>[];
    void add(IconData icon, String text) {
      if (text.isEmpty) return;
      if (parts.isNotEmpty) {
        parts.add(
          const Text(
            '  ·  ',
            style: TextStyle(color: Colors.white38, fontSize: 9.5),
          ),
        );
      }
      parts.add(Icon(icon, color: _kPosterGoldDeep, size: 12));
      parts.add(const SizedBox(width: 4));
      parts.add(
        Flexible(
          child: Text(
            text.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    add(Icons.calendar_month, data.dateLabel);
    add(Icons.location_on, data.venue);
    add(
      Icons.emoji_events,
      [data.tournamentName, data.seasonLabel].where((s) => s.isNotEmpty).join(' '),
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: parts,
    );
  }
}
