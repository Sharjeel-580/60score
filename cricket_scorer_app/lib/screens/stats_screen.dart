import 'package:flutter/material.dart';

import '../models.dart';
import '../scoring.dart';
import '../store.dart';
import '../theme.dart';
import '../tournament_engine.dart';
import 'settings_screen.dart';
import 'tournament_stats.dart';

Map<String, CareerStats> careerOf(Store store) {
  final map = computeCareerStats(store.matches);
  applyManualStats(map, store.manualStats);
  return map;
}

/// All known persons (team squads + registered players), id -> name.
Map<String, String> allPersons(Store store) {
  final map = <String, String>{};
  for (final t in store.teams) {
    for (final p in t.players) {
      map[p.id] = p.name;
    }
  }
  for (final r in store.regPlayers) {
    map[r.id] = r.name;
  }
  return map;
}

/// One stat column in a leaderboard row: header label + value getter.
class _StatCol {
  final String label;
  final String Function(CareerStats c) value;
  const _StatCol(this.label, this.value);
}

/// Team id of a squad player, '' when the player is not in any squad.
String _playerTeamId(Store store, String playerId) {
  for (final t in store.teams) {
    if (t.players.any((p) => p.id == playerId)) return t.id;
  }
  return '';
}

/// Team name of a squad player, '' when the player is not in any squad.
String _playerTeamName(Store store, String playerId) {
  for (final t in store.teams) {
    if (t.players.any((p) => p.id == playerId)) return t.name;
  }
  return '';
}

/// First letters of the first two words, uppercased ("MA Kings" -> "MK").
String _initials(String name) {
  final parts = name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) return '?';
  return parts.map((w) => w[0].toUpperCase()).join();
}

/// Rank badge: gold for 1, silver for 2, bronze for 3.
Widget _rankCircle(int rank) {
  Color bg;
  var fg = kNavyDeep;
  if (rank == 1) {
    bg = kGold;
  } else if (rank == 2) {
    bg = kSilver;
  } else if (rank == 3) {
    bg = kCopper;
  } else {
    bg = kPanel2;
    fg = kSilver;
  }
  return Container(
    width: 26,
    height: 26,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: bg,
      border: rank > 3
          ? Border.all(color: kCyan.withValues(alpha: 0.3))
          : null,
    ),
    child: Text(
      '$rank',
      style: TextStyle(
        color: fg,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  );
}

/// One tappable leaderboard row: rank, team avatar, name + team, stat
/// columns, chevron -> player profile (existing screen).
Widget _leaderboardRow(
  BuildContext context,
  Store store,
  int rank,
  CareerStats c,
  List<_StatCol> columns,
) {
  final persons = allPersons(store);
  final name = persons[c.playerId] ?? store.playerName(c.playerId);
  final team = _playerTeamName(store, c.playerId);
  return InkWell(
    onTap: () => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PlayerProfileScreen(store: store, playerId: c.playerId),
      ),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          _rankCircle(rank),
          const SizedBox(width: 8),
          TeamAvatar(team.isNotEmpty ? team : name, radius: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: kWhite,
                  ),
                ),
                if (team.isNotEmpty)
                  Text(
                    team,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: kSilver, fontSize: 11),
                  ),
              ],
            ),
          ),
          for (final col in columns)
            SizedBox(
              width: 40,
              child: Column(
                children: [
                  Text(
                    col.label,
                    style: const TextStyle(color: kSilver, fontSize: 9.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    col.value(c),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: kWhite,
                    ),
                  ),
                ],
              ),
            ),
          const Icon(Icons.chevron_right, color: kSilver, size: 18),
        ],
      ),
    ),
  );
}

class StatsScreen extends StatefulWidget {
  final Store store;
  final VoidCallback onOpenDrawer;
  const StatsScreen({
    super.key,
    required this.store,
    required this.onOpenDrawer,
  });

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  Store get store => widget.store;

  // Filters.
  String? _tournamentId;
  int? _overs; // null = all formats
  String? _teamId; // null = all teams

  int _category = 0; // 0 Players, 1 Teams, 2 Tournaments
  int _subTab = 0; // 0 Top Performers, 1 Batting, 2 Bowling, 3 All Rounders, 4 Fielding
  int _teamView = 0; // 0 Points Table, 1 Team Comparison

  static const _subTabs = [
    'Top Performers',
    'Batting',
    'Bowling',
    'All Rounders',
    'Fielding',
  ];

