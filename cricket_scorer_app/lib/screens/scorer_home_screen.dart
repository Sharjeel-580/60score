import 'package:flutter/material.dart';

import '../auth_service.dart';
import '../models.dart';
import '../points_table_share.dart';
import '../publish_service.dart';
import '../store.dart';
import '../theme.dart';
import '../tournament_engine.dart';
import '../widgets/player_avatar.dart';
import 'fixture_detail_screen.dart';
import 'match_setup_screen.dart';
import 'nrr_calculator_screen.dart';
import 'scorecard_screen.dart';
import 'scoring_screen.dart';
import 'settings_screen.dart';
import 'tournament_stats.dart';

// 60Score v1.1.2 Matches screen: status tabs, filters, and match cards
// matching the approved redesign reference. Real data only — every list is
// derived from store.matches plus the active tab/filters.
class ScorerHomeScreen extends StatefulWidget {
  final Store store;
  final VoidCallback onOpenDrawer;
  const ScorerHomeScreen(
      {super.key, required this.store, required this.onOpenDrawer});

  @override
  State<ScorerHomeScreen> createState() => _ScorerHomeScreenState();
}

class _ScorerHomeScreenState extends State<ScorerHomeScreen> {
  Store get store => widget.store;

  // 0 = All, 1 = Live, 2 = Upcoming, 3 = Completed.
  int _tab = 0;
  String? _tournamentId;
  String? _teamId;
  int? _overs;
  // Default order is the straight fixture sequence (v1.3.5):
  // chronological ascending — the nearest match first and the
  // Grand Final last. The filter sheet can flip it to newest-first.
  String _sort = 'oldest'; // 'newest' | 'oldest'

