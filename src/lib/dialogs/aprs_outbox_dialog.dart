import 'package:flutter/material.dart';

import '../aprs/aprs_outbox.dart';
import '../aprs/aprs_link_policy.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

String aprsDeliveryLabel(AppLocalizations l10n, AprsDelivery state) => switch (state) {
  AprsDelivery.queued => l10n.aprsDeliveryQueued,
  AprsDelivery.sent => l10n.aprsDeliverySent,
  AprsDelivery.digipeated => l10n.aprsDeliveryDigipeated,
  AprsDelivery.delivered => l10n.aprsDeliveryDelivered,
  AprsDelivery.rejected => l10n.aprsDeliveryRejected,
  AprsDelivery.failed => l10n.aprsDeliveryFailed,
  AprsDelivery.paused => l10n.aprsDeliveryPaused,
  AprsDelivery.stopped => l10n.aprsDeliveryStopped,
};

String aprsComposeErrorLabel(AppLocalizations l10n, AprsComposeError error) => switch (error) {
  AprsComposeError.empty => l10n.aprsEmptyMessage,
  AprsComposeError.ascii => l10n.aprsAsciiOnly,
  AprsComposeError.reserved => l10n.aprsReservedText,
  AprsComposeError.tooLong => l10n.aprsTooLong,
  AprsComposeError.address => l10n.aprsInvalidAddress,
  AprsComposeError.radio => l10n.aprsNoChannel,
};

String aprsLinkPolicyLabel(AppLocalizations l10n, AprsLinkPolicy policy) => switch (policy) {
  AprsLinkPolicy.automatic => l10n.aprsLinkAutomatic,
  AprsLinkPolicy.rfOnly => l10n.aprsLinkRfOnly,
  AprsLinkPolicy.internetOnly => l10n.aprsLinkInternetOnly,
  AprsLinkPolicy.both => l10n.aprsLinkBoth,
};

List<AprsOutgoingMessage> aprsOutboxSnapshot(Object? data) {
  if (data is! List) return [];
  return data.map((m) => AprsOutgoingMessage.fromJson(Map<String, dynamic>.from(m as Map))).toList();
}

Future<void> showAprsOutboxDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AprsOutboxDialog());

class _AprsOutboxDialog extends StatefulWidget {
  const _AprsOutboxDialog();
  @override
  State<_AprsOutboxDialog> createState() => _AprsOutboxDialogState();
}

class _AprsOutboxDialogState extends State<_AprsOutboxDialog> {
  final _broker = DataBrokerClient();
  List<AprsOutgoingMessage> _messages = [];
  late int _attempts;
  late int _seconds;

  @override
  void initState() {
    super.initState();
    _attempts = (_broker.getValue<int>(0, 'AprsRetryAttempts', 6) ?? 6).clamp(1, 10);
    _seconds = (_broker.getValue<int>(0, 'AprsRetrySeconds', 30) ?? 30).clamp(10, 300);
    _read(_broker.getValueDynamic(1, 'AprsOutbox', []));
    _broker.subscribe(deviceId: 1, name: 'AprsOutbox', callback: (_, _, data) {
      if (mounted) setState(() => _read(data));
    });
  }

  void _read(Object? data) {
    _messages = aprsOutboxSnapshot(data)..sort((a, b) => b.created.compareTo(a.created));
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final delays = {10, 15, 30, 60, 90, 120, 180, 240, 300, _seconds}.toList()..sort();
    return HTDialog(
      title: l10n.aprsOutbox,
      maxWidth: 620,
      maxHeight: 650,
      content: SizedBox(
        height: 470,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.aprsRetrySettings),
          Wrap(spacing: 16, children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${l10n.aprsRetryAttempts}: '),
              DropdownButton<int>(value: _attempts,
                items: [for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _attempts = value);
                  _broker.dispatch(deviceId: 0, name: 'AprsRetryAttempts', data: value);
                }),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${l10n.aprsRetrySeconds}: '),
              DropdownButton<int>(value: _seconds,
                items: [for (final delay in delays) DropdownMenuItem(value: delay, child: Text('$delay'))],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _seconds = value);
                  _broker.dispatch(deviceId: 0, name: 'AprsRetrySeconds', data: value);
                }),
            ]),
          ]),
          Text(l10n.aprsStopNote, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Expanded(child: _messages.isEmpty ? Center(child: Text(l10n.aprsOutboxEmpty)) :
            ListView.builder(itemCount: _messages.length, itemBuilder: (_, index) {
              final message = _messages[index];
              final canRetry = !message.parts.any((p) => p.pending) && message.parts.any((p) => !p.answered);
              return Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${message.source} > ${message.destination} - ${aprsDeliveryLabel(l10n, message.state)}'),
                  Text(aprsLinkPolicyLabel(l10n, message.linkPolicy), style: Theme.of(context).textTheme.bodySmall),
                  Text(message.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                  for (var i = 0; i < message.parts.length; i++)
                    Text('${i + 1}/${message.parts.length}: ${aprsDeliveryLabel(l10n, message.parts[i].state)}'
                      ' (${message.parts[i].attempts}/${message.maxAttempts})'
                      '${message.parts[i].error == null ? '' : ' - ${message.parts[i].error}'}',
                      style: Theme.of(context).textTheme.bodySmall),
                  Wrap(children: [
                    if (canRetry) TextButton(onPressed: () => _broker.dispatch(deviceId: 1,
                      name: 'RetryAprsMessage', data: message.id, store: false), child: Text(l10n.aprsRetryResume)),
                    if (message.active) TextButton(onPressed: () => _broker.dispatch(deviceId: 1,
                      name: 'StopAprsMessage', data: message.id, store: false), child: Text(l10n.aprsStopRetries)),
                  ]),
                ],
              )));
            })),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonClose))],
    );
  }
}
