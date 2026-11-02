import 'package:flutter/material.dart';

import '../blocs/home/home_state.dart';

class YouTubeTrackingSection extends StatelessWidget {
  const YouTubeTrackingSection({
    super.key,
    required this.state,
    required this.onSettingsRequested,
    required this.onRetry,
  });

  final HomeState state;
  final VoidCallback onSettingsRequested;
  final VoidCallback onRetry;

  Future<void> _showDisclosure(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('YouTube Shorts tracking'),
        content: const SingleChildScrollView(
          child: Text(
            'Doom Meter uses Android Accessibility access to observe YouTube’s screen structure '
            'and estimate transitions between Shorts, including moving backward.\n\n'
            'Daily counts and activity times stay on this device. Video titles, comments, '
            'and usernames are not saved or sent to a server.\n\n'
            'This is experimental and may miss or misclassify transitions. Detected YouTube '
            'totals replace manual YouTube test counts when tracking is enabled.\n\n'
            'In Settings, open Installed apps → Doom Meter — YouTube Shorts tracking and '
            'enable its main switch. You can disable it there at any time.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted) onSettingsRequested();
  }

  @override
  Widget build(BuildContext context) {
    final busy = state.isTrackingStatusLoading || state.isSyncingNativeCounts;
    final status = !state.isTrackingSupported
        ? 'Available on Android'
        : state.isTrackingStatusLoading
        ? 'Checking…'
        : !state.isTrackingStatusKnown
        ? 'Status unavailable'
        : state.isYouTubeTrackingEnabled
        ? 'Active'
        : 'Disabled';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'YouTube Shorts tracking',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Status: $status',
              key: const ValueKey('youtube-tracking-status'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Estimate Shorts transitions while you use YouTube. Stored locally. Experimental.',
            ),
            if (state.isSyncingNativeCounts)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (state.trackingErrorMessage != null) ...[
              const SizedBox(height: 12),
              Text(state.trackingErrorMessage!),
              TextButton(
                onPressed: busy ? null : onRetry,
                child: const Text('Retry tracking sync'),
              ),
            ],
            if (state.isTrackingSupported) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('youtube-tracking-settings'),
                onPressed: busy ? null : () => _showDisclosure(context),
                icon: const Icon(Icons.accessibility_new_rounded),
                label: Text(
                  state.isYouTubeTrackingEnabled
                      ? 'Manage tracking'
                      : 'Enable tracking',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
