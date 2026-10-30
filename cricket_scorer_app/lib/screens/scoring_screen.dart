import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../debug_info.dart';
import '../dls.dart';
import '../models.dart';
import '../nav_memory.dart';
import '../nrr_calculator.dart';
import '../potm.dart';
import '../scoring.dart';
import '../store.dart';
import '../sync_service.dart';
import '../theme.dart';
import '../tts_service.dart';
import '../tournament_engine.dart';
import '../widgets/charts.dart';
import '../widgets/potm_picker.dart';
import 'scorecard_screen.dart';
import 'super_over_screen.dart';

class ScoringScreen extends StatefulWidget {
  final Store store;
  final Match match;
  const ScoringScreen({super.key, required this.store, required this.match});

  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  Store get store => widget.store;
  Match get match => widget.match;

  /// One-time voice-commentary hint: shown until dismissed once,
  /// then never again (persisted flag). The default stays OFF.
  bool _showVoiceHint = false;

  @override
  void initState() {
    super.initState();
    // Scoring guard (user design): while this screen is open, NO
    // network runs at all (v1.4.4 light version) — a push owed
    // during scoring is deferred, never dropped, and the local-only
    // close runs when scoring ends (see dispose).
    SyncService().scoringActive = true;
    // Recents resume (v1.4.5): remember this screen so a cold start
    // after an OS kill can come back here (cleared on dispose).
    NavMemory.save('scoring', match.id);
    // Feature 7 (D batch): load the persisted voice-commentary
    // setting (default OFF) so the AppBar toggle shows the truth.
    TtsService.instance.loadEnabled().then((_) {
      if (mounted) setState(() {});
    });
    SharedPreferences.getInstance().then((prefs) {
      if (prefs.getBool('voice_hint_seen') != true && mounted) {
        setState(() => _showVoiceHint = true);
      }
    });
  }

