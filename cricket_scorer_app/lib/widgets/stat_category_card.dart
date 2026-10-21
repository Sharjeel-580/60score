// Compact top-performer category card (redesign, v1.3.1 batch #2).
// Replaces the old big plain boxes (label + "No data yet" floating in
// empty space) on the Statistics grids: a small icon chip + label up
// top, then the leader's photo, name and a prominent value side by
// side; when the category is empty, one small muted line instead.
// Used by the owner's TournamentStatsTab and the read-only published
// preview, so both grids look identical. Presentation only.
import 'package:flutter/material.dart';

import '../theme.dart';
import 'player_avatar.dart';

class StatCategoryCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;

  /// True when this category has a leader to show.
  final bool hasData;

  /// Headline figure, e.g. "245" / "5/18" / "24 balls".
  final String value;

  /// Leader's name ('' for pair records — [detail] then carries the
  /// names and is shown in the name slot instead).
  final String playerName;
  final String teamName;
  final String detail;

  /// Leader's photo (base64), '' when none.
  final String photoBase64;
  final String role;
  final VoidCallback? onTap;

  const StatCategoryCard({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.hasData,
    this.value = '',
    this.playerName = '',
    this.teamName = '',
    this.detail = '',
    this.photoBase64 = '',
    this.role = 'Batter',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nameLine = playerName.isNotEmpty ? playerName : detail;
    final subLine = playerName.isNotEmpty
        ? (teamName.isNotEmpty ? teamName : detail)
        : teamName;
    return Container(
      decoration: BoxDecoration(
        gradient: kOceanCardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 16, color: accent),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    if (onTap != null && hasData)
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Colors.white38,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (!hasData)
                  const Row(
                    children: [
                      Icon(Icons.hourglass_empty,
                          size: 14, color: Colors.white38),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'No data yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      if (playerName.isNotEmpty)
                        PlayerAvatar(
                          photoBase64:
                              photoBase64.isEmpty ? null : photoBase64,
                          role: role,
                          name: playerName,
                          radius: 17,
                        ),
                      if (playerName.isNotEmpty) const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nameLine,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: kWhite,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (subLine.isNotEmpty)
                              Text(
                                subLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            value,
                            maxLines: 1,
                            style: TextStyle(
                              color: accent,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
