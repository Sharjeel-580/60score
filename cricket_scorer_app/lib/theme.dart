// 60Score design system.
// Approved branding: deep navy / near-black backgrounds, teal-cyan primary
// accents, amber-gold secondary accents, silver + white text, restrained
// cricket-red indicators. Metallic silver "60", red ball, golden stumps.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'player_io.dart';

// ---------- Color tokens ----------
// Ocean theme (approved Oct 2026): kCyan/kTeal now resolve to the Ocean
// palette — sunset orange primary accent, ocean steel borders. Names kept
// for compatibility across 20+ screens; values migrated to Ocean.
const kNavyDeep = Color(0xFF00002A); // app background (ocean black)
const kNavy = Color(0xFF1A3F75); // deep ocean surface
const kPanel = Color(0xFF1A3F75); // card background (ocean deep)
const kPanel2 = Color(0xFF262262); // raised card / dialog (sunset navy)
const kCyan = Color(0xFFF16623); // sunset orange — primary accent
const kTeal = Color(0xFF4E6A9C); // ocean steel — secondary accent / borders
const kTealDark = Color(0xFF2A4A73);
const kGold = Color(0xFFF2B33D); // amber-gold — tertiary accent (badges)
const kAmber = Color(0xFFE09A1F);
const kSilver = Color(0xFFE6EEF7); // mist text
const kWhite = Colors.white;
const kRed = Color(0xFFE5484D); // restrained cricket-red (indicators only)
const kGreen = Color(0xFF3ECF6F);

// ---------- Dual-palette professional system (user reference, Oct 2026) ----------
// Palette A — "Sunset": vivid orange on deep navy-purple.
const kSunsetOrange = Color(0xFFF16623);
const kSunsetOrangeDeep = Color(0xFFD14E0F);
const kSunsetOrangeSoft = Color(0xFFFF9A5C);
const kSunsetNavy = Color(0xFF262262);
const kSunsetNavyDeep = Color(0xFF1A1848);
// Palette B — "Ocean": monochrome blue scale.
const kOceanBlack = Color(0xFF00002A);
const kOceanDeep = Color(0xFF1A3F75);
const kOceanSteel = Color(0xFF4E6A9C);
const kOceanMist = Color(0xFFE6EEF7);
const kOceanFaint = Color(0xFF9DB4D0);

