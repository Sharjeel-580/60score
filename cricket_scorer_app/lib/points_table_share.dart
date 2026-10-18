// Shareable tournament points-table image.
//
// Renders the real standings off-screen, captures as PNG and opens the
// system share sheet. Uses leaguePointsTable — never fabricated values.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'models.dart';
import 'scoring.dart';
import 'store.dart';
import 'theme.dart';
import 'tournament_engine.dart';
import 'widgets/player_avatar.dart';

/// Share the selected tournament's real points table as a branded image.
Future<void> sharePointsTableImage(
  BuildContext context,
  Store store,
  Tournament tournament,
) async {
  final rows = leaguePointsTable(tournament, store.matches);
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
            child: _PointsTableCard(
              store: store,
              tournament: tournament,
              rows: rows,
            ),
          ),
        ),
      ),
    ),
  );
  Overlay.of(context).insert(entry);
  await Future.delayed(const Duration(milliseconds: 400));
  try {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await boundary.toImage(pixelRatio: 2.5);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/pointstable_${tournament.id}_${DateTime.now().millisecondsSinceEpoch}.png');
    final data = bytes.buffer.asUint8List();
    await file.writeAsBytes(data, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: '60Score points table — ${tournament.name}',
      ),
    );
  } finally {
    entry.remove();
  }
}

class _PointsTableCard extends StatelessWidget {
  final Store store;
  final Tournament tournament;
  final List<PointsRow> rows;
  const _PointsTableCard({
    required this.store,
    required this.tournament,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final qualified = tournament.qualificationFinalized
        ? tournament.qualifiedTeamIds.toSet()
        : <String>{};
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
          // Branding + tournament header.
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
                      tournament.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const Text(
                      'Points Table',
                      style: TextStyle(
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
          if (rows.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: const Color(0xFF10222F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kCyan.withValues(alpha: 0.35)),
              ),
              child: const Text(
                'No completed matches yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF10222F),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: kCyan.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  _headerRow(),
                  const Divider(height: 1, color: Colors.white12),
                  for (var i = 0; i < rows.length; i++) ...[
                    _dataRow(i + 1, rows[i],
                        qualified.contains(rows[i].teamId)),
                    if (i < rows.length - 1)
                      const Divider(height: 1, color: Colors.white12),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _headerRow() {
    const hs = TextStyle(
      color: kGold,
      fontWeight: FontWeight.w800,
      fontSize: 11,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          const SizedBox(
              width: 26,
              child: Text('#', style: hs, textAlign: TextAlign.center)),
          const SizedBox(width: 6),
          const SizedBox(width: 28),
          const SizedBox(width: 8),
          const Expanded(child: Text('Team', style: hs)),
          ...['P', 'W', 'L', 'T', 'NR', 'Pts']
              .map((h) => SizedBox(
                  width: 30,
                  child: Text(h, style: hs, textAlign: TextAlign.center))),
          const SizedBox(
              width: 52, child: Text('NRR', style: hs, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _dataRow(int pos, PointsRow r, bool isQ) {
    final name = store.teamName(r.teamId);
    const cs = TextStyle(color: Colors.white, fontSize: 12);
    return Container(
      color: isQ ? kGold.withValues(alpha: 0.10) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$pos',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // v1.1.7: team identity = assigned captain's photo.
          CaptainAvatar(store: store, teamId: r.teamId, radius: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (isQ) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: kGold,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Q',
                      style: TextStyle(
                        color: Color(0xFF060D18),
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final v in [
            '${r.played}',
            '${r.won}',
            '${r.lost}',
            '${r.tied}',
            '${r.noResult}',
            '${r.points}'
          ])
            SizedBox(
                width: 30,
                child: Text(v, style: cs, textAlign: TextAlign.center)),
          SizedBox(
            width: 52,
            child: Text(
              r.nrr.toStringAsFixed(3),
              style: cs,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
