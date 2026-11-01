/*
Copyright 2026 Ylian Saint-Hilaire
Licensed under the Apache License, Version 2.0 (the "License");
http://www.apache.org/licenses/LICENSE-2.0
*/

import 'package:flutter/material.dart';

import '../handlers/agent_api.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';

/// Shows that test agents are connected (see [AgentApi]) and gives the
/// operator a one-click Stop, which releases everything agents hold and turns
/// the agent API off. Hidden while no agent is connected.
class AgentControlBanner extends StatefulWidget {
  const AgentControlBanner({super.key});

  @override
  State<AgentControlBanner> createState() => _AgentControlBannerState();
}

class _AgentControlBannerState extends State<AgentControlBanner> {
  final DataBrokerClient _broker = DataBrokerClient();
  Map<Object?, Object?>? _state;

  @override
  void initState() {
    super.initState();
    _apply(_broker.getValueDynamic(1, AgentApi.controlValue, null));
    _broker.subscribe(
      deviceId: 1,
      name: AgentApi.controlValue,
      callback: (_, _, data) {
        if (mounted) setState(() => _apply(data));
      },
    );
  }

  void _apply(Object? data) => _state = data is Map ? data : null;

  @override
  void dispose() {
    _broker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    if (state == null || state['active'] != true) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final clients = (state['clients'] as num?)?.toInt() ?? 1;
    final radios = (state['radios'] as List?)?.join(', ') ?? '';
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(
          children: [
            Icon(Icons.smart_toy, size: 16, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                radios.isEmpty
                    ? l10n.agentControlActive(clients)
                    : l10n.agentControlActiveRadios(clients, radios),
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: scheme.onErrorContainer,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.stop_circle, size: 16),
              label: Text(l10n.agentControlStop),
              onPressed: () => _broker.dispatch(
                deviceId: 1,
                name: AgentApi.stopEvent,
                data: null,
                store: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
