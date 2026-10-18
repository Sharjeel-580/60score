// "Select Player of the Match" dialog.
//
// Shows the auto-generated shortlist (max 3, ranked by actual match stats).
// The user taps one candidate and confirms; "Skip" returns null so the
// caller can auto-select the highest-ranked candidate. The award is saved
// on the match (update, never duplicate).
import 'package:flutter/material.dart';

import '../models.dart';
import '../potm.dart';
import '../store.dart';
import '../theme.dart';
import 'player_avatar.dart';

/// Opens the dialog. Returns the chosen playerId, or null when skipped.
Future<String?> showPotmPickerDialog(
  BuildContext context,
  Store store,
  Match match,
) {
  return showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (c) => _PotmDialog(store: store, match: match),
  );
}

class _PotmDialog extends StatefulWidget {
  final Store store;
  final Match match;
  const _PotmDialog({required this.store, required this.match});

  @override
  State<_PotmDialog> createState() => _PotmDialogState();
}

class _PotmDialogState extends State<_PotmDialog> {
  late final List<PotmCandidate> _candidates;
  String? _selected;

  @override
  void initState() {
    super.initState();
    _candidates = potmShortlist(widget.match, widget.store);
    // Pre-select the previously saved award so edits show the current pick.
    if (widget.match.manOfMatchId.isNotEmpty &&
        _candidates.any((c) => c.playerId == widget.match.manOfMatchId)) {
      _selected = widget.match.manOfMatchId;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Player of the Match'),
      content: SizedBox(
        width: 360,
        child: _candidates.isEmpty
            ? const Text(
                'No eligible players with recorded figures in this match. '
                'You can still pick one manually from the playing XIs.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Top performers by match impact — tap to select.',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _candidates.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final c = _candidates[i];
                        final sel = _selected == c.playerId;
                        return InkWell(
                          onTap: () =>
                              setState(() => _selected = c.playerId),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: sel
                                    ? kGold
                                    : Colors.white
                                        .withValues(alpha: 0.15),
                                width: sel ? 2 : 1,
                              ),
                              color: sel
                                  ? kGold.withValues(alpha: 0.12)
                                  : kPanel,
                            ),
                            child: Row(
                              children: [
                                PlayerAvatar(
                                  photoBase64: c.photoBase64.isEmpty
                                      ? null
                                      : c.photoBase64,
                                  role: c.role,
                                  name: c.name,
                                  radius: 24,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (i == 0)
                                            const Padding(
                                              padding: EdgeInsets.only(
                                                  right: 4),
                                              child: Icon(
                                                Icons.emoji_events,
                                                size: 14,
                                                color: kGold,
                                              ),
                                            ),
                                          Expanded(
                                            child: Text(
                                              c.name,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        [
                                          if (c.teamName.isNotEmpty)
                                            c.teamName,
                                          c.role,
                                        ].join(' • '),
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 11,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        c.figureLine,
                                        style: const TextStyle(
                                          color: kCyan,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (sel)
                                  const Icon(
                                    Icons.check_circle,
                                    color: kGold,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: _selected == null
              ? null
              : () => Navigator.pop(context, _selected),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