  @override
  void initState() {
    super.initState();
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

  bool get _hasActiveFilters =>
      _tournamentId != null || _teamId != null || _overs != null;

  bool _isLive(Match m) => m.status == 'live';

  bool _isUpcoming(Match m) =>
      m.status == 'upcoming' || m.status == 'scheduled';

  List<Match> _applyFilters(List<Match> input) {
    final list = input.where((m) {
      if (_tournamentId != null && m.tournamentId != _tournamentId) {
        return false;
      }
      if (_teamId != null &&
          m.teamAId != _teamId &&
          m.teamBId != _teamId) {
        return false;
      }
      if (_overs != null && m.oversLimit != _overs) return false;
      return true;
    }).toList();
    list.sort((a, b) {
      // Fixtures without a date always go last.
      if (a.dateIso.isEmpty && b.dateIso.isEmpty) return 0;
      if (a.dateIso.isEmpty) return 1;
      if (b.dateIso.isEmpty) return -1;
      final c = a.dateIso.compareTo(b.dateIso);
      return _sort == 'newest' ? -c : c;
    });
    return list;
  }

  /// Tap target per lifecycle: live -> scorer, upcoming/scheduled ->
  /// fixture hub, completed -> scorecard. noResult/cancelled fixtures go to
  /// the fixture hub too (never the scorecard — that was the red-screen bug).
  void _openMatch(Match m) {
    if (m.status == 'live') {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ScoringScreen(store: store, match: m)),
      );
      return;
    }
    if (m.status == 'completed') {
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ScorecardScreen(store: store, match: m)),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => FixtureDetailScreen(store: store, matchId: m.id)),
    );
  }

  /// Delete ONE match (v1.3.5: completed matches; v1.3.7: also
  /// upcoming / cancelled / noResult fixtures), with confirmation —
  /// the points table and statistics recompute from the remaining
  /// records on their own. LIVE matches are excluded: deleting a
  /// match while its scoring screen is open would corrupt the
  /// live session.
  Future<void> _confirmDeleteMatch(Match m) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete match?'),
        content: Text(
          'Delete ${store.teamName(m.teamAId)} vs '
          '${store.teamName(m.teamBId)}'
          '${m.status == 'completed' ? ' and its scorecard' : ''}? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await store.deleteMatch(m.id);
    }
  }

  void _showNewMatchMenu(BuildContext buttonCtx) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final box = buttonCtx.findRenderObject() as RenderBox?;
    final RelativeRect position;
    if (box != null && overlay != null) {
      final topLeft =
          box.localToGlobal(Offset.zero, ancestor: overlay);
      final bottomRight =
          box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
      position = RelativeRect.fromRect(
          Rect.fromPoints(topLeft, bottomRight), Offset.zero & overlay.size);
    } else {
      position = const RelativeRect.fromLTRB(200, 200, 0, 0);
    }
    showMenu<String>(
      context: buttonCtx,
      position: position,
      color: kPanel2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'quick',
          child: Row(
            children: const [
              Icon(Icons.flash_on, color: kCyan, size: 20),
              SizedBox(width: 10),
              Text('Quick Match', style: TextStyle(color: kWhite)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'tournament',
          child: Row(
            children: const [
              Icon(Icons.emoji_events, color: kGold, size: 20),
              SizedBox(width: 10),
              Text('Tournament Match', style: TextStyle(color: kWhite)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null || !mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MatchSetupScreen(store: store)),
      );
    });
  }

  void _openAdvancedFilters() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Advanced Filters',
                      style: TextStyle(
                          color: kWhite,
                          fontSize: 18,
                          fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'SORT BY DATE',
                      style: TextStyle(
                          color: kSilver,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1),
                    ),
                    RadioGroup<String>(
                      groupValue: _sort,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _sort = v);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          RadioListTile<String>(
                            value: 'newest',
                            title: Text('Date: newest first',
                                style: TextStyle(color: kWhite)),
                            activeColor: kGold,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                          RadioListTile<String>(
                            value: 'oldest',
                            title: Text('Date: oldest first',
                                style: TextStyle(color: kWhite)),
                            activeColor: kGold,
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _hasActiveFilters
                            ? () {
                                setState(() {
                                  _tournamentId = null;
                                  _teamId = null;
                                  _overs = null;
                                });
                                Navigator.pop(sheetCtx);
                              }
                            : null,
                        icon: const Icon(Icons.filter_alt_off, size: 18),
                        label: const Text('Clear all filters'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kGold,
                          side: const BorderSide(color: kGold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = _applyFilters(
        store.matches.where(_isUpcoming).toList());
    final live =
        _applyFilters(store.matches.where(_isLive).toList());
    final completed = _applyFilters(store.matches
        .where((m) => !_isLive(m) && !_isUpcoming(m))
        .toList());

    final sections = <Widget>[];
    switch (_tab) {
      case 1:
        sections.add(_liveSection(live));
        break;
      case 2:
        sections.add(_upcomingSection(upcoming));
        break;
      case 3:
        sections.add(_completedSection(completed));
        break;
      default:
        sections.add(_upcomingSection(upcoming));
        sections.add(_liveSection(live));
        if (completed.isNotEmpty) sections.add(_completedSection(completed));
    }

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            BrandedHeader(
              onMenu: widget.onOpenDrawer,
              onSettings: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SettingsScreen(store: store)),
              ),
            ),
            _titleRow(),
            const SizedBox(height: 12),
            _tabsRow(),
            const SizedBox(height: 10),
            _filtersRow(),
            ...sections,
          ],
        ),
      ),
    );
  }

  Widget _titleRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Matches',
                  style: TextStyle(
                      color: kWhite,
                      fontSize: 24,
                      fontWeight: FontWeight.w900),
                ),
                SizedBox(height: 2),
                Text(
                  'View, manage and score all your matches',
                  style: TextStyle(color: kSilver, fontSize: 13),
                ),
              ],
            ),
          ),
          Builder(
            builder: (btnCtx) => ElevatedButton(
              onPressed: () => _showNewMatchMenu(btnCtx),
              style: ElevatedButton.styleFrom(
                backgroundColor: kCyan,
                foregroundColor: const Color(0xFF062A33),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 20),
                  SizedBox(width: 6),
                  Text('New Match',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabsRow() {
    const tabs = <(String, IconData, int)>[
      ('All Matches', Icons.list_alt, 0),
      ('Live Matches', Icons.sensors, 1),
      ('Upcoming', Icons.calendar_month, 2),
      ('Completed', Icons.check_circle, 3),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            SizedBox(
              width: 128,
              child: OptionCard(
                title: tabs[i].$1,
                icon: tabs[i].$2,
                selected: _tab == tabs[i].$3,
                onTap: () => setState(() => _tab = tabs[i].$3),
              ),
            ),
            if (i < tabs.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _filtersRow() {
    final tournaments = store.tournaments;
    final teams = store.teams;
    final formats = <int>{for (final m in store.matches) m.oversLimit}
        .toList()
      ..sort();

    final tournamentLabel = _tournamentId == null
        ? 'All Tournaments'
        : (store.tournamentById(_tournamentId)?.name ?? 'Tournament');
    final teamLabel = _teamId == null
        ? 'All Teams'
        : store.teamName(_teamId!);
    final formatLabel =
        _overs == null ? 'All Formats' : '$_overs overs';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: _filterChip(
              icon: Icons.emoji_events,
              label: tournamentLabel,
              onSelected: (v) => setState(
                  () => _tournamentId = v.isEmpty ? null : v),
              items: [
                const PopupMenuItem(
                    value: '', child: Text('All Tournaments')),
                for (final t in tournaments)
                  PopupMenuItem(
                      value: t.id,
                      child: Text(t.name,
                          overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _filterChip(
              icon: Icons.groups,
              label: teamLabel,
              onSelected: (v) =>
                  setState(() => _teamId = v.isEmpty ? null : v),
              items: [
                const PopupMenuItem(
                    value: '', child: Text('All Teams')),
                for (final t in teams)
                  PopupMenuItem(
                      value: t.id,
                      child: Text(t.name,
                          overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _filterChip(
              icon: Icons.sports_cricket,
              label: formatLabel,
              onSelected: (v) => setState(
                  () => _overs = v.isEmpty ? null : int.parse(v)),
              items: [
                const PopupMenuItem(
                    value: '', child: Text('All Formats')),
                for (final o in formats)
                  PopupMenuItem(
                      value: '$o', child: Text('$o overs')),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _advancedFilterButton(),
        ],
      ),
    );
  }

  Widget _filterChip({
    required IconData icon,
    required String label,
    required List<PopupMenuEntry<String>> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      color: kPanel2,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (_) => items,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
        decoration: BoxDecoration(
          color: kPanel2,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: kCyan.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: kSilver, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style:
                    const TextStyle(color: kWhite, fontSize: 13),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down,
                color: kSilver, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _advancedFilterButton() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: _openAdvancedFilters,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: kPanel2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: kCyan.withValues(alpha: 0.25)),
            ),
            child: const Icon(Icons.tune, color: kSilver, size: 20),
          ),
        ),
        if (_hasActiveFilters || _sort != 'oldest')
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: kGold,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _upcomingSection(List<Match> matches) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          icon: Icons.calendar_month,
          title: 'Upcoming Matches',
          trailing: _tab == 2 || matches.length > 4
              ? null
              : ViewAllLink(onTap: () => setState(() => _tab = 2)),
        ),
        if (matches.isEmpty)
          const EmptyState(
            icon: Icons.calendar_month,
            title: 'No upcoming matches',
            subtitle: 'New fixtures will appear here once scheduled.',
          )
        else
          for (var i = 0; i < matches.length; i++)
            _matchCard(matches[i], number: i + 1),
      ],
    );
  }

  Widget _liveSection(List<Match> matches) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
          child: Row(
            children: [
              const Icon(Icons.sensors, color: kRed, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'LIVE MATCHES',
                  style: TextStyle(
                    color: kWhite,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (_tab != 1 && matches.isNotEmpty)
                ViewAllLink(onTap: () => setState(() => _tab = 1)),
            ],
          ),
        ),
        if (matches.isEmpty)
          const EmptyState(
            icon: Icons.sensors,
            title: 'No live matches at the moment',
            subtitle:
                'When a match is live, it will appear here for quick access.',
          )
        else
          for (var i = 0; i < matches.length; i++)
            _matchCard(matches[i], number: i + 1),
      ],
    );
  }

  Widget _completedSection(List<Match> matches) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          icon: Icons.check_circle,
          title: 'Completed Matches',
          trailing: _tab == 3
              ? null
              : ViewAllLink(onTap: () => setState(() => _tab = 3)),
        ),
        if (matches.isEmpty)
          const EmptyState(
            icon: Icons.check_circle,
            title: 'No completed matches yet',
            subtitle:
                'Finished matches will appear here with full scorecards.',
          )
        else
          for (var i = 0; i < matches.length; i++)
            _matchCard(matches[i], number: i + 1),
      ],
    );
  }

  /// Split "06 Nov 2026, 03:00 PM" into date/time lines.
  (String, String) _dateTimeParts(String dateIso) {
    final full = formatFixtureDate(dateIso);
    if (full == 'Date TBD') return ('Date TBD', '');
    final idx = full.indexOf(', ');
    if (idx < 0) return (full, '');
    return (full.substring(0, idx), full.substring(idx + 2));
  }

  Widget _matchCard(Match m, {required int number}) {
    final (dateStr, timeStr) = _dateTimeParts(m.dateIso);
    final venue = m.venue.trim().isEmpty ? 'Venue TBD' : m.venue.trim();
    final nameA = store.teamName(m.teamAId);
    final nameB = store.teamName(m.teamBId);
    final title = m.matchTitle.trim().isNotEmpty
        ? m.matchTitle.trim()
        : 'Match $number';
    final stageTag =
        m.stage == 'league' ? 'LEAGUE' : stageLabel(m.stage).toUpperCase();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _openMatch(m),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(14),
            border:
                Border.all(color: kCyan.withValues(alpha: 0.22)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left: match no + date/time/venue.
              SizedBox(
                width: 116,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          color: kWhite,
                          fontWeight: FontWeight.w800,
                          fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    _metaRow(Icons.calendar_month, dateStr),
                    if (timeStr.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _metaRow(Icons.access_time, timeStr),
                    ],
                    const SizedBox(height: 4),
                    _metaRow(Icons.location_on, venue, maxLines: 2),
                  ],
                ),
              ),
              // Center: teams + VS + stage tag.
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kGold.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: kGold.withValues(alpha: 0.6)),
                      ),
                      child: Text(
                        stageTag,
                        style: const TextStyle(
                            color: kGold,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CaptainAvatar(
                                  store: store,
                                  teamId: m.teamAId,
                                  radius: 20),
                              const SizedBox(height: 4),
                              Text(
                                nameA,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: kWhite,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding:
                              EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            'VS',
                            style: TextStyle(
                              color: kRed,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CaptainAvatar(
                                  store: store,
                                  teamId: m.teamBId,
                                  radius: 20),
                              const SizedBox(height: 4),
                              Text(
                                nameB,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: kWhite,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (m.status == 'completed' &&
                        m.resultText.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          m.resultText.trim(),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: kSilver, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              // Right: status pill + arrow (+ delete for non-live).
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StatusPill(m.status),
                  const SizedBox(height: 10),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: kGoldGradient,
                      boxShadow: [
                        BoxShadow(
                          color: kGold.withValues(alpha: 0.35),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFF2B1C05),
                      size: 26,
                    ),
                  ),
                  if (m.status != 'live')
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: kSilver,
                      tooltip: 'Delete match',
                      onPressed: () => _confirmDeleteMatch(m),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaRow(IconData icon, String text, {int maxLines = 1}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: kSilver, size: 13),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: kSilver, fontSize: 11.5),
          ),
        ),
      ],
    );
  }
}

