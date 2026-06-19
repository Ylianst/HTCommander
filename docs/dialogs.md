# Creating Dialogs in HTCommander

This guide explains how to create dialog boxes using the common dialog utilities.

## Quick Reference

### Using Built-in Dialog Helpers

For simple dialogs, use the `DialogHelper` static methods:

```dart
import 'package:htcommander/dialogs/dialogs.dart';

// Confirmation dialog (returns true/false)
final confirmed = await DialogHelper.showConfirmDialog(
  context,
  title: 'Delete Channel',
  message: 'Are you sure you want to delete this channel?',
  okText: 'Delete',      // optional, defaults to 'OK'
  cancelText: 'Cancel',  // optional, defaults to 'Cancel'
);

if (confirmed) {
  // User clicked OK
}

// Information dialog
await DialogHelper.showInfoDialog(
  context,
  title: 'Success',
  message: 'Channel saved successfully.',
);

// Error dialog (includes error icon)
await DialogHelper.showErrorDialog(
  context,
  title: 'Connection Failed',
  message: 'Could not connect to the radio. Please check Bluetooth.',
);
```

## Creating a Custom Dialog

### Step 1: Create the Dialog File

Create a new file in `lib/dialogs/`, e.g., `channel_dialog.dart`:

```dart
import 'package:flutter/material.dart';
import 'dialog_utils.dart';

class ChannelDialog extends StatefulWidget {
  final RadioChannelInfo? channel; // null for new channel

  const ChannelDialog({super.key, this.channel});

  @override
  State<ChannelDialog> createState() => _ChannelDialogState();
}

class _ChannelDialogState extends State<ChannelDialog> {
  late TextEditingController _nameController;
  late TextEditingController _freqController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.channel?.name ?? '');
    _freqController = TextEditingController(
      text: widget.channel?.frequencyDisplay ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _freqController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HTDialog(
      title: widget.channel == null ? 'New Channel' : 'Edit Channel',
      maxWidth: 400,
      maxHeight: 300,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Channel Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _freqController,
            decoration: const InputDecoration(
              labelText: 'Frequency (MHz)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          style: DialogStyles.secondaryButtonStyle(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _onSave,
          style: DialogStyles.primaryButtonStyle(context),
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _onSave() {
    // Validate and return result
    final name = _nameController.text.trim();
    final freq = double.tryParse(_freqController.text) ?? 0;
    
    if (name.isEmpty) {
      DialogHelper.showErrorDialog(
        context,
        title: 'Validation Error',
        message: 'Please enter a channel name.',
      );
      return;
    }

    Navigator.of(context).pop(RadioChannelInfo(
      channelId: widget.channel?.channelId ?? -1,
      name: name,
      rxFreq: (freq * 1000000).round(),
    ));
  }
}
```

### Step 2: Export the Dialog

Add to `lib/dialogs/dialogs.dart`:

```dart
export 'dialog_utils.dart';
export 'about_dialog.dart';
export 'channel_dialog.dart';  // Add this line
```

### Step 3: Show the Dialog

```dart
import 'package:htcommander/dialogs/dialogs.dart';

// Show and get result
final result = await showDialog<RadioChannelInfo>(
  context: context,
  builder: (context) => ChannelDialog(channel: existingChannel),
);

if (result != null) {
  // User saved - result contains the new/edited channel
  print('Saved channel: ${result.name}');
}
```

## Dialog Utilities Reference

### DialogStyles

Common styling constants:

| Property | Description |
|----------|-------------|
| `backgroundColor` | Light gray (`#D3D3D3`) matching C# app |
| `padding` | Standard 16px padding |
| `titleStyle` | 18pt bold text |
| `labelStyle` | 13pt medium weight |
| `bodyStyle` | 13pt regular |
| `linkStyle` | 13pt blue underlined |
| `primaryButtonStyle(context)` | Blue button with white text |
| `secondaryButtonStyle(context)` | Text button with dark text |

### HTDialog Widget

Base dialog with consistent styling:

```dart
HTDialog(
  title: 'Dialog Title',        // optional
  content: MyContent(),         // required - main dialog body
  actions: [                    // optional - bottom buttons
    TextButton(...),
    ElevatedButton(...),
  ],
  maxWidth: 500,                // optional, default 500
  maxHeight: 400,               // optional, default 400
  padding: EdgeInsets.all(16),  // optional
)
```

## Dialog Patterns from C# Reference

When porting dialogs from the C# codebase, follow these patterns:

| C# Pattern | Flutter Equivalent |
|------------|-------------------|
| `Form` | `StatefulWidget` with `HTDialog` |
| `DialogResult.OK` | `Navigator.of(context).pop(result)` |
| `DialogResult.Cancel` | `Navigator.of(context).pop(null)` |
| `ShowDialog()` | `showDialog<T>(context:, builder:)` |
| `MessageBox.Show()` | `DialogHelper.showInfoDialog()` |
| `TextBox` | `TextField` |
| `ComboBox` | `DropdownButton` or `DropdownButtonFormField` |
| `CheckBox` | `Checkbox` or `CheckboxListTile` |
| `NumericUpDown` | `TextField` with `keyboardType: TextInputType.number` |

## Tips

1. **Always dispose controllers** - Use `dispose()` to clean up `TextEditingController`, `FocusNode`, etc.

2. **Return typed results** - Use `showDialog<T>()` with a specific type for type-safe results.

3. **Validate before closing** - Check input validity in the save handler, not just on close.

4. **Match C# sizing** - Check the C# `.Designer.cs` files for original dialog dimensions.

5. **Use responsive layouts** - Use `LayoutBuilder` to adapt when dialogs are resized or on smaller screens.
