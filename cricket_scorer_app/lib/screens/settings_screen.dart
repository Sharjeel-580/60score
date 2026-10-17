// Settings screen (§26): backup/restore, player import-export, notification
// preferences, reset app (§29), and app info. Offline-first — no accounts,
// no cloud.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../store.dart';
import '../theme.dart';
import 'about_screen.dart';
import 'backup_screen.dart';
import 'registration_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Store store;
  const SettingsScreen({super.key, required this.store});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _kNotifMatch = 'set_notif_match';
  static const _kNotifBackup = 'set_notif_backup';

  bool _notifMatch = true;
  bool _notifBackup = true;
  bool _loadedPrefs = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _notifMatch = prefs.getBool(_kNotifMatch) ?? true;
      _notifBackup = prefs.getBool(_kNotifBackup) ?? true;
    } catch (_) {}
    if (mounted) setState(() => _loadedPrefs = true);
  }

  Future<void> _savePref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reset App'),
        content: const Text(
          'Deletes all teams, players, matches, tournaments, drafts and '
          'restores the default Super Sixty League Season 2K26 with its '
          '18 fixtures. Backups and exported files are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: kRed),
            child: const Text('Reset everything'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.store.resetApp();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('App reset — default tournament restored'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const SectionHeader('Data'),
          ScoreCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup, color: kCyan),
                  title: const Text(
                    'Backup & Restore',
                    style: TextStyle(color: kWhite),
                  ),
                  subtitle: const Text(
                    'Manual, automatic and Downloads backups',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                  onTap: () => _open(BackupScreen(store: store)),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.import_export, color: kCyan),
                  title: const Text(
                    'Player import/export',
                    style: TextStyle(color: kWhite),
                  ),
                  subtitle: const Text(
                    'Excel / CSV player lists',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                  onTap: () => _open(RegistrationScreen(store: store)),
                ),
              ],
            ),
          ),
          const SectionHeader('Notifications'),
          const Text(
            'Preferences only — no cloud, reminders stay on this device.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ScoreCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  value: _notifMatch,
                  onChanged: _loadedPrefs
                      ? (v) {
                          setState(() => _notifMatch = v);
                          _savePref(_kNotifMatch, v);
                        }
                      : null,
                  title: const Text(
                    'Match reminders',
                    style: TextStyle(color: kWhite),
                  ),
                  subtitle: const Text(
                    'Remind before upcoming fixtures',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  activeThumbColor: kCyan,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: _notifBackup,
                  onChanged: _loadedPrefs
                      ? (v) {
                          setState(() => _notifBackup = v);
                          _savePref(_kNotifBackup, v);
                        }
                      : null,
                  title: const Text(
                    'Backup reminders',
                    style: TextStyle(color: kWhite),
                  ),
                  subtitle: const Text(
                    'Remind when no recent backup exists',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  activeThumbColor: kCyan,
                ),
              ],
            ),
          ),
          const SectionHeader('Appearance'),
          const ScoreCard(
            child: Row(
              children: [
                Icon(Icons.dark_mode, color: kGold),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Dark theme (default)',
                    style: TextStyle(color: kWhite),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader('Reset'),
          ScoreCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ScoreButton(
                  label: 'Reset App',
                  icon: Icons.delete_forever,
                  kind: ScoreButtonKind.danger,
                  onPressed: _confirmReset,
                ),
              ],
            ),
          ),
          const SectionHeader('About'),
          ScoreCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: kCyan),
              title: const Text(
                'About 60Score',
                style: TextStyle(color: kWhite),
              ),
              subtitle: const Text(
                'Version, credits and description',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: Colors.white54,
              ),
              onTap: () => _open(const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
