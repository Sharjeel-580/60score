// Pure TTS phrase-builder tests (no TTS engine involved).
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/tts_service.dart';

void main() {
  group('ttsOverSummary', () {
    test('basic: end of over, team, score', () {
      final s = ttsOverSummary(
        teamName: 'Dolphins',
        runs: 85,
        wickets: 3,
        oversText: '6.0',
      );
      expect(s, 'End of over 6. Dolphins 85 for 3.');
    });

    test('overs text without .0 and mid-over text pass through', () {
      expect(
        ttsOverSummary(teamName: 'Kings', runs: 10, wickets: 0, oversText: '1'),
        contains('End of over 1.'),
      );
      expect(
        ttsOverSummary(
          teamName: 'Kings',
          runs: 40,
          wickets: 1,
          oversText: '4.3',
        ),
        contains('End of over 4.3.'),
      );
    });

    test('with target and balls: need / balls-left context', () {
      final s = ttsOverSummary(
        teamName: 'Dolphins',
        runs: 85,
        wickets: 3,
        oversText: '6.0',
        target: 119,
        inningsNo: 2,
        ballsBowled: 36,
        ballsTotal: 48,
      );
      expect(s, contains('End of over 6. Dolphins 85 for 3.'));
      expect(s, contains('Need 34 off 12 balls.'));
    });

    test('with target but no balls info: runs-to-win phrasing', () {
      final s = ttsOverSummary(
        teamName: 'Dolphins',
        runs: 85,
        wickets: 3,
        oversText: '6.0',
        target: 119,
      );
      expect(s, contains('Need 34 runs to win.'));
      expect(s, isNot(contains('off')));
    });

    test('without target there is no chase context', () {
      final s = ttsOverSummary(
        teamName: 'Dolphins',
        runs: 85,
        wickets: 3,
        oversText: '6.0',
        ballsBowled: 36,
        ballsTotal: 48,
      );
      expect(s, isNot(contains('Need')));
    });

    test('singular ball wording and target reached', () {
      final one = ttsOverSummary(
        teamName: 'Dolphins',
        runs: 118,
        wickets: 3,
        oversText: '7.5',
        target: 119,
        ballsBowled: 47,
        ballsTotal: 48,
      );
      expect(one, contains('Need 1 off 1 ball.'));
      final done = ttsOverSummary(
        teamName: 'Dolphins',
        runs: 119,
        wickets: 3,
        oversText: '7.5',
        target: 119,
        ballsBowled: 47,
        ballsTotal: 48,
      );
      expect(done, contains('Target reached.'));
    });
  });

  group('ttsWicket', () {
    test('exact phrase shape', () {
      expect(
        ttsWicket(
          batsmanName: 'Ahmed',
          teamName: 'Dolphins',
          runs: 85,
          wickets: 3,
        ),
        'Wicket! Ahmed out. Dolphins 85 for 3.',
      );
    });
  });

  group('ttsMilestone', () {
    test('fifty wording at 50, hundred wording at 100', () {
      expect(ttsMilestone(batsmanName: 'Ahmed', runs: 50),
          'Fifty for Ahmed!');
      expect(ttsMilestone(batsmanName: 'Ahmed', runs: 73),
          'Fifty for Ahmed!');
      expect(ttsMilestone(batsmanName: 'Ahmed', runs: 100),
          'Hundred for Ahmed!');
      expect(ttsMilestone(batsmanName: 'Ahmed', runs: 137),
          'Hundred for Ahmed!');
    });

    test('below fifty falls back to reaches phrasing', () {
      expect(ttsMilestone(batsmanName: 'Ahmed', runs: 25),
          'Ahmed reaches 25.');
    });
  });
}
