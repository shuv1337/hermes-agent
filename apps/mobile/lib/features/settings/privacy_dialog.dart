import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:hermes_mobile/core/config/release_config.dart';
import 'package:hermes_mobile/l10n/l10n.dart';

/// Shows the app's concise data-flow disclosure and the publisher policy link.
///
/// This is shared by Connect and Settings so the disclosure is accessible
/// before a reviewer or user signs in to a gateway.
Future<void> showPrivacyDialog(BuildContext context) async {
  final policyUri = ReleaseConfig.privacyPolicyUri;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(context.l10n.privacyAndData),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.privacyDataFlow),
            const SizedBox(height: 12),
            Text(context.l10n.privacyOnDevice),
            const SizedBox(height: 12),
            Text(context.l10n.privacyNoAnalytics),
            if (policyUri == null) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.privacyPolicyMissing,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(context.l10n.ok),
        ),
        if (policyUri != null)
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(context.l10n.openPrivacyPolicy),
            onPressed: () async {
              Navigator.pop(dialogContext);
              try {
                final opened = await launchUrl(
                  policyUri,
                  mode: LaunchMode.externalApplication,
                );
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.couldNotOpenLink)),
                  );
                }
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(context.l10n.couldNotOpenLink)),
                  );
                }
              }
            },
          ),
      ],
    ),
  );
}
