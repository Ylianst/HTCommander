import 'package:flutter/material.dart';

import '../aprs/aprs_outbox.dart';
import '../aprs/aprs_link_policy.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import 'dialog_utils.dart';

String aprsDeliveryLabel(AppLocalizations l10n, AprsDelivery state) =>
    switch (state) {
      AprsDelivery.queued => l10n.aprsDeliveryQueued,
      AprsDelivery.sent => l10n.aprsDeliverySent,
      AprsDelivery.digipeated => l10n.aprsDeliveryDigipeated,
      AprsDelivery.delivered => l10n.aprsDeliveryDelivered,
      AprsDelivery.rejected => l10n.aprsDeliveryRejected,
      AprsDelivery.failed => l10n.aprsDeliveryFailed,
      AprsDelivery.paused => l10n.aprsDeliveryPaused,
      AprsDelivery.stopped => l10n.aprsDeliveryStopped,
    };

String aprsComposeErrorLabel(AppLocalizations l10n, AprsComposeError error) =>
    switch (error) {
      AprsComposeError.empty => l10n.aprsEmptyMessage,
      AprsComposeError.ascii => l10n.aprsAsciiOnly,
      AprsComposeError.reserved => l10n.aprsReservedText,
      AprsComposeError.tooLong => l10n.aprsTooLong,
      AprsComposeError.address => l10n.aprsInvalidAddress,
      AprsComposeError.radio => l10n.aprsNoChannel,
    };

String aprsLinkPolicyLabel(AppLocalizations l10n, AprsLinkPolicy policy) =>
    switch (policy) {
      AprsLinkPolicy.automatic => l10n.aprsLinkAutomatic,
      AprsLinkPolicy.rfOnly => l10n.aprsLinkRfOnly,
      AprsLinkPolicy.internetOnly => l10n.aprsLinkInternetOnly,
      AprsLinkPolicy.both => l10n.aprsLinkBoth,
    };

List<AprsOutgoingMessage> aprsOutboxSnapshot(Object? data) {
  if (data is! List) return [];
  return data
      .map(
        (m) =>
            AprsOutgoingMessage.fromJson(Map<String, dynamic>.from(m as Map)),
      )
      .toList();
}

