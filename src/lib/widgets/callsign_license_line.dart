/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../callsign/callsign_record.dart';
import '../services/callsign_lookup_service.dart';

/// Looks [callsign] up in the offline callsign database. Returns null when the
/// database isn't installed, the callsign is unknown, or the lookup fails.
Future<CallsignRecord?> lookupCallsignRecord(String callsign) async {
  final service = CallsignLookupService.instance;
  if (callsign.trim().isEmpty || !service.isAvailable) return null;
  try {
    return (await service.lookup(callsign))?.record;
  } catch (_) {
    return null;
  }
}

/// Just the license class/grade (e.g. "Technician", "General") for [rec], or
/// null when unknown. Shown inline next to the callsign.
String? licenseGradeText(CallsignRecord? rec) {
  if (rec == null) return null;
  final grade = rec.operatorClassName.isNotEmpty
      ? rec.operatorClassName
      : rec.qualificationsName;
  return grade.isEmpty ? null : grade;
}

/// The "name • location" summary as its own row (icon + text), or null when
/// [rec] has neither.
Widget? buildLicenseLine(BuildContext context, CallsignRecord? rec) {
  if (rec == null) return null;
  final parts = <String>[];
  if (rec.name.isNotEmpty) parts.add(rec.name);
  if (rec.location.isNotEmpty) parts.add(rec.location);
  if (parts.isEmpty) return null;
  final scheme = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Row(
      children: [
        Icon(Icons.badge_outlined, size: 13, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            parts.join('  •  '),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// Bold [callsign] with the license grade inline beside it, followed by the
/// name/location line — the same layout as the APRS map's station info bar.
Widget buildCallsignLicenseBlock(
  BuildContext context,
  String callsign,
  CallsignRecord? rec,
) {
  final scheme = Theme.of(context).colorScheme;
  final gradeText = licenseGradeText(rec);
  final line = buildLicenseLine(context, rec);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Text(
            callsign,
            style: const TextStyle(fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
          if (gradeText != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                gradeText,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      ?line,
    ],
  );
}
