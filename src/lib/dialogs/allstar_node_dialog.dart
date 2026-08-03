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
// allstar_node_dialog.dart - Settings UI for managing saved AllStarLink nodes
// and the add/edit node editor dialog. The node list is persisted directly on
// Data Broker device 0 ('AllStarNodes'); the AllStarManager watches that key and
// (re)advertises AllStarLink availability accordingly.
//

import 'package:flutter/material.dart';

import '../allstar/allstar_node.dart';
import '../allstar/iax2_constants.dart';
import '../l10n/app_localizations.dart';
import '../services/data_broker_client.dart';

/// The AllStarLink settings tab body: a list of saved nodes with add / edit /
/// delete, backed by Data Broker device 0.
class AllStarNodesSettings extends StatefulWidget {
  const AllStarNodesSettings({super.key});

  @override
  State<AllStarNodesSettings> createState() => _AllStarNodesSettingsState();
}

class _AllStarNodesSettingsState extends State<AllStarNodesSettings> {
  final DataBrokerClient _broker = DataBrokerClient();
  List<AllStarNode> _nodes = <AllStarNode>[];

  @override
  void initState() {
    super.initState();
    _nodes = _load();
  }

  List<AllStarNode> _load() {
    final Object? raw = _broker.getValueDynamic(0, allStarNodesKey);
    if (raw is! List) return <AllStarNode>[];
    final List<AllStarNode> out = <AllStarNode>[];
    for (final Object? e in raw) {
      if (e is Map) out.add(AllStarNode.fromMap(e));
    }
    return out;
  }

  void _save() {
    _broker.dispatch(
      deviceId: 0,
      name: allStarNodesKey,
      data: _nodes.map((AllStarNode n) => n.toMap()).toList(),
      store: true,
    );
  }

  Future<void> _add() async {
    final AllStarNode? node = await showAllStarNodeDialog(context);
    if (node == null) return;
    setState(() => _nodes = <AllStarNode>[..._nodes, node]);
    _save();
  }

  Future<void> _edit(int index) async {
    final AllStarNode? node =
        await showAllStarNodeDialog(context, existing: _nodes[index]);
    if (node == null) return;
    setState(() {
      final List<AllStarNode> next = <AllStarNode>[..._nodes];
      next[index] = node;
      _nodes = next;
    });
    _save();
  }

  Future<void> _delete(int index) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool ok = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text(l10n.settingsAllStarDeleteNode),
            content: Text(
                l10n.settingsAllStarDeleteNodeConfirm(_nodes[index].name)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(l10n.commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(l10n.settingsAllStarDeleteNode),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    setState(() {
      final List<AllStarNode> next = <AllStarNode>[..._nodes];
      next.removeAt(index);
      _nodes = next;
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.settingsAllStarIntro),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {},
            child: Text('AllStarLink.org',
                style: TextStyle(
                    color: theme.colorScheme.primary,
                    decoration: TextDecoration.underline)),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Text(l10n.settingsAllStarNodes,
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add),
                label: Text(l10n.settingsAllStarAddNode),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_nodes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(l10n.settingsAllStarNoNodes,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            )
          else
            ..._nodes.asMap().entries.map((MapEntry<int, AllStarNode> e) {
              final AllStarNode n = e.value;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.cell_tower),
                  title: Text(n.name.isNotEmpty ? n.name : n.nodeNumber),
                  subtitle: Text(n.description),
                  onTap: () => _edit(e.key),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: l10n.settingsAllStarDeleteNode,
                    onPressed: () => _delete(e.key),
                  ),
                ),
              );
            }),
          const SizedBox(height: 12),
          Text(l10n.settingsAllStarNodeHelp,
              style: TextStyle(
                  fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

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

  bool get _valid =>
      _host.text.trim().isNotEmpty && _number.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    Navigator.of(context).pop(AllStarNode(
      name: _name.text.trim().isNotEmpty ? _name.text.trim() : _number.text.trim(),
      host: _host.text.trim(),
      port: int.tryParse(_port.text.trim()) ?? iax2DefaultPort,
      iaxUser: _user.text.trim(),
      iaxSecret: _secret.text,
      nodeNumber: _number.text.trim(),
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
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: l10n.settingsAllStarNodeName,
                  hintText: l10n.settingsAllStarNodeNameHint,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _host,
                      decoration: InputDecoration(
                          labelText: l10n.settingsAllStarNodeHost),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: l10n.settingsAllStarNodePort),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _number,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: l10n.settingsAllStarNodeNumber),
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
