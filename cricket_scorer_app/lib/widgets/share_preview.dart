// Fit-to-screen preview for captured share images (v1.2.2).
//
// The summary / Top-5 stats cards are tall; before this preview the
// only way to view them was the shared PNG, whose top ran under the
// phone's camera/notch in full-screen viewers. This dialog keeps the
// whole card inside the SafeArea: a single image is scaled to fit,
// multiple images scroll. The shared image itself is unchanged —
// this only gates the share behind a quick visual check.
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Shows [images] fitted to the screen and returns true when the
/// user taps Share, false on Cancel/close.
Future<bool> showSharePreview(
  BuildContext context, {
  required String title,
  required List<Uint8List> images,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => Dialog.fullscreen(
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(c, false),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: images.length == 1
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: Image.memory(images.first),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        for (final img in images) ...[
                          Image.memory(img),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(c, true),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
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
  return ok ?? false;
}