// Signature gradients.
const kSunsetGradient = LinearGradient(
  colors: [kSunsetOrangeSoft, kSunsetOrange, kSunsetOrangeDeep],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const kOceanCardGradient = LinearGradient(
  colors: [kOceanDeep, kSunsetNavy],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const kHeroGlowGradient = RadialGradient(
  center: Alignment.topCenter,
  radius: 1.2,
  colors: [Color(0x33F16623), Color(0x00000000)],
);

// Legacy aliases (kept so older screens keep compiling during migration).
const kBg = kNavyDeep;
const kCopper = Color(0xFFF8AE6D);
const kOrangeRed = Color(0xFFE4572E);

// ---------- Professional shade scales (A1 color system) ----------
// Navy depth scale — use for layered surfaces (deepest -> lightest).
const kNavy950 = Color(0xFF05090F);
const kNavy900 = Color(0xFF070D18); // == kNavyDeep
const kNavy800 = Color(0xFF0C1526);
const kNavy700 = Color(0xFF101A30); // == kNavy
const kNavy600 = Color(0xFF16233D); // == kPanel
const kNavy500 = Color(0xFF1C2C4B); // == kPanel2
const kNavy400 = Color(0xFF263B5E);
const kNavy300 = Color(0xFF3A5178);

// Cyan accent scale.
const kCyan700 = Color(0xFF0E9DB8); // == kTeal
const kCyan500 = Color(0xFF19D7F2); // == kCyan
const kCyan300 = Color(0xFF6FE9FF);
const kCyan100 = Color(0xFFC8F6FF);

// Gold accent scale.
const kGold700 = Color(0xFFB97A12);
const kGold500 = Color(0xFFF2B33D); // == kGold
const kGold300 = Color(0xFFFFD47E);
const kGold100 = Color(0xFFFFEDC2);

// Text hierarchy.
const kTextPrimary = Color(0xFFFFFFFF);
const kTextSecondary = Color(0xFFC9D4E3); // == kSilver
const kTextMuted = Color(0xFF8A97AD);
const kTextFaint = Color(0xFF5C6B84);

// Premium gradients.
const kCyanGradient = LinearGradient(
  colors: [kCyan300, kCyan500, kCyan700],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const kCardSheen = LinearGradient(
  colors: [Color(0x14FFFFFF), Color(0x00000000)],
  begin: Alignment.topCenter,
  end: Alignment.center,
);

ThemeData buildScore60Theme() {
  // Ocean-led professional theme (approved Oct 2026):
  // deep blue surfaces (#00002A / #1A3F75), sunset orange (#F16623) primary
  // accent, mist-white text.
  final scheme = ColorScheme.dark(
    primary: kSunsetOrange,
    onPrimary: kWhite,
    secondary: kOceanSteel,
    onSecondary: kWhite,
    tertiary: kSunsetOrangeSoft,
    surface: kOceanDeep,
    onSurface: kWhite,
    surfaceContainerHighest: kSunsetNavy,
    error: kRed,
    onError: kWhite,
  );
  final textTheme = Typography.whiteMountainView.apply(
    bodyColor: kOceanMist,
    displayColor: kWhite,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: kOceanBlack,
    appBarTheme: const AppBarTheme(
      backgroundColor: kOceanBlack,
      foregroundColor: kWhite,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: kOceanDeep,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: kOceanSteel.withValues(alpha: 0.45)),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: kSunsetNavy),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kOceanBlack,
      selectedItemColor: kSunsetOrange,
      unselectedItemColor: kOceanFaint,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kOceanBlack,
      indicatorColor: kSunsetOrange.withValues(alpha: 0.18),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: kOceanBlack),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kOceanDeep,
      hintStyle: const TextStyle(color: kOceanFaint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kOceanSteel.withValues(alpha: 0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kOceanSteel.withValues(alpha: 0.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kSunsetOrange, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kSunsetNavy,
      side: BorderSide(color: kOceanSteel.withValues(alpha: 0.5)),
      labelStyle: const TextStyle(color: kOceanMist),
    ),
    dividerColor: kOceanSteel.withValues(alpha: 0.4),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kSunsetNavy,
      contentTextStyle: TextStyle(color: kWhite),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kSunsetOrange,
      foregroundColor: kWhite,
    ),
  );
}

// ---------- Reusable components ----------

/// Standard branded card used across every screen.
class ScoreCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool highlight;
  const ScoreCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight
              ? kGold.withValues(alpha: 0.55)
              : kCyan.withValues(alpha: 0.16),
          width: highlight ? 1.5 : 1,
        ),
        gradient: highlight
            ? LinearGradient(
                colors: [
                  kGold.withValues(alpha: 0.12),
                  kPanel,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [kNavy500, kNavy600],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: (highlight ? kGold : kCyan).withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: card,
    );
  }
}

