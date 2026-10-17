// 60Score — offline cricket scorer for the Super Sixty League.
// Made by Sharjeel.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'store.dart';
import 'theme.dart';
import 'backup_service.dart';
import 'screens/home_screen.dart';
import 'screens/match_setup_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/scorer_home_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/teams_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/about_screen.dart';
import 'widgets/app_logo.dart';

void main() {
  runApp(const Score60App());
}

class Score60App extends StatelessWidget {
  const Score60App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '60Score',
      debugShowCheckedModeBanner: false,
      theme: buildScore60Theme(),
      home: const SplashGate(),
    );
  }
}

/// Splash: full-bleed artwork (60Score logo, Made by Sharjeel),
/// then the app shell once local data is loaded.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  final Store store = Store();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final minSplash = Future.delayed(const Duration(milliseconds: 1400));
    await store.load();
    // Daily automatic backup (keeps last 14) — fire and forget.
    runDailyAutoBackup(store);
    await minSplash;
    if (!mounted) return;
    setState(() => _ready = true);
    if (!store.welcomeDone) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showWelcome());
    }
  }

  Future<void> _showWelcome() async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Welcome to 60Score'),
        content: const Text(
          'Your offline home for the Super Sixty League.\n\n'
          'How do you want to start?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'fresh'),
            child: const Text('Fresh Start'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'import'),
            child: const Text('Import Players (Excel / CSV)'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'later'),
            child: const Text('Add Past Scores Later'),
          ),
        ],
      ),
    );
    store.welcomeDone = true;
    await store.persist();
    if (choice == 'import' && mounted) {
      final picked = await pickPlayerListFile();
      if (picked != null && picked.rows.isNotEmpty) {
        for (final r in picked.rows) {
          store.regPlayers.add(r.toRegPlayer(Store.newId('reg')));
        }
        await store.persist();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Imported ${picked.rows.length} players — open Players from the menu',
              ),
            ),
          );
        }
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(
          child: Image.asset(
            'assets/splash.png',
            fit: BoxFit.cover,
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => HomeShell(store: store),
    );
  }
}

/// App shell: bottom navigation (Home / Matches / New Match / Statistics /
/// More) plus a half-width side drawer. New Match pushes the setup screen
/// without changing tabs; More opens the drawer.
class HomeShell extends StatefulWidget {
  final Store store;
  const HomeShell({super.key, required this.store});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _navIndex = 0; // 0 Home, 1 Matches, 2 New Match (action), 3 Statistics, 4 More (action)
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  Store get store => widget.store;

  /// Bottom-nav index -> IndexedStack page index.
  int get _pageIndex => _navIndex == 3 ? 2 : _navIndex;

  void _onNavTap(int i) {
    if (i == 2) {
      // New Match: push the setup screen, keep the current tab selected.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MatchSetupScreen(store: store),
        ),
      );
      return;
    }
    if (i == 4) {
      _scaffoldKey.currentState?.openDrawer();
      return;
    }
    setState(() => _navIndex = i);
  }

  void _closeDrawerAndGoTab(int navIndex) {
    Navigator.pop(context);
    setState(() => _navIndex = navIndex);
  }

  void _closeDrawerAndPush(Widget page) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(),
      body: IndexedStack(
        index: _pageIndex,
        children: [
          HomeScreen(
            store: store,
            onOpenDrawer: () =>
                _scaffoldKey.currentState?.openDrawer(),
            onSelectTab: _onNavTap,
          ),
          ScorerHomeScreen(store: store),
          StatsScreen(store: store),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _navIndex,
        onTap: _onNavTap,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_cricket_outlined),
            activeIcon: Icon(Icons.sports_cricket),
            label: 'Matches',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle),
            label: 'New Match',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart_outlined),
            activeIcon: Icon(Icons.bar_chart),
            label: 'Statistics',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: 'More',
          ),
        ],
      ),
    );
  }

  /// Half-width drawer: min(320, 58% of screen width).
  /// The native Drawer already closes on outside taps and back navigation.
  Widget _buildDrawer() {
    return Drawer(
      width: math.min(320.0, MediaQuery.of(context).size.width * 0.58),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: kTealDark),
                ),
              ),
              child: Row(
                children: [
                  const AppLogo(height: 44),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '60Score',
                        style: TextStyle(
                          color: kWhite,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Cricket Scoring, Simplified.',
                        style: TextStyle(color: kSilver, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _drawerItem(
                    icon: Icons.emoji_events_outlined,
                    label: 'Tournaments',
                    onTap: () {
                      final t = store.tournamentById(
                        Store.defaultTournamentId,
                      );
                      if (t == null) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Default tournament not found'),
                          ),
                        );
                        return;
                      }
                      _closeDrawerAndPush(
                        TournamentDetailScreen(
                          store: store,
                          tournament: t,
                        ),
                      );
                    },
                  ),
                  _drawerItem(
                    icon: Icons.group_outlined,
                    label: 'Teams',
                    onTap: () =>
                        _closeDrawerAndPush(TeamsScreen(store: store)),
                  ),
                  _drawerItem(
                    icon: Icons.how_to_reg_outlined,
                    label: 'Players',
                    onTap: () => _closeDrawerAndPush(
                      RegistrationScreen(store: store),
                    ),
                  ),
                  _drawerItem(
                    icon: Icons.event_outlined,
                    label: 'Fixtures',
                    onTap: () => _closeDrawerAndGoTab(1),
                  ),
                  _drawerItem(
                    icon: Icons.scoreboard_outlined,
                    label: 'Scorecards',
                    onTap: () => _closeDrawerAndGoTab(1),
                  ),
                  _drawerItem(
                    icon: Icons.import_export_outlined,
                    label: 'Import / Export',
                    onTap: () => _closeDrawerAndPush(
                      RegistrationScreen(store: store),
                    ),
                  ),
                  const Divider(height: 16),
                  _drawerItem(
                    icon: Icons.backup_outlined,
                    label: 'Backup / Restore',
                    onTap: () => _closeDrawerAndPush(
                      BackupScreen(store: store),
                    ),
                  ),
                  _drawerItem(
                    icon: Icons.settings_outlined,
                    label: 'Settings',
                    onTap: () => _closeDrawerAndPush(
                      SettingsScreen(store: store),
                    ),
                  ),
                  _drawerItem(
                    icon: Icons.info_outline,
                    label: 'About',
                    onTap: () => _closeDrawerAndPush(const AboutScreen()),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Made by Sharjeel',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: kCyan, size: 22),
      title: Text(
        label,
        style: const TextStyle(
          color: kWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}
