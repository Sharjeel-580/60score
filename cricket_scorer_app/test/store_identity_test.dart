// Per-identity data separation (v1.3.1): every account (uid) and the
// guest workspace keep SEPARATE local data on the same device. A guest
// or a different account must never see — or edit — the owner's data.
// Pre-v1.3.1 (unscoped) device data is the OWNER's: only the account
// whose email is kOwnerEmail may claim it (claim-guard); everyone
// else leaves the legacy keys untouched and starts empty.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cricket_scorer_app/account_profile.dart';
import 'package:cricket_scorer_app/models.dart';
import 'package:cricket_scorer_app/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('guest and account data are fully separate', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.activateIdentity('guest');
    await s.upsertTournament(Tournament(id: 'guest_t', name: 'Guest Cup'));
    await s.upsertTeam(Team(id: 'guest_team', name: 'Guest XI'));

    // A signed-in account starts with its OWN empty workspace.
    await s.activateIdentity('uid_owner');
    expect(s.tournaments, isEmpty);
    expect(s.teams, isEmpty);
    await s.upsertTournament(Tournament(id: 'owner_t', name: 'Owner League'));

    // Switching back restores each workspace exactly as it was left.
    await s.activateIdentity('guest');
    expect(s.tournaments.map((t) => t.id), ['guest_t']);
    expect(s.teams.map((t) => t.id), ['guest_team']);
    await s.activateIdentity('uid_owner');
    expect(s.tournaments.map((t) => t.id), ['owner_t']);
    expect(s.teams, isEmpty);
  });

  test('the locked scope is always empty (post-logout state)', () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.activateIdentity('uid_owner');
    await s.upsertTournament(Tournament(id: 'owner_t', name: 'Owner League'));
    await s.activateIdentity('locked');
    expect(s.tournaments, isEmpty);
    expect(s.teams, isEmpty);
    // …and the owner's data is still intact under their own scope.
    await s.activateIdentity('uid_owner');
    expect(s.tournaments.map((t) => t.id), ['owner_t']);
  });

  test('legacy device data is claimed by the OWNER account only',
      () async {
    SharedPreferences.setMockInitialValues({});
    // Write data the way the pre-v1.3.1 build did: unscoped keys.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cricscore_tournaments_v1',
      jsonEncode([
        Tournament(id: 'legacy_t', name: 'Super Sixty League').toJson(),
      ]),
    );
    await prefs.setString(
      'cricscore_teams_v1',
      jsonEncode([Team(id: 'legacy_team', name: 'Legacy XI').toJson()]),
    );

    final s = Store();
    // A guest must NOT see the legacy (owner's) data…
    await s.activateIdentity('guest');
    expect(s.tournaments, isEmpty);
    expect(s.teams, isEmpty);

    // …but the owner account (matching email) claims it as its own.
    await s.activateAccount('uid_owner', email: kOwnerEmail);
    expect(s.tournaments.map((t) => t.id), ['legacy_t']);
    expect(s.teams.map((t) => t.id), ['legacy_team']);
    // Legacy keys are gone afterwards.
    expect(prefs.getString('cricscore_tournaments_v1'), isNull);
    expect(prefs.getString('cricscore_teams_v1'), isNull);

    // A second account finds nothing to claim and starts empty.
    await s.activateAccount('uid_other', email: 'someone@else.com');
    expect(s.tournaments, isEmpty);
    expect(s.teams, isEmpty);
  });

  test('a non-owner account never claims legacy data; keys survive',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cricscore_tournaments_v1',
      jsonEncode([
        Tournament(id: 'legacy_t', name: 'Super Sixty League').toJson(),
      ]),
    );
    await prefs.setString(
      'cricscore_teams_v1',
      jsonEncode([Team(id: 'legacy_team', name: 'Legacy XI').toJson()]),
    );

    final s = Store();
    // Another person's email login: starts empty, claims nothing…
    await s.activateAccount('uid_fan', email: 'fan@example.com');
    expect(s.tournaments, isEmpty);
    expect(s.teams, isEmpty);
    // …and the legacy keys are still there for the owner.
    expect(prefs.getString('cricscore_tournaments_v1'), isNotNull);
    expect(prefs.getString('cricscore_teams_v1'), isNotNull);

    // A phone login carries no email: also never claims.
    await s.activateAccount('uid_phone');
    expect(s.tournaments, isEmpty);
    expect(prefs.getString('cricscore_tournaments_v1'), isNotNull);

    // The direct call without the owner email refuses too.
    expect(await s.claimLegacyData('uid_owner'), isFalse);
    expect(
        await s.claimLegacyData('uid_owner', email: 'fan@example.com'),
        isFalse);
    expect(prefs.getString('cricscore_tournaments_v1'), isNotNull);

    // The owner can still claim afterwards on the same phone.
    await s.activateAccount('uid_owner', email: kOwnerEmail);
    expect(s.tournaments.map((t) => t.id), ['legacy_t']);
    expect(s.teams.map((t) => t.id), ['legacy_team']);
    expect(prefs.getString('cricscore_tournaments_v1'), isNull);
  });

  test('an account with its own data is never overwritten by a claim',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();
    await s.activateIdentity('uid_owner');
    await s.upsertTournament(Tournament(id: 'owner_t', name: 'Owner League'));

    // Legacy keys appear afterwards (e.g. written by an older build
    // still installed on the device): the claim must not touch the
    // account's existing scope.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cricscore_tournaments_v1',
      jsonEncode([
        Tournament(id: 'legacy_t', name: 'Super Sixty League').toJson(),
      ]),
    );
    final claimed =
        await s.claimLegacyData('uid_owner', email: kOwnerEmail);
    expect(claimed, isFalse);
    await s.activateIdentity('uid_owner');
    expect(s.tournaments.map((t) => t.id), ['owner_t']);
  });

  test('user codes are deterministic, well-formed and uid-specific', () {
    final code = userCodeForUid('uid_owner');
    expect(code, matches(RegExp(r'^60S-[0-9A-Z]{6}$')));
    expect(userCodeForUid('uid_owner'), code);
    expect(userCodeForUid('uid_other'), isNot(code));
  });

  test('account activation creates a profile in the account scope only',
      () async {
    SharedPreferences.setMockInitialValues({});
    final s = Store();

    // Guests never get a profile.
    await s.activateIdentity('guest');
    expect(s.profile, isNull);

    await s.activateAccount(
      'uid_pro',
      email: 'pro@example.com',
      displayName: 'Pro Scorer',
    );
    expect(s.profile, isNotNull);
    expect(s.profile!.displayName, 'Pro Scorer');
    expect(s.profile!.contact, 'pro@example.com');
    expect(s.profile!.userCode, userCodeForUid('uid_pro'));

    // The profile is per-account: another account gets its own, and
    // switching back restores the first account's profile untouched.
    await s.activateAccount('uid_two', email: 'two@example.com');
    expect(s.profile!.userCode, userCodeForUid('uid_two'));
    expect(s.profile!.displayName, 'two'); // email-prefix fallback
    await s.activateIdentity('uid_pro');
    expect(s.profile!.displayName, 'Pro Scorer');

    // Phone accounts: no email/display name — neutral fallback name.
    await s.activateAccount('uid_phone', phoneNumber: '+923001234567');
    expect(s.profile!.displayName, 'Player');
    expect(s.profile!.contact, '+923001234567');
  });
}
