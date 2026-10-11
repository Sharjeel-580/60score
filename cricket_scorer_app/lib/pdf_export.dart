// Scorecard PDF generation (official pdf package, pure Dart widgets).
//
// Design: 60Score brand theme (dark navy header, teal table headers, copper
// result band). ASCII text only - the standard PDF fonts have no emoji or
// bullet glyphs, so anything outside WinAnsi renders as tofu boxes.
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';
import 'scoring.dart';

// Brand palette (same as the app theme).
final _navy = PdfColor.fromHex('#0B1B26');
final _teal = PdfColor.fromHex('#057490');
final _tealDark = PdfColor.fromHex('#016682');
final _cyan = PdfColor.fromHex('#0CE8F8');
final _copper = PdfColor.fromHex('#F8AE6D');
final _rowAlt = PdfColor.fromHex('#F2F7F9');

Future<Uint8List> buildScorecardPdf(
  Match m,
  String Function(String id) nameOf,
  String Function(String teamId) teamName, {
  String tournamentName = '',
}) async {
  final doc = pw.Document();

  final titleStyle = pw.TextStyle(
    fontSize: 22,
    fontWeight: pw.FontWeight.bold,
    color: _cyan,
  );
  final subTitle = pw.TextStyle(
    fontSize: 13,
    fontWeight: pw.FontWeight.bold,
    color: _navy,
  );
  final h2 = pw.TextStyle(
    fontSize: 12,
    fontWeight: pw.FontWeight.bold,
    color: PdfColors.white,
  );
  final small = const pw.TextStyle(fontSize: 9);
  final smallGrey = pw.TextStyle(fontSize: 9, color: PdfColors.grey700);

  pw.Widget headerCell(String text) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 9.5,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
      ),
    ),
  );

  pw.Widget bodyCell(String text) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2.5),
    child: pw.Text(text, style: const pw.TextStyle(fontSize: 9.5)),
  );

  pw.Widget table(List<String> head, List<List<String>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _teal),
          children: head.map(headerCell).toList(),
        ),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isOdd ? _rowAlt : PdfColors.white,
            ),
            children: rows[i].map(bodyCell).toList(),
          ),
      ],
    );
  }

  pw.Widget inningsHeader(String text) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: pw.BoxDecoration(
      color: _tealDark,
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Text(text, style: h2),
  );

  final metaBits = <String>[
    '${teamName(m.teamAId)} vs ${teamName(m.teamBId)}',
    '${m.oversLimit} overs',
    if (m.matchTitle.isNotEmpty) m.matchTitle,
    if (m.venue.isNotEmpty) m.venue,
    if (m.dateIso.isNotEmpty) m.dateIso,
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) {
        final widgets = <pw.Widget>[
          // ---- branded header band ----
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: _navy,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('60SCORE', style: titleStyle),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Match Scorecard',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                if (tournamentName.isNotEmpty) ...[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    tournamentName,
                    style: pw.TextStyle(fontSize: 11, color: _copper),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(metaBits.join('  |  '), style: smallGrey),
          pw.Text(
            'Toss: ${teamName(m.tossWinnerId)} chose to ${m.tossDecision} first',
            style: smallGrey,
          ),
          pw.SizedBox(height: 10),
        ];
        for (final inn in m.innings) {
          widgets.add(
            inningsHeader(
              '${teamName(inn.battingTeamId)}  -  ${inn.totalRuns}/${inn.wickets} '
              '(${oversText(inn.legalBalls, inn.ballsPerOver)} overs)',
            ),
          );
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(pw.Text('Batting', style: subTitle));
          widgets.add(pw.SizedBox(height: 3));
          final batRows = <List<String>>[];
          for (final pid in inn.battingXI) {
            final f = inn.batting[pid];
            if (f == null || !f.batted) continue;
            final sr = f.balls == 0
                ? '-'
                : (f.runs * 100 / f.balls).toStringAsFixed(1);
            batRows.add([
              nameOf(pid),
              f.out ? resolveHowOut(f.howOut, nameOf) : 'not out',
              '${f.runs}',
              '${f.balls}',
              '${f.fours}',
              '${f.sixes}',
              sr,
            ]);
          }
          widgets.add(
            table(['Batter', 'Dismissal', 'R', 'B', '4s', '6s', 'SR'], batRows),
          );
          final dnb = inn.battingXI
              .where((id) => !(inn.batting[id]?.batted ?? false))
              .map(nameOf)
              .toList();
          if (dnb.isNotEmpty) {
            widgets.add(pw.SizedBox(height: 3));
            widgets.add(
              pw.Text('Did not bat: ${dnb.join(', ')}', style: small),
            );
          }
          widgets.add(pw.SizedBox(height: 3));
          widgets.add(
            pw.Text(
              'Extras: ${inn.extrasTotal} (wd ${inn.widesRuns}, nb ${inn.noBallRuns}, b ${inn.byeRuns}, lb ${inn.legByeRuns})',
              style: small,
            ),
          );
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(pw.Text('Bowling', style: subTitle));
          widgets.add(pw.SizedBox(height: 3));
          final bowlRows = <List<String>>[];
          for (final pid in inn.bowling.keys) {
            final f = inn.bowling[pid]!;
            if (f.legalBalls == 0 && f.wides == 0 && f.noBalls == 0) continue;
            final econ = f.legalBalls == 0
                ? '-'
                : (f.runs * inn.ballsPerOver / f.legalBalls).toStringAsFixed(2);
            bowlRows.add([
              nameOf(pid),
              oversText(f.legalBalls, inn.ballsPerOver),
              '${f.maidens}',
              '${f.runs}',
              '${f.wickets}',
              econ,
            ]);
          }
          widgets.add(table(['Bowler', 'O', 'M', 'R', 'W', 'Econ'], bowlRows));
          if (inn.fallOfWickets.isNotEmpty) {
            widgets.add(pw.SizedBox(height: 4));
            widgets.add(
              pw.Text(
                'Fall of wickets: ${inn.fallOfWickets.map((w) => '${w.runs}-${w.wicketNo} (${nameOf(w.playerId)}, ${w.overText} ov)').join(', ')}',
                style: small,
              ),
            );
          }
          widgets.add(pw.SizedBox(height: 12));
        }
        if (m.resultText.isNotEmpty) {
          widgets.add(
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: _copper,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                'Result: ${m.resultText}',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: _navy,
                ),
              ),
            ),
          );
          widgets.add(pw.SizedBox(height: 6));
        }
        if (m.manOfMatchId.isNotEmpty) {
          widgets.add(
            pw.Text(
              'Player of the Match: ${nameOf(m.manOfMatchId)}',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _tealDark,
              ),
            ),
          );
          widgets.add(pw.SizedBox(height: 6));
        }
        // ---- footer: credit stays prominent at the bottom ----
        widgets.add(pw.SizedBox(height: 10));
        widgets.add(
          pw.Center(
            child: pw.Text(
              'Made by Sharjeel',
              style: pw.TextStyle(
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                color: _tealDark,
              ),
            ),
          ),
        );
        widgets.add(pw.SizedBox(height: 2));
        widgets.add(
          pw.Center(
            child: pw.Text(
              'Generated by 60Score',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ),
        );
        return widgets;
      },
    ),
  );
  return doc.save();
}
