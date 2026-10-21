// Push guard + post-pull republish arming (v1.3.2, bug #R1).
//
// The race: a debounced push scheduled right after login could land
// before the activation's first pull read the cloud backup, and
// overwrite it with a not-yet-pulled local scope (on a fresh device,
// a completely empty dataset). SyncPushGuard is the gating logic:
// no push until the first pull settles, deferred pushes flush once
// on settle, and an all-empty flush over an existing remote backup
// is suppressed when that pull imported nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/store.dart';
import 'package:cricket_scorer_app/sync_service.dart';

void main() {
  group('SyncPushGuard gate', () {
    test('push is blocked until the first pull settles', () {
      final g = SyncPushGuard();
      expect(g.allowsPush('uid_a'), isFalse);
      g.settle('uid_a',
          imported: false, docSeen: false, emptyDataset: false);
      expect(g.allowsPush('uid_a'), isTrue);
    });

    test('a deferred push flushes once when the pull settles', () {
      final g = SyncPushGuard();
      expect(g.allowsPush('uid_a'), isFalse);
      g.defer('uid_a');
      expect(
        g.settle('uid_a',
            imported: true, docSeen: true, emptyDataset: false),
        isTrue,
      );
      // The deferral is consumed — a later settle flushes nothing.
      expect(
        g.settle('uid_a',
            imported: true, docSeen: true, emptyDataset: false),
        isFalse,
      );
    });

    test('no deferred push means settle reports no flush', () {
      final g = SyncPushGuard();
      expect(
        g.settle('uid_a',
            imported: true, docSeen: true, emptyDataset: false),
        isFalse,
      );
    });

    test('a different identity starts a fresh guarded window', () {
      final g = SyncPushGuard();
      g.settle('uid_a', imported: true, docSeen: true, emptyDataset: false);
      expect(g.allowsPush('uid_a'), isTrue);
      expect(g.allowsPush('uid_b'), isFalse);
    });

    test('reset closes the gate again (identity switch / log-out)', () {
      final g = SyncPushGuard();
      g.settle('uid_a', imported: true, docSeen: true, emptyDataset: false);
      expect(g.allowsPush('uid_a'), isTrue);
      g.reset();
      expect(g.allowsPush('uid_a'), isFalse);
    });
  });

  group('SyncPushGuard empty-dataset suppression', () {
    test('all-empty flush is suppressed when the pull imported nothing '
        'and a remote backup exists (the #R1 data-loss shape)', () {
      final g = SyncPushGuard();
      g.defer('uid_a');
      expect(
        g.settle('uid_a',
            imported: false, docSeen: true, emptyDataset: true),
        isFalse,
      );
      expect(g.emptyPushSuppressed(true), isTrue);
    });

    test('a non-empty deferred push still flushes when the pull '
        'imported nothing (local edits made during the window)', () {
      final g = SyncPushGuard();
      g.defer('uid_a');
      expect(
        g.settle('uid_a',
            imported: false, docSeen: true, emptyDataset: false),
        isTrue,
      );
      expect(g.emptyPushSuppressed(false), isFalse);
    });

    test('an empty flush is not suppressed when no remote backup '
        'exists (brand-new account — nothing to overwrite)', () {
      final g = SyncPushGuard();
      g.defer('uid_a');
      expect(
        g.settle('uid_a',
            imported: false, docSeen: false, emptyDataset: true),
        isTrue,
      );
      expect(g.emptyPushSuppressed(true), isFalse);
    });

    test('an empty flush is not suppressed after a pull that '
        'imported data (local now mirrors the remote)', () {
      final g = SyncPushGuard();
      g.defer('uid_a');
      expect(
        g.settle('uid_a',
            imported: true, docSeen: true, emptyDataset: true),
        isTrue,
      );
      expect(g.emptyPushSuppressed(true), isFalse);
    });
  });

  group('SyncPushGuard.datasetIsEmpty', () {
    test('empty store is empty; any core record makes it non-empty',
        () {
      final s = Store();
      expect(SyncPushGuard.datasetIsEmpty(s), isTrue);
      s.teams = [Team(id: 't', name: 'XI')];
      expect(SyncPushGuard.datasetIsEmpty(s), isFalse);

      final s2 = Store();
      s2.tournaments = [Tournament(id: 'c', name: 'Cup')];
      expect(SyncPushGuard.datasetIsEmpty(s2), isFalse);

      final s3 = Store();
      s3.matches = [
        Match(
          id: 'm',
          teamAId: 'a',
          teamBId: 'b',
          xiA: const [],
          xiB: const [],
          tossWinnerId: 'a',
        ),
      ];
      expect(SyncPushGuard.datasetIsEmpty(s3), isFalse);
    });
  });

  group('SyncService.shouldArmRepublishAfterPull', () {
    test('arms only when the pull applied data carrying a published '
        'tournament', () {
      expect(
        SyncService.shouldArmRepublishAfterPull(
            applied: true, hasPublished: true),
        isTrue,
      );
      expect(
        SyncService.shouldArmRepublishAfterPull(
            applied: true, hasPublished: false),
        isFalse,
      );
      expect(
        SyncService.shouldArmRepublishAfterPull(
            applied: false, hasPublished: true),
        isFalse,
      );
      expect(
        SyncService.shouldArmRepublishAfterPull(
            applied: false, hasPublished: false),
        isFalse,
      );
    });
  });
}