  @override
  void initState() {
    super.initState();
    final tids = store.tournaments.map((t) => t.id).toList();
    if (tids.isNotEmpty) {
      _tournamentId = tids.first;
    }
    store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  /// Tournament filter, guarded against a stale selection.
  String? get _effectiveTournamentId {
    if (_tournamentId == null) return null;
    return store.tournaments.any((t) => t.id == _tournamentId)
        ? _tournamentId
        : null;
  }

  /// Matches after the format filter. Tournament scoping is applied inside
  /// [computeCareerStats] via its tournamentId parameter (same computation).
  List<Match> _filteredMatches() {
    if (_overs == null) return store.matches;
    return store.matches.where((m) => m.oversLimit == _overs).toList();
  }

  /// Career stats over the filtered matches (same computation as before).
  Map<String, CareerStats> _career() {
    final map = computeCareerStats(
      _filteredMatches(),
      tournamentId: _effectiveTournamentId,
    );
    applyManualStats(map, store.manualStats);
    return map;
  }

  /// Keep only players of the selected team (no-op when "All Teams").
  List<CareerStats> _inTeam(List<CareerStats> list) {
    if (_teamId == null) return list;
    return list
        .where((c) => _playerTeamId(store, c.playerId) == _teamId)
        .toList();
  }

  /// Tournament used for the points table: selected, else the first.
  Tournament? _pointsTournament() {
    final ts = store.tournaments;
    if (ts.isEmpty) return null;
    final tid = _effectiveTournamentId;
    if (tid != null) {
      for (final t in ts) {
        if (t.id == tid) return t;
      }
    }
    return ts.first;
  }

  @override
  Widget build(BuildContext context) {
    final formats = <int>{
      for (final m in store.matches) m.oversLimit,
    }.toList()
      ..sort();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            BrandedHeader(
              onMenu: widget.onOpenDrawer,
              onSettings: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(store: store),
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.bar_chart, color: kCyan, size: 32),
                const SizedBox(width: 8),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Statistics',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: kWhite,
                        ),
                      ),
                      Text(
                        'Players, Teams and Tournament Stats',
                        style: TextStyle(fontSize: 12.5, color: kSilver),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: kSilver),
                  tooltip: 'More statistics options',
                  onSelected: (v) async {
                    if (v == 'add_past') {
                      await _addOrEditPastScore(context);
                      if (mounted) setState(() {});
                    } else if (v == 'manual') {
                      _showManualEntries(context);
                    } else if (v == 'archive') {
                      _showMatchArchive(context);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'add_past',
                      child: Text('Add past scores'),
                    ),
                    PopupMenuItem(
                      value: 'manual',
                      child: Text('Past score entries (manual)'),
                    ),
                    PopupMenuItem(
                      value: 'archive',
                      child: Text('Match Archive'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            _filtersRow(formats),
            const SizedBox(height: 10),
            _categoryTabs(),
            const SizedBox(height: 4),
            if (_category == 0)
              ..._playersView()
            else if (_category == 1)
              ..._teamsView()
            else
              ..._tournamentsView(),
          ],
        ),
      ),
    );
  }

  // ------------------------------ filters ------------------------------

  Widget _filtersRow(List<int> formats) {
    return Row(
      children: [
        _filterBox<String>(
          icon: Icons.emoji_events,
          iconColor: kGold,
          value: _effectiveTournamentId,
          hint: 'Tournament',
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All Tournaments'),
            ),
            for (final t in store.tournaments)
              DropdownMenuItem<String?>(
                value: t.id,
                child: Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _tournamentId = v),
        ),
        const SizedBox(width: 8),
        _filterBox<int>(
          icon: Icons.sports_cricket,
          iconColor: kCyan,
          value: _overs,
          hint: 'Format',
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('All Formats'),
            ),
            for (final o in formats)
              DropdownMenuItem<int?>(value: o, child: Text('T$o')),
          ],
          onChanged: (v) => setState(() => _overs = v),
        ),
        const SizedBox(width: 8),
        _filterBox<String>(
          icon: Icons.groups,
          iconColor: kTeal,
          value: _teamId,
          hint: 'Team',
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('All Teams'),
            ),
            for (final t in store.teams)
              DropdownMenuItem<String?>(
                value: t.id,
                child: Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => setState(() => _teamId = v),
        ),
      ],
    );
  }

  Widget _filterBox<T>({
    required IconData icon,
    required Color iconColor,
    required T? value,
    required String hint,
    required List<DropdownMenuItem<T?>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kCyan.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<T?>(
                  value: value,
                  isExpanded: true,
                  isDense: true,
                  hint: Text(
                    hint,
                    style: const TextStyle(color: kSilver, fontSize: 12),
                  ),
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: kSilver,
                    size: 20,
                  ),
                  dropdownColor: kPanel2,
                  style: const TextStyle(
                    color: kWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  items: items,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------- category tabs ----------------------------

  Widget _categoryTabs() {
    Widget tab(String title, IconData icon, int index) {
      return Expanded(
        child: OptionCard(
          title: title,
          icon: icon,
          selected: _category == index,
          onTap: () => setState(() => _category = index),
        ),
      );
    }

    return Row(
      children: [
        tab('Players', Icons.person, 0),
        const SizedBox(width: 8),
        tab('Teams', Icons.groups, 1),
        const SizedBox(width: 8),
        tab('Tournaments', Icons.emoji_events, 2),
      ],
    );
  }

  // ------------------------------ players ------------------------------

  List<Widget> _playersView() {
    final career = _career();
    final batCols = [
      _StatCol('Runs', (c) => '${c.runs}'),
      _StatCol('Inns', (c) => '${c.inningsBatted}'),
      _StatCol('Avg', (c) => c.battingAverage.toStringAsFixed(1)),
      _StatCol('SR', (c) => c.battingSR.toStringAsFixed(1)),
    ];
    final bowlCols = [
      _StatCol('Wkts', (c) => '${c.wickets}'),
      _StatCol('Overs', (c) => oversText(c.ballsBowled, 6)),
      _StatCol('Econ', (c) => c.economy.toStringAsFixed(1)),
      _StatCol(
        'Avg',
        (c) => c.wickets == 0 ? '-' : c.bowlingAverage.toStringAsFixed(1),
      ),
    ];
    final arCols = [
      _StatCol('Runs', (c) => '${c.runs}'),
      _StatCol('Wkts', (c) => '${c.wickets}'),
      _StatCol('MVP', (c) => c.mvpPoints.toStringAsFixed(0)),
      _StatCol('SR', (c) => c.battingSR.toStringAsFixed(1)),
    ];
    final fieldCols = [
      _StatCol('Ct', (c) => '${c.catches}'),
      _StatCol('St', (c) => '${c.stumpings}'),
      _StatCol('RO', (c) => '${c.runOuts}'),
      _StatCol('MVP', (c) => c.mvpPoints.toStringAsFixed(0)),
    ];
    final hsCols = [
      _StatCol('HS', (c) => '${c.highScore}'),
      _StatCol('Runs', (c) => '${c.runs}'),
      _StatCol('Inns', (c) => '${c.inningsBatted}'),
      _StatCol('SR', (c) => c.battingSR.toStringAsFixed(1)),
    ];
    final bestCols = [
      _StatCol('Best', (c) => c.bestFigures),
      _StatCol('Wkts', (c) => '${c.wickets}'),
      _StatCol('Econ', (c) => c.economy.toStringAsFixed(1)),
      _StatCol(
        'Avg',
        (c) => c.wickets == 0 ? '-' : c.bowlingAverage.toStringAsFixed(1),
      ),
    ];

    final byRuns = _inTeam(career.values.toList())
      ..sort((a, b) => b.runs.compareTo(a.runs));
    final byWkts = _inTeam(career.values.toList())
      ..sort((a, b) => b.wickets.compareTo(a.wickets));
    final byMVP = _inTeam(career.values.toList())
      ..sort((a, b) => b.mvpPoints.compareTo(a.mvpPoints));
    final byField = _inTeam(career.values.toList())
      ..sort(
        (a, b) => (b.catches + b.stumpings + b.runOuts)
            .compareTo(a.catches + a.stumpings + a.runOuts),
      );
    final byHS = _inTeam(career.values.toList())
      ..sort((a, b) => b.highScore.compareTo(a.highScore));
    final byBowl = _inTeam(career.values.toList())
      ..sort((a, b) {
        if (b.bestWickets != a.bestWickets) {
          return b.bestWickets.compareTo(a.bestWickets);
        }
        return a.bestRuns.compareTo(b.bestRuns);
      });

    void pushFull({
      required String title,
      required String subtitle,
      required IconData icon,
      required List<CareerStats> leaders,
      required List<_StatCol> columns,
    }) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _FullLeaderboardScreen(
            store: store,
            title: title,
            subtitle: subtitle,
            icon: icon,
            leaders: leaders,
            columns: columns,
          ),
        ),
      );
    }

    final out = <Widget>[_subTabsRow(), const SizedBox(height: 2)];
    if (_subTab == 0) {
      out.add(
        _leaderCard(
          icon: Icons.sports_cricket,
          iconColor: kGold,
          title: 'Top Batsmen',
          subtitle: 'Most Runs',
          leaders: byRuns.where((c) => c.runs > 0).take(5).toList(),
          columns: batCols,
          onViewAll: () => pushFull(
            title: 'Top Batsmen',
            subtitle: 'Most Runs',
            icon: Icons.sports_cricket,
            leaders: byRuns.where((c) => c.runs > 0).toList(),
            columns: batCols,
          ),
        ),
      );
      out.add(
        _leaderCard(
          icon: Icons.sports_baseball,
          iconColor: kCyan,
          title: 'Top Bowlers',
          subtitle: 'Most Wickets',
          leaders: byWkts.where((c) => c.wickets > 0).take(5).toList(),
          columns: bowlCols,
          onViewAll: () => pushFull(
            title: 'Top Bowlers',
            subtitle: 'Most Wickets',
            icon: Icons.sports_baseball,
            leaders: byWkts.where((c) => c.wickets > 0).toList(),
            columns: bowlCols,
          ),
        ),
      );
    } else if (_subTab == 1) {
      out.add(
        _leaderCard(
          icon: Icons.sports_cricket,
          iconColor: kGold,
          title: 'Top Batsmen',
          subtitle: 'Most Runs',
          leaders: byRuns.where((c) => c.runs > 0).take(10).toList(),
          columns: batCols,
          onViewAll: () => pushFull(
            title: 'Top Batsmen',
            subtitle: 'Most Runs',
            icon: Icons.sports_cricket,
            leaders: byRuns.where((c) => c.runs > 0).toList(),
            columns: batCols,
          ),
        ),
      );
    } else if (_subTab == 2) {
      out.add(
        _leaderCard(
          icon: Icons.sports_baseball,
          iconColor: kCyan,
          title: 'Top Bowlers',
          subtitle: 'Most Wickets',
          leaders: byWkts.where((c) => c.wickets > 0).take(10).toList(),
          columns: bowlCols,
          onViewAll: () => pushFull(
            title: 'Top Bowlers',
            subtitle: 'Most Wickets',
            icon: Icons.sports_baseball,
            leaders: byWkts.where((c) => c.wickets > 0).toList(),
            columns: bowlCols,
          ),
        ),
      );
    } else if (_subTab == 3) {
      final ars = byMVP
          .where((c) => c.runs > 0 && c.wickets > 0)
          .toList();
      out.add(
        _leaderCard(
          icon: Icons.star,
          iconColor: kGold,
          title: 'Top All Rounders',
          subtitle: 'MVP Points',
          leaders: ars.take(10).toList(),
          columns: arCols,
          onViewAll: () => pushFull(
            title: 'Top All Rounders',
            subtitle: 'MVP Points',
            icon: Icons.star,
            leaders: ars,
            columns: arCols,
          ),
        ),
      );
    } else {
      final fielders = byField
          .where((c) => c.catches + c.stumpings + c.runOuts > 0)
          .toList();
      out.add(
        _leaderCard(
          icon: Icons.sports_handball,
          iconColor: kCyan,
          title: 'Top Fielders',
          subtitle: 'Most Dismissals',
          leaders: fielders.take(10).toList(),
          columns: fieldCols,
          onViewAll: () => pushFull(
            title: 'Top Fielders',
            subtitle: 'Most Dismissals',
            icon: Icons.sports_handball,
            leaders: fielders,
            columns: fieldCols,
          ),
        ),
      );
    }
    out.add(_teamStatsSection());
    out.add(
      _moreStatsSection(
        byHS: byHS,
        byBowl: byBowl,
        hsCols: hsCols,
        bestCols: bestCols,
      ),
    );
    return out;
  }

  Widget _subTabsRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (int i = 0; i < _subTabs.length; i++)
            Padding(
              padding: EdgeInsets.only(
                right: i == _subTabs.length - 1 ? 0 : 8,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => _subTab = i),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: _subTab == i
                        ? const LinearGradient(
                            colors: [kCyan, kTealDark],
                          )
                        : null,
                    color: _subTab == i ? null : kPanel2,
                    border: Border.all(
                      color: _subTab == i
                          ? kCyan
                          : kCyan.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _subTabs[i],
                    style: TextStyle(
                      color: _subTab == i ? kNavyDeep : kSilver,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _leaderCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required List<CareerStats> leaders,
    required List<_StatCol> columns,
    required VoidCallback onViewAll,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kCyan.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: kWhite,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: kSilver,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              ViewAllLink(onTap: onViewAll),
            ],
          ),
          const SizedBox(height: 2),
          if (leaders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No data yet',
                style: TextStyle(color: kSilver, fontSize: 12),
              ),
            ),
          for (int i = 0; i < leaders.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: kCyan.withValues(alpha: 0.12)),
            _leaderboardRow(context, store, i + 1, leaders[i], columns),
          ],
        ],
      ),
    );
  }

  // ---------------------------- team section ----------------------------

  Widget _teamStatsSection() {
    final t = _pointsTournament();
    final rows = t == null
        ? <PointsRow>[]
        : leaguePointsTable(t, _filteredMatches());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          icon: Icons.groups,
          title: 'Team Statistics',
          trailing: ViewAllLink(
            onTap: () => setState(() => _category = 1),
          ),
        ),
        Row(
          children: [
            _filterBox<int>(
              icon: Icons.bar_chart,
              iconColor: kGold,
              value: _teamView,
              hint: 'View',
              items: const [
                DropdownMenuItem<int?>(value: 0, child: Text('Points Table')),
                DropdownMenuItem<int?>(
                  value: 1,
                  child: Text('Team Comparison'),
                ),
              ],
              onChanged: (v) => setState(() => _teamView = v ?? 0),
            ),
            const SizedBox(width: 8),
            _filterBox<String>(
              icon: Icons.compare_arrows,
              iconColor: kCyan,
              value: null,
              hint: 'Team Comparison',
              items: const [
                DropdownMenuItem<String?>(
                  value: 'h2h',
                  child: Text('Head-to-head'),
                ),
              ],
              onChanged: (v) {
                if (v == 'h2h') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HeadToHeadScreen(store: store),
                    ),
                  );
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No team data yet',
              style: TextStyle(color: kSilver, fontSize: 12),
            ),
          )
        else
          SizedBox(
            height: 134,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: rows.length,
              itemBuilder: (_, i) => _teamCard(rows[i], i + 1),
            ),
          ),
      ],
    );
  }

  Widget _teamCard(PointsRow r, int rank) {
    final name = store.teamName(r.teamId);
    final label = _teamView == 0 ? '${r.points} PTS' : '${r.won}W ${r.lost}L';
    return Container(
      width: 96,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [kPanel2, kPanel],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(
          color: rank == 1 ? kGold : kCyan.withValues(alpha: 0.25),
          width: rank == 1 ? 1.6 : 1,
        ),
        boxShadow: rank == 1
            ? [
                BoxShadow(
                  color: kGold.withValues(alpha: 0.25),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TeamAvatar(name, radius: 24),
          const SizedBox(height: 6),
          Text(
            _initials(name),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: kWhite,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: kGold,
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------- more statistics ---------------------------

  Widget _moreStatsSection({
    required List<CareerStats> byHS,
    required List<CareerStats> byBowl,
    required List<_StatCol> hsCols,
    required List<_StatCol> bestCols,
  }) {
    final t = _pointsTournament();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(icon: Icons.pie_chart, title: 'More Statistics'),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.5,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          children: [
            _moreCard(
              icon: Icons.list_alt,
              color: const Color(0xFFB388FF),
              title: 'Detailed Stats',
              subtitle: 'Batting, Bowling, Fielding, All Rounders',
              onTap: t == null
                  ? null
                  : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              TournamentStatsTab(store: store, tournament: t),
                        ),
                      ),
            ),
            _moreCard(
              icon: Icons.star,
              color: kCyan,
              title: 'Highest Scores',
              subtitle: 'Individual & Team',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _FullLeaderboardScreen(
                    store: store,
                    title: 'Highest Scores',
                    subtitle: 'Individual & Team',
                    icon: Icons.star,
                    leaders: byHS.where((c) => c.highScore > 0).toList(),
                    columns: hsCols,
                  ),
                ),
              ),
            ),
            _moreCard(
              icon: Icons.sports_cricket,
              color: kGold,
              title: 'Best Bowling',
              subtitle: 'Figures & Economy',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _FullLeaderboardScreen(
                    store: store,
                    title: 'Best Bowling',
                    subtitle: 'Figures & Economy',
                    icon: Icons.sports_cricket,
                    leaders: byBowl.where((c) => c.bestWickets > 0).toList(),
                    columns: bestCols,
                  ),
                ),
              ),
            ),
            _moreCard(
              icon: Icons.emoji_events,
              color: kTeal,
              title: 'Records',
              subtitle: 'Tournament Records',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _RecordsScreen(
                    store: store,
                    tournamentId: _effectiveTournamentId,
                    overs: _overs,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _moreCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.28),
                color.withValues(alpha: 0.10),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: kWhite,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: kSilver,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------- teams -------------------------------

  List<Widget> _teamsView() {
    final t = _pointsTournament();
    final rows = t == null
        ? <PointsRow>[]
        : leaguePointsTable(t, _filteredMatches());
    return [
      SectionTitle(
        icon: Icons.emoji_events,
        title: 'Points Table',
        trailing: t == null
            ? null
            : Text(
                t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kSilver, fontSize: 11),
              ),
      ),
      if (rows.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'No completed matches yet',
              style: TextStyle(color: kSilver, fontSize: 13),
            ),
          ),
        ),
      for (int i = 0; i < rows.length; i++) _pointsRow(rows[i], i + 1),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => HeadToHeadScreen(store: store)),
        ),
        icon: const Icon(Icons.compare_arrows),
        label: const Text('Head-to-head'),
      ),
    ];
  }

  Widget _pointsRow(PointsRow r, int rank) {
    final name = store.teamName(r.teamId);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: rank == 1 ? kGold : kCyan.withValues(alpha: 0.2),
          width: rank == 1 ? 1.4 : 1,
        ),
      ),
      child: Row(
        children: [
          _rankCircle(rank),
          const SizedBox(width: 8),
          TeamAvatar(name, radius: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: kWhite,
                  ),
                ),
                Text(
                  'P ${r.played} • W ${r.won} • L ${r.lost} • T ${r.tied}',
                  style: const TextStyle(color: kSilver, fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${r.points} PTS',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: kGold,
                ),
              ),
              Text(
                'NRR ${r.nrr >= 0 ? '+' : ''}${r.nrr.toStringAsFixed(2)}',
                style: const TextStyle(color: kSilver, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------- tournaments -----------------------------

  List<Widget> _tournamentsView() {
    return [
      const SectionTitle(icon: Icons.emoji_events, title: 'Tournaments'),
      if (store.tournaments.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              'No tournaments yet',
              style: TextStyle(color: kSilver, fontSize: 13),
            ),
          ),
        ),
      for (final t in store.tournaments)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kCyan.withValues(alpha: 0.2)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    TournamentStatsTab(store: store, tournament: t),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.emoji_events,
                    color: kGold,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: kWhite,
                          ),
                        ),
                        Text(
                          '${t.teamIds.length} teams • ${store.matches.where((m) => m.tournamentId == t.id).length} matches${t.venue.isNotEmpty ? ' • ${t.venue}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: kSilver,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: kSilver,
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  /// Restored from the previous version: manually add a past performance
  /// for stats history (feeds careerOf via applyManualStats).
  /// Add a manual past-score entry — or, with [existing], edit one
  /// (v1.3.7: manual entries could be added and deleted but never
  /// edited). In edit mode the player is fixed (an entry belongs to
  /// its player; delete + re-add to move it) and every figure field
  /// is prefilled from the entry.
  Future<void> _addOrEditPastScore(
    BuildContext context, {
    ManualStatEntry? existing,
  }) async {
    final persons = allPersons(store);
    String? playerId =
        existing?.playerId ??
        (persons.isNotEmpty ? persons.keys.first : null);
    final nameCtrl = TextEditingController();
    final labelCtrl = TextEditingController(text: existing?.matchLabel ?? '');
    final runs = TextEditingController(text: '${existing?.runs ?? 0}');
    final balls = TextEditingController(text: '${existing?.balls ?? 0}');
    final fours = TextEditingController(text: '${existing?.fours ?? 0}');
    final sixes = TextEditingController(text: '${existing?.sixes ?? 0}');
    final wkts = TextEditingController(text: '${existing?.wickets ?? 0}');
    final conceded =
        TextEditingController(text: '${existing?.runsConceded ?? 0}');
    final ballsBowled =
        TextEditingController(text: '${existing?.ballsBowled ?? 0}');
    var notOut = existing?.notOut ?? false;
    int n(TextEditingController c) => int.tryParse(c.text) ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: Text(
            existing == null
                ? 'Add past score (manual)'
                : 'Edit past score (manual)',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (existing != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Player: ${existing.playerName}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  )
                else ...[
                  if (persons.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: playerId,
                      decoration:
                          const InputDecoration(labelText: 'Player'),
                      items: persons.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setD(() => playerId = v),
                    ),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Or type a new player name',
                    ),
                  ),
                ],
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Match label (e.g. Season 1 Final)',
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: runs,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Runs'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: balls,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Balls'),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fours,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: '4s'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: sixes,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: '6s'),
                      ),
                    ),
                  ],
                ),
                CheckboxListTile(
                  value: notOut,
                  title: const Text('Not out'),
                  onChanged: (v) => setD(() => notOut = v ?? false),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: wkts,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Wickets',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: conceded,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Runs conceded',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: ballsBowled,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Balls bowled',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      if (existing != null) {
        existing.matchLabel = labelCtrl.text.trim().isEmpty
            ? 'Past match'
            : labelCtrl.text.trim();
        existing.runs = n(runs);
        existing.balls = n(balls);
        existing.fours = n(fours);
        existing.sixes = n(sixes);
        existing.notOut = notOut;
        existing.wickets = n(wkts);
        existing.runsConceded = n(conceded);
        existing.ballsBowled = n(ballsBowled);
        await store.upsertManualStat(existing);
        return;
      }
      var id = playerId;
      var name = id != null ? (persons[id] ?? '') : '';
      if (nameCtrl.text.trim().isNotEmpty) {
        id = Store.newId('reg');
        name = nameCtrl.text.trim();
        await store.upsertRegPlayer(RegPlayer(id: id, name: name));
      }
      if (id == null) return;
      await store.addManualStat(
        ManualStatEntry(
          id: Store.newId('manual'),
          playerId: id,
          playerName: name,
          matchLabel: labelCtrl.text.trim().isEmpty
              ? 'Past match'
              : labelCtrl.text.trim(),
          dateIso: DateTime.now().toIso8601String().substring(0, 10),
          runs: n(runs),
          balls: n(balls),
          fours: n(fours),
          sixes: n(sixes),
          notOut: notOut,
          wickets: n(wkts),
          runsConceded: n(conceded),
          ballsBowled: n(ballsBowled),
        ),
      );
    }
  }

  /// Restored from the previous version: list + delete manual entries.
  void _showManualEntries(BuildContext context) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Past score entries (manual)'),
        content: SizedBox(
          width: double.maxFinite,
          child: store.manualStats.isEmpty
              ? const Text(
                  'No manual entries. Use "Add past scores" to bring in old performances.',
                  style: TextStyle(color: Colors.white54),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: store.manualStats.length,
                  itemBuilder: (_, i) {
                    final e = store.manualStats[i];
                    return ListTile(
                      dense: true,
                      title: Text('${e.playerName} — ${e.matchLabel}'),
                      subtitle: Text(
                        '${e.runs} (${e.balls}) • ${e.wickets} wkts • ${e.runsConceded} conceded • manual entry',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit entry',
                            onPressed: () async {
                              Navigator.pop(c);
                              await _addOrEditPastScore(
                                context,
                                existing: e,
                              );
                              if (context.mounted) {
                                _showManualEntries(context);
                                setState(() {});
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Delete entry',
                            onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (d) => AlertDialog(
                              title: const Text('Delete entry?'),
                              content: Text(
                                'Delete the manual entry for ${e.playerName}?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(d, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(d, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await store.deleteManualStat(e.id);
                            if (context.mounted) {
                              Navigator.pop(c);
                              _showManualEntries(context);
                              setState(() {});
                            }
                          }
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Restored from the previous version: completed-matches archive.
  void _showMatchArchive(BuildContext context) {
    final archive = store.matches
        .where((m) => m.status == 'completed')
        .toList()
      ..sort((a, b) => b.dateIso.compareTo(a.dateIso));
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Match Archive'),
        content: SizedBox(
          width: double.maxFinite,
          child: archive.isEmpty
              ? const Text(
                  'No completed matches yet.',
                  style: TextStyle(color: Colors.white54),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: archive.length,
                  itemBuilder: (_, i) {
                    final m = archive[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${store.teamName(m.teamAId)} vs ${store.teamName(m.teamBId)}',
                      ),
                      subtitle: Text(
                        m.resultText.isNotEmpty
                            ? m.resultText
                            : '${m.dateIso} • ${m.status}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (d) => AlertDialog(
                              title: const Text('Delete match?'),
                              content: const Text(
                                'Delete this match and its scorecard? This cannot be undone.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(d, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(d, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await store.deleteMatch(m.id);
                            if (context.mounted) {
                              Navigator.pop(c);
                              _showMatchArchive(context);
                              setState(() {});
                            }
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Full leaderboard screen: every row from an existing computed list.
class _FullLeaderboardScreen extends StatelessWidget {
  final Store store;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<CareerStats> leaders;
  final List<_StatCol> columns;
  const _FullLeaderboardScreen({
    required this.store,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.leaders,
    required this.columns,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(icon, color: kGold, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.normal,
                      color: kSilver,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: leaders.isEmpty
          ? const Center(
              child: Text(
                'No data yet',
                style: TextStyle(color: kSilver),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: leaders.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: kCyan.withValues(alpha: 0.12)),
              itemBuilder: (c, i) =>
                  _leaderboardRow(c, store, i + 1, leaders[i], columns),
            ),
    );
  }
}

/// Tournament records screen, built on the existing record computations
/// (fastestMilestones, inningsPowerLeaders, bestPartnerships).
class _RecordsScreen extends StatelessWidget {
  final Store store;
  final String? tournamentId;
  final int? overs;
  const _RecordsScreen({
    required this.store,
    this.tournamentId,
    this.overs,
  });

  @override
  Widget build(BuildContext context) {
    final ms = overs == null
        ? store.matches
        : store.matches.where((m) => m.oversLimit == overs).toList();
    final fastest = fastestMilestones(ms, tournamentId: tournamentId);
    final power = inningsPowerLeaders(ms, tournamentId: tournamentId);
    final parts = bestPartnerships(ms, tournamentId: tournamentId);
    final persons = allPersons(store);
    String nameOf(String id) => persons[id] ?? store.playerName(id);

    Widget playerRow(int rank, String pid, String primary, String secondary) {
      final name = nameOf(pid);
      final team = _playerTeamName(store, pid);
      return InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PlayerProfileScreen(store: store, playerId: pid),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              _rankCircle(rank),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: kWhite,
                        fontSize: 14,
                      ),
                    ),
                    if (team.isNotEmpty)
                      Text(
                        team,
                        style: const TextStyle(
                          color: kSilver,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    primary,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: kGold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    secondary,
                    style: const TextStyle(
                      color: kSilver,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const Icon(Icons.chevron_right, color: kSilver, size: 18),
            ],
          ),
        ),
      );
    }

    Widget section(String title, IconData icon, List<Widget> rows) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kCyan.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: kGold, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: kWhite,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No records yet',
                  style: TextStyle(color: kSilver, fontSize: 12),
                ),
              ),
            ...rows,
          ],
        ),
      );
    }

    final fifties = fastest.fifties.take(10).toList();
    final hundreds = fastest.hundreds.take(10).toList();
    final sixes = power.sixes.take(10).toList();
    final fours = power.fours.take(10).toList();
    final partnerships = parts.take(10).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Records')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          section(
            'Fastest Fifty',
            Icons.bolt,
            [
              for (int i = 0; i < fifties.length; i++)
                playerRow(
                  i + 1,
                  fifties[i].playerId,
                  '${fifties[i].balls} balls',
                  '${fifties[i].runs} runs',
                ),
            ],
          ),
          section(
            'Fastest Hundred',
            Icons.bolt,
            [
              for (int i = 0; i < hundreds.length; i++)
                playerRow(
                  i + 1,
                  hundreds[i].playerId,
                  '${hundreds[i].balls} balls',
                  '${hundreds[i].runs} runs',
                ),
            ],
          ),
          section(
            'Best Partnerships',
            Icons.handshake,
            [
              for (int i = 0; i < partnerships.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      _rankCircle(i + 1),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${nameOf(partnerships[i].batter1Id)} & ${nameOf(partnerships[i].batter2Id)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: kWhite,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${partnerships[i].runs}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: kGold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            '${partnerships[i].balls} balls',
                            style: const TextStyle(
                              color: kSilver,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
          section(
            'Most Sixes in an Innings',
            Icons.rocket_launch,
            [
              for (int i = 0; i < sixes.length; i++)
                playerRow(
                  i + 1,
                  sixes[i].playerId,
                  '${sixes[i].count} sixes',
                  '${sixes[i].runs} runs',
                ),
            ],
          ),
          section(
            'Most Fours in an Innings',
            Icons.rocket_launch,
            [
              for (int i = 0; i < fours.length; i++)
                playerRow(
                  i + 1,
                  fours[i].playerId,
                  '${fours[i].count} fours',
                  '${fours[i].runs} runs',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class PlayerProfileScreen extends StatelessWidget {
  final Store store;
  final String playerId;
  const PlayerProfileScreen({
    super.key,
    required this.store,
    required this.playerId,
  });

  @override
  Widget build(BuildContext context) {
    final career = careerOf(store);
    final c = career[playerId] ?? CareerStats(playerId);
    final reg = store.regById(playerId);
    final manual = store.manualStats.where((e) => e.playerId == playerId);
    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: const TextStyle(color: Colors.white70)),
          ),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(store.playerName(playerId))),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          if (reg != null)
            Text(
              '${reg.role} • ${reg.battingStyle} bat • ${reg.bowlingStyle}'
              '${reg.area.isNotEmpty ? ' • ${reg.area}' : ''}'
              '${reg.age > 0 ? ' • Age ${reg.age}' : ''}'
              '${reg.category.isNotEmpty ? ' • ${reg.category}' : ''}',
              style: const TextStyle(color: Colors.white70),
            ),
          const SizedBox(height: 8),
          const Text(
            'Batting',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: kCyan,
            ),
          ),
          row('Matches', '${c.matches}'),
          row('Innings', '${c.inningsBatted}'),
          row('Runs', '${c.runs}'),
          row('Balls faced', '${c.ballsFaced}'),
          row('High score', '${c.highScore}'),
          row('Average', c.battingAverage.toStringAsFixed(2)),
          row('Strike rate', c.battingSR.toStringAsFixed(1)),
          row('50s / 100s', '${c.fifties} / ${c.hundreds}'),
          row('4s / 6s', '${c.fours} / ${c.sixes}'),
          row('Not outs', '${c.notOuts}'),
          const Divider(height: 24),
          const Text(
            'Bowling',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: kCyan,
            ),
          ),
          row('Balls bowled', '${c.ballsBowled}'),
          row('Overs', oversText(c.ballsBowled, 6)),
          row('Runs conceded', '${c.runsConceded}'),
          row('Wickets', '${c.wickets}'),
          row(
            'Average',
            c.wickets == 0 ? '-' : c.bowlingAverage.toStringAsFixed(2),
          ),
          row('Economy', c.economy.toStringAsFixed(2)),
          row(
            'Strike rate',
            c.wickets == 0 ? '-' : c.bowlingSR.toStringAsFixed(1),
          ),
          row('Best figures', c.bestFigures),
          const Divider(height: 24),
          const Text(
            'Fielding & MVP',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: kCyan,
            ),
          ),
          row('Catches', '${c.catches}'),
          row('Stumpings', '${c.stumpings}'),
          row('Run outs', '${c.runOuts}'),
          row('MVP points', c.mvpPoints.toStringAsFixed(0)),
          if (manual.isNotEmpty) ...[
            const Divider(height: 24),
            const Text(
              'Manual past-score entries',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: kCopper,
              ),
            ),
            for (final e in manual)
              ListTile(
                dense: true,
                title: Text(e.matchLabel),
                subtitle: Text(
                  '${e.runs} (${e.balls}) • ${e.wickets} wkts • ${e.runsConceded} conceded',
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class CompareScreen extends StatefulWidget {
  final Store store;
  const CompareScreen({super.key, required this.store});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  String? aId;
  String? bId;

  @override
  Widget build(BuildContext context) {
    final persons = allPersons(widget.store);
    final career = careerOf(widget.store);
    aId ??= persons.isNotEmpty ? persons.keys.elementAt(0) : null;
    if (persons.length > 1) bId ??= persons.keys.elementAt(1);
    final a = aId != null ? (career[aId] ?? CareerStats(aId!)) : null;
    final b = bId != null ? (career[bId] ?? CareerStats(bId!)) : null;
    Widget picker(String label, String? value, void Function(String?) fn) {
      return DropdownButtonFormField<String>(
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: persons.entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: fn,
      );
    }

    Widget row(String label, String va, String vb) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              va,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60),
            ),
          ),
          Expanded(
            child: Text(
              vb,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Compare players')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              Expanded(
                child: picker('Player A', aId, (v) => setState(() => aId = v)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: picker('Player B', bId, (v) => setState(() => bId = v)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (a != null && b != null) ...[
            row('Matches', '${a.matches}', '${b.matches}'),
            row('Runs', '${a.runs}', '${b.runs}'),
            row('High score', '${a.highScore}', '${b.highScore}'),
            row(
              'Bat average',
              a.battingAverage.toStringAsFixed(1),
              b.battingAverage.toStringAsFixed(1),
            ),
            row(
              'Bat SR',
              a.battingSR.toStringAsFixed(1),
              b.battingSR.toStringAsFixed(1),
            ),
            row(
              '50s / 100s',
              '${a.fifties}/${a.hundreds}',
              '${b.fifties}/${b.hundreds}',
            ),
            row('Wickets', '${a.wickets}', '${b.wickets}'),
            row(
              'Economy',
              a.economy.toStringAsFixed(2),
              b.economy.toStringAsFixed(2),
            ),
            row('Best figures', a.bestFigures, b.bestFigures),
            row(
              'MVP points',
              a.mvpPoints.toStringAsFixed(0),
              b.mvpPoints.toStringAsFixed(0),
            ),
          ],
        ],
      ),
    );
  }
}

class HeadToHeadScreen extends StatefulWidget {
  final Store store;
  const HeadToHeadScreen({super.key, required this.store});

  @override
  State<HeadToHeadScreen> createState() => _HeadToHeadScreenState();
}

class _HeadToHeadScreenState extends State<HeadToHeadScreen> {
  String? aId;
  String? bId;

  @override
  Widget build(BuildContext context) {
    final teams = widget.store.teams;
    aId ??= teams.isNotEmpty ? teams[0].id : null;
    if (teams.length > 1) bId ??= teams[1].id;
    final h = (aId != null && bId != null && aId != bId)
        ? headToHead(widget.store.matches, aId!, bId!)
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Head-to-head')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: aId,
                  decoration: const InputDecoration(labelText: 'Team A'),
                  items: teams
                      .map(
                        (t) =>
                            DropdownMenuItem(value: t.id, child: Text(t.name)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => aId = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: bId,
                  decoration: const InputDecoration(labelText: 'Team B'),
                  items: teams
                      .map(
                        (t) =>
                            DropdownMenuItem(value: t.id, child: Text(t.name)),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => bId = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (h != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'Played: ${h.played}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text('${widget.store.teamName(aId!)} wins: ${h.aWins}'),
                    Text('${widget.store.teamName(bId!)} wins: ${h.bWins}'),
                    Text('Tied: ${h.tied} • No result: ${h.noResult}'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
