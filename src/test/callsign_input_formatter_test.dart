import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/utils/callsign_input_formatter.dart';

void main() {
  const formatter = CallsignInputFormatter();

  TextEditingValue edit(String text) => TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  test('inserts the dash as soon as the SSID digit is typed', () {
    final result = formatter.formatEditUpdate(edit('KK7VZT'), edit('KK7VZT7'));
    expect(result.text, 'KK7VZT-7');
    expect(result.selection.baseOffset, 8);
  });

  test('supports typing and pasting two-digit SSIDs', () {
    expect(
      formatter.formatEditUpdate(edit('N1RMS-10'), edit('KK7VZT7')).text,
      'KK7VZT-7',
    );
    expect(
      formatter.formatEditUpdate(edit('KK7VZT-1'), edit('KK7VZT-15')).text,
      'KK7VZT-15',
    );
    for (var ssid = 0; ssid <= 15; ssid++) {
      expect(
        formatter.formatEditUpdate(edit(''), edit('kk7vzt$ssid')).text,
        'KK7VZT-$ssid',
      );
    }
  });

  test(
    'leaves base callsigns, explicit SSIDs and other identifiers intact',
    () {
      for (final text in [
        'KK7VZT',
        'K7',
        '3DA0ABC',
        'WIDE1-1',
        'KK7VZT-7',
        'KK7VZT16',
        'KK7VZT123',
        'TOOLONG7ABC7',
        'KK7VZT/P',
        'KK7VZT7@EXAMPLE.COM',
        '1234567890',
      ]) {
        expect(formatter.formatEditUpdate(edit(''), edit(text)).text, text);
      }
    },
  );

  test('formats callsigns in a list without changing APRS aliases', () {
    expect(
      formatter
          .formatEditUpdate(edit(''), edit('kk7vzt7, n1abc12 WIDE1-1'))
          .text,
      'KK7VZT-7, N1ABC-12 WIDE1-1',
    );
  });

  test('does not split digit-leading callsign prefixes during typing', () {
    for (final callsign in ['3DA0AB', '3D2ABC', '9A1ABC', '4U1ITU']) {
      var value = edit('');
      for (final character in callsign.split('')) {
        value = formatter.formatEditUpdate(
          value,
          edit('${value.text}$character'),
        );
      }
      expect(value.text, callsign);
      expect(
        formatter.formatEditUpdate(value, edit('${value.text}7')).text,
        '$callsign-7',
      );
    }
  });

  test('does not reinsert a deleted dash or SSID', () {
    expect(
      formatter.formatEditUpdate(edit('KK7VZT-7'), edit('KK7VZT7')).text,
      'KK7VZT7',
    );
    expect(
      formatter.formatEditUpdate(edit('KK7VZT-7'), edit('KK7VZT-')).text,
      'KK7VZT-',
    );
  });

  test('keeps selection and cursor aligned with inserted dashes', () {
    final result = formatter.formatEditUpdate(
      edit(''),
      const TextEditingValue(
        text: 'KK7VZT7 N1ABC2',
        selection: TextSelection(baseOffset: 3, extentOffset: 13),
      ),
    );
    expect(result.text, 'KK7VZT-7 N1ABC-2');
    expect(
      result.selection,
      const TextSelection(baseOffset: 3, extentOffset: 15),
    );
  });

  test('does not alter an active IME composing region', () {
    const value = TextEditingValue(
      text: 'kk7vzt7',
      composing: TextRange(start: 0, end: 7),
    );
    expect(formatter.formatEditUpdate(edit(''), value), value);
  });

  test('recipient formatter preserves pasted emails and formats callsigns', () {
    final recipientFormatter = CallsignRecipientInputFormatter();
    expect(
      recipientFormatter
          .formatEditUpdate(edit(''), edit('kk7vzt7;User@example.com;N1ABC15'))
          .text,
      'kk7vzt-7;User@example.com;N1ABC-15',
    );
  });

  for (final address in [
    'kk7vzt7@example.com',
    'kk7vzt7.name@example.com',
    'kk7vzt7+tag@example.com',
    'kk7vzt7@N1ABC7.com',
  ]) {
    test('recipient formatter preserves typed email $address', () {
      final recipientFormatter = CallsignRecipientInputFormatter();
      var value = edit('');
      for (final character in address.split('')) {
        value = recipientFormatter.formatEditUpdate(
          value,
          edit('${value.text}$character'),
        );
      }
      expect(value.text, address);
      expect(value.selection.baseOffset, address.length);
    });
  }

  test('recipient formatter tracks multiple callsigns before an email', () {
    final recipientFormatter = CallsignRecipientInputFormatter();
    final callsigns = recipientFormatter.formatEditUpdate(
      edit(''),
      edit('N1ABC2;kk7vzt7'),
    );
    final result = recipientFormatter.formatEditUpdate(
      callsigns,
      edit('${callsigns.text}@example.com'),
    );
    expect(result.text, 'N1ABC-2;kk7vzt7@example.com');
  });

  test('recipient formatter preserves explicitly typed email dashes', () {
    final recipientFormatter = CallsignRecipientInputFormatter();
    final callsign = recipientFormatter.formatEditUpdate(
      edit(''),
      edit('kk7vzt-7'),
    );
    expect(
      recipientFormatter
          .formatEditUpdate(callsign, edit('${callsign.text}@example.com'))
          .text,
      'kk7vzt-7@example.com',
    );
  });
}
