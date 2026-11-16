// Copyright 2026 Ylian Saint-Hilaire - Apache 2.0
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import '../widgets/chat_widget.dart';

/// Replaces each archive page instead of accumulating older messages in RAM.
class StoredHistoryDialog extends StatefulWidget {
  const StoredHistoryDialog({
    super.key,
    required this.sources,
    required this.messageBuilder,
    this.onMessageDoubleTap,
    this.onMessageContextMenu,
  });

  final Map<String, String> sources;
  final ChatMessage? Function(Map<String, dynamic> data, int id) messageBuilder;
  final ValueChanged<ChatMessage>? onMessageDoubleTap;
  final void Function(ChatMessage, Offset)? onMessageContextMenu;

  @override
  State<StoredHistoryDialog> createState() => _StoredHistoryDialogState();
}

class _StoredHistoryDialogState extends State<StoredHistoryDialog> {
  final DataBrokerClient _broker = DataBrokerClient();
  final String _clientId =
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
  late String _source;
  List<ChatMessage> _messages = [];
  List<int>? _before;
  bool _hasMore = false;
  bool _loading = false;
  bool _atNewest = true;
  String? _error;
  String? _requestId;
  int _serial = 0;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _source = widget.sources.keys.first;
    _broker.subscribe(
      deviceId: 1,
      name: 'StoredChatHistoryPage',
      callback: _onPage,
    );
    _load(null);
  }

  void _load(List<int>? before) {
    _timeout?.cancel();
    setState(() {
      _loading = true;
      _error = null;
      _atNewest = before == null;
      _requestId = '$_clientId-${_serial++}';
    });
    _timeout = Timer(const Duration(seconds: 15), () {
      _fail(TimeoutException('Stored history request timed out'));
    });
    _broker.dispatch(
      deviceId: 1,
      name: 'RequestStoredChatHistory',
      store: false,
      data: {'requestId': _requestId, 'source': _source, 'before': before},
    );
  }

  void _onPage(int deviceId, String name, Object? data) {
    if (!mounted || data is! Map || data['requestId'] != _requestId) return;
    _timeout?.cancel();
    if (data['error'] != null) {
      _fail(StateError(data['error'].toString()));
      return;
    }
    try {
      final entries = data['entries'] as List;
      final messages = <ChatMessage>[];
      for (final entry in entries) {
        final row = entry as Map;
        final message = widget.messageBuilder(
          Map<String, dynamic>.from(row['data'] as Map),
          row['id'] as int,
        );
        if (message != null) messages.add(message);
      }
      setState(() {
        _messages = messages;
        _before = (data['before'] as List?)?.cast<int>();
        _hasMore = data['hasMore'] == true;
        _loading = false;
        _requestId = null;
      });
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    _broker.logError('Stored history: $error');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _requestId = null;
      _error = '$error';
    });
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _broker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return Dialog(
      child: SizedBox(
        width: 900,
        height: 650,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(AppLocalizations.of(context).chatHistory),
                  ),
                  if (widget.sources.length > 1)
                    DropdownButton<String>(
                      value: _source,
                      items: [
                        for (final entry in widget.sources.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: _loading
                          ? null
                          : (source) {
                              if (source == null) return;
                              _source = source;
                              _messages = [];
                              _before = null;
                              _hasMore = false;
                              _load(null);
                            },
                    ),
                  IconButton(
                    tooltip: material.firstPageTooltip,
                    icon: const Icon(Icons.first_page),
                    onPressed: _loading || _atNewest ? null : () => _load(null),
                  ),
                  IconButton(
                    tooltip: material.previousPageTooltip,
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _loading || !_hasMore
                        ? null
                        : () => _load(_before),
                  ),
                  IconButton(
                    tooltip: material.refreshIndicatorSemanticLabel,
                    icon: const Icon(Icons.refresh),
                    onPressed: _loading ? null : () => _load(null),
                  ),
                  CloseButton(),
                ],
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: SelectableText(
                  '${AppLocalizations.of(context).commonError}: $_error',
                ),
              ),
            Expanded(
              child: ChatWidget(
                key: ValueKey('$_source-$_before'),
                messages: _messages,
                onMessageDoubleTap: widget.onMessageDoubleTap,
                onMessageContextMenu: widget.onMessageContextMenu,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
