import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../aprs/ota.dart';
import '../l10n/app_localizations.dart';
import 'chat_widget.dart';

class OtaConversationPanel extends StatefulWidget {
  final List<ChatMessage> messages;
  final String localStation;
  final bool canCompose;
  final ValueChanged<String> onCompose;
  final VoidCallback onBeaconSettings;

  const OtaConversationPanel({
    super.key,
    required this.messages,
    required this.localStation,
    required this.canCompose,
    required this.onCompose,
    required this.onBeaconSettings,
  });

  @override
  State<OtaConversationPanel> createState() => _OtaConversationPanelState();
}

class _OtaConversationPanelState extends State<OtaConversationPanel> {
  bool _expanded = true;
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _refresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).otaOpenFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final replies = <OtaReceived>[];
    final seen = <String>{};
    for (final message in widget.messages) {
      if (message.isSender ||
          !isOtaPeer(message.senderCallsign) ||
          message.authState == ChatAuthState.failed) {
        continue;
      }
      // RF and internet copies retain their original timestamp in history.
      final key = '${message.time.millisecondsSinceEpoch}:${message.message}';
      if (!seen.add(key)) continue;
      final reply = decodeOtaReply(message.message);
      if (reply != null) replies.add(OtaReceived(reply, message.time));
    }
    replies.sort((a, b) => a.time.compareTo(b.time));
    final ops = OtaPages();
    var chasers = OtaPages();
    final info = <String, OtaReceived>{};
    final descriptions = <String, OtaReceived>{};
    final activities = <OtaReceived>[];
    OtaReceived? host;
    for (final received in replies) {
      final r = received.reply;
      switch (r.kind) {
        case OtaReplyKind.ops:
          ops.add(received);
        case OtaReplyKind.chasers:
          chasers.add(received);
        case OtaReplyKind.info:
        case OtaReplyKind.missing:
          info[r.station!.split('-').first] = received;
        case OtaReplyKind.description:
          descriptions[r.station!.split('-').first] = received;
        case OtaReplyKind.hosting:
          if (r.station == widget.localStation) {
            if (host == null ||
                received.time.difference(host.time) >=
                    const Duration(hours: 2)) {
              host = received;
              chasers = OtaPages();
              activities.removeWhere(
                (a) => const {
                  OtaReplyKind.beaconHost,
                  OtaReplyKind.hosting,
                  OtaReplyKind.complete,
                  OtaReplyKind.pendingQsl,
                }.contains(a.reply.kind),
              );
            }
          }
          activities.add(received);
        case OtaReplyKind.complete:
          host = null;
          activities.removeWhere(
            (a) => const {
              OtaReplyKind.beaconHost,
              OtaReplyKind.hosting,
              OtaReplyKind.pendingQsl,
            }.contains(a.reply.kind),
          );
          activities.add(received);
        case OtaReplyKind.beaconChase:
        case OtaReplyKind.chasing:
        case OtaReplyKind.confirmed:
          if (activities.any(
            (a) =>
                a.reply.kind == r.kind &&
                a.reply.station?.split('-').first ==
                    r.station?.split('-').first,
          )) {
            continue;
          }
          activities.removeWhere(
            (a) =>
                const {
                  OtaReplyKind.beaconChase,
                  OtaReplyKind.chasing,
                  OtaReplyKind.confirmed,
                }.contains(a.reply.kind) &&
                a.reply.station?.split('-').first ==
                    r.station?.split('-').first,
          );
          activities.add(received);
        case OtaReplyKind.beaconHost:
          if (!activities.any((a) => a.reply.kind == OtaReplyKind.beaconHost)) {
            activities.add(received);
          }
        default:
          activities.add(received);
      }
    }
    final hosting =
        host != null && now.difference(host.time) < const Duration(hours: 2);
    final waiting = chasers.received;
    final discovered = ops.received;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.cell_tower, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.otaTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: _expanded ? l10n.otaCollapse : l10n.otaExpand,
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          if (_expanded)
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _action(
                          l10n.otaCheckSetup,
                          'PING',
                          Icons.network_check,
                        ),
                        _action(l10n.otaFindOps, 'CQ!', Icons.search),
                        _action(l10n.otaHost, 'HOST', Icons.cell_tower),
                        TextButton.icon(
                          onPressed: widget.onBeaconSettings,
                          icon: const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                          ),
                          label: Text(l10n.otaBeaconSettings),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              _open(Uri.https('aprsota.org', '/handbook')),
                          icon: const Icon(Icons.help_outline, size: 16),
                          label: Text(l10n.otaHandbook),
                        ),
                        TextButton(
                          onPressed: () => _open(
                            Uri.https(
                              'aprsota.org',
                              '/${widget.localStation.split('-').first}',
                            ),
                          ),
                          child: Text(l10n.otaMyActivity),
                        ),
                      ],
                    ),
                    Text(
                      l10n.otaGuide,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (hosting) ...[
                      const Divider(),
                      Text(l10n.otaHosting(widget.localStation)),
                      Wrap(
                        spacing: 6,
                        children: [
                          _action('INFO', 'INFO!', Icons.info_outline),
                          _action('TIME', 'TIME!', Icons.timer_outlined),
                          _action('CHASERS', 'CHASERS!', Icons.people_outline),
                          _action('STAY', 'STAY', Icons.more_time),
                          _action('BLAST', 'BLAST', Icons.campaign_outlined),
                          _action(
                            l10n.otaEndOp,
                            'DONE',
                            Icons.stop_circle_outlined,
                          ),
                        ],
                      ),
                      if (waiting.isNotEmpty) ...[
                        _pageStatus(waiting, chasers.ambiguous, now),
                        if (!chasers.ambiguous &&
                            now.difference(waiting.last.time) <
                                const Duration(minutes: 3))
                          for (final station in waiting.expand(
                            (r) => r.reply.stations,
                          ))
                            _stationRow(station, [
                              _action('QSL', 'QSL $station', Icons.reply),
                            ]),
                      ],
                    ],
                    if (discovered.isNotEmpty) ...[
                      const Divider(),
                      Text(
                        l10n.otaOnAir,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      _pageStatus(discovered, ops.ambiguous, now),
                      if (!ops.ambiguous)
                        for (final page in discovered)
                          for (final op in page.reply.ops)
                            _opCard(
                              op,
                              page.time,
                              info[op.station.split('-').first],
                              descriptions[op.station.split('-').first],
                              now,
                            ),
                    ],
                    for (final detail in info.values)
                      if (!discovered.any(
                        (p) => p.reply.ops.any(
                          (op) =>
                              op.station.split('-').first ==
                              detail.reply.station!.split('-').first,
                        ),
                      ))
                        if (detail.reply.kind == OtaReplyKind.missing)
                          _activity(detail, hosting, now)
                        else
                          _opCard(
                            detail.reply.ops.single,
                            detail.time,
                            detail,
                            descriptions[detail.reply.station!
                                .split('-')
                                .first],
                            now,
                          ),
                    if (activities.isNotEmpty) ...[
                      const Divider(),
                      for (final activity in activities.reversed.take(6))
                        _activity(activity, hosting, now),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _action(String label, String command, IconData icon) =>
      TextButton.icon(
        onPressed: widget.canCompose ? () => widget.onCompose(command) : null,
        icon: Icon(icon, size: 16),
        label: Text(label),
      );

  Widget _stationRow(String station, List<Widget> actions) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    children: [Text(station), ...actions],
  );

  Widget _pageStatus(List<OtaReceived> pages, bool ambiguous, DateTime now) {
    final l10n = AppLocalizations.of(context);
    final total = pages.first.reply.total;
    final count = pages.fold(
      0,
      (n, p) => n + p.reply.ops.length + p.reply.stations.length,
    );
    return Text(
      ambiguous
          ? l10n.otaUncertain
          : now.difference(pages.last.time) >= const Duration(minutes: 3)
          ? l10n.otaStale
          : total == 0
          ? l10n.otaNoneReported
          : l10n.otaPages(pages.length, pages.first.reply.pages, count, total),
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  Widget _opCard(
    OtaOp op,
    DateTime time,
    OtaReceived? detail,
    OtaReceived? description,
    DateTime now,
  ) {
    final l10n = AppLocalizations.of(context);
    if (detail?.reply.kind == OtaReplyKind.missing &&
        !detail!.time.isBefore(time)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.otaNotHosting(op.station)),
          _action(l10n.otaDetails, 'INFO! ${op.station}', Icons.info_outline),
        ],
      );
    }
    final freshDetail =
        detail != null &&
        !detail.time.isBefore(time) &&
        now.difference(detail.time) < const Duration(minutes: 3);
    final shown = freshDetail ? detail.reply.ops.single : op;
    final observed = freshDetail ? detail.time : time;
    final elapsed = now.difference(observed).inMinutes;
    final remaining = shown.minutes == null ? null : shown.minutes! - elapsed;
    final stale = remaining == null || remaining <= 0 || elapsed >= 3;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stationRow(shown.station, [
            _action(
              l10n.otaDetails,
              'INFO! ${shown.station}',
              Icons.info_outline,
            ),
            _action(
              l10n.otaChase,
              'CHASE ${shown.station}',
              Icons.flag_outlined,
            ),
          ]),
          Text(
            '${shown.grid ?? '-'} - ${stale ? l10n.otaStale : l10n.otaMinutes(remaining)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (freshDetail)
            Text(l10n.otaStats(shown.qsos!, shown.waiting!, shown.points!)),
          if (description != null &&
              description.time.difference(observed).abs() <
                  const Duration(minutes: 2))
            Text(description.reply.text ?? ''),
        ],
      ),
    );
  }

  Widget _activity(OtaReceived received, bool hosting, DateTime now) {
    final l10n = AppLocalizations.of(context);
    final r = received.reply;
    final recent = now.difference(received.time) < const Duration(minutes: 5);
    final label = switch (r.kind) {
      OtaReplyKind.beaconHost || OtaReplyKind.beaconChase =>
        recent ? l10n.otaWaitingPosition(widget.localStation) : l10n.otaStale,
      OtaReplyKind.chasing => l10n.otaWaitingQsl(r.station!),
      OtaReplyKind.pendingQsl => l10n.otaPendingQsl(r.station!),
      OtaReplyKind.confirmed => l10n.otaConfirmed(r.station!),
      OtaReplyKind.hosting => l10n.otaHosting(r.station!),
      OtaReplyKind.missing => l10n.otaNotHosting(r.station!),
      OtaReplyKind.time => l10n.otaTimer(r.minutes!, r.cap!),
      _ => r.text ?? r.raw,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                r.kind == OtaReplyKind.confirmed
                    ? Icons.verified_outlined
                    : Icons.info_outline,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text(label)),
            ],
          ),
          if (r.kind == OtaReplyKind.beaconHost ||
              r.kind == OtaReplyKind.beaconChase)
            Text(
              l10n.otaPositionHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (r.text != null && r.text != label) Text(r.text!),
          Text(
            DateFormat.yMd(
              Localizations.localeOf(context).toString(),
            ).add_Hm().format(received.time.toLocal()),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Wrap(
            spacing: 6,
            children: [
              if (r.kind == OtaReplyKind.pendingQsl && hosting)
                _action('QSL', 'QSL ${r.station}', Icons.reply),
              if (r.link != null)
                TextButton(
                  onPressed: () => _open(r.link!),
                  child: Text(l10n.otaViewOp),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
