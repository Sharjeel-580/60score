import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/draft.dart';

RegPlayer rp(String id, String name) => RegPlayer(id: id, name: name);

void main() {
  group('draft flow', () {
    test('linear order: turns rotate through teams, rounds increment', () {
      final d = Draft(
          id: 'd1', name: 'D', teamIds: ['t1', 't2'], squadSize: 2);
      final pool = [rp('p1', 'A'), rp('p2', 'B'), rp('p3', 'C'), rp('p4', 'E')];
      var turn = nextTurn(d)!;
      expect(turn.round, 1);
      expect(turn.pickNo, 1);
      expect(turn.teamId, 't1');
      expect(applyPick(d, pool[0]), isTrue);
      turn = nextTurn(d)!;
      expect(turn.teamId, 't2');
      expect(applyPick(d, pool[1]), isTrue);
      turn = nextTurn(d)!;
      expect(turn.round, 2);
      expect(turn.teamId, 't1');
      expect(applyPick(d, pool[2]), isTrue);
      expect(applyPick(d, pool[3]), isTrue);
      expect(d.isComplete, isTrue);
      expect(d.status, 'completed');
      expect(nextTurn(d), isNull);
      expect(draftProgress(d), 1.0);
      final squads = draftSquads(d);
      expect(squads['t1']!.map((p) => p.playerId), ['p1', 'p3']);
      expect(squads['t2']!.map((p) => p.playerId), ['p2', 'p4']);
    });

    test('duplicate pick is rejected', () {
      final d = Draft(id: 'd1', name: 'D', teamIds: ['t1', 't2'], squadSize: 3);
      final p = rp('p1', 'A');
      expect(applyPick(d, p), isTrue);
      expect(applyPick(d, p), isFalse);
      expect(d.picks.length, 1);
    });

    test('undo removes last pick and reopens the draft', () {
      final d = Draft(id: 'd1', name: 'D', teamIds: ['t1'], squadSize: 1);
      expect(applyPick(d, rp('p1', 'A')), isTrue);
      expect(d.status, 'completed');
      expect(undoPick(d), isTrue);
      expect(d.picks, isEmpty);
      expect(d.status, 'active');
      expect(undoPick(d), isFalse);
    });

    test('snake order reverses in round 2', () {
      final d = Draft(
          id: 'd1',
          name: 'D',
          teamIds: ['t1', 't2', 't3'],
          squadSize: 2,
          snakeOrder: true);
      final order = <String>[];
      for (var i = 1; i <= 6; i++) {
        order.add(nextTurn(d)!.teamId);
        applyPick(d, rp('p$i', 'P$i'));
      }
      expect(order, ['t1', 't2', 't3', 't3', 't2', 't1']);
    });
  });
}
