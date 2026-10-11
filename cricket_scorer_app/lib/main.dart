// 60Score — offline cricket scorer, draft & registration
// for the Super Sixty League. Made by Sharjeel.
import 'package:flutter/material.dart';

import 'store.dart';
import 'theme.dart';
import 'screens/registration_screen.dart';
import 'screens/draft_screen.dart';
import 'screens/scorer_home_screen.dart';
import 'screens/stats_screen.dart';

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

/// Splash: full league logo (as-is, uncropped) + "Made by Sharjeel",
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
                'Imported ${picked.rows.length} players — see the Registration tab',
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
      // Splash: full-bleed AI artwork (60Score logo, Loading, Made by Sharjeel).
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

class HomeShell extends StatefulWidget {
  final Store store;
  const HomeShell({super.key, required this.store});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 2; // start on Scorer

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final pages = [
      RegistrationScreen(store: store),
      DraftListScreen(store: store),
      ScorerHomeScreen(store: store),
      StatsScreen(store: store),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.how_to_reg),
            label: 'Registration',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.swap_horiz), label: 'Draft'),
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_cricket),
            label: 'Scorer',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Stats'),
        ],
      ),
    );
  }
}