class TournamentDetailScreen extends StatefulWidget {
  final Store store;
  final Tournament tournament;
  const TournamentDetailScreen({
    super.key,
    required this.store,
    required this.tournament,
  });

  @override
  State<TournamentDetailScreen> createState() => _TournamentDetailScreenState();
}

class _TournamentDetailScreenState extends State<TournamentDetailScreen> {
  Store get store => widget.store;
  Tournament get tournament => widget.tournament;

  /// Latest playoff recalculation outcome (idempotent engine pass).
  /// Fetched once on open and re-run whenever a fixture screen pops back.
  PlayoffUpdate? _playoffUpdate;

  @override
  void initState() {
    super.initState();
    _runPlayoffUpdate();
  }

  Future<void> _runPlayoffUpdate() async {
    final update = await applyPlayoffUpdate(store, tournament.id);
    if (mounted) setState(() => _playoffUpdate = update);
  }

  /// Team IDs currently shown with a Q badge. Final qualifiers when the
  /// league stage is locked, otherwise mathematically guaranteed
  /// provisional qualifiers.
  Set<String> get _qualifierIds {
    final finalQ = _playoffUpdate?.finalQualifiers ?? tournament.qualifiedTeamIds;
    if (tournament.qualificationFinalized && finalQ.isNotEmpty) {
      return finalQ.toSet();
    }
    return (_playoffUpdate?.provisionalQualifiers ?? const <String>[]).toSet();
  }

