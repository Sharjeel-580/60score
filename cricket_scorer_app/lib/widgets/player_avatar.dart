// Player avatar widget: shows player photo if available, otherwise a
// role-specific icon (Batter / Bowler / All-Rounder / Wicket-Keeper).
// Used everywhere a player appears: lists, teams, posters, player-of-match.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme.dart';

/// Returns the Material icon best representing a player role.
IconData roleIcon(String role) {
  final r = role.toLowerCase();
  if (r.contains('bowl') && r.contains('bat') ||
      r.contains('all-rounder') ||
      r.contains('allrounder')) {
    return Icons.sports_cricket; // all-rounder: bat + ball
  }
  if (r.contains('bowl')) {
    return Icons.sports_baseball; // bowler: ball
  }
  if (r.contains('keeper') || r.contains('wicket')) {
    return Icons.front_hand; // wicket-keeper: glove/hand
  }
  return Icons.sports_cricket; // batter: bat (default)
}

/// Background tint per role for the fallback icon circle.
Color roleColor(String role) {
  final r = role.toLowerCase();
  if (r.contains('bowl') && !r.contains('bat') && !r.contains('all')) {
    return const Color(0xFF7C4DFF); // purple for bowlers
  }
  if (r.contains('all-rounder') || r.contains('allrounder')) {
    return const Color(0xFFFF9800); // orange for all-rounders
  }
  if (r.contains('keeper') || r.contains('wicket')) {
    return const Color(0xFF00BCD4); // cyan for keepers
  }
  return const Color(0xFF29B6F6); // blue for batters
}

/// Circular player avatar: photo (base64) when available, role icon otherwise.
class PlayerAvatar extends StatelessWidget {
  final String? photoBase64;
  final String role;
  final String name;
  final double radius;

  const PlayerAvatar({
    super.key,
    this.photoBase64,
    this.role = 'Batter',
    this.name = '',
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (photoBase64 != null && photoBase64!.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(photoBase64!);
        return CircleAvatar(
          radius: radius,
          backgroundColor: kPanel2,
          backgroundImage: MemoryImage(bytes),
          onBackgroundImageError: (_, _) {},
        );
      } catch (_) {
        // Fall through to icon on bad data.
      }
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: roleColor(role).withValues(alpha: 0.25),
      child: Icon(
        roleIcon(role),
        color: roleColor(role),
        size: radius * 1.1,
      ),
    );
  }
}