Future<void> showAprsOutboxDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const _AprsOutboxDialog(),
);

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
    _attempts = (_broker.getValue<int>(0, 'AprsRetryAttempts', 6) ?? 6).clamp(
      1,
      10,
    );
    _seconds = (_broker.getValue<int>(0, 'AprsRetrySeconds', 30) ?? 30).clamp(
      10,
      300,
    );
    _read(_broker.getValueDynamic(1, 'AprsOutbox', []));
    _broker.subscribe(
      deviceId: 1,
      name: 'AprsOutbox',
      callback: (_, _, data) {
        if (mounted) setState(() => _read(data));
      },
    );
  }

  void _read(Object? data) {
    _messages = aprsOutboxSnapshot(data)
      ..sort((a, b) => b.created.compareTo(a.created));
  }

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  BoxDecoration _sectionDecoration(ThemeData theme) => BoxDecoration(
    color: theme.colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(12),
    boxShadow: [
      BoxShadow(
        color: theme.shadowColor.withValues(alpha: 0.05),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );

  Widget _buildMessage(AprsOutgoingMessage message, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, swatch) = switch (message.state) {
      AprsDelivery.queued => (Icons.schedule, Colors.amber),
      AprsDelivery.sent => (Icons.send_rounded, Colors.blue),
      AprsDelivery.digipeated => (Icons.cell_tower, Colors.teal),
      AprsDelivery.delivered => (Icons.check_circle, Colors.green),
      AprsDelivery.rejected => (Icons.cancel, Colors.red),
      AprsDelivery.failed => (Icons.error, Colors.red),
      AprsDelivery.paused => (Icons.pause_circle_filled, Colors.orange),
      AprsDelivery.stopped => (Icons.stop_circle, Colors.blueGrey),
    };
    final color = swatch[theme.brightness == Brightness.dark ? 300 : 800]!;
    final status = aprsDeliveryLabel(l10n, message.state);
    final secondaryStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final canRetry =
        !message.parts.any((p) => p.pending) &&
        message.parts.any((p) => !p.answered);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: _sectionDecoration(theme),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: status,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${message.source} > ${message.destination}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  message.text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  aprsLinkPolicyLabel(l10n, message.linkPolicy),
                  style: secondaryStyle,
                ),
                for (var i = 0; i < message.parts.length; i++)
                  Text(
                    '${i + 1}/${message.parts.length}: ${aprsDeliveryLabel(l10n, message.parts[i].state)}'
                    ' (${message.parts[i].attempts}/${message.maxAttempts})'
                    '${message.parts[i].error == null ? '' : ' - ${message.parts[i].error}'}',
                    style: secondaryStyle,
                  ),
                if (canRetry || message.active) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (canRetry)
                        TextButton.icon(
                          onPressed: () => _broker.dispatch(
                            deviceId: 1,
                            name: 'RetryAprsMessage',
                            data: message.id,
                            store: false,
                          ),
                          icon: const Icon(Icons.refresh, size: 18),
                          label: Text(l10n.aprsRetryResume),
                        ),
                      if (message.active)
                        TextButton.icon(
                          onPressed: () => _broker.dispatch(
                            deviceId: 1,
                            name: 'StopAprsMessage',
                            data: message.id,
                            store: false,
                          ),
                          icon: const Icon(Icons.stop, size: 18),
                          label: Text(l10n.aprsStopRetries),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final delays = {10, 15, 30, 60, 90, 120, 180, 240, 300, _seconds}.toList()
      ..sort();
    return Dialog(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 650),
        child: Padding(
          padding: DialogStyles.padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.outbox_rounded, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.aprsOutbox,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: SizedBox(
                  height: 520,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: _sectionDecoration(theme),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.tune,
                                    size: 20,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.aprsRetrySettings,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final width = constraints.maxWidth < 400
                                      ? constraints.maxWidth
                                      : (constraints.maxWidth - 16) / 2;
                                  return Wrap(
                                    spacing: 16,
                                    runSpacing: 12,
                                    children: [
                                      SizedBox(
                                        width: width,
                                        child: DropdownButtonFormField<int>(
                                          initialValue: _attempts,
                                          isExpanded: true,
                                          decoration:
                                              DialogStyles.inputDecoration(
                                                context,
                                                labelText:
                                                    l10n.aprsRetryAttempts,
                                              ),
                                          items: [
                                            for (var i = 1; i <= 10; i++)
                                              DropdownMenuItem(
                                                value: i,
                                                child: Text('$i'),
                                              ),
                                          ],
                                          onChanged: (value) {
                                            if (value == null) return;
                                            setState(() => _attempts = value);
                                            _broker.dispatch(
                                              deviceId: 0,
                                              name: 'AprsRetryAttempts',
                                              data: value,
                                            );
                                          },
                                        ),
                                      ),
                                      SizedBox(
                                        width: width,
                                        child: DropdownButtonFormField<int>(
                                          initialValue: _seconds,
                                          isExpanded: true,
                                          decoration:
                                              DialogStyles.inputDecoration(
                                                context,
                                                labelText:
                                                    l10n.aprsRetrySeconds,
                                              ),
                                          items: [
                                            for (final delay in delays)
                                              DropdownMenuItem(
                                                value: delay,
                                                child: Text('$delay'),
                                              ),
                                          ],
                                          onChanged: (value) {
                                            if (value == null) return;
                                            setState(() => _seconds = value);
                                            _broker.dispatch(
                                              deviceId: 0,
                                              name: 'AprsRetrySeconds',
                                              data: value,
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.aprsStopNote,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_messages.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.outbox_outlined,
                                size: 48,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                l10n.aprsOutboxEmpty,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        SliverList.builder(
                          itemCount: _messages.length,
                          itemBuilder: (_, index) =>
                              _buildMessage(_messages[index], l10n),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: DialogStyles.primaryButtonStyle(context),
                  child: Text(l10n.commonClose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
