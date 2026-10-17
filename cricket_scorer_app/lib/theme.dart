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
const kNavyDeep = Color(0xFF070D18); // app background (near-black navy)
const kNavy = Color(0xFF101A30); // deep navy surface
const kPanel = Color(0xFF16233D); // card background
const kPanel2 = Color(0xFF1C2C4B); // raised card / dialog
const kCyan = Color(0xFF19D7F2); // electric cyan — primary accent
const kTeal = Color(0xFF0E9DB8); // teal — secondary accent / borders
const kTealDark = Color(0xFF0B6E84);
const kGold = Color(0xFFF2B33D); // amber-gold — secondary accent
const kAmber = Color(0xFFE09A1F);
const kSilver = Color(0xFFC9D4E3); // silver text
const kWhite = Colors.white;
const kRed = Color(0xFFE5484D); // restrained cricket-red (indicators only)
const kGreen = Color(0xFF3ECF6F);

// Legacy aliases (kept so older screens keep compiling during migration).
const kBg = kNavyDeep;
const kCopper = Color(0xFFF8AE6D);
const kOrangeRed = Color(0xFFE4572E);

ThemeData buildScore60Theme() {
  final scheme = ColorScheme.dark(
    primary: kCyan,
    onPrimary: const Color(0xFF062A33),
    secondary: kGold,
    onSecondary: const Color(0xFF2B1C05),
    tertiary: kTeal,
    surface: kPanel,
    onSurface: kWhite,
    surfaceContainerHighest: kPanel2,
    error: kRed,
    onError: kWhite,
  );
  final textTheme = Typography.whiteMountainView.apply(
    bodyColor: kSilver,
    displayColor: kWhite,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: kNavyDeep,
    appBarTheme: const AppBarTheme(
      backgroundColor: kNavy,
      foregroundColor: kWhite,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: kPanel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: kCyan.withValues(alpha: 0.14)),
      ),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: kPanel2),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: kNavy,
      selectedItemColor: kCyan,
      unselectedItemColor: Colors.white54,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kNavy,
      indicatorColor: kCyan.withValues(alpha: 0.18),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: kNavy),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kPanel,
      hintStyle: const TextStyle(color: Colors.white38),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kTeal.withValues(alpha: 0.4)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: kTeal.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kCyan, width: 1.5),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kPanel2,
      side: BorderSide(color: kTeal.withValues(alpha: 0.5)),
      labelStyle: const TextStyle(color: kSilver),
    ),
    dividerColor: kTealDark.withValues(alpha: 0.5),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kPanel2,
      contentTextStyle: TextStyle(color: kWhite),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kCyan,
      foregroundColor: Color(0xFF062A33),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? kGold.withValues(alpha: 0.55)
              : kCyan.withValues(alpha: 0.14),
          width: highlight ? 1.5 : 1,
        ),
        gradient: highlight
            ? LinearGradient(
                colors: [
                  kGold.withValues(alpha: 0.10),
                  kPanel,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: card,
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
