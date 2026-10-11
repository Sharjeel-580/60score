import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/player_io.dart';

void main() {
  group('CSV import/export', () {
    test('round trip preserves all fields incl commas in remarks', () {
      final rows = [
        PlayerRow(
          teamName: 'AB Knights',
          playerName: 'Ali Khan',
          jerseyNo: 7,
          role: 'All-Rounder',
          battingStyle: 'Right-hand',
          bowlingStyle: 'Right-arm fast',
          captain: true,
          wicketKeeper: false,
          area: 'Sargodha',
          phone: '03001234567',
          availability: 'Available',
          remarks: 'Strong hitter, death bowler',
        ),
        PlayerRow(
          teamName: 'MA Kings',
          playerName: 'Bilal Ahmed',
          role: 'Wicket-Keeper',
          wicketKeeper: true,
          availability: 'Not Available',
        ),
      ];
      final csv = rowsToCsv(rows);
      final parsed = parsePlayersCsv(csv);
      expect(parsed.errors, isEmpty);
      expect(parsed.rows.length, 2);
      final a = parsed.rows[0];
      expect(a.playerName, 'Ali Khan');
      expect(a.teamName, 'AB Knights');
      expect(a.jerseyNo, 7);
      expect(a.captain, isTrue);
      expect(a.wicketKeeper, isFalse);
      expect(a.remarks, 'Strong hitter, death bowler');
      expect(a.phone, '03001234567');
      final b = parsed.rows[1];
      expect(b.wicketKeeper, isTrue);
      expect(b.availability, 'Not Available');
    });

    test('header matching is case/order tolerant', () {
      const csv = 'phone number,PLAYER NAME,Team,jersey,ROLE\n'
          '03009998877,Zain Ul Abidin,US Lions,10,Bowler\n';
      final parsed = parsePlayersCsv(csv);
      expect(parsed.errors, isEmpty);
      expect(parsed.rows.single.playerName, 'Zain Ul Abidin');
      expect(parsed.rows.single.teamName, 'US Lions');
      expect(parsed.rows.single.jerseyNo, 10);
      expect(parsed.rows.single.role, 'Bowler');
      expect(parsed.rows.single.phone, '03009998877');
    });

    test('empty and header-only files report errors, no crash', () {
      expect(parsePlayersCsv('').errors, isNotEmpty);
      expect(parsePlayersCsv('').rows, isEmpty);
      final headerOnly = parsePlayersCsv(
          'Team Name,Player Name,Jersey No,Role,Batting Style,Bowling Style,Captain,Wicket-Keeper,Area,Phone Number,Availability,Remarks\n');
      expect(headerOnly.rows, isEmpty);
      expect(headerOnly.errors, isNotEmpty);
    });

    test('missing Player Name column is an error', () {
      final parsed = parsePlayersCsv('Team,Runs\nAB Knights,50\n');
      expect(parsed.rows, isEmpty);
      expect(parsed.errors.join(' '), contains('Player Name'));
    });
  });

  group('XLSX import/export', () {
    test('xlsx round trip', () {
      final rows = [
        PlayerRow(
            teamName: 'Shazi Hawks',
            playerName: 'Hamza Tariq',
            jerseyNo: 12,
            role: 'Batter',
            captain: false,
            wicketKeeper: true,
            area: 'Bhalwal'),
      ];
      final bytes = rowsToXlsxBytes(rows);
      expect(bytes.isNotEmpty, isTrue);
      final parsed = parsePlayersXlsx(bytes);
      expect(parsed.errors, isEmpty);
      expect(parsed.rows.single.playerName, 'Hamza Tariq');
      expect(parsed.rows.single.jerseyNo, 12);
      expect(parsed.rows.single.wicketKeeper, isTrue);
      expect(parsed.rows.single.area, 'Bhalwal');
    });
  });
}
