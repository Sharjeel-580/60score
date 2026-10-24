// D/L Standard Edition calculator tests.
//
// The table embedded in lib/dls.dart is the published Standard
// Edition over-by-over table (see that file's header): it gives
// 25 overs / 0 wickets = 66.5%, 20 / 0 = 56.6%, 10 / 0 = 32.1%.
// An older (1998) abbreviated extract quotes 68.7% for 25 / 0 —
// the worked example below asserts what THIS table gives, with
// the difference noted.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/dls.dart';

void main() {
  group('dlResourcePct anchors (Standard Edition table)', () {
    test('50 overs / 0 wickets is exactly 100.0', () {
      expect(
        dlResourcePct(oversRemaining: 50, wicketsLost: 0),
        100.0,
      );
    });

    test('0 overs is 0 at any wickets value', () {
      for (var w = 0; w <= 9; w++) {
        expect(dlResourcePct(oversRemaining: 0, wicketsLost: w), 0.0);
      }
    });

    test('published row values', () {
      // From the embedded over-by-over Standard Edition table.
      expect(dlResourcePct(oversRemaining: 25, wicketsLost: 0), 66.5);
      expect(dlResourcePct(oversRemaining: 20, wicketsLost: 0), 56.6);
      expect(dlResourcePct(oversRemaining: 10, wicketsLost: 0), 32.1);
      expect(dlResourcePct(oversRemaining: 40, wicketsLost: 0), 89.3);
      expect(dlResourcePct(oversRemaining: 30, wicketsLost: 0), 75.1);
      expect(dlResourcePct(oversRemaining: 5, wicketsLost: 0), 17.2);
      expect(dlResourcePct(oversRemaining: 50, wicketsLost: 2), 85.1);
      expect(dlResourcePct(oversRemaining: 50, wicketsLost: 5), 49.0);
      expect(dlResourcePct(oversRemaining: 50, wicketsLost: 9), 4.7);
      expect(dlResourcePct(oversRemaining: 15, wicketsLost: 0), 45.2);
      expect(dlResourcePct(oversRemaining: 3, wicketsLost: 0), 10.6);
      expect(dlResourcePct(oversRemaining: 2, wicketsLost: 0), 7.2);
      expect(dlResourcePct(oversRemaining: 1, wicketsLost: 0), 3.6);
    });

    test('clamping: overs > 50, negative overs, 10 wickets', () {
      expect(dlResourcePct(oversRemaining: 60, wicketsLost: 0), 100.0);
      expect(dlResourcePct(oversRemaining: -3, wicketsLost: 0), 0.0);
      expect(dlResourcePct(oversRemaining: 30, wicketsLost: 10), 0.0);
      expect(dlResourcePct(oversRemaining: 30, wicketsLost: -1),
          dlResourcePct(oversRemaining: 30, wicketsLost: 0));
    });

    test('linear interpolation between whole-over rows', () {
      // 25.5 overs / 0 wkts: halfway between 66.5 (25) and 68.3 (26).
      expect(
        dlResourcePct(oversRemaining: 25.5, wicketsLost: 0),
        closeTo(67.4, 0.001),
      );
      // 10 overs 3 balls = 10.5: halfway between 32.1 and 34.9.
      expect(
        dlResourcePct(oversRemaining: 10.5, wicketsLost: 0),
        closeTo(33.5, 0.001),
      );
      // Interpolated value always lies between its neighbours.
      final v = dlResourcePct(oversRemaining: 17.25, wicketsLost: 3);
      expect(v, greaterThan(dlResourcePct(oversRemaining: 17, wicketsLost: 3)));
      expect(v, lessThan(dlResourcePct(oversRemaining: 18, wicketsLost: 3)));
    });
  });

  group('monotonicity over the grid', () {
    test('resources never increase as overs decrease', () {
      for (var w = 0; w <= 9; w++) {
        var prev = 0.0;
        for (var overs = 0; overs <= 50; overs++) {
          final v = dlResourcePct(
            oversRemaining: overs.toDouble(),
            wicketsLost: w,
          );
          // Reading overs ascending, resources are non-decreasing;
          // equivalently they never increase as overs decrease.
          expect(v, greaterThanOrEqualTo(prev));
          prev = v;
        }
      }
    });

    test('resources never increase as wickets increase', () {
      for (var overs = 0; overs <= 50; overs++) {
        var prev = double.infinity;
        for (var w = 0; w <= 9; w++) {
          final v = dlResourcePct(
            oversRemaining: overs.toDouble(),
            wicketsLost: w,
          );
          expect(v, lessThanOrEqualTo(prev));
          prev = v;
        }
      }
    });
  });

  group('dlsTarget', () {
    test('worked example: 250 in 50 overs, Team 2 cut to 25 overs', () {
      // R1 = 100 (full innings), R2 = resource at 25 overs / 0 wkts.
      // This table gives R2 = 66.5 (the older 1998 abbreviated
      // extract quotes 68.7, which would give par 171.7 / target
      // 172). With 66.5: par = 250 * 66.5 / 100 = 166.25, so the
      // target asserted here is floor(166.25) + 1 = 167.
      final r2 = dlResourcePct(oversRemaining: 25, wicketsLost: 0);
      expect(r2, 66.5);
      final r = dlsTarget(
        team1Score: 250,
        team1ResourcePct: 100,
        team2ResourcePct: r2,
      );
      expect(r.parScore, closeTo(166.25, 0.001));
      expect(r.target, 167);
      expect(r.team1ResourcePct, 100);
      expect(r.team2ResourcePct, 66.5);
    });

    test('equal resources: target is team1Score + 1', () {
      final r = dlsTarget(
        team1Score: 200,
        team1ResourcePct: 75.1,
        team2ResourcePct: 75.1,
      );
      expect(r.parScore, 200.0);
      expect(r.target, 201);
    });

    test('R2 > R1 branch uses the G50 uplift', () {
      // Team 1 made 200, innings terminated after 40 of 50 overs
      // with 4 wickets down: resources still remaining at
      // termination = resource at 10 overs / 4 wkts = 28.3, so
      // R1 = 100 - 28.3 = 71.7. Team 2 gets a full 50 overs: R2 = 100.
      final r1 = resourcesForTerminatedInnings(
        oversAtStart: 50,
        oversRemainingAtTermination: 10,
        wicketsLostAtTermination: 4,
      );
      expect(r1, closeTo(71.7, 0.001));
      final r = dlsTarget(
        team1Score: 200,
        team1ResourcePct: r1,
        team2ResourcePct: 100,
      );
      // par = 200 + 245 * (100 - 71.7) / 100 = 200 + 69.335 = 269.335
      expect(r.parScore, closeTo(269.335, 0.001));
      expect(r.target, 270);
      expect(r.target, greaterThan(201));
    });
  });

  group('interruption helpers', () {
    test('resourcesAtInningsStart is the 0-wicket resource', () {
      expect(resourcesAtInningsStart(50), 100.0);
      expect(resourcesUsedAtInningsStart(20), 56.6);
      expect(resourcesAtInningsStart(25),
          dlResourcePct(oversRemaining: 25, wicketsLost: 0));
    });

    test('resourceLost for an interruption during innings 2', () {
      // Play stops at 20 overs left, 2 down (52.4%) and resumes
      // at 10 overs left, 2 down (30.8%): lost = 21.6.
      final lost = resourceLost(
        oversAtInterruption: 20,
        wickets: 2,
        oversAtResumption: 10,
      );
      expect(lost, closeTo(21.6, 0.001));
      // No overs lost -> no resource lost.
      expect(
        resourceLost(oversAtInterruption: 20, wickets: 2, oversAtResumption: 20),
        0.0,
      );
      // R2 after that interruption from a 50-over start:
      // 100 - 21.6 = 78.4? No — R2 is the resource of the innings
      // after the interruption relative to its own start. For an
      // innings that STARTED at 20 overs (56.6 at 0 down is for a
      // different state); check the composed helper instead:
      final r = resourcesAfterInterruptions(
        oversAtStart: 50,
        interruptions: [
          (oversAtInterruption: 20, wickets: 0, oversAtResumption: 10),
        ],
      );
      // Start 100, lost = 56.6 - 32.1 = 24.5 -> R = 75.5.
      expect(r, closeTo(75.5, 0.001));
    });

    test('terminated innings 1: R1 = start - remaining', () {
      // Started at 50 (100%), terminated with 20 overs left and
      // 0 wickets down (56.6% unused): R1 = 43.4.
      final r1 = resourcesForTerminatedInnings(
        oversAtStart: 50,
        oversRemainingAtTermination: 20,
        wicketsLostAtTermination: 0,
      );
      expect(r1, closeTo(43.4, 0.001));
    });
  });
}
