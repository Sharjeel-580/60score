// Shareable Top-5 statistics images.
//
// Renders branded stat cards off-screen, captures them as PNG and opens the
// system share sheet. Uses computeCareerStats + real completed-match data —
// never fabricated values. Detailed Stats UI itself stays untouched.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'scoring.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/player_avatar.dart';

/// One ranked player row inside a stat category.
class StatEntry {
  final String playerId;
  final String value;
  final String sub;
  StatEntry(this.playerId, this.value, this.sub);
}

/// One Top-5 category (label + ranked entries).
class StatCategory {
  final String label;
  final IconData icon;
  final List<StatEntry> entries;
  StatCategory(this.label, this.icon, this.entries);
}

String _teamOf(Store store, String playerId) {
  for (final t in store.teams) {
    if (t.players.any((p) => p.id == playerId)) return t.name;
  }
  return '';
}

/// Build the 12 supported Top-5 categories from real career stats.
/// Categories with no eligible players are skipped (no fake rows).
/// Public for unit testing.
List<StatCategory> buildStatCategories(Store store, String? tournamentId) {
  final career = computeCareerStats(store.matches, tournamentId: tournamentId);
  final list = career.values.toList();

  List<StatEntry> top5(
    List<CareerStats> sorted,
    bool Function(CareerStats) include,
    String Function(CareerStats) value,
    String Function(CareerStats) sub,
  ) =>
      sorted
          .where(include)
          .take(5)
          .map((c) => StatEntry(c.playerId, value(c), sub(c)))
          .toList();

  final byRuns = [...list]..sort((a, b) => b.runs.compareTo(a.runs));
  final byHS = [...list]..sort((a, b) => b.highScore.compareTo(a.highScore));
  final byAvg = [...list]
    ..sort((a, b) => b.battingAverage.compareTo(a.battingAverage));
  final bySR = [...list]..sort((a, b) => b.battingSR.compareTo(a.battingSR));
  final bySixes = [...list]..sort((a, b) => b.sixes.compareTo(a.sixes));
  final byFours = [...list]..sort((a, b) => b.fours.compareTo(a.fours));
  final byWkts = [...list]..sort((a, b) => b.wickets.compareTo(a.wickets));
  final byBowlFig = [...list]
    ..sort((a, b) {
      if (b.bestWickets != a.bestWickets) {
        return b.bestWickets.compareTo(a.bestWickets);
      }
      return a.bestRuns.compareTo(b.bestRuns);
    });
  final byEcon = [...list]..sort((a, b) => a.economy.compareTo(b.economy));
  final byBowlAvg = [...list]
    ..sort((a, b) => a.bowlingAverage.compareTo(b.bowlingAverage));
  final byCatches = [...list]..sort((a, b) => b.catches.compareTo(a.catches));
  final byStump = [...list]..sort((a, b) => b.stumpings.compareTo(a.stumpings));

  final cats = <StatCategory>[
    StatCategory(
      'Top Run Scorers',
      Icons.sports_cricket,
      top5(byRuns, (c) => c.runs > 0, (c) => '${c.runs}',
          (c) => 'Avg ${c.battingAverage.toStringAsFixed(1)}'),
    ),
    StatCategory(
      'Highest Individual Scores',
      Icons.star_outline,
      top5(byHS, (c) => c.highScore > 0, (c) => '${c.highScore}',
          (c) => '${c.runs} runs'),
    ),
    StatCategory(
      'Best Batting Averages',
      Icons.trending_up,
      top5(
          byAvg,
          (c) => c.inningsBatted >= 2 && c.dismissals > 0,
          (c) => c.battingAverage.toStringAsFixed(1),
          (c) => '${c.runs} runs'),
    ),
    StatCategory(
      'Best Strike Rates',
      Icons.bolt_outlined,
      top5(
          bySR,
          (c) => c.ballsFaced >= 30,
          (c) => c.battingSR.toStringAsFixed(1),
          (c) => '${c.runs} runs'),
    ),
    StatCategory(
      'Most Sixes',
      Icons.rocket_launch_outlined,
      top5(bySixes, (c) => c.sixes > 0, (c) => '${c.sixes}',
          (c) => '${c.runs} runs'),
    ),
    StatCategory(
      'Most Fours',
      Icons.grid_4x4_outlined,
      top5(byFours, (c) => c.fours > 0, (c) => '${c.fours}',
          (c) => '${c.runs} runs'),
    ),
    StatCategory(
      'Top Wicket Takers',
      Icons.sports_baseball,
      top5(byWkts, (c) => c.wickets > 0, (c) => '${c.wickets}',
          (c) => 'Econ ${c.economy.toStringAsFixed(2)}'),
    ),
    StatCategory(
      'Best Bowling Figures',
      Icons.emoji_events_outlined,
      top5(byBowlFig, (c) => c.bestWickets > 0, (c) => c.bestFigures,
          (c) => '${c.wickets} wkts'),
    ),
    StatCategory(
      'Best Bowling Economy',
      Icons.speed_outlined,
      top5(
          byEcon,
          (c) => c.ballsBowled >= 24,
          (c) => c.economy.toStringAsFixed(2),
          (c) => '${c.wickets} wkts'),
    ),
    StatCategory(
      'Best Bowling Averages',
      Icons.show_chart,
      top5(
          byBowlAvg,
          (c) => c.wickets >= 3,
          (c) => c.bowlingAverage.toStringAsFixed(1),
          (c) => '${c.wickets} wkts'),
    ),
    StatCategory(
      'Most Catches',
      Icons.front_hand_outlined,
      top5(byCatches, (c) => c.catches > 0, (c) => '${c.catches}', (_) => ''),
    ),
    StatCategory(
      'Most Stumpings',
      Icons.waving_hand_outlined,
      top5(byStump, (c) => c.stumpings > 0, (c) => '${c.stumpings}',
          (_) => ''),
    ),
  ];
  return cats.where((c) => c.entries.isNotEmpty).toList();
}

