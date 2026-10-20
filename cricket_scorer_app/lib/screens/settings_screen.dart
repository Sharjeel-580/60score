// Settings screen (§26): notification preferences, data management
// (backup/restore, player import-export), reset app (§29), appearance
// note, and app info. Offline-first — no accounts, no cloud.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../store.dart';
import '../theme.dart';
import '../auth_service.dart';
import '../sync_service.dart';
import 'about_screen.dart';
import 'backup_screen.dart';
import 'login_screen.dart';
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

  Widget _settingsRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: kCyan),
      title: Text(title, style: const TextStyle(color: kWhite)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white54),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const SectionTitle(
            icon: Icons.account_circle_outlined,
            title: 'Account & Sync',
          ),
          ScoreCard(
            padding: EdgeInsets.zero,
            child: AnimatedBuilder(
              animation: AuthService(),
              builder: (context, _) {
                final auth = AuthService();
                if (auth.isLoggedIn) {
                  final sync = SyncService();
                  final lastSync = sync.lastSyncAt;
                  return Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.verified_user,
                            color: kGreen),
                        title: const Text('Logged in',
                            style: TextStyle(color: kWhite)),
                        subtitle: Text(
                          auth.displayName,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.cloud_sync,
                            color: kCyan),
                        title: const Text('Cloud sync',
                            style: TextStyle(color: kWhite)),
                        subtitle: Text(
                          sync.lastError != null
                              ? 'Last attempt failed — will retry '
                                  'automatically'
                              : lastSync == null
                                  ? 'Data syncs automatically when online'
                                  : 'Last synced: '
                                      '${lastSync.day}/${lastSync.month} '
                                      '${lastSync.hour}:'
                                      '${lastSync.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        trailing: TextButton(
                          child: const Text('Sync now'),
                          onPressed: () async {
                            await sync.pull(store);
                            await store.persist();
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                      const Divider(height: 1),
                      _settingsRow(
                        icon: Icons.logout,
                        title: 'Log out',
                        subtitle: 'Data stays on this device',
                        onTap: () async {
                          await auth.signOut();
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  );
                }
                return _settingsRow(
                  icon: Icons.login,
                  title: 'Log in / Sign up',
                  subtitle:
                      'Email, Google or phone — sync data across devices',
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => LoginScreen(store: store)));
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
          ),
          const SectionTitle(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 2),
            child: Text(
              'Preferences only — no cloud, reminders stay on this device.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
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
          const SectionTitle(
            icon: Icons.storage_outlined,
            title: 'Data Management',
          ),
          ScoreCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _settingsRow(
                  icon: Icons.backup,
                  title: 'Backup & Restore',
                  subtitle: 'Manual, automatic and Downloads backups',
                  onTap: () => _open(BackupScreen(store: store)),
                ),
                const Divider(height: 1),
                _settingsRow(
                  icon: Icons.import_export,
                  title: 'Player import/export',
                  subtitle: 'Excel / CSV player lists',
                  onTap: () => _open(RegistrationScreen(store: store)),
                ),
              ],
            ),
          ),
          const SectionTitle(
            icon: Icons.palette_outlined,
            title: 'Appearance',
          ),
          // Info only — the app ships with a single dark navy theme;
          // there is no stored theme preference to toggle.
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
          const SizedBox(height: 12),
          ScoreCard(
            padding: EdgeInsets.zero,
            child: ExpansionTile(
              leading: const Icon(
                Icons.warning_amber_rounded,
                color: kRed,
              ),
              title: const Text(
                'Reset App',
                style: TextStyle(
                  color: kWhite,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: const Text(
                'Advanced — restore default data',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              iconColor: kRed,
              collapsedIconColor: Colors.white54,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
              ],
            ),
          ),
          const SectionTitle(
            icon: Icons.info_outline,
            title: 'About & App Info',
          ),
          ScoreCard(
            padding: EdgeInsets.zero,
            child: _settingsRow(
              icon: Icons.info_outline,
              title: 'About 60Score',
              subtitle: 'Version, credits and description',
              onTap: () => _open(const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