/// Premium screen background: deep navy with a soft cyan radial glow at the
/// top — gives every screen a professional, lit-from-above feel.
class PremiumBackground extends StatelessWidget {
  final Widget child;
  const PremiumBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [kNavy800, kNavyDeep],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: 0,
            right: 0,
            height: 320,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 1.0,
                    colors: [
                      kCyan.withValues(alpha: 0.10),
                      kCyan.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Big dramatic score display — for hero cards and live matches.
/// Huge heavy numerals with a soft cyan glow.
class HeroScore extends StatelessWidget {
  final String score;
  final String? label;
  const HeroScore({super.key, required this.score, this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          score,
          style: TextStyle(
            color: kWhite,
            fontSize: 44,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
            shadows: [
              Shadow(
                color: kCyan.withValues(alpha: 0.45),
                blurRadius: 18,
              ),
            ],
          ),
        ),
        if (label != null)
          Text(
            label!,
            style: const TextStyle(
              color: kTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
      ],
    );
  }
}

/// Section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeader(this.title, {super.key, this.action});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: kCyan,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: kWhite,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // ignore: use_null_aware_elements
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// Gold "Q" qualification badge for the points table.
class QBadge extends StatelessWidget {
  final bool provisional;
  const QBadge({super.key, this.provisional = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: provisional
            ? kGold.withValues(alpha: 0.18)
            : kGold.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kGold),
      ),
      child: Text(
        provisional ? 'Q*' : 'Q',
        style: TextStyle(
          color: provisional ? kGold : const Color(0xFF2B1C05),
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Small status pill (LIVE / UPCOMING / COMPLETED / CANCELLED).
class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    late Color fg;
    late Color bg;
    late String label;
    switch (status) {
      case 'live':
        fg = kRed;
        bg = kRed.withValues(alpha: 0.14);
        label = 'LIVE';
        break;
      case 'upcoming':
      case 'scheduled':
        fg = kCyan;
        bg = kCyan.withValues(alpha: 0.14);
        label = 'UPCOMING';
        break;
      case 'completed':
        fg = kGreen;
        bg = kGreen.withValues(alpha: 0.14);
        label = 'COMPLETED';
        break;
      case 'cancelled':
        fg = Colors.white54;
        bg = Colors.white10;
        label = 'CANCELLED';
        break;
      default:
        fg = kGold;
        bg = kGold.withValues(alpha: 0.14);
        label = status.toUpperCase();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

enum ScoreButtonKind { primary, gold, ghost, danger }

/// Standard branded button.
class ScoreButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ScoreButtonKind kind;
  final IconData? icon;
  const ScoreButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ScoreButtonKind.primary,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    switch (kind) {
      case ScoreButtonKind.primary:
        bg = kCyan;
        fg = const Color(0xFF062A33);
        break;
      case ScoreButtonKind.gold:
        bg = kGold;
        fg = const Color(0xFF2B1C05);
        break;
      case ScoreButtonKind.ghost:
        bg = Colors.transparent;
        fg = kCyan;
        break;
      case ScoreButtonKind.danger:
        bg = kRed;
        fg = kWhite;
        break;
    }
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
        ],
        Text(
          label,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ],
    );
    if (kind == ScoreButtonKind.ghost) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: const BorderSide(color: kCyan),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: child,
      );
    }
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
      child: child,
    );
  }
}

/// Circular team avatar with initials.
class TeamAvatar extends StatelessWidget {
  final String name;
  final double radius;
  const TeamAvatar(this.name, {super.key, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: kPanel2,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              kCyan.withValues(alpha: 0.35),
              kTealDark.withValues(alpha: 0.6),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: kCyan.withValues(alpha: 0.4)),
        ),
        child: Center(
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: TextStyle(
              color: kWhite,
              fontWeight: FontWeight.w800,
              fontSize: radius * 0.7,
            ),
          ),
        ),
      ),
    );
  }
}

/// Friendly empty-state placeholder.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 48, color: kTeal),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: kWhite,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Small labeled statistic chip.
class StatChip extends StatelessWidget {
  final String label;
  final String value;
  const StatChip(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: kPanel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kTeal.withValues(alpha: 0.35)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: kWhite,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ---------- v1.1.2 redesign: shared components ----------

/// Gold gradient used for primary action buttons and highlights.
const kGoldGradient = LinearGradient(
  colors: [Color(0xFFF6C453), kGold, kAmber],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Branded screen header: hamburger (left), centered 60Score logo +
/// tagline, settings (right). Used on Home / Matches / Statistics.
class BrandedHeader extends StatelessWidget {
  final VoidCallback onMenu;
  final VoidCallback? onSettings;
  const BrandedHeader({
    super.key,
    required this.onMenu,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu, color: kWhite, size: 28),
            onPressed: onMenu,
          ),
          const Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '60Score',
                  style: TextStyle(
                    color: kWhite,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  'Cricket Scoring, Simplified.',
                  style: TextStyle(color: kSilver, fontSize: 11),
                ),
              ],
            ),
          ),
          if (onSettings != null)
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined, color: kSilver),
              onPressed: onSettings,
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// Gradient action card (Home 5-card row, Quick Actions).
class ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;
  final double iconSize;
  const ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
    this.iconSize = 30,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: gradient.last.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: kWhite, size: iconSize),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: kWhite,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: kWhite.withValues(alpha: 0.85),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gold gradient primary button (Create Match, Save Settings, ...).
class GoldButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: kGoldGradient,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: kGold.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: const Color(0xFF2B1C05), size: 22),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF2B1C05),
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Section title row: icon + UPPERCASE title + optional trailing action.
class SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  const SectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Icon(icon, color: kGold, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: kWhite,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
          ),
          if (trailing != null) ...[trailing!],
        ],
      ),
    );
  }
}

