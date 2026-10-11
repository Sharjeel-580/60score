// Scorecard PDF generation (official pdf package, pure Dart widgets).
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'models.dart';
import 'scoring.dart';

Future<Uint8List> buildScorecardPdf(
  Match m,
  String Function(String id) nameOf,
  String Function(String teamId) teamName,
) async {
  final doc = pw.Document();
  final titleStyle =
      pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold);
  final h2 = pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold);
  final small = const pw.TextStyle(fontSize: 9);

  pw.Widget table(List<String> head, List<List<String>> rows) {
    pw.Widget cellWidget(String text, {bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: pw.Text(text,
              style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: bold ? pw.FontWeight.bold : null)),
        );
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: head.map((h) => cellWidget(h, bold: true)).toList(),
        ),
        for (final r in rows)
          pw.TableRow(children: r.map((c) => cellWidget(c)).toList()),
      ],
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) {
        final widgets = <pw.Widget>[
          pw.Text('60Score — Match Scorecard', style: titleStyle),
          pw.SizedBox(height: 4),
          pw.Text(
              '${teamName(m.teamAId)} vs ${teamName(m.teamBId)} • ${m.oversLimit} overs'
              '${m.venue.isNotEmpty ? ' • ${m.venue}' : ''}'
              '${m.dateIso.isNotEmpty ? ' • ${m.dateIso}' : ''}',
              style: small),
          pw.Text(
              'Toss: ${teamName(m.tossWinnerId)} chose to ${m.tossDecision} first',
              style: small),
          pw.SizedBox(height: 10),
        ];
        for (final inn in m.innings) {
          widgets.add(pw.Text(
              '${teamName(inn.battingTeamId)} innings — ${inn.totalRuns}/${inn.wickets} '
              '(${oversText(inn.legalBalls, inn.ballsPerOver)} overs)',
              style: h2));
          widgets.add(pw.SizedBox(height: 4));
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
          widgets.add(table(
              ['Batter', 'Dismissal', 'R', 'B', '4s', '6s', 'SR'], batRows));
          final dnb = inn.battingXI
              .where((id) => !(inn.batting[id]?.batted ?? false))
              .map(nameOf)
              .toList();
          if (dnb.isNotEmpty) {
            widgets.add(pw.Text('Did not bat: ${dnb.join(', ')}', style: small));
          }
          widgets.add(pw.Text(
              'Extras: ${inn.extrasTotal} (wd ${inn.widesRuns}, nb ${inn.noBallRuns}, b ${inn.byeRuns}, lb ${inn.legByeRuns})',
              style: small));
          widgets.add(pw.SizedBox(height: 6));
          final bowlRows = <List<String>>[];
          for (final pid in inn.bowling.keys) {
            final f = inn.bowling[pid]!;
            if (f.legalBalls == 0 && f.wides == 0 && f.noBalls == 0) continue;
            final econ = f.legalBalls == 0
                ? '-'
                : (f.runs * inn.ballsPerOver / f.legalBalls)
                    .toStringAsFixed(2);
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
            widgets.add(pw.Text(
                'Fall of wickets: ${inn.fallOfWickets.map((w) => '${w.runs}-${w.wicketNo} (${nameOf(w.playerId)}, ${w.overText} ov)').join(', ')}',
                style: small));
          }
          widgets.add(pw.SizedBox(height: 12));
        }
        if (m.resultText.isNotEmpty) {
          widgets.add(pw.Text('Result: ${m.resultText}',
              style: pw.TextStyle(
                  fontSize: 12, fontWeight: pw.FontWeight.bold)));
        }
        if (m.manOfMatchId.isNotEmpty) {
          widgets.add(pw.Text('Man of the Match: ${nameOf(m.manOfMatchId)}',
              style: small));
        }
        widgets.add(pw.SizedBox(height: 14));
        widgets.add(pw.Text('Generated by 60Score • Made by Sharjeel',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)));
        return widgets;
      },
    ),
  );
  return doc.save();
}
