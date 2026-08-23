/*
Copyright 2026 Ylian Saint-Hilaire

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

//
// allstar_node_dialog.dart - The add/edit editor dialog for an AllStarLink
// channel (node). Channels are managed from the radio panel and persisted on
// Data Broker device 0 ('AllStarNodes'); this file only provides the editor.
//

import 'package:flutter/material.dart';

import '../allstar/allstar_node.dart';
import '../allstar/iax2_constants.dart';
import '../l10n/app_localizations.dart';

/// Shows the add/edit node editor. Returns the new/updated node, or null if
/// cancelled.
Future<AllStarNode?> showAllStarNodeDialog(BuildContext context,
    {AllStarNode? existing}) {
  return showDialog<AllStarNode>(
    context: context,
    builder: (BuildContext ctx) => _AllStarNodeEditor(existing: existing),
  );
}

class _AllStarNodeEditor extends StatefulWidget {
  final AllStarNode? existing;
  const _AllStarNodeEditor({this.existing});

  @override
  State<_AllStarNodeEditor> createState() => _AllStarNodeEditorState();
}

class _AllStarNodeEditorState extends State<_AllStarNodeEditor> {
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _secret;
  late final TextEditingController _number;
  bool _obscure = true;
  AllStarAuthMode _authMode = AllStarAuthMode.node;

  @override
  void initState() {
    super.initState();
    final AllStarNode? n = widget.existing;
    _name = TextEditingController(text: n?.name ?? '');
    _host = TextEditingController(text: n?.host ?? '');
    _port = TextEditingController(text: (n?.port ?? iax2DefaultPort).toString());
    _user = TextEditingController(text: n?.iaxUser ?? '');
    _secret = TextEditingController(text: n?.iaxSecret ?? '');
    _number = TextEditingController(text: n?.nodeNumber ?? '');
    _authMode = n?.authMode ?? AllStarAuthMode.account;
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _secret.dispose();
    _number.dispose();
    super.dispose();
  }

  bool get _valid {
    if (_number.text.trim().isEmpty) return false;
    if (_authMode == AllStarAuthMode.node) return _host.text.trim().isNotEmpty;
    return true;
  }

  void _submit() {
    if (!_valid) return;
    final bool account = _authMode == AllStarAuthMode.account;
    Navigator.of(context).pop(AllStarNode(
      name: _name.text.trim().isNotEmpty ? _name.text.trim() : _number.text.trim(),
      host: account ? '' : _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? iax2DefaultPort,
      iaxUser: account ? '' : _user.text.trim(),
      iaxSecret: account ? '' : _secret.text,
      nodeNumber: _number.text.trim(),
      authMode: _authMode,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.existing == null
          ? l10n.settingsAllStarAddNode
          : l10n.settingsAllStarEditNode),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SegmentedButton<AllStarAuthMode>(
                segments: <ButtonSegment<AllStarAuthMode>>[
                  ButtonSegment<AllStarAuthMode>(
                    value: AllStarAuthMode.account,
                    label: Text(l10n.settingsAllStarAuthModeAccount),
                  ),
                  ButtonSegment<AllStarAuthMode>(
                    value: AllStarAuthMode.node,
                    label: Text(l10n.settingsAllStarAuthModeNode),
                  ),
                ],
                selected: <AllStarAuthMode>{_authMode},
                onSelectionChanged: (Set<AllStarAuthMode> s) =>
                    setState(() => _authMode = s.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: l10n.settingsAllStarNodeName,
                  hintText: l10n.settingsAllStarNodeNameHint,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _number,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: l10n.settingsAllStarNodeNumber),
              ),
              if (_authMode == AllStarAuthMode.node) ...<Widget>[
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final host = TextField(
                      controller: _host,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                          labelText: l10n.settingsAllStarNodeHost),
                    );
                    final port = TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: l10n.settingsAllStarNodePort),
                    );
                    // Stack host/port on narrow screens so the port field and
                    // its label stay legible instead of being crushed.
                    if (constraints.maxWidth < 300) {
                      return Column(
                        children: <Widget>[
                          host,
                          const SizedBox(height: 8),
                          port,
                        ],
                      );
                    }
                    return Row(
                      children: <Widget>[
                        Expanded(flex: 3, child: host),
                        const SizedBox(width: 8),
                        Expanded(child: port),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _user,
                  decoration: InputDecoration(
                      labelText: l10n.settingsAllStarNodeUser),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _secret,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: l10n.settingsAllStarNodeSecret,
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: Text(l10n.commonOk),
        ),
      ],
    );
  }
}
