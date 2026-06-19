# Widget Guide

This guide covers the UI components and tab widgets in HTCommander.

## Radio Panel

The `RadioPanelControl` widget (`widgets/radio_panel.dart`) displays the radio with overlaid controls.

### Layout

```
┌─────────────────────┐
│      VR-N76         │  ← Friendly name
│    ┌─────────┐      │
│    │  APRS   │      │  ← VFO A (channel name)
│    │144.390  │      │  ← VFO A (frequency)
│    ├─────────┤      │  ← Separator
│    │ Simplex │      │  ← VFO B (channel name)
│    │146.520  │      │  ← VFO B (frequency)
│    │    GPS: │      │  ← GPS status
│    └─────────┘      │
│    ▓▓▓▓▓░░░░░       │  ← RSSI bar
│                     │
│    [  Radio.png  ]  │
│                     │
├─────────────────────┤
│ [     Connect     ] │  ← Connect button (disconnected)
└─────────────────────┘

OR when connected:

├─────────────────────┤
│ APRS │Simplex│Rptr  │  ← Channel grid
│ Wthr │ FRS 1 │GMRS 1│
└─────────────────────┘
```

### Key Features

- **Fixed width image**: Radio always 280px wide, centered
- **Overlay positioning**: Controls positioned as ratios of original image dimensions
- **Context menu on channels**: Right-click or long-press shows menu
- **State management**: `_isConnected`, `_isConnecting`, VFO states

### Channel Context Menu

```dart
// Triggered by right-click or long-press on channel
void _showChannelContextMenu(BuildContext context, Offset position, RadioChannelInfo channel) {
  showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(...),
    items: [
      PopupMenuItem(value: 'show', child: Text('Show')),
      PopupMenuItem(value: 'setA', child: Text('Set VFO A')),
      PopupMenuItem(value: 'setB', child: Text('Set VFO B')),
      PopupMenuDivider(),
      PopupMenuItem(value: 'showAll', child: Text('Show All Channels')),
    ],
  );
}
```

## Tab Widgets

All tabs follow a consistent pattern:

### Basic Tab Structure

```dart
class MyTab extends StatefulWidget {
  const MyTab({super.key});

  @override
  State<MyTab> createState() => _MyTabState();
}

class _MyTabState extends State<MyTab> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with controls
        _buildHeader(),
        // Main content
        Expanded(child: _buildContent()),
        // Optional footer
        _buildFooter(),
      ],
    );
  }
}
```

### Responsive Headers

Headers use `LayoutBuilder` to hide controls when narrow:

```dart
Widget _buildHeader() {
  return LayoutBuilder(
    builder: (context, constraints) {
      final showButton = constraints.maxWidth > 200;
      
      return Container(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            const Text('Title'),
            const Spacer(),
            if (showButton)
              ElevatedButton(
                onPressed: _onAction,
                child: const Text('Action'),
              ),
          ],
        ),
      );
    },
  );
}
```

### Overflow Prevention

Tabs use several techniques to prevent overflow:

1. **Clip behavior on containers**:
```dart
Container(
  clipBehavior: Clip.hardEdge,
  decoration: BoxDecoration(), // Required for clipBehavior
  child: ...
)
```

2. **Flexible/Expanded widgets**:
```dart
Row(
  children: [
    Expanded(child: Text('Long text...', overflow: TextOverflow.ellipsis)),
    const SizedBox(width: 8),
    IconButton(...),
  ],
)
```

3. **LayoutBuilder for conditional content**:
```dart
LayoutBuilder(
  builder: (context, constraints) {
    if (constraints.maxWidth < 300) {
      return CompactView();
    }
    return FullView();
  },
)
```

## Common Patterns

### Table with Sortable Columns

Used in Mail, Contacts tabs:

```dart
DataTable(
  sortColumnIndex: _sortColumnIndex,
  sortAscending: _sortAscending,
  columns: [
    DataColumn(
      label: Text('Name'),
      onSort: (columnIndex, ascending) {
        setState(() {
          _sortColumnIndex = columnIndex;
          _sortAscending = ascending;
          _sortData();
        });
      },
    ),
  ],
  rows: _data.map((item) => DataRow(
    cells: [DataCell(Text(item.name))],
  )).toList(),
)
```

### Chat/Message List

Used in APRS, BBS, Chat widgets:

```dart
ListView.builder(
  reverse: true,  // Latest at bottom
  itemCount: _messages.length,
  itemBuilder: (context, index) {
    final message = _messages[index];
    return ChatBubble(
      message: message,
      isOutgoing: message.isFromMe,
    );
  },
)
```

### Input with Send Button

```dart
Row(
  children: [
    Expanded(
      child: TextField(
        controller: _inputController,
        decoration: const InputDecoration(
          hintText: 'Type message...',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _sendMessage(),
      ),
    ),
    const SizedBox(width: 8),
    IconButton(
      icon: const Icon(Icons.send),
      onPressed: _sendMessage,
    ),
  ],
)
```

## Color Scheme

Consistent colors matching the C# app:

| Use | Color | Hex |
|-----|-------|-----|
| Dialog background | Light gray | `#D3D3D3` |
| Radio display bg | Dark gray | `#565658` |
| Panel background | Mid gray | `#808080` |
| Active VFO | Yellow | `#DDD300` |
| Inactive VFO | Light gray | `#D3D3D3` |
| Channel A selected | Pale goldenrod | `#EEE8AA` |
| Channel B selected | Khaki | `#F0E68C` |
| Channel default | Dark khaki | `#BDB76B` |

## Creating a New Tab

1. Create `lib/widgets/my_tab.dart`:

```dart
import 'package:flutter/material.dart';

class MyTab extends StatefulWidget {
  const MyTab({super.key});

  @override
  State<MyTab> createState() => _MyTabState();
}

class _MyTabState extends State<MyTab> {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('My Tab Content'),
    );
  }
}
```

2. Add import in `main.dart`:
```dart
import 'widgets/my_tab.dart';
```

3. Add to tab list in `_HTCommanderHomeState`:
```dart
final List<Tab> _tabs = [
  // ... existing tabs
  const Tab(text: 'My Tab'),
];

final List<Widget> _tabContents = [
  // ... existing contents
  const MyTab(),
];
```

4. Add detach menu item (optional):
```dart
PopupMenuItem(
  value: 'detach_mytab',
  child: Text('Detach My Tab'),
),
```
