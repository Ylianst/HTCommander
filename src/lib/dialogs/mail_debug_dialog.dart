import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';
import '../winlink/winlink_client.dart';
import 'dialog_utils.dart';

/// Shows the Winlink traffic / debug log dialog (ports `MailClientDebugForm`).
///
/// Subscribes to the broker traffic events emitted by `WinlinkClient` and
/// renders them in a console-style view.
Future<void> showMailDebugDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _MailDebugDialog(),
  );
}

/// A single rendered console line with a colored prefix and body.
class _DebugLine {
  const _DebugLine({
    this.prefix,
    this.prefixColor,
    required this.text,
    required this.textColor,
  });

  final String? prefix;
  final Color? prefixColor;
  final String text;
  final Color textColor;
}

class _MailDebugDialog extends StatefulWidget {
  const _MailDebugDialog();

  @override
  State<_MailDebugDialog> createState() => _MailDebugDialogState();
}

class _MailDebugDialogState extends State<_MailDebugDialog> {
  static const Color _green = Color(0xFF2E8B2E);
  static const Color _cornflowerBlue = Color(0xFF6495ED);
  static const Color _gainsboro = Color(0xFFDCDCDC);
  static const Color _yellow = Color(0xFFFFD500);

  final DataBrokerClient _broker = DataBrokerClient();
  final ScrollController _scrollController = ScrollController();
  final List<_DebugLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkTraffic',
      callback: _onTraffic,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkStateMessage',
      callback: _onStateMessage,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkDebugClear',
      callback: _onClear,
    );
    _broker.subscribe(
      deviceId: 1,
      name: 'WinlinkDebugHistory',
      callback: _onHistory,
    );

    // Request debug history from the WinlinkClient.
    _broker.dispatch(
      deviceId: 1,
      name: 'WinlinkDebugHistoryRequest',
      data: true,
      store: false,
    );
  }

  @override
  void dispose() {
    _broker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onHistory(int deviceId, String name, Object? data) {
    if (data is! List) return;
    final history = data.whereType<WinlinkDebugEntry>().toList();
    setState(() {
      _lines.clear();
      for (final entry in history) {
        _appendEntry(
          entry.address,
          entry.outgoing,
          entry.data,
          entry.isStateMessage,
        );
      }
    });
    _scrollToBottom();
  }

  void _onTraffic(int deviceId, String name, Object? data) {
    if (data is! Map) return;
    final address = (data['Address'] as String?) ?? '';
    final outgoing = (data['Outgoing'] as bool?) ?? false;
    final text = data['Data']?.toString() ?? '';
    if (text.isEmpty) return;
    setState(() => _appendEntry(address, outgoing, text, false));
    _scrollToBottom();
  }

  void _onStateMessage(int deviceId, String name, Object? data) {
    final text = data as String?;
    if (text == null || text.isEmpty) return;
    setState(() => _appendEntry('', false, text, true));
    _scrollToBottom();
  }

  void _onClear(int deviceId, String name, Object? data) {
    setState(() => _lines.clear());
  }

  void _appendEntry(
    String address,
    bool outgoing,
    String text,
    bool isStateMessage,
  ) {
    if (isStateMessage) {
      _lines.add(_DebugLine(text: text, textColor: _yellow));
    } else {
      _lines.add(
        _DebugLine(
          prefix: outgoing ? '$address < ' : '$address > ',
          prefixColor: _green,
          text: text,
          textColor: outgoing ? _cornflowerBlue : _gainsboro,
        ),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return HTDialog(
      title: l10n.mdbgTitle,
      maxWidth: 640,
      maxHeight: 520,
      content: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(color: Colors.grey.shade700),
        ),
        padding: const EdgeInsets.all(8),
        child: _lines.isEmpty
            ? Center(
                child: Text(
                  l10n.mdbgNoTraffic,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              )
            : SingleChildScrollView(
                controller: _scrollController,
                child: SelectableText.rich(
                  TextSpan(
                    children: [
                      for (var i = 0; i < _lines.length; i++) ...[
                        if (_lines[i].prefix != null)
                          TextSpan(
                            text: _lines[i].prefix,
                            style: TextStyle(color: _lines[i].prefixColor),
                          ),
                        TextSpan(
                          text: _lines[i].text,
                          style: TextStyle(color: _lines[i].textColor),
                        ),
                        if (i < _lines.length - 1) const TextSpan(text: '\n'),
                      ],
                    ],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: DialogStyles.primaryButtonStyle(context),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}
