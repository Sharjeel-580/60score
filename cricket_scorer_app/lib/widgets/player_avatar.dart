// Player avatar widget: shows player photo if available, otherwise a
// role-specific icon (Batter / Bowler / All-Rounder / Wicket-Keeper).
// Used everywhere a player appears: lists, teams, posters, player-of-match.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../store.dart';
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

/// Circular player avatar: photo (base64) when available, otherwise a
/// fallback icon. By default the icon is role-specific; pass [fallbackIcon]
/// (e.g. Icons.person) to force a plain icon instead.
class PlayerAvatar extends StatelessWidget {
  final String? photoBase64;
  final String role;
  final String name;
  final double radius;
  final IconData? fallbackIcon;

  const PlayerAvatar({
    super.key,
    this.photoBase64,
    this.role = 'Batter',
    this.name = '',
    this.radius = 20,
    this.fallbackIcon,
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
        fallbackIcon ?? roleIcon(role),
        color: roleColor(role),
        size: radius * 1.1,
      ),
    );
  }
}

/// v1.1.7: Team avatar replaced by the assigned captain's actual photo.
///
/// Resolves the team's captain (player with isCaptain) and shows their photo
/// via the shared player record ([Store.photoForPlayer]). Falls back to a
/// plain person icon when no captain is assigned or no photo exists — never
/// team initials, never a role icon, never another player's photo.
class CaptainAvatar extends StatelessWidget {
  final Store store;
  final String teamId;
  final double radius;

  const CaptainAvatar({
    super.key,
    required this.store,
    required this.teamId,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    String? photo;
    final t = store.teamById(teamId);
    if (t != null) {
      for (final p in t.players) {
        if (p.isCaptain) {
          final ph = store.photoForPlayer(p.id);
          if (ph.isNotEmpty) photo = ph;
          break;
        }
      }
    }
    return PlayerAvatar(
      photoBase64: photo,
      radius: radius,
      fallbackIcon: Icons.person,
    );
  }
}
