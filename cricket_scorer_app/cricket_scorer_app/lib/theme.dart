// 60Score theme — colours taken strictly from the Super Sixty League
// logo: bluish/cyan family on the left, red/copper-orange on the right,
// on a dark smoky near-black navy background. Shades are used as-is.
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'player_io.dart';

const kBg = Color(0xFF030A10);
const kPanel = Color(0xFF0A1F2C);
const kPanel2 = Color(0xFF0D2838);
const kCyan = Color(0xFF0CE8F8);
const kTeal = Color(0xFF057490);
const kTealDark = Color(0xFF016682);
const kCopper = Color(0xFFF8AE6D);
const kOrangeRed = Color(0xFFE4572E);

ThemeData buildScore60Theme() {
  final scheme = ColorScheme.dark(
    primary: kCyan,
    onPrimary: const Color(0xFF03222B),
    secondary: kOrangeRed,
    onSecondary: Colors.white,
    surface: kPanel,
    onSurface: Colors.white,
    error: const Color(0xFFFF6B5E),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: kBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF06141D),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(color: kPanel),
    dialogTheme: const DialogThemeData(backgroundColor: kPanel),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF06141D),
      selectedItemColor: kCyan,
      unselectedItemColor: Colors.white54,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF0A1B26),
      border: OutlineInputBorder(),
    ),
    chipTheme: const ChipThemeData(side: BorderSide(color: kTeal)),
    dividerColor: kTealDark,
  );
}

/// Write [bytes] to a temp file and open the system share sheet.
Future<void> shareBytes(String filename, List<int> bytes,
    {String? text}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path)],
    text: text,
  ));
}

Future<void> shareCsvFile(String filename, String csv) =>
    shareBytes(filename, utf8.encode(csv), text: '60Score player list');

Future<void> shareXlsxFile(String filename, List<PlayerRow> rows) =>
    shareBytes(filename, rowsToXlsxBytes(rows),
        text: '60Score player list');

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
  final isXlsx = (f.extension ?? '').toLowerCase() == 'xlsx' ||
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
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(picked.errors.isEmpty
                    ? 'No players found in that file'
                    : picked.errors.join('; '))));
            return;
          }
          await onImport(picked.rows);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text('Imported ${picked.rows.length} players from ${picked.sourceName}')));
          }
        } else if (v == 'export_csv') {
          await shareCsvFile('$exportName.csv', rowsToCsv(exportRows()));
        } else if (v == 'export_xlsx') {
          await shareXlsxFile('$exportName.xlsx', exportRows());
        } else if (v == 'copy_csv') {
          await copyToClipboard(rowsToCsv(exportRows()));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CSV copied to clipboard')));
          }
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'import', child: Text('Import from Excel / CSV')),
        PopupMenuItem(value: 'export_xlsx', child: Text('Export to Excel (.xlsx)')),
        PopupMenuItem(value: 'export_csv', child: Text('Export to CSV')),
        PopupMenuItem(value: 'copy_csv', child: Text('Copy CSV to clipboard')),
      ],
    );
  }
}