/// Cyan "View All >" trailing link.
class ViewAllLink extends StatelessWidget {
  final VoidCallback onTap;
  const ViewAllLink({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'View All',
            style: TextStyle(
              color: kCyan,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          Icon(Icons.chevron_right, color: kCyan, size: 18),
        ],
      ),
    );
  }
}

/// Numbered settings section card (New Match screen sections).
class NumberedSection extends StatelessWidget {
  final int number;
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? headerAction;
  const NumberedSection({
    super.key,
    required this.number,
    required this.title,
    this.subtitle,
    required this.child,
    this.headerAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kCyan.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: kCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kCyan.withValues(alpha: 0.4)),
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: kCyan,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
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
                        color: kWhite,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (headerAction != null) ...[headerAction!],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Selectable option chip card (format cards, toss options, tabs).
class OptionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  const OptionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            gradient: selected ? kGoldGradient : null,
            color: selected ? null : kPanel2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? kGold
                  : kCyan.withValues(alpha: 0.25),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: kGold.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  color: selected
                      ? const Color(0xFF2B1C05)
                      : kSilver,
                  size: 20,
                ),
                const SizedBox(height: 4),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFF2B1C05)
                      : kWhite,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF2B1C05).withValues(alpha: 0.8)
                        : Colors.white54,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- File helpers (kept from previous version) ----------

/// Write [bytes] to a temp file and open the system share sheet.
Future<void> shareBytes(
  String filename,
  List<int> bytes, {
  String? text,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], text: text),
  );
}

Future<void> shareCsvFile(String filename, String csv) =>
    shareBytes(filename, utf8.encode(csv), text: '60Score player list');

Future<void> shareXlsxFile(String filename, List<PlayerRow> rows) =>
    shareBytes(filename, rowsToXlsxBytes(rows), text: '60Score player list');

Future<void> copyToClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

class PickedPlayers {
  final List<PlayerRow> rows;
  final List<String> errors;
  final String sourceName;
  PickedPlayers(this.rows, this.errors, this.sourceName);
}

/// Let the user pick a .csv or .xlsx player list and parse it.
Future<PickedPlayers?> pickPlayerListFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv', 'xlsx'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final f = result.files.first;
  final bytes = f.bytes;
  if (bytes == null) {
    return PickedPlayers([], ['Could not read the selected file'], f.name);
  }
  final isXlsx =
      (f.extension ?? '').toLowerCase() == 'xlsx' ||
      f.name.toLowerCase().endsWith('.xlsx');
  final parsed = isXlsx
      ? parsePlayersXlsx(bytes)
      : parsePlayersCsv(String.fromCharCodes(bytes));
  return PickedPlayers(parsed.rows, parsed.errors, f.name);
}

/// Import / Export popup used on every player-list screen.
class PlayerListIoButtons extends StatelessWidget {
  final List<PlayerRow> Function() exportRows;
  final Future<void> Function(List<PlayerRow> rows) onImport;
  final String exportName;
  const PlayerListIoButtons({
    super.key,
    required this.exportRows,
    required this.onImport,
    required this.exportName,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.import_export),
      tooltip: 'Import / Export',
      onSelected: (v) async {
        if (v == 'import') {
          final picked = await pickPlayerListFile();
          if (picked == null) return;
          if (!context.mounted) return;
          if (picked.rows.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  picked.errors.isEmpty
                      ? 'No players found in that file'
                      : picked.errors.join('; '),
                ),
              ),
            );
            return;
          }
          await onImport(picked.rows);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Imported ${picked.rows.length} players from ${picked.sourceName}',
                ),
              ),
            );
          }
        } else if (v == 'export_csv') {
          await shareCsvFile('$exportName.csv', rowsToCsv(exportRows()));
        } else if (v == 'export_xlsx') {
          await shareXlsxFile('$exportName.xlsx', exportRows());
        } else if (v == 'copy_csv') {
          await copyToClipboard(rowsToCsv(exportRows()));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('CSV copied to clipboard')),
            );
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'import', child: Text('Import from Excel / CSV')),
        PopupMenuItem(
          value: 'export_xlsx',
          child: Text('Export to Excel (.xlsx)'),
        ),
        PopupMenuItem(value: 'export_csv', child: Text('Export to CSV')),
        PopupMenuItem(value: 'copy_csv', child: Text('Copy CSV to clipboard')),
      ],
    );
  }
}
