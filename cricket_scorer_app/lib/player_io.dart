// Player list import/export for 60Score: CSV (pure Dart) and Excel .xlsx
// (via the `excel` package, also pure Dart — no Flutter imports here so
// everything is unit-testable).
//
// Canonical columns:
// Team Name | Player Name | Jersey No | Role | Batting Style |
// Bowling Style | Captain | Wicket-Keeper | Area | Phone Number |
// Availability | Remarks
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'models.dart';

const List<String> kPlayerColumns = [
  'Team Name',
  'Player Name',
  'Jersey No',
  'Role',
  'Batting Style',
  'Bowling Style',
  'Captain',
  'Wicket-Keeper',
  'Area',
  'Phone Number',
  'Availability',
  'Remarks',
];

class PlayerRow {
  String teamName;
  String playerName;
  int jerseyNo;
  String role;
  String battingStyle;
  String bowlingStyle;
  bool captain;
  bool wicketKeeper;
  String area;
  String phone;
  String availability;
  String remarks;

  PlayerRow({
    this.teamName = '',
    required this.playerName,
    this.jerseyNo = 0,
    this.role = 'Batter',
    this.battingStyle = 'Right-hand',
    this.bowlingStyle = 'None',
    this.captain = false,
    this.wicketKeeper = false,
    this.area = '',
    this.phone = '',
    this.availability = 'Available',
    this.remarks = '',
  });

  List<String> toCells() => [
    teamName,
    playerName,
    jerseyNo > 0 ? '$jerseyNo' : '',
    role,
    battingStyle,
    bowlingStyle,
    captain ? 'Y' : 'N',
    wicketKeeper ? 'Y' : 'N',
    area,
    phone,
    availability,
    remarks,
  ];

  RegPlayer toRegPlayer(String id) => RegPlayer(
    id: id,
    name: playerName,
    role: role,
    availability: availability,
    area: area,
    phone: phone,
    remarks: remarks,
    battingStyle: battingStyle,
    bowlingStyle: bowlingStyle,
    teamName: teamName,
    jerseyNo: jerseyNo,
    isCaptain: captain,
    isKeeper: wicketKeeper,
  );

  Player toTeamPlayer(String id) => Player(
    id: id,
    name: playerName,
    jerseyNo: jerseyNo,
    role: role,
    battingStyle: battingStyle,
    bowlingStyle: bowlingStyle,
    isCaptain: captain,
    isKeeper: wicketKeeper,
  );
}

PlayerRow rowFromRegPlayer(RegPlayer p, {String teamName = ''}) => PlayerRow(
  teamName: teamName.isNotEmpty ? teamName : p.teamName,
  playerName: p.name,
  jerseyNo: p.jerseyNo,
  role: p.role,
  battingStyle: p.battingStyle,
  bowlingStyle: p.bowlingStyle,
  captain: p.isCaptain,
  wicketKeeper: p.isKeeper,
  area: p.area,
  phone: p.phone,
  availability: p.availability,
  remarks: p.remarks,
);

PlayerRow rowFromPlayer(Player p, String teamName) => PlayerRow(
  teamName: teamName,
  playerName: p.name,
  jerseyNo: p.jerseyNo,
  role: p.role,
  battingStyle: p.battingStyle,
  bowlingStyle: p.bowlingStyle,
  captain: p.isCaptain,
  wicketKeeper: p.isKeeper,
);

// ---------------- CSV ----------------

String _csvCell(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

String rowsToCsv(List<PlayerRow> rows) {
  final buf = StringBuffer();
  buf.writeln(kPlayerColumns.map(_csvCell).join(','));
  for (final r in rows) {
    buf.writeln(r.toCells().map(_csvCell).join(','));
  }
  return buf.toString();
}

/// Minimal RFC-4180 CSV parser (handles quotes, commas, CRLF, newlines
/// inside quoted fields).
List<List<String>> parseCsvMatrix(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var inQuotes = false;
  var i = 0;
  final s = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  while (i < s.length) {
    final ch = s[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(ch);
      i++;
      continue;
    }
    if (ch == '"') {
      inQuotes = true;
      i++;
    } else if (ch == ',') {
      row.add(field.toString());
      field = StringBuffer();
      i++;
    } else if (ch == '\n') {
      row.add(field.toString());
      field = StringBuffer();
      rows.add(row);
      row = <String>[];
      i++;
    } else {
      field.write(ch);
      i++;
    }
  }
  row.add(field.toString());
  rows.add(row);
  return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}

// ---------------- Header mapping + matrix -> rows ----------------

String _norm(String h) => h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

const Map<String, String> _headerAliases = {
  'teamname': 'team',
  'team': 'team',
  'playername': 'player',
  'player': 'player',
  'name': 'player',
  'fullname': 'player',
  'jerseyno': 'jersey',
  'jersey': 'jersey',
  'jerseynumber': 'jersey',
  'number': 'jersey',
  'no': 'jersey',
  'role': 'role',
  'playingrole': 'role',
  'battingstyle': 'batting',
  'batting': 'batting',
  'bowlingstyle': 'bowling',
  'bowling': 'bowling',
  'captain': 'captain',
  'cap': 'captain',
  'wicketkeeper': 'keeper',
  'wicketkeeping': 'keeper',
  'wk': 'keeper',
  'keeper': 'keeper',
  'area': 'area',
  'city': 'area',
  'location': 'area',
  'phonenumber': 'phone',
  'phone': 'phone',
  'mobile': 'phone',
  'contact': 'phone',
  'contactnumber': 'phone',
  'availability': 'availability',
  'available': 'availability',
  'remarks': 'remarks',
  'remark': 'remarks',
  'notes': 'remarks',
  'note': 'remarks',
};

String normalizeRole(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty) return 'Batter';
  if (t.contains('all')) return 'All-Rounder';
  if (t.contains('keep') || t == 'wk' || t.contains('wicket')) {
    return 'Wicket-Keeper';
  }
  if (t.contains('bowl')) return 'Bowler';
  return 'Batter';
}

