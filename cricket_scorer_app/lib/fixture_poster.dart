// Shareable fixture/match poster image.
//
// Renders a branded poster off-screen (teams, VS, venue, date/time,
// tournament, captains with photos), captures it as PNG and opens the
// system share sheet. Follows the same pattern as summary_share.dart.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'models.dart';
import 'screens/fixture_detail_screen.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets/player_avatar.dart';

Future<void> shareFixturePoster(
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
            child: _FixturePosterCard(store: store, match: match),
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
        'fixture_${match.id}.png',
        bytes.buffer.asUint8List(),
        text: '60Score match poster',
      );
    }
  } finally {
    entry.remove();
  }
}

class _FixturePosterCard extends StatelessWidget {
  final Store store;
  final Match match;
  const _FixturePosterCard({required this.store, required this.match});

  String _teamName(String id) => store.teamName(id);

  Player? _captain(String teamId) {
    final t = store.teamById(teamId);
    if (t == null) return null;
    for (final p in t.players) {
      if (p.isCaptain) return p;
    }
    return null;
  }

  Widget _teamBlock(String teamId, CrossAxisAlignment align) {
    final name = _teamName(teamId);
    final cap = _captain(teamId);
    return Expanded(
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kPanel2,
              border: Border.all(color: kCyan, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              name.isEmpty
                  ? '?'
                  : name
                      .split(' ')
                      .map((w) => w.isEmpty ? '' : w[0])
                      .take(2)
                      .join()
                      .toUpperCase(),
              style: const TextStyle(
                color: kWhite,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name.isEmpty ? 'TBD' : name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (cap != null) ...[
            PlayerAvatar(
              photoBase64:
                  cap.photoBase64.isEmpty ? null : cap.photoBase64,
              role: cap.role,
              name: cap.name,
              radius: 24,
            ),
            const SizedBox(height: 4),
            Text(
              'C: ${cap.name}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kGold,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else
            const Text(
              'Captain TBD',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tournamentName = match.tournamentId == null
        ? ''
        : (store.tournamentById(match.tournamentId!)?.name ?? '');
    return Container(
      width: 480,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1B33), Color(0xFF060D18)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kGold.withOpacity(0.5), width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          const Text(
            '60SCORE',
            style: TextStyle(
              color: kGold,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          if (tournamentName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              tournamentName.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: kCyan,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: kGold.withOpacity(0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kGold.withOpacity(0.6)),
            ),
            child: Text(
              stageLabel(match.stage).toUpperCase(),
              style: const TextStyle(
                color: kGold,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Teams
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _teamBlock(match.teamAId, CrossAxisAlignment.center),
              const Padding(
                padding: EdgeInsets.only(top: 18),
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: kGold,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
              _teamBlock(match.teamBId, CrossAxisAlignment.center),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 12),
          // Date / venue / format
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_month, size: 16, color: kCyan),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  formatFixtureDate(match.dateIso),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 16, color: kCyan),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  match.venue.isNotEmpty ? match.venue : 'Venue TBD',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${match.oversLimit} overs per side',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(height: 14),
          const Text(
            'Made by Sharjeel • 60Score',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
