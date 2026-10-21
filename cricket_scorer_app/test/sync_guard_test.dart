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

  // v1.3.3 regression tests — the 2026-10-21 live data loss:
  // a NEW device (v1.3.2) logged into the owner's account, showed
  // EMPTY, and its empty pushes then destroyed the cloud backup;
  // the original phone imported the empty copy and lost its data
  // too. Root causes pinned here at the logic level:
  //  (1) the fresh scope's local clock read "now" (stamped by the
  //      activation persists), so the pull judged the good backup
  //      "older" and never imported it;
  //  (2) the v1.3.2 empty-push suppression only covered the
  //      settle-time deferred flush — ordinary pushes after settle
  //      were unvetted;
  //  (3) the pull happily applied an all-empty remote dataset over
  //      a non-empty local one.
  group('SyncService.decidePull (2026-10-21 regression)', () {
    test('fresh empty scope + non-empty backup imports REGARDLESS of '
        'timestamps (today: local clock "now" vs backup from 13:49)',
        () {
      expect(
        SyncService.decidePull(
            localEmpty: true, remoteEmpty: false, remoteNewer: false),
        PullDecision.importRemote,
      );
      expect(
        SyncService.decidePull(
            localEmpty: true, remoteEmpty: false, remoteNewer: true),
        PullDecision.importRemote,
      );
    });

    test('empty backup is never imported over local data — local is '
        'kept and pushed up, even when the empty copy is "newer" '
        '(today: the original phone importing the clobbered backup)',
        () {
      expect(
        SyncService.decidePull(
            localEmpty: false, remoteEmpty: true, remoteNewer: true),
        PullDecision.keepLocalAndPush,
      );
      expect(
        SyncService.decidePull(
            localEmpty: false, remoteEmpty: true, remoteNewer: false),
        PullDecision.keepLocalAndPush,
      );
    });

    test('both sides non-empty: classic last-write-wins by timestamp',
        () {
      expect(
        SyncService.decidePull(
            localEmpty: false, remoteEmpty: false, remoteNewer: true),
        PullDecision.importRemote,
      );
      expect(
        SyncService.decidePull(
            localEmpty: false, remoteEmpty: false, remoteNewer: false),
        PullDecision.noImport,
      );
    });

    test('both sides empty: nothing to import either way', () {
      expect(
        SyncService.decidePull(
            localEmpty: true, remoteEmpty: true, remoteNewer: true),
        PullDecision.importRemote, // applies empties over empties: a no-op
      );
      expect(
        SyncService.decidePull(
            localEmpty: true, remoteEmpty: true, remoteNewer: false),
        PullDecision.noImport,
      );
    });
  });

  group('SyncPushGuard post-settle pushes (2026-10-21 regression)',
      () {
    test('an ordinary empty push AFTER settle stays suppressed for a '
        'never-imported empty scope (the v1.3.2 hole: only the '
        'deferred flush was vetted)', () {
      final g = SyncPushGuard();
      // The pull settles the way today's did: backup seen holding
      // data, nothing imported, local dataset empty.
      expect(
        g.settle('uid_a',
            imported: false,
            docSeen: true,
            emptyDataset: true,
            remoteNonEmpty: true),
        isFalse, // no deferred flush either
      );
      // The first regular persist after settle — the push that
      // destroyed the backup in v1.3.2 — is refused...
      expect(g.pushPermitted(emptyDataset: true), isFalse);
      // ...and so is every later one in this activation.
      expect(g.pushPermitted(emptyDataset: true), isFalse);
      expect(g.emptyPushSuppressed(true), isTrue);
    });

    test('once the user creates data, pushes flow; deleting that '
        'data afterwards may sync (explicit user action)', () {
      final g = SyncPushGuard();
      g.settle('uid_a',
          imported: false,
          docSeen: true,
          emptyDataset: true,
          remoteNonEmpty: true);
      expect(g.pushPermitted(emptyDataset: true), isFalse);
      // User creates a tournament on the fresh device.
      expect(g.pushPermitted(emptyDataset: false), isTrue);
      // User deletes it again — a deliberate wipe of data they held
      // in this activation, so the empty state may sync.
      expect(g.pushPermitted(emptyDataset: true), isTrue);
    });

    test('deleting everything after a successful import may sync '
        '(the local dataset mirrors the remote, then the user wipes)',
        () {
      final g = SyncPushGuard();
      g.settle('uid_a',
          imported: true,
          docSeen: true,
          emptyDataset: false,
          remoteNonEmpty: true);
      expect(g.pushPermitted(emptyDataset: true), isTrue);
    });

    test('a scope that already held data may sync its own wipe even '
        'when the pull imported nothing (remote judged older)', () {
      final g = SyncPushGuard();
      g.settle('uid_a',
          imported: false,
          docSeen: true,
          emptyDataset: false, // local scope was non-empty at settle
          remoteNonEmpty: true);
      expect(g.pushPermitted(emptyDataset: true), isTrue);
    });

    test('a permitted empty push lifts suppression for what follows '
        '(the backup now genuinely is empty)', () {
      final g = SyncPushGuard();
      g.settle('uid_a',
          imported: true,
          docSeen: true,
          emptyDataset: false,
          remoteNonEmpty: true);
      expect(g.pushPermitted(emptyDataset: true), isTrue);
      g.notePushed(emptyDataset: true);
      expect(g.emptyPushSuppressed(true), isFalse);
    });

    test('pushPermitted stays closed before the first pull settles',
        () {
      final g = SyncPushGuard();
      expect(g.pushPermitted(emptyDataset: false), isFalse);
      expect(g.pushPermitted(emptyDataset: true), isFalse);
    });
  });
}