String normalizeBatting(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.contains('left')) return 'Left-hand';
  return 'Right-hand';
}

String normalizeBowling(String raw) {
  final t = raw.trim().toLowerCase();
  if (t.isEmpty || t == 'none' || t == '-' || t == 'no') return 'None';
  final arm = t.contains('left') ? 'Left-arm' : 'Right-arm';
  if (t.contains('spin') || t.contains('slow') || t.contains('orthodox')) {
    return '$arm spin';
  }
  if (t.contains('fast') || t.contains('pace')) return '$arm fast';
  return '$arm medium';
}

bool _toBool(String v) {
  final t = v.trim().toLowerCase();
  return t == 'y' ||
      t == 'yes' ||
      t == 'true' ||
      t == '1' ||
      t == 'c' ||
      t == 'wk';
}

class ParseResult {
  final List<PlayerRow> rows;
  final List<String> errors;
  ParseResult(this.rows, this.errors);
}

ParseResult rowsFromMatrix(List<List<String>> matrix) {
  final errors = <String>[];
  final rows = <PlayerRow>[];
  if (matrix.isEmpty) {
    return ParseResult(rows, ['File is empty']);
  }
  final header = matrix.first;
  final colIndex = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final key = _headerAliases[_norm(header[i])];
    if (key != null && !colIndex.containsKey(key)) colIndex[key] = i;
  }
  if (!colIndex.containsKey('player')) {
    errors.add('Could not find a "Player Name" column in the header');
    return ParseResult(rows, errors);
  }
  String cell(List<String> r, String key) {
    final idx = colIndex[key];
    if (idx == null || idx >= r.length) return '';
    return r[idx].trim();
  }

  for (var r = 1; r < matrix.length; r++) {
    final line = matrix[r];
    final name = cell(line, 'player');
    if (name.isEmpty) continue;
    final jerseyText = cell(line, 'jersey');
    final availRaw = cell(line, 'availability');
    rows.add(
      PlayerRow(
        teamName: cell(line, 'team'),
        playerName: name,
        jerseyNo: (double.tryParse(jerseyText) ?? 0).toInt(),
        role: normalizeRole(cell(line, 'role')),
        battingStyle: normalizeBatting(cell(line, 'batting')),
        bowlingStyle: normalizeBowling(cell(line, 'bowling')),
        captain: _toBool(cell(line, 'captain')),
        wicketKeeper: _toBool(cell(line, 'keeper')),
        area: cell(line, 'area'),
        phone: cell(line, 'phone'),
        availability: availRaw.isEmpty
            ? 'Available'
            : (availRaw.toLowerCase().startsWith('not') ||
                      availRaw.toLowerCase() == 'no' ||
                      availRaw.toLowerCase() == 'unavailable'
                  ? 'Not Available'
                  : 'Available'),
        remarks: cell(line, 'remarks'),
      ),
    );
  }
  if (rows.isEmpty && errors.isEmpty) {
    errors.add('No player rows found');
  }
  return ParseResult(rows, errors);
}

ParseResult parsePlayersCsv(String text) =>
    rowsFromMatrix(parseCsvMatrix(text));

// ---------------- XLSX ----------------

Uint8List rowsToXlsxBytes(List<PlayerRow> rows) {
  final excel = Excel.createExcel();
  try {
    excel.delete('Sheet1');
  } catch (_) {
    // default sheet name differs by version; harmless if it stays
  }
  final sheet = excel['Players'];
  sheet.appendRow(kPlayerColumns.map((c) => TextCellValue(c)).toList());
  for (final r in rows) {
    sheet.appendRow(r.toCells().map((c) => TextCellValue(c)).toList());
  }
  final encoded = excel.encode();
  return Uint8List.fromList(encoded ?? <int>[]);
}

ParseResult parsePlayersXlsx(Uint8List bytes) {
  try {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      return ParseResult([], ['No sheets found in the Excel file']);
    }
    // Prefer a sheet named like "Players", else the first sheet.
    String? sheetName;
    for (final name in excel.tables.keys) {
      if (name.toLowerCase().contains('player')) sheetName = name;
    }
    sheetName ??= excel.tables.keys.first;
    final table = excel.tables[sheetName]!;
    final matrix = <List<String>>[];
    String fmt(Object? v) {
      if (v == null) return '';
      if (v is num) {
        // Avoid '7.0' / scientific notation for jerseys and phone numbers.
        if (v == v.roundToDouble()) return '${v.toInt()}';
        return '$v';
      }
      return v.toString();
    }

    for (final row in table.rows) {
      matrix.add(row.map((c) => fmt(c?.value)).toList());
    }
    return rowsFromMatrix(matrix);
  } catch (e) {
    return ParseResult([], ['Could not read Excel file: $e']);
  }
}
