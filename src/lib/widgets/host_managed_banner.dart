/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0

A slim informational banner shown on the hosted web build for features whose
work is performed entirely by the desktop host (e.g. the BBS and Torrent
servers). The web UI cannot run these itself, so their local controls are inert
here and this banner explains that the desktop app is in charge.
*/

import 'package:flutter/material.dart';

/// A thin banner indicating that a feature is managed by the desktop host.
class HostManagedBanner extends StatelessWidget {
  const HostManagedBanner({super.key, required this.message});

  /// The explanation shown to the user.
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
