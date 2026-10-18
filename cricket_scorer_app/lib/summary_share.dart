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

  String _batLine(String pid, BatFig f) =>
      '${store.playerName(pid)}|${f.runs}${f.out ? '' : '*'} (${f.balls})';

  String _bowlLine(String pid, BowlFig f) =>
      '${store.playerName(pid)}|${f.wickets}-${f.runs}';

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0B1B26);
    const cardBg = Color(0xFF10222F);
    final tournament = match.tournamentId == null
        ? null
        : store.tournamentById(match.tournamentId!);
    final result = match.resultText.isNotEmpty
        ? match.resultText
        : computeResult(match, store.teamName);

    Widget inningsBlock(InningsState inn) {
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
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    store.teamName(inn.battingTeamId).toUpperCase(),
                    style: const TextStyle(
                      color: kCyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ),
                Text(
                  'Overs ${oversText(inn.legalBalls, inn.ballsPerOver)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                const SizedBox(width: 10),
                Text(
                  '${inn.totalRuns}-${inn.wickets}',
                  style: const TextStyle(
                    color: kCyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in batters.take(3))
                        _kvLine(_batLine(e.key, e.value)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in bowlers.take(3))
                        _kvLine(_bowlLine(e.key, e.value)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      width: 420,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'SUMMARY',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                    letterSpacing: 3,
                  ),
                ),
              ),
              Text(
                '60SCORE',
                style: TextStyle(
                  color: kCyan.withValues(alpha: 0.85),
                  fontSize: 11,
                  letterSpacing: 4,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (tournament != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tournament.name,
                style: const TextStyle(color: kCopper, fontSize: 13),
              ),
            ),
          if (match.dateIso.isNotEmpty)
            Text(
              match.dateIso,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          const SizedBox(height: 12),
          for (final inn in match.innings) inningsBlock(inn),
          if (result.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: kCopper,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                result,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF0B1B26),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          if (match.manOfMatchId.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kTealDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Builder(builder: (_) {
                    final pl = store.findPlayer(match.manOfMatchId);
                    return PlayerAvatar(
                      photoBase64: (pl?.photoBase64 ?? '').isEmpty
                          ? null
                          : pl!.photoBase64,
                      role: pl?.role ?? 'Batter',
                      name: store.playerName(match.manOfMatchId),
                      radius: 18,
                    );
                  }),
                  const SizedBox(width: 10),
                  const Text(
                    'Player of the Match',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    store.playerName(match.manOfMatchId),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Center(
            child: Column(
              children: [
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
                  '60Score • Super Sixty League',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Name|figure" split into two aligned texts.
  Widget _kvLine(String pair) {
    final idx = pair.indexOf('|');
    final name = idx < 0 ? pair : pair.substring(0, idx);
    final fig = idx < 0 ? '' : pair.substring(idx + 1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Text(
            fig,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