  bool get _qualificationFinal =>
      tournament.qualificationFinalized &&
      ((_playoffUpdate?.finalQualifiers ?? tournament.qualifiedTeamIds)
          .isNotEmpty);

  /// Publish / unpublish this tournament (owner only, login required).
  /// Manual action only — publishing is never automatic.
  Future<void> _togglePublish() async {
    final wasPublished = tournament.published;
    final svc = PublishService();
    final err = wasPublished
        ? await svc.unpublish(store, tournament)
        : await svc.publish(store, tournament);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              (wasPublished
                  ? 'Unpublished — it no longer appears in Search.'
                  : 'Published — anyone can find it in Search '
                      '(view-only).'),
        ),
      ),
    );
  }

  Future<void> _openFixture(Match m) async {
    late final Widget screen;
    switch (m.status) {
      case 'live':
        screen = ScoringScreen(store: store, match: m);
        break;
      case 'completed':
        screen = ScorecardScreen(store: store, match: m);
        break;
      default:
        // upcoming / noResult / cancelled -> detail screen (never the
        // scorecard; that was the red-screen routing bug).
        screen = FixtureDetailScreen(store: store, matchId: m.id);
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (!mounted) return;
    setState(() {});
    await _runPlayoffUpdate();
  }

  /// Branded fixture card used by both the league and playoff sections.
  Widget _fixtureCard(Match m, {String? stageOverride}) {
    final title = m.matchTitle.isNotEmpty
        ? m.matchTitle
        : (stageOverride ?? 'League Fixture');
    final subtitle = m.resultText.isNotEmpty
        ? m.resultText
        : '${formatFixtureDate(m.dateIso)}'
              '${m.venue.isNotEmpty ? ' · ${m.venue}' : ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ScoreCard(
        onTap: () => _openFixture(m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: kCyan,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                StatusPill(m.status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                CaptainAvatar(store: store, teamId: m.teamAId),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    store.teamName(m.teamAId),
                    style: const TextStyle(
                      color: kWhite,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const Text(
                  'vs',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                Expanded(
                  child: Text(
                    store.teamName(m.teamBId),
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: kWhite,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                CaptainAvatar(store: store, teamId: m.teamBId),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = leaguePointsTable(tournament, store.matches);
    final qualifierIds = _qualifierIds;
    final leagueFixtures = store.matches
        .where((m) => m.tournamentId == tournament.id && m.stage == 'league')
        .toList()
      ..sort((a, b) => a.dateIso.compareTo(b.dateIso));
    final playoffFixtures = playoffMatchesOf(tournament.id, store.matches);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tournament.name),
          actions: [
            if (AuthService().isLoggedIn)
              IconButton(
                icon: Icon(
                  tournament.published ? Icons.public : Icons.public_off,
                  color: tournament.published ? kGreen : null,
                ),
                tooltip: tournament.published
                    ? 'Published — tap to unpublish'
                    : 'Publish (public, view-only)',
                onPressed: _togglePublish,
              ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'Share points table',
              // v1.1.7: shareable points-table image from real standings.
              onPressed: () =>
                  sharePointsTableImage(context, store, tournament),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (tournament.published) {
                  PublishService().deletePublishedDoc(tournament.id);
                }
                await store.deleteTournament(tournament.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Points Table'),
              Tab(text: 'Fixtures'),
              Tab(text: 'Stats'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  MatchSetupScreen(store: store, tournamentId: tournament.id),
            ),
          ).then((_) => setState(() {})),
          icon: const Icon(Icons.add),
          label: const Text('New fixture'),
        ),
        body: TabBarView(
          children: [
            // Points table (ICC NRR) with playoff qualification badges
            ListView(
              padding: const EdgeInsets.all(10),
              children: [
                if (qualifierIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Row(
                      children: [
                        _qualificationFinal
                            ? const QBadge()
                            : const QBadge(provisional: true),
                        const SizedBox(width: 8),
                        Text(
                          _qualificationFinal
                              ? 'Qualified for the playoffs'
                              : 'Q* = provisional qualification (mathematically guaranteed)',
                          style: const TextStyle(
                            color: kGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 12,
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('Team')),
                      DataColumn(label: Text('P')),
                      DataColumn(label: Text('W')),
                      DataColumn(label: Text('L')),
                      DataColumn(label: Text('T')),
                      DataColumn(label: Text('NR')),
                      DataColumn(label: Text('Pts')),
                      DataColumn(label: Text('NRR')),
                      DataColumn(label: Text('Adj')),
                    ],
                    rows: [
                      for (var i = 0; i < rows.length; i++)
                        DataRow(
                          color: qualifierIds.contains(rows[i].teamId)
                              ? WidgetStateProperty.all(
                                  kGold.withValues(alpha: 0.10),
                                )
                              : null,
                          cells: [
                            DataCell(Text('${i + 1}')),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(store.teamName(rows[i].teamId)),
                                  if (qualifierIds
                                      .contains(rows[i].teamId)) ...[
                                    const SizedBox(width: 6),
                                    _qualificationFinal
                                        ? const QBadge()
                                        : const QBadge(provisional: true),
                                  ],
                                ],
                              ),
                            ),
                            DataCell(Text('${rows[i].played}')),
                            DataCell(Text('${rows[i].won}')),
                            DataCell(Text('${rows[i].lost}')),
                            DataCell(Text('${rows[i].tied}')),
                            DataCell(Text('${rows[i].noResult}')),
                            DataCell(
                              Text(
                                '${rows[i].points}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: kCyan,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(rows[i].nrr.toStringAsFixed(3)),
                            ),
                            DataCell(
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: 'Custom points adjustment',
                                onPressed: () =>
                                    _editAdjustment(context, rows[i].teamId),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'NRR uses the ICC rule: aggregate runs per over scored minus conceded across the tournament; a team bowled out is deemed to have faced its full overs quota.',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: FilledButton.tonalIcon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NrrCalculatorScreen(store: store),
                      ),
                    ),
                    icon: const Icon(Icons.calculate),
                    label: const Text('NRR Calculator'),
                  ),
                ),
              ],
            ),
            // Fixtures — league and playoffs, with status-based routing
            ListView(
              padding: const EdgeInsets.all(10),
              children: [
                const SectionHeader('League Fixtures'),
                if (leagueFixtures.isEmpty)
                  const EmptyState(
                    icon: Icons.event_note,
                    title: 'No league fixtures',
                    subtitle: 'Use the + button to add fixtures.',
                  ),
                for (final m in leagueFixtures) _fixtureCard(m),
                const SectionHeader('Playoffs'),
                if (playoffFixtures.isEmpty)
                  const EmptyState(
                    icon: Icons.emoji_events_outlined,
                    title: 'No playoff fixtures',
                    subtitle:
                        'Semifinals and the final appear here once added.',
                  ),
                for (final m in playoffFixtures)
                  _fixtureCard(m, stageOverride: stageLabel(m.stage)),
                const SizedBox(height: 70),
              ],
            ),
            // Tournament stats (Stumps-style leaderboards)
            TournamentStatsTab(store: store, tournament: tournament),
          ],
        ),
      ),
    );
  }

  Future<void> _editAdjustment(BuildContext context, String teamId) async {
    final ctrl = TextEditingController(
      text: '${tournament.pointsAdjustments[teamId] ?? 0}',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Custom points — ${store.teamName(teamId)}'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(signed: true),
          decoration: const InputDecoration(
            labelText: 'Adjustment (added to earned points)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final v = int.tryParse(ctrl.text) ?? 0;
      if (v == 0) {
        tournament.pointsAdjustments.remove(teamId);
      } else {
        tournament.pointsAdjustments[teamId] = v;
      }
      await store.persist();
      if (mounted) setState(() {});
    }
  }
}