/// Capture one off-screen card as PNG bytes.
Future<Uint8List?> _captureCard(OverlayState overlay, Widget card) async {
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
            child: card,
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  await Future.delayed(const Duration(milliseconds: 400));
  try {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 2.5);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  } finally {
    entry.remove();
  }
}

/// Share the Top-5 statistics as one or two branded images.
///
/// Batting categories go on the first image, bowling + fielding on the
/// second, so text stays readable. Uses real completed-match data only.
Future<void> shareStatsImage(
  BuildContext context,
  Store store, {
  String? tournamentId,
}) async {
  final cats = buildStatCategories(store, tournamentId);
  if (cats.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No statistics to share yet.')),
    );
    return;
  }
  final scope = tournamentId == null
      ? 'All Matches'
      : (store.tournamentById(tournamentId)?.name ?? 'Tournament');
  // Split for readability: batting first, bowling + fielding second.
  final batting = cats.sublist(0, cats.length > 6 ? 6 : cats.length);
  final bowling =
      cats.length > 6 ? cats.sublist(6) : const <StatCategory>[];
  final groups = <List<StatCategory>>[batting];
  if (bowling.isNotEmpty) groups.add(bowling);

  // Grab the overlay before any async gap (lint: use_build_context_synchronously).
  final overlay = Overlay.of(context);
  final dir = await getTemporaryDirectory();
  final files = <XFile>[];
  for (var i = 0; i < groups.length; i++) {
    final bytes = await _captureCard(
      overlay,
      _StatsCard(
        store: store,
        scope: scope,
        title: groups.length == 1
            ? 'Top 5 Statistics'
            : (i == 0 ? 'Top 5 Batting' : 'Top 5 Bowling & Fielding'),
        categories: groups[i],
      ),
    );
    if (bytes == null) continue;
    final file = File(
        '${dir.path}/stats_${tournamentId ?? 'all'}_${DateTime.now().millisecondsSinceEpoch}_$i.png');
    await file.writeAsBytes(bytes, flush: true);
    files.add(XFile(file.path));
  }
  if (files.isEmpty) return;
  await SharePlus.instance.share(
    ShareParams(files: files, text: '60Score statistics — $scope'),
  );
}

class _StatsCard extends StatelessWidget {
  final Store store;
  final String scope;
  final String title;
  final List<StatCategory> categories;
  const _StatsCard({
    required this.store,
    required this.scope,
    required this.title,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 460,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1B2E), Color(0xFF060D18)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Branding header.
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: kCyan,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '60SCORE',
                  style: TextStyle(
                    color: Color(0xFF060D18),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      scope,
                      style: const TextStyle(
                        color: kGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final cat in categories) ...[
            _categorySection(cat),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _categorySection(StatCategory cat) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF10222F),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kCyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(cat.icon, color: kGold, size: 16),
              const SizedBox(width: 6),
              Text(
                cat.label,
                style: const TextStyle(
                  color: kGold,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < cat.entries.length; i++)
            _playerRow(i + 1, cat.entries[i]),
        ],
      ),
    );
  }

  Widget _playerRow(int rank, StatEntry e) {
    final photo = store.photoForPlayer(e.playerId);
    final name = store.playerName(e.playerId);
    final team = _teamOf(store, e.playerId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.white54,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          PlayerAvatar(
            photoBase64: photo.isEmpty ? null : photo,
            radius: 15,
            fallbackIcon: Icons.person,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (team.isNotEmpty)
                  Text(
                    team,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          if (e.sub.isNotEmpty)
            Text(
              e.sub,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
            ),
          const SizedBox(width: 8),
          Text(
            e.value,
            style: const TextStyle(
              color: kCyan,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
