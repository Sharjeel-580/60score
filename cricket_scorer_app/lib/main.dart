// 60Score — offline cricket scorer for the Super Sixty League.
// Made by Sharjeel.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'store.dart';
import 'theme.dart';
import 'auth_service.dart';
import 'backup_service.dart';
import 'screens/home_screen.dart';
import 'screens/match_setup_screen.dart';
import 'screens/scorer_home_screen.dart';
import 'screens/tournaments_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/teams_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/about_screen.dart';
import 'screens/draft_screen.dart';
import 'widgets/app_logo.dart';
import 'widgets/splash_image.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Fire-and-forget: falls back to offline mode when Firebase is not set up.
  AuthService().init();
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
        body: const SizedBox.expand(
          child: SplashImage(),
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
          ScorerHomeScreen(
            store: store,
            onOpenDrawer: () =>
                _scaffoldKey.currentState?.openDrawer(),
          ),
          StatsScreen(
            store: store,
            onOpenDrawer: () =>
                _scaffoldKey.currentState?.openDrawer(),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  /// Custom bottom bar: Home | Matches | (gold + circle) | Statistics | More.
  /// Index contract (shared with HomeScreen.onSelectTab):
  /// 0 Home, 1 Matches, 2 New Match (action), 3 Statistics, 4 More (drawer).
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: kNavy,
        border: Border(
          top: BorderSide(color: kGold.withValues(alpha: 0.35), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: kGold.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: [
              _navBtn(0, Icons.home_outlined, Icons.home, 'Home'),
              _navBtn(
                1,
                Icons.sports_cricket_outlined,
                Icons.sports_cricket,
                'Matches',
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _onNavTap(2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -6),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: kGoldGradient,
                            border: Border.all(
                              color: kGold.withValues(alpha: 0.8),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: kGold.withValues(alpha: 0.5),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Color(0xFF2B1C05),
                            size: 30,
                          ),
                        ),
                      ),
                      const Text(
                        'New Match',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _navBtn(
                3,
                Icons.bar_chart_outlined,
                Icons.bar_chart,
                'Statistics',
              ),
              _navBtn(4, Icons.menu, Icons.menu, 'More'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navBtn(
    int index,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    final active = _navIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => _onNavTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              active ? activeIcon : icon,
              color: active ? kGold : Colors.white54,
              size: 24,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: active ? kGold : Colors.white54,
                fontSize: 11,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sidebar per the approved reference: 7 items only —
  /// Home, Tournaments, Teams & Players, Drafting, Statistics,
  /// Settings, About 60Score.
  Widget _buildDrawer() {
    return Drawer(
      width: math.min(320.0, MediaQuery.of(context).size.width * 0.82),
      backgroundColor: kNavyDeep,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: logo + name + tagline + close.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppLogo(height: 64),
                        SizedBox(height: 10),
                        Text(
                          '60Score',
                          style: TextStyle(
                            color: kWhite,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Cricket Scoring, Simplified.',
                          style:
                              TextStyle(color: kSilver, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close, color: kWhite),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                    vertical: 8, horizontal: 12),
                children: [
                  _drawerCard(
                    icon: Icons.home,
                    label: 'Home',
                    selected: _navIndex == 0,
                    onTap: () => _closeDrawerAndGoTab(0),
                  ),
                  _drawerCard(
                    icon: Icons.emoji_events,
                    label: 'Tournaments',
                    onTap: () => _closeDrawerAndPush(
                      TournamentsScreen(store: store),
                    ),
                  ),
                  _drawerCard(
                    icon: Icons.groups,
                    label: 'Teams & Players',
                    onTap: () =>
                        _closeDrawerAndPush(TeamsScreen(store: store)),
                  ),
                  _drawerCard(
                    icon: Icons.edit_note,
                    label: 'Drafting',
                    onTap: () => _closeDrawerAndPush(
                      DraftListScreen(store: store),
                    ),
                  ),
                  _drawerCard(
                    icon: Icons.bar_chart,
                    label: 'Statistics',
                    selected: _navIndex == 3,
                    onTap: () => _closeDrawerAndGoTab(3),
                  ),
                  const Divider(height: 24, color: kTealDark),
                  _drawerCard(
                    icon: Icons.settings,
                    label: 'Settings',
                    onTap: () => _closeDrawerAndPush(
                      SettingsScreen(store: store),
                    ),
                  ),
                  _drawerCard(
                    icon: Icons.info,
                    label: 'About 60Score',
                    onTap: () =>
                        _closeDrawerAndPush(const AboutScreen()),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Version 1.1.2',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: selected ? kGoldGradient : null,
        color: selected ? null : kPanel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? kGold.withValues(alpha: 0.7)
              : kCyan.withValues(alpha: 0.18),
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: selected ? const Color(0xFF2B1C05) : kCyan,
          size: 26,
        ),
        title: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF2B1C05) : kWhite,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: selected
              ? const Color(0xFF2B1C05)
              : Colors.white54,
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}
