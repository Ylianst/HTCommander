import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/update_service.dart';
import 'update_dialog.dart';

/// Custom About dialog matching the C# AboutForm
class HTAboutDialog extends StatelessWidget {
  const HTAboutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.data?.version ?? '';
        return _buildDialog(context, version);
      },
    );
  }

  Widget _buildDialog(BuildContext context, String version) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: scheme.surface, // Light gray like C# app
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 650, maxHeight: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Hide image when width is too narrow (less than 520px)
                    final showImage = constraints.maxWidth >= 520;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left side: App icon (only when width allows)
                        if (showImage) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.asset(
                              'assets/images/AppIcon.png',
                              width: 200,
                              height: 200,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 200,
                                  height: 200,
                                  color: scheme.surfaceContainerHighest,
                                  child: const Icon(Icons.radio, size: 80),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                        ],
                        // Right side: Info
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title
                                const Text(
                                  'Handi-Talkie Commander',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // Version and author info
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  ).aboutVersionAuthor(version),
                                  style: TextStyle(fontSize: 13),
                                ),
                                const SizedBox(height: 12),
                                _buildAttribution(
                                  'Handi-Talkie Commander',
                                  'https://github.com/Ylianst/HTCommander',
                                ),
                                _buildAttribution(
                                  'Based on BenLink by Kyle Husmann, KC3SLD',
                                  'https://github.com/khusmann/benlink',
                                ),
                                _buildAttribution(
                                  'Uses ported code from WB2OSZ',
                                  'https://github.com/wb2osz/direwolf',
                                ),
                                _buildAttribution(
                                  'Uses APRS-Parser by Lee, K0QED',
                                  'https://github.com/k0qed/aprs-parser',
                                ),
                                _buildAttribution(
                                  'Radio firmware update by Cyrus Field, N0TEZ',
                                  'https://github.com/repins267',
                                ),
                                _buildAttribution(
                                  'Map data provided by OpenStreetMap, the project\nthat creates and distributes free geographic\ndata for the world.',
                                  'https://openstreetmap.org',
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (UpdateService.instance.isSupported)
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        showDialog(
                          context: context,
                          builder: (context) => const UpdateDialog(),
                        );
                      },
                      child: Text(
                        AppLocalizations.of(context).aboutCheckForUpdates,
                      ),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(AppLocalizations.of(context).commonClose),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAttribution(String label, String url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _launchUrl(url),
            child: const Padding(
              padding: EdgeInsets.only(right: 6, top: 1),
              child: Icon(Icons.link, size: 16, color: Colors.blue),
            ),
          ),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