  Future<void> _dismissVoiceHint() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_hint_seen', true);
    if (mounted) setState(() => _showVoiceHint = false);
  }

  @override
  void dispose() {
    // Scoring guard: scoring closed — run the local-only close
    // (final local save, no push, no pull — v1.4.5 fully local).
    // (v1.4.4: live sync no longer exists; v1.4.5 removed the
    // close-time sync and manual sync as well.)
    if (SyncService().scoringActive) {
      SyncService().scoringActive = false;
      unawaited(SyncService().syncAfterScoring(store));
    }
    NavMemory.clear('scoring', match.id);
    super.dispose();
  }

  InningsState get inn {
    if (match.innings.isEmpty) startInnings(match, 1);
    return match.innings.last;
  }

  String nameOf(String id) => store.playerName(id);
  Team? teamOf(String id) => store.teamById(id);

  Future<void> _afterChange() async {
    final wasLive = match.status == 'live';
    try {
      computeResult(match, store.teamName);
      // Smoothness (v1.4.3): per ball, only the matches key is
      // written — teams/photos and everything else are untouched
      // by a ball, so re-encoding them per ball was pure load.
      // v1.4.5 action feedback: per-ball SUCCESS stays silent, but
      // a failed save must surface (persist returns false instead
      // of throwing now, so the catch below would never see it).
      final saved = await store.persistMatchesOnly();
      if (!saved) {
        DebugInfo.record('Ball save failed', StackTrace.current);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ball could not be saved — try again.'),
            ),
          );
        }
      }
      await _runPlayoffUpdate();
    } catch (e, st) {
      // Silent-close guard: _afterChange runs inside _record,
      // which every ball button calls WITHOUT await — a throw
      // here used to be an unhandled async error that killed the
      // app with no dialog. Record it for the debug screen and
      // keep the UI on the last good state instead — and tell the
      // user, so a failed update is never silent.
      DebugInfo.record(e, st);
      debugPrint('Scoring _afterChange failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scoring update failed — try again.'),
          ),
        );
      }
    }
    // Scoring guard: scoring ends when the match leaves live
    // status — run the local-only close (final save, no network).
    // Undo after completion returns the match to live, which
    // re-arms the guard for the resumed scoring.
    if (wasLive && match.status != 'live') {
      SyncService().scoringActive = false;
      unawaited(SyncService().syncAfterScoring(store));
    } else if (!wasLive && match.status == 'live') {
      SyncService().scoringActive = true;
    }
    if (mounted) setState(() {});
  }

  /// Recompute playoff qualification/seeding after any scoring change.
  /// The engine is idempotent and only persists when something changed.
  /// Consequential corrections (after qualification was locked) ask for
  /// explicit confirmation instead of being applied silently.
  Future<void> _runPlayoffUpdate() async {
    final tid = match.tournamentId;
    if (tid == null) return;
    final update = await applyPlayoffUpdate(store, tid);
    if (update.needsConfirmation && mounted) {
      final apply = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Playoff reseeding needed'),
          content: Text(update.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep current'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      );
      if (apply == true && mounted) {
        await applyPlayoffUpdate(store, tid, force: true);
      }
    }
  }

  // ---------- dialogs ----------

  /// Player picker. Returns the index into the filtered list, or -1
  /// when the "Add new player" tile was tapped (only when
  /// [addNewTeamId] is given: the scoring pickers offer it, the
  /// dismissal pickers do not).
  Future<int?> _pickPlayer(
    String title,
    List<String> ids, {
    String? excludeId,
    String? addNewTeamId,
  }) async {
    final list = ids.where((id) => id != excludeId).toList();
    final hasAdd = addNewTeamId != null;
    return showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: list.length + (hasAdd ? 1 : 0),
            itemBuilder: (c, i) {
              if (i == list.length) {
                return ListTile(
                  leading: const Icon(Icons.person_add, color: kGold),
                  title: const Text('Add new player…'),
                  onTap: () => Navigator.pop(c, -1),
                );
              }
              return ListTile(
                title: Text(nameOf(list[i])),
                onTap: () => Navigator.pop(c, i),
              );
            },
          ),
        ),
      ),
    ).then(
      (idx) => idx == null || idx < 0 ? idx : list.indexOf(list[idx]),
    );
  }

  /// Ask for a name and add the player to [teamId]'s squad (if new)
  /// and to this match's XI (11-player cap). Returns the player id,
  /// or null when cancelled / XI full.
  ///
  /// v1.4.8: a name already in the squad is REUSED, never re-minted
  /// (duplicate identity: batting under the squad id, bowling under
  /// the fresh id). Only a new or ambiguous name mints a fresh id.
  Future<String?> _addNewPlayerToXi(String teamId) async {
    final team = teamOf(teamId);
    if (team == null) return null;
    if (match.xiFor(teamId).length >= 11) {
      _snack('Playing XI is full (11 players).');
      return null;
    }
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Add new player — ${team.name}'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Player name',
            hintText: 'e.g. Ahmed Raza',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, nameController.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return null;
    // v1.4.8: never mint a second id for a name already in the
    // squad (duplicate identity — see uniqueSquadPlayerByName).
    final existing = uniqueSquadPlayerByName(team, name);
    if (existing != null) {
      if (match.xiFor(teamId).contains(existing.id)) return existing.id;
      if (!addToMatchXI(match, teamId, existing.id)) {
        _snack('Playing XI is full (11 players).');
        return null;
      }
      await store.persist();
      if (mounted) setState(() {});
      return existing.id;
    }
    final id = Store.newId('player');
    team.players.add(Player(id: id, name: name));
    if (!addToMatchXI(match, teamId, id)) {
      team.players.removeWhere((p) => p.id == id);
      _snack('Playing XI is full (11 players).');
      return null;
    }
    // Full save required here: this adds a player to the TEAM and to
    // the match XI — two collections (teams + matches) — so neither
    // granular persist alone covers it.
    await store.persist();
    if (mounted) setState(() {});
    return id;
  }

  Future<void> _chooseOpeners() async {
    final battingXI = inn.battingXI;
    final bowlingXI = inn.bowlingXI;
    String? striker = battingXI.isNotEmpty ? battingXI[0] : null;
    String? nonStriker = battingXI.length > 1 ? battingXI[1] : null;
    String? bowler = bowlingXI.isNotEmpty ? bowlingXI[0] : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('Openers & first bowler'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fresh XI lists on every rebuild: a player added
              // mid-dialog appears in the dropdowns at once.
              _playerDropdown(
                'Striker',
                inn.battingXI,
                striker,
                (v) => setD(() => striker = v),
              ),
              _playerDropdown(
                'Non-striker',
                inn.battingXI,
                nonStriker,
                (v) => setD(() => nonStriker = v),
              ),
              _playerDropdown(
                'Bowler',
                inn.bowlingXI,
                bowler,
                (v) => setD(() => bowler = v),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        final id = await _addNewPlayerToXi(
                          inn.battingTeamId,
                        );
                        if (id != null) setD(() {});
                      },
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text('Add new batter'),
                    ),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () async {
                        final id = await _addNewPlayerToXi(
                          inn.bowlingTeamId,
                        );
                        if (id != null) setD(() {});
                      },
                      icon: const Icon(Icons.person_add, size: 18),
                      label: const Text('Add new bowler'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && striker != null && nonStriker != null && bowler != null) {
      if (striker == nonStriker) {
        _snack('Striker and non-striker must be different');
        return;
      }
      setOpeners(inn, striker!, nonStriker!, bowler!);
      await _afterChange();
    }
  }

  Widget _playerDropdown(
    String label,
    List<String> ids,
    String? value,
    void Function(String?) onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      // Expanded + ellipsis (owner UI rule 2026-10-24): long
      // player names must never push the dropdown past the
      // dialog/screen width.
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: ids
          .map((id) => DropdownMenuItem(
                value: id,
                child: Text(
                  nameOf(id),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _chooseNextBatter() async {
    final inn = this.inn;
    final atCrease = {inn.strikerId, inn.nonStrikerId}..remove('');
    final out = inn.batting.entries
        .where((e) => e.value.out)
        .map((e) => e.key)
        .toSet();
    var available = inn.battingXI
        .where((id) => !atCrease.contains(id) && !out.contains(id))
        .toList();
    if (available.isEmpty && match.lastManStands) {
      // Last man stands: a dismissed batter may return as the partner.
      available = inn.battingXI.where((id) => !atCrease.contains(id)).toList();
    }
    final idx = await _pickPlayer(
      'Next batter',
      available,
      addNewTeamId: inn.battingTeamId,
    );
    if (idx == -1) {
      final newId = await _addNewPlayerToXi(inn.battingTeamId);
      if (newId != null) await _placeNextBatter(inn, newId);
    } else if (idx != null) {
      await _placeNextBatter(inn, available[idx]);
    }
  }

  /// Place the next batter, confirming the end after a run-out:
  /// the scorer picks whether the new batter takes strike or goes
  /// to the non-striker's end (batters crossed). Every other
  /// dismissal keeps the auto behavior (fill the empty end).
  Future<void> _placeNextBatter(InningsState inn, String playerId) async {
    final last = inn.events.isNotEmpty ? inn.events.last : null;
    final runOut = last != null && last.isWicket && last.wicketType == 'runOut';
    if (runOut) {
      final toNonStrikerEnd = await _askRunOutEnd();
      if (toNonStrikerEnd == null) return; // dismissed: place nothing
      if (toNonStrikerEnd) {
        if (inn.nonStrikerId.isNotEmpty) {
          // Not-out batter moves to strike; new batter takes his end.
          inn.strikerId = inn.nonStrikerId;
          inn.nonStrikerId = '';
        }
      } else if (inn.strikerId.isNotEmpty && inn.nonStrikerId.isEmpty) {
        // New batter on strike (e.g. after a last-ball run-out the
        // ends already swapped): move the not-out batter across.
        inn.nonStrikerId = inn.strikerId;
        inn.strikerId = '';
      }
    }
    setNextBatter(inn, playerId);
    await _afterChange();
  }

  /// Run-out end confirm: null when the dialog is dismissed.
  Future<bool?> _askRunOutEnd() {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Run out — new batter?'),
        content: const Text(
          'Is the new batter on strike, or at the non-striker end '
          '(batters crossed before the run out)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('On strike'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Non-striker end'),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseBowler({String title = 'Bowler for next over'}) async {
    final inn = this.inn;
    final available = inn.bowlingXI
        .where((id) => id != inn.lastBowlerId)
        .toList();
    final idx = await _pickPlayer(
      title,
      available,
      addNewTeamId: inn.bowlingTeamId,
    );
    if (idx == -1) {
      final newId = await _addNewPlayerToXi(inn.bowlingTeamId);
      if (newId != null) {
        if (!setBowler(inn, newId)) {
          _snack('That bowler bowled the previous over');
          return;
        }
        await _afterChange();
      }
    } else if (idx != null) {
      if (!setBowler(inn, available[idx])) {
        _snack('That bowler bowled the previous over');
        return;
      }
      await _afterChange();
    }
  }

  /// Events of the over currently in progress: every event recorded
  /// after the last completed over boundary.
  List<BallEvent> _currentOverEvents(InningsState inn) {
    final bpo = inn.ballsPerOver;
    if (bpo <= 0) return const [];
    final threshold = inn.legalBalls - (inn.legalBalls % bpo);
    var legalBefore = 0;
    final out = <BallEvent>[];
    for (final e in inn.events) {
      if (legalBefore >= threshold) out.add(e);
      if (e.legalBall) legalBefore++;
    }
    return out;
  }

  /// The bowler may only be corrected while the current over has
  /// not started: a bowler is picked but no ball of his over has
  /// been bowled yet. Once any event of the over exists, the bowler
  /// is locked and undo is the correction path.
  bool _canChangeBowler(InningsState inn) =>
      match.status == 'live' &&
      !inn.isComplete &&
      !inn.awaitingBowler &&
      inn.currentBowlerId.isNotEmpty &&
      _currentOverEvents(inn).isEmpty;

  /// Re-open the bowler picker to correct a wrong pick. A bowler
  /// who never bowled a ball leaves no empty figure row behind.
  Future<void> _changeBowler() async {
    final inn = this.inn;
    final previous = inn.currentBowlerId;
    final oldFig = inn.bowling[previous];
    await _chooseBowler(title: 'Change bowler');
    if (inn.currentBowlerId != previous &&
        oldFig != null &&
        oldFig.legalBalls == 0 &&
        oldFig.runs == 0 &&
        oldFig.wickets == 0 &&
        oldFig.wides == 0 &&
        oldFig.noBalls == 0) {
      inn.bowling.remove(previous);
      await _afterChange();
    }
  }

  Future<BallInput?> _ballDialog({
    required String title,
    int initialRuns = 0,
    bool runsEditable = true,
    List<String> wicketTypes = const [],
    String runsLabel = 'Runs',
  }) async {
    var runs = initialRuns;
    String? wicketType = wicketTypes.isEmpty ? null : null;
    String? fielder;
    var outIsStriker = true;
    final bowlingXI = inn.bowlingXI;
    return showDialog<BallInput>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (runsEditable)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        onPressed: () =>
                            setD(() => runs = runs > 0 ? runs - 1 : 0),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text(
                        '$runs',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: () => setD(() => runs++),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      // Flexible (owner UI rule 2026-10-24):
                      // labels like 'runs completed (run out)'
                      // must wrap inside the dialog, not spill.
                      Flexible(
                        child: Text(
                          runsLabel,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                if (wicketTypes.isNotEmpty) ...[
                  const Divider(),
                  DropdownButtonFormField<String?>(
                    initialValue: wicketType,
                    // Expanded + ellipsis (owner UI rule
                    // 2026-10-24): 'Obstructing the Field' etc.
                    // must fit the dialog at 360dp.
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Wicket (optional)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('No wicket'),
                      ),
                      ...wicketTypes.map(
                        (w) => DropdownMenuItem(
                          value: w,
                          child: Text(
                            w,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setD(() => wicketType = v),
                  ),
                  // Fielder selector: hidden for dismissals with
                  // no fielder choice — Bowled / LBW / Hit Wicket
                  // (bowler only), Mankad (fielder is fixed to the
                  // bowler), Retired Out, Obstructing the Field,
                  // Hit the Ball Twice and Timed Out (no fielder).
                  if (wicketType != null &&
                      wicketType != 'Bowled' &&
                      wicketType != 'LBW' &&
                      wicketType != 'Hit Wicket' &&
                      wicketType != 'Mankad' &&
                      wicketType != 'Retired Out' &&
                      wicketType != 'Obstructing the Field' &&
                      wicketType != 'Hit the Ball Twice' &&
                      wicketType != 'Timed Out')
                    _playerDropdown(
                      'Fielder',
                      bowlingXI,
                      fielder,
                      (v) => setD(() => fielder = v),
                    ),
                  if (wicketType == 'Run Out' || wicketType == 'Mankad')
                    DropdownButtonFormField<bool>(
                      initialValue: outIsStriker,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Who is out?',
                      ),
                      items: const [
                        DropdownMenuItem(value: true, child: Text('Striker')),
                        DropdownMenuItem(
                          value: false,
                          child: Text('Non-striker'),
                        ),
                      ],
                      onChanged: (v) => setD(() => outIsStriker = v ?? true),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final typeMap = {
                  'Bowled': 'bowled',
                  'Caught': 'caught',
                  'LBW': 'lbw',
                  'Run Out': 'runOut',
                  'Stumped': 'stumped',
                  'Hit Wicket': 'hitWicket',
                  'Mankad': 'mankad',
                  'Retired Out': 'retiredOut',
                  'Obstructing the Field': 'obstructing',
                  'Hit the Ball Twice': 'hitTwice',
                  'Timed Out': 'timedOut',
                };
                Navigator.pop(
                  c,
                  BallInput(
                    batRuns: runs,
                    isWicket: wicketType != null,
                    wicketType: wicketType == null
                        ? ''
                        : (typeMap[wicketType] ?? ''),
                    // Mankad: the bowler is the fielder of record.
                    fielderId: wicketType == 'Mankad'
                        ? inn.currentBowlerId
                        : (fielder ?? ''),
                    outPlayerId:
                        (wicketType == 'Run Out' || wicketType == 'Mankad')
                        ? (outIsStriker ? inn.strikerId : inn.nonStrikerId)
                        : '',
                  ),
                );
              },
              child: const Text('Record ball'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _record(BallInput input) async {
    // Feature 7: capture pre-ball facts for milestone detection —
    // every scoring path on this screen funnels through _record.
    final s = inn;
    final strikerBefore = s.strikerId;
    final runsBefore =
        strikerBefore.isEmpty ? 0 : (s.batting[strikerBefore]?.runs ?? 0);
    final legalBefore = s.legalBalls;
    final ok = applyBall(s, input);
    if (!ok) {
      _snack('Ball could not be recorded');
      return;
    }
    await _afterChange();
    _speakBallEvents(input, strikerBefore, runsBefore, legalBefore);
  }

  /// Feature 7 — voice commentary: speaks (in order) a wicket
  /// call, a 50/100 milestone and the over-end summary for the
  /// ball just recorded. No-op unless the persisted TTS setting is
  /// ON; TtsService swallows all errors so scoring can never be
  /// blocked by speech.
  void _speakBallEvents(
    BallInput input,
    String strikerBefore,
    int runsBefore,
    int legalBefore,
  ) {
    final tts = TtsService.instance;
    if (!tts.enabled) return;
    final s = inn;
    final phrases = <String>[];
    if (input.isWicket && s.events.isNotEmpty) {
      phrases.add(ttsWicket(
        batsmanName: nameOf(s.events.last.outPlayerId),
        teamName: store.teamName(s.battingTeamId),
        runs: s.totalRuns,
        wickets: s.wickets,
      ));
    }
    if (strikerBefore.isNotEmpty) {
      final runsAfter = s.batting[strikerBefore]?.runs ?? 0;
      if ((runsBefore < 50 && runsAfter >= 50) ||
          (runsBefore < 100 && runsAfter >= 100)) {
        phrases.add(ttsMilestone(
          batsmanName: nameOf(strikerBefore),
          runs: runsAfter,
        ));
      }
    }
    if (s.legalBalls > legalBefore && s.legalBalls % s.ballsPerOver == 0) {
      phrases.add(ttsOverSummary(
        teamName: store.teamName(s.battingTeamId),
        runs: s.totalRuns,
        wickets: s.wickets,
        oversText: oversText(s.legalBalls, s.ballsPerOver),
        target: s.target > 0 ? s.target : null,
        ballsBowled: s.legalBalls,
        ballsTotal: s.oversLimit * s.ballsPerOver,
      ));
    }
    for (final p in phrases) {
      tts.speak(p);
    }
  }

  /// Feature 2 — Revised target (DLS): Duckworth–Lewis Standard
  /// Edition calculation for the common local cases — innings 2
  /// shortened before it starts, innings 1 terminated early, and
  /// ONE interruption during innings 2. The result can be applied
  /// as the live target of the current (second) innings; nothing
  /// is changed until the scorer taps Apply.
  Future<void> _showDlsDialog() async {
    final bpo = match.ballsPerOver;
    double? oversOf(String text) {
      final balls = ballsFromOversText(text, bpo);
      return balls == null ? null : balls / bpo;
    }

    String oversLabel(int balls) =>
        '${balls ~/ bpo}.${balls % bpo}';

    final t1Score = TextEditingController(
      text: match.innings.isNotEmpty
          ? '${match.innings[0].totalRuns}'
          : '',
    );
    final t2StartOvers = TextEditingController(
      text: match.innings.length >= 2
          ? oversLabel(
              match.innings[1].oversLimit * bpo)
          : oversLabel(match.oversLimit * bpo),
    );
    final t1OversLeft = TextEditingController(text: '0');
    final t1Wkts = TextEditingController(text: '0');
    final intAt = TextEditingController();
    final intWkts = TextEditingController(text: '0');
    final intResumed = TextEditingController();
    var t1Terminated = false;
    var hasInterruption = false;
    DlsResult? result;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) {
          Widget field(String label, TextEditingController ctl) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextField(
                  controller: ctl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: label,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
          void compute() {
            final score = int.tryParse(t1Score.text.trim());
            final t2Overs = oversOf(t2StartOvers.text);
            if (score == null || score < 0) {
              setD(() {
                error = 'Team 1 score theek se likho';
                result = null;
              });
              return;
            }
            if (t2Overs == null || t2Overs < 0) {
              setD(() {
                error = 'Innings 2 ke overs theek se likho (e.g. 6.3)';
                result = null;
              });
              return;
            }
            final startOvers = match.oversLimit.toDouble();
            var r1 = dlResourcePct(
                oversRemaining: startOvers, wicketsLost: 0);
            if (t1Terminated) {
              final left = oversOf(t1OversLeft.text);
              final wk = int.tryParse(t1Wkts.text.trim());
              if (left == null || wk == null || wk < 0 || wk > 10) {
                setD(() {
                  error = 'Innings 1 termination walay numbers theek karo';
                  result = null;
                });
                return;
              }
              r1 = resourcesForTerminatedInnings(
                oversAtStart: startOvers,
                oversRemainingAtTermination: left,
                wicketsLostAtTermination: wk,
              );
            }
            var r2 = dlResourcePct(oversRemaining: t2Overs, wicketsLost: 0);
            if (hasInterruption) {
              final at = oversOf(intAt.text);
              final resumed = oversOf(intResumed.text);
              final wk = int.tryParse(intWkts.text.trim());
              if (at == null || resumed == null || wk == null ||
                  wk < 0 || wk > 10) {
                setD(() {
                  error = 'Interruption walay numbers theek karo';
                  result = null;
                });
                return;
              }
              r2 = resourcesAfterInterruptions(
                oversAtStart: t2Overs,
                interruptions: [
                  (
                    oversAtInterruption: at,
                    wickets: wk,
                    oversAtResumption: resumed,
                  ),
                ],
              );
            }
            setD(() {
              error = null;
              result = dlsTarget(
                team1Score: score,
                team1ResourcePct: r1,
                team2ResourcePct: r2,
              );
            });
          }

          final canApply = result != null &&
              match.innings.length >= 2 &&
              match.status == 'live';
          return AlertDialog(
            title: const Text('Revised target (DLS)'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  field('Team 1 score', t1Score),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Innings 1 ended early'),
                    value: t1Terminated,
                    onChanged: (v) => setD(() => t1Terminated = v),
                  ),
                  if (t1Terminated) ...[
                    field('Overs left when innings 1 ended', t1OversLeft),
                    field('Wickets lost at that point', t1Wkts),
                  ],
                  field('Overs for innings 2 (start)', t2StartOvers),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Play stopped during innings 2'),
                    value: hasInterruption,
                    onChanged: (v) => setD(() => hasInterruption = v),
                  ),
                  if (hasInterruption) ...[
                    field('Overs left when play stopped', intAt),
                    field('Wickets lost at that point', intWkts),
                    field('Overs left when play resumed', intResumed),
                  ],
                  const Text(
                    'Duckworth–Lewis Standard Edition (G50 = 245). '
                    'Overs are written as overs.balls, e.g. 6.3.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  if (result != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Par score: ${result!.parScore.toStringAsFixed(1)}\n'
                        'Revised target: ${result!.target}\n'
                        'Resources — Team 1: '
                        '${result!.team1ResourcePct.toStringAsFixed(1)}% • '
                        'Team 2: '
                        '${result!.team2ResourcePct.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: kCyan,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Close'),
              ),
              TextButton(onPressed: compute, child: const Text('Calculate')),
              FilledButton(
                onPressed: canApply
                    ? () async {
                        inn.target = result!.target;
                        Navigator.pop(c);
                        await _afterChange();
                        _snack('Target set to ${result!.target} (DLS)');
                      }
                    : null,
                child: const Text('Apply as target'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Wagon-wheel plot dialog: the scorer taps the wheel where the ball went.
  /// Returns the normalized tap point (boundary = 1.0), Offset(0,0) when the
  /// scorer taps "Skip" (record without plotting), or null on cancel.
  Future<Offset?> _plotShotDialog(String title) {
    final diameter =
        (MediaQuery.of(context).size.width - 140).clamp(220.0, 320.0);
    return showDialog<Offset>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Wheel par tap karo — ball kidhar gayi',
              style: TextStyle(fontSize: 13, color: Colors.white60),
            ),
            const SizedBox(height: 8),
            _PlotWheel(
              diameter: diameter,
              onTap: (p) => Navigator.of(c).pop(p),
            ),
            const SizedBox(height: 8),
            const WagonLegend(),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(const Offset(0, 0)),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final inn = this.inn;
    final battingTeam = teamOf(inn.battingTeamId);
    final needsOpeners =
        inn.events.isEmpty && inn.strikerId == '' && match.status == 'live';
    final crr = inn.legalBalls == 0
        ? 0.0
        : inn.totalRuns * inn.ballsPerOver / inn.legalBalls;
    final target = inn.target;
    final needRuns = target > 0 ? target - inn.totalRuns : 0;
    final ballsLeft = inn.oversLimit * inn.ballsPerOver - inn.legalBalls;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${store.teamName(match.teamAId)} vs ${store.teamName(match.teamBId)}',
        ),
        actions: [
          IconButton(
            icon: Icon(
              TtsService.instance.enabled
                  ? Icons.volume_up
                  : Icons.volume_off,
            ),
            tooltip: 'Voice commentary (TTS)',
            onPressed: () async {
              final tts = TtsService.instance;
              await tts.setEnabled(!tts.enabled);
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo last ball',
            // Undo runs only when the stack is non-empty. Events
            // without steps (legacy data, or a restart before v1.4.5
            // persisted the stack) must never fail silently: the
            // button stays tappable so the reason can be told.
            onPressed: inn.events.isEmpty && inn.undoStack.isEmpty
                ? null
                : () async {
                    if (inn.undoStack.isEmpty) {
                      _snack('Undo is not available for this ball.');
                      return;
                    }
                    if (undoLastBall(inn)) {
                      if (match.status == 'completed') {
                        match.status = 'live';
                        match.resultText = '';
                      }
                      await _afterChange();
                    }
                  },
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final nav = Navigator.of(context);
              if (v == 'xi') {
                await _editPlayingXi();
              } else if (v == 'dls') {
                await _showDlsDialog();
              } else if (v == 'retirehurt') {
                await _retireHurt();
              } else if (v == 'retiredout') {
                await _retiredOutBetweenBalls();
              } else if (v == 'timedout') {
                await _timedOut();
              } else if (v == 'scorecard') {
                nav.push(
                  MaterialPageRoute(
                    builder: (_) => ScorecardScreen(store: store, match: match),
                  ),
                );
              } else if (v == 'noresult') {
                match.status = 'noResult';
                match.resultText = 'No result';
                // Match-only change; the playoff engine below persists
                // its own tournament changes when it has any.
                await store.persistMatchesOnly();
                // A no-result finalizes the fixture: refresh qualification.
                // (No confirmation dialog here — the screen is closing;
                // any needsConfirmation case surfaces on the next scoring
                // change or when the tournament screen re-runs the engine.)
                final tid = match.tournamentId;
                if (tid != null) await applyPlayoffUpdate(store, tid);
                nav.pop();
              } else if (v == 'endinnings') {
                // v1.4.5: end the current innings early. The flag
                // makes the innings read complete, so the existing
                // innings-break card takes over: Start 2nd innings
                // (target = this total + 1, via startInnings) for
                // the 1st innings, or the normal match-finish flow
                // for the last innings. Totals are untouched —
                // nothing is faked into the counters.
                final isFirst = match.innings.length == 1;
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('End innings?'),
                    content: Text(
                      isFirst
                          ? 'End the 1st innings now? The 2nd innings '
                              'will start chasing ${inn.totalRuns + 1}.'
                          : 'End this innings now? The match will '
                              'finish on the current totals.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('End innings'),
                      ),
                    ],
                  ),
                );
                if (confirm != true) return;
                inn.endedEarly = true;
                await _afterChange();
              } else if (v == 'delete') {
                // v1.3.7: the standard confirm — this was the one
                // delete in the app with none, on a LIVE match.
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (d) => AlertDialog(
                    title: const Text('Delete match?'),
                    content: const Text(
                      'Delete this match and its scorecard? '
                      'This cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(d, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(d, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm != true) return;
                await store.deleteMatch(match.id);
                nav.pop();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'xi', child: Text('Edit Playing XI')),
              const PopupMenuItem(
                value: 'dls',
                child: Text('Revised target (DLS)'),
              ),
              const PopupMenuItem(
                value: 'retirehurt',
                child: Text('Retire batsman (hurt)'),
              ),
              const PopupMenuItem(
                value: 'retiredout',
                child: Text('Retired Out (between balls)'),
              ),
              const PopupMenuItem(
                value: 'timedout',
                child: Text('Timed Out (batter not yet in)'),
              ),
              const PopupMenuItem(
                  value: 'scorecard', child: Text('View scorecard')),
              const PopupMenuItem(
                  value: 'noresult', child: Text('Mark no result')),
              // Only while the innings is still open — once it is
              // complete the break card already owns the flow.
              if (!inn.isComplete)
                const PopupMenuItem(
                    value: 'endinnings', child: Text('End innings')),
              const PopupMenuItem(value: 'delete', child: Text('Delete match')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_showVoiceHint)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Distinct from the AppBar speaker toggle icon,
                    // so widget tests (and users) never confuse them.
                    const Icon(Icons.record_voice_over, color: kGold),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Voice commentary is toggled by the speaker '
                        'icon above (currently off by default). It '
                        'speaks on wickets, milestones and over '
                        'summaries.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: _dismissVoiceHint,
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${battingTeam?.name ?? ''} — Innings ${match.innings.length}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${inn.totalRuns}/${inn.wickets}  (${oversText(inn.legalBalls, inn.ballsPerOver)} ov)   CRR ${crr.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: kCyan,
                    ),
                  ),
                  if (target > 0)
                    Text(
                      'Target $target • Need $needRuns off $ballsLeft balls',
                      style: const TextStyle(color: kCopper),
                    ),
                  const Divider(),
                  if (inn.strikerId.isNotEmpty)
                    _creaseRow(inn.strikerId, true, inn),
                  if (inn.nonStrikerId.isNotEmpty)
                    _creaseRow(inn.nonStrikerId, false, inn),
                  if (inn.currentBowlerId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Bowling: ${nameOf(inn.currentBowlerId)} ${_bowlerLine(inn)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  if (match.status == 'live' &&
                      !inn.isComplete &&
                      inn.strikerId.isNotEmpty &&
                      inn.nonStrikerId.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Tap a name for strike • Double-tap to change player',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  const SizedBox(height: 6),
                  _thisOverRow(inn),
                ],
              ),
            ),
          ),
          if (inn.events.isNotEmpty && match.status == 'live')
            _liveWagonCard(inn),
          // A completed innings always shows the break card, even
          // when openers were never picked (e.g. End innings tapped
          // on a fresh match) — the openers prompt on a completed
          // innings would be a dead end, since no ball can be bowled.
          if (inn.isComplete)
            _inningsBreakCard()
          else if (needsOpeners)
            FilledButton.icon(
              onPressed: _chooseOpeners,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Select openers & bowler'),
            )
          else if (match.status == 'live' &&
              inn.awaitingBatter &&
              !inn.isComplete)
            FilledButton.icon(
              onPressed: _chooseNextBatter,
              icon: const Icon(Icons.person_add),
              label: const Text('Select next batter'),
            )
          else if (match.status == 'live' &&
              inn.awaitingBowler &&
              !inn.isComplete)
            FilledButton.icon(
              onPressed: _chooseBowler,
              icon: const Icon(Icons.sports_baseball),
              label: const Text('Select bowler for next over'),
            )
          else if (match.status == 'live')
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_canChangeBowler(inn))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                      onPressed: _changeBowler,
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Change bowler'),
                    ),
                  ),
                _scoringPad(),
              ],
            ),
        ],
      ),
    );
  }

  Widget _creaseRow(String pid, bool striker, InningsState inn) {
    final f = inn.batting[pid];
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        '${nameOf(pid)}${striker ? ' *' : ''}   ${f?.runs ?? 0} (${f?.balls ?? 0})',
        style: TextStyle(
          fontWeight: striker ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
    // Crease corrections (v1.3.4): single tap on a batsman's name
    // gives him the strike; double tap replaces him at the crease
    // (e.g. the wrong opener was selected). Only while this innings
    // is being scored — a finished innings is corrected from the
    // scorecard's Edit screen instead.
    if (match.status != 'live' || inn.isComplete) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        if (setStrikeTo(inn, pid)) await _afterChange();
      },
      onDoubleTap: () => _replaceBatsman(pid),
      child: row,
    );
  }

  /// Double-tap on a batsman at the crease: pick the player who
  /// should actually be there (wrong opener selected). The
  /// replacement takes over the crease place and any figure
  /// recorded under the wrong name.
  Future<void> _replaceBatsman(String outId) async {
    final candidates = replaceBatsmanCandidates(inn, outId);
    if (candidates.isEmpty) {
      _snack('No other batter available to replace ${nameOf(outId)}');
      return;
    }
    final idx = await _pickPlayer(
      'Replace ${nameOf(outId)} with',
      candidates,
    );
    if (idx != null && replaceBatsman(inn, outId, candidates[idx])) {
      await _afterChange();
    }
  }

  /// Menu action: retire a batsman HURT (full dismissal set).
  /// Not a wicket — he may resume later via "Select next batter",
  /// which lists him again because he is not out.
  Future<void> _retireHurt() async {
    final inn = this.inn;
    if (match.status != 'live' || inn.isComplete) {
      _snack('The innings is not in play');
      return;
    }
    final atCrease = [inn.strikerId, inn.nonStrikerId]
        .where((id) => id.isNotEmpty)
        .toList();
    if (atCrease.isEmpty) {
      _snack('No batsman at the crease');
      return;
    }
    final idx = await _pickPlayer('Retire batsman (hurt)', atCrease);
    if (idx == null) return;
    if (retireBatsmanHurt(inn, atCrease[idx])) {
      await _afterChange();
    } else {
      _snack('That batsman cannot retire hurt');
    }
  }

  /// Menu action: Retired Out between balls — a wicket with no
  /// ball bowled and no bowler credit; he cannot return.
  Future<void> _retiredOutBetweenBalls() async {
    final inn = this.inn;
    if (match.status != 'live' || inn.isComplete) {
      _snack('The innings is not in play');
      return;
    }
    final atCrease = [inn.strikerId, inn.nonStrikerId]
        .where((id) => id.isNotEmpty)
        .toList();
    if (atCrease.isEmpty) {
      _snack('No batsman at the crease');
      return;
    }
    final idx = await _pickPlayer('Retired Out — who?', atCrease);
    if (idx == null) return;
    if (dismissBatsmanWithoutBall(inn, atCrease[idx], 'retiredOut')) {
      await _afterChange();
    } else {
      _snack('That batsman cannot be retired out');
    }
  }

  /// Menu action: Timed Out — a batsman who has NOT come in yet
  /// loses his wicket without a ball being bowled.
  Future<void> _timedOut() async {
    final inn = this.inn;
    if (match.status != 'live' || inn.isComplete) {
      _snack('The innings is not in play');
      return;
    }
    final candidates = inn.battingXI.where((id) {
      if (id == inn.strikerId || id == inn.nonStrikerId) return false;
      final f = inn.batting[id];
      return f == null || !f.batted;
    }).toList();
    if (candidates.isEmpty) {
      _snack('Every batter has already come in');
      return;
    }
    final idx = await _pickPlayer('Timed Out — who?', candidates);
    if (idx == null) return;
    if (dismissBatsmanWithoutBall(inn, candidates[idx], 'timedOut')) {
      await _afterChange();
    } else {
      _snack('That batsman cannot be timed out');
    }
  }

  String _bowlerLine(InningsState inn) {
    final f = inn.bowling[inn.currentBowlerId];
    if (f == null) return '';
    return '${oversText(f.legalBalls, inn.ballsPerOver)}-${f.maidens}-${f.runs}-${f.wickets}';
  }

  /// Mid-match Playing XI correction (v1.3.5): a player can join
  /// or leave either side's XI while the match is live. The two
  /// batters at the crease, the current bowler, and anyone who has
  /// already batted or bowled in this match cannot be removed —
  /// the dialog says why instead of letting the record break.
  Future<void> _editPlayingXi() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Playing XI'),
        content: SizedBox(
          width: double.maxFinite,
          child: StatefulBuilder(
            builder: (c, setD) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _liveXiTeam(setD, inn.battingTeamId),
                  const SizedBox(height: 12),
                  _liveXiTeam(setD, inn.bowlingTeamId),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _liveXiTeam(
    StateSetter setD,
    String teamId,
  ) {
    final team = teamOf(teamId);
    final xi = match.xiFor(teamId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${team?.name ?? ''} (${xi.length})',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        for (final pid in xi)
          Row(
            children: [
              Expanded(
                child: Text(
                  nameOf(pid),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                tooltip: 'Remove from Playing XI',
                onPressed: () async {
                  final block = liveXiRemovalBlock(match, inn, pid);
                  if (block != null) {
                    _snack(block);
                    return;
                  }
                  removeFromMatchXI(match, teamId, pid);
                  await _afterChange();
                  setD(() {});
                },
              ),
            ],
          ),
        TextButton.icon(
          onPressed: () async {
            if (team == null) return;
            final candidates = team.players
                .map((p) => p.id)
                .where((id) => !xi.contains(id))
                .toList();
            if (candidates.isEmpty) {
              _snack('Every squad player is already in the Playing XI.');
              return;
            }
            final idx = await _pickPlayer(
              'Add to Playing XI — ${team.name}',
              candidates,
            );
            if (idx != null) {
              if (!addToMatchXI(match, teamId, candidates[idx])) {
                _snack('Playing XI is full (11 players). '
                    'Remove a player first.');
                return;
              }
              await _afterChange();
              setD(() {});
            }
          },
          icon: const Icon(Icons.person_add, size: 18),
          label: const Text('Add player'),
        ),
      ],
    );
  }

  Widget _thisOverRow(InningsState inn) {
    final events = inn.events;
    var legal = 0;
    var start = 0;
    for (var i = 0; i < events.length; i++) {
      if (events[i].legalBall) {
        legal++;
        if (legal % inn.ballsPerOver == 1 && i > 0) start = i;
        if (legal % inn.ballsPerOver == 0) start = i + 1;
      }
    }
    final overEvents = events.sublist(start.clamp(0, events.length));
    // Wrap, not Row (owner UI rule 2026-10-24): a wide-heavy over
    // has more chips than a 360dp screen fits on one line — the
    // chips must flow to the next line instead of overflowing.
    return Wrap(
      spacing: 0,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('This over: ', style: TextStyle(color: Colors.white60)),
        ...overEvents.map(
          (e) => Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: e.isWicket
                  ? kOrangeRed
                  : (e.batRuns >= 4 && e.extraType == 'none' ? kTeal : kPanel2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(e.display, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  /// Live wagon wheel for the current striker, rebuilt after every ball.
  Widget _liveWagonCard(InningsState inn) {
    final striker = inn.strikerId;
    if (striker.isEmpty) return const SizedBox.shrink();
    final shots = wagonWheelShots(inn, striker);
    final shotCounts = <int, int>{}; // runs value -> balls (striker)
    var strikerWkts = 0;
    for (final e in inn.events) {
      if (e.strikerId != striker || e.extraType == 'wide') continue;
      if (e.isWicket && e.outPlayerId == striker) strikerWkts++;
      shotCounts[e.batRuns] = (shotCounts[e.batRuns] ?? 0) + 1;
    }
    Widget chip(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: kPanel2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
    return Card(
      child: ExpansionTile(
        // v1.2.2: the live wagon wheel starts CLOSED (was
        // initiallyExpanded: true, so it sat open from the first
        // ball and the scorer had to close it by hand). It opens
        // only when the scorer taps it. Keyed per striker so a new
        // batsman never inherits an open wheel.
        key: ValueKey('live-wagon-$striker'),
        initiallyExpanded: false,
        title: Text(
          'Wagon wheel - live (${nameOf(striker)})',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        children: [
          Center(child: WagonWheel(shots: shots)),
          const SizedBox(height: 6),
          const WagonLegend(),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final r in [1, 2, 3, 4, 6])
                chip('${r}s: ${shotCounts[r] ?? 0}'),
              chip('W: $strikerWkts'),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _inningsBreakCard() {
    final isFirst = match.innings.length == 1;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text(
              isFirst ? 'Innings break' : 'Match finished',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (isFirst)
              FilledButton.icon(
                onPressed: () async {
                  startInnings(match, 2);
                  await _afterChange();
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start 2nd innings'),
              )
            else ...[
              Text(
                computeResult(match, store.teamName),
                style: const TextStyle(color: kCyan, fontSize: 15),
              ),
              const SizedBox(height: 8),
              _momPicker(),
              if (matchIsTied(match)) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            SuperOverScreen(store: store, match: match),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.flash_on),
                  label: const Text('Play Super Over'),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  final nav = Navigator.of(context);
                  computeResult(match, store.teamName);
                  // v1.1.5: no manual POTM pick? Auto-select the
                  // highest-ranked eligible candidate (never random).
                  if (match.manOfMatchId.isEmpty) {
                    final top = potmShortlist(match, store);
                    if (top.isNotEmpty) {
                      match.manOfMatchId = top.first.playerId;
                    }
                  }
                  match.status = 'completed';
                  await store.persistMatchesOnly();
                  nav.pushReplacement(
                    MaterialPageRoute(
                      builder: (_) =>
                          ScorecardScreen(store: store, match: match),
                    ),
                  );
                },
                icon: const Icon(Icons.emoji_events),
                label: const Text('Finish & view scorecard'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Player of the Match picker (v1.1.5): opens the stat-based shortlist
  /// dialog. The old dropdown is gone; selection is saved on the match.
  Widget _momPicker() {
    final hasPick = match.manOfMatchId.isNotEmpty;
    return OutlinedButton.icon(
      onPressed: () async {
        final picked = await showPotmPickerDialog(context, store, match);
        if (picked != null && picked.isNotEmpty) {
          match.manOfMatchId = picked;
          await store.persistMatchesOnly();
          if (mounted) setState(() {});
        }
      },
      icon: const Icon(Icons.emoji_events_outlined),
      label: Text(
        hasPick
            ? 'POTM: ${nameOf(match.manOfMatchId)} (tap to change)'
            : 'Select Player of the Match',
      ),
    );
  }

  Widget _scoringPad() {
    Widget runBtn(String label, int runs) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: runs >= 4 ? kTeal : kPanel2,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () async {
            // Scoring shots: tap the wagon wheel to plot where it went.
            double? sx, sy;
            if (runs > 0) {
              final p = await _plotShotDialog('$label runs — shot plot');
              if (p == null) return; // cancelled
              if (p != const Offset(0, 0)) {
                sx = p.dx;
                sy = p.dy;
              }
            }
            _record(BallInput(batRuns: runs, shotX: sx, shotY: sy));
          },
          child: Text(label, style: const TextStyle(fontSize: 17)),
        ),
      ),
    );
    Widget extraBtn(String label, VoidCallback fn) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: fn,
          child: Text(label),
        ),
      ),
    );
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            runBtn('0', 0),
            runBtn('1', 1),
            runBtn('2', 2),
            runBtn('3', 3),
          ],
        ),
        Row(
          children: [
            runBtn('4', 4),
            runBtn('6', 6),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kPanel2,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final input = await _ballDialog(
                      title: 'Other runs',
                      runsLabel: 'runs',
                    );
                    if (input != null) {
                      _record(BallInput(batRuns: input.batRuns));
                    }
                  },
                  child: const Text('Other', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kOrangeRed,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () async {
                    final input = await _ballDialog(
                      title: 'Wicket',
                      runsEditable: true,
                      runsLabel: 'runs completed (run out)',
                      wicketTypes: const [
                        'Bowled',
                        'Caught',
                        'LBW',
                        'Run Out',
                        'Stumped',
                        'Hit Wicket',
                        'Mankad',
                        'Retired Out',
                        'Obstructing the Field',
                        'Hit the Ball Twice',
                        'Timed Out',
                      ],
                    );
                    if (input != null && input.isWicket) {
                      if (input.wicketType != 'runOut') input.batRuns = 0;
                      final p = await _plotShotDialog('Wicket — shot plot');
                      if (p == null) return;
                      if (p != const Offset(0, 0)) {
                        input.shotX = p.dx;
                        input.shotY = p.dy;
                      }
                      _record(input);
                    }
                  },
                  child: const Text('Wicket', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            extraBtn('Wide', () async {
              final input = await _ballDialog(
                title: 'Wide ball',
                runsLabel: 'extra runs beyond penalty',
                wicketTypes: const ['Stumped', 'Run Out'],
              );
              if (input != null) {
                _record(
                  BallInput(
                    extraType: 'wide',
                    extraRuns: input.batRuns,
                    isWicket: input.isWicket,
                    wicketType: input.wicketType,
                    fielderId: input.fielderId,
                    outPlayerId: input.outPlayerId,
                  ),
                );
              }
            }),
            extraBtn('No Ball', () async {
              final input = await _ballDialog(
                title: 'No ball',
                runsLabel: 'runs off the bat',
                wicketTypes: const ['Run Out'],
              );
              if (input != null) {
                _record(
                  BallInput(
                    extraType: 'noBall',
                    batRuns: input.batRuns,
                    isWicket: input.isWicket,
                    wicketType: input.wicketType,
                    fielderId: input.fielderId,
                    outPlayerId: input.outPlayerId,
                  ),
                );
              }
            }),
            extraBtn('Bye', () async {
              final input = await _ballDialog(
                title: 'Byes',
                initialRuns: 1,
                runsLabel: 'byes',
                wicketTypes: const ['Run Out'],
              );
              if (input != null) {
                _record(
                  BallInput(
                    extraType: 'bye',
                    batRuns: input.batRuns,
                    isWicket: input.isWicket,
                    wicketType: input.wicketType,
                    fielderId: input.fielderId,
                    outPlayerId: input.outPlayerId,
                  ),
                );
              }
            }),
            extraBtn('Leg Bye', () async {
              final input = await _ballDialog(
                title: 'Leg byes',
                initialRuns: 1,
                runsLabel: 'leg byes',
                wicketTypes: const ['Run Out'],
              );
              if (input != null) {
                _record(
                  BallInput(
                    extraType: 'legBye',
                    batRuns: input.batRuns,
                    isWicket: input.isWicket,
                    wicketType: input.wicketType,
                    fielderId: input.fielderId,
                    outPlayerId: input.outPlayerId,
                  ),
                );
              }
            }),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Interactive empty wagon wheel used to plot where a shot went.
/// Taps are converted to normalized coordinates (boundary = 1.0).
class _PlotWheel extends StatelessWidget {
  final double diameter;
  final ValueChanged<Offset> onTap;
  const _PlotWheel({required this.diameter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Builder(
        builder: (c) => GestureDetector(
          onTapDown: (d) {
            final box = c.findRenderObject() as RenderBox;
            final local = box.globalToLocal(d.globalPosition);
            final r = diameter / 2 - 6;
            final nx = (local.dx - diameter / 2) / r;
            final ny = (local.dy - diameter / 2) / r;
            onTap(Offset(
              nx.clamp(-1.2, 1.2).toDouble(),
              ny.clamp(-1.2, 1.2).toDouble(),
            ));
          },
          child: WagonWheel(shots: const [], diameter: diameter),
        ),
      ),
    );
  }
}
