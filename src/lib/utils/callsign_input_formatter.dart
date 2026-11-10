import 'package:flutter/services.dart';

class CallsignInputFormatter extends TextInputFormatter {
  const CallsignInputFormatter({this.uppercase = true});

  final bool uppercase;

  static final _missingDash = RegExp(
    r'(^|[ ,;])([A-Z0-9]*[A-Z][0-9][A-Z]+)([0-9]{1,2})(?=$|[ ,;])',
    caseSensitive: false,
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;

    var text = uppercase ? newValue.text.toUpperCase() : newValue.text;
    final insertions = <int>[];
    final deletedDash =
        oldValue.text.contains('-') &&
        oldValue.text.replaceFirst('-', '') == newValue.text;
    if (!deletedDash) {
      for (final match in _missingDash.allMatches(text)) {
        final callsign = match.group(2)!;
        if (callsign.length <= 6 && int.parse(match.group(3)!) <= 15) {
          insertions.add(
            match.start + match.group(1)!.length + callsign.length,
          );
        }
      }
    }
    for (final offset in insertions.reversed) {
      text = '${text.substring(0, offset)}-${text.substring(offset)}';
    }
    if (text == newValue.text) return newValue;

    int adjustedOffset(int offset) => offset < 0
        ? offset
        : offset + insertions.where((insertion) => insertion <= offset).length;

    return newValue.copyWith(
      text: text,
      selection: newValue.selection.copyWith(
        baseOffset: adjustedOffset(newValue.selection.baseOffset),
        extentOffset: adjustedOffset(newValue.selection.extentOffset),
      ),
      composing: TextRange.empty,
    );
  }
}

class CallsignRecipientInputFormatter extends TextInputFormatter {
  final _automaticDashes = <int>{};
  String _lastText = '';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    if (oldValue.text != _lastText) _automaticDashes.clear();

    var prefix = 0;
    while (prefix < oldValue.text.length &&
        prefix < newValue.text.length &&
        oldValue.text[prefix] == newValue.text[prefix]) {
      prefix++;
    }
    var oldEnd = oldValue.text.length;
    var newEnd = newValue.text.length;
    while (oldEnd > prefix &&
        newEnd > prefix &&
        oldValue.text[oldEnd - 1] == newValue.text[newEnd - 1]) {
      oldEnd--;
      newEnd--;
    }
    final delta = newEnd - oldEnd;
    final dashes = <int>{
      for (final offset in _automaticDashes)
        if (offset < prefix) offset else if (offset >= oldEnd) offset + delta,
    };
    final removals = <int>[];
    for (final token in RegExp(r'[^ ,;]+').allMatches(newValue.text)) {
      if (!token.group(0)!.contains(RegExp(r'[@._%+/]'))) continue;
      removals.addAll(
        dashes.where((offset) => offset >= token.start && offset < token.end),
      );
    }
    removals.sort();
    var value = newValue;
    for (final offset in removals.reversed) {
      int shifted(int position) => position > offset ? position - 1 : position;
      value = value.copyWith(
        text: value.text.replaceRange(offset, offset + 1, ''),
        selection: value.selection.copyWith(
          baseOffset: shifted(value.selection.baseOffset),
          extentOffset: shifted(value.selection.extentOffset),
        ),
        composing: TextRange.empty,
      );
    }
    final remaining = <int>{
      for (final offset in dashes)
        if (!removals.contains(offset))
          offset - removals.where((removal) => removal < offset).length,
    };
    final formatted = const CallsignInputFormatter(
      uppercase: false,
    ).formatEditUpdate(oldValue, value);
    _automaticDashes.clear();
    var sourceOffset = 0;
    for (var offset = 0; offset < formatted.text.length; offset++) {
      if (sourceOffset < value.text.length &&
          formatted.text[offset] == value.text[sourceOffset]) {
        if (remaining.contains(sourceOffset)) _automaticDashes.add(offset);
        sourceOffset++;
      } else {
        _automaticDashes.add(offset);
      }
    }
    _lastText = formatted.text;
    return formatted;
  }
}
