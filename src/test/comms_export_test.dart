import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/dialogs/message_details_dialog.dart';
import 'package:htcommander/utils/comms_export.dart';
import 'package:htcommander/widgets/chat_widget.dart';

void main() {
  final time = DateTime.utc(2026, 10, 31, 12, 30);
  ChatMessage entry({String id = '1', String text = 'Hello', DateTime? at}) =>
      ChatMessage(
        id: id,
        route: 'Chat [Local] N0CALL > CQ',
        senderCallsign: 'N0CALL',
        message: text,
        time: at ?? time,
        isSender: true,
        authState: ChatAuthState.success,
        tag: CommsMessageDetails(
          encoding: 'BSS',
          time: at ?? time,
          channel: 'Local',
          isReceived: false,
          source: 'N0CALL',
          destination: 'CQ',
          latitude: 0,
          longitude: -122.5,
          duration: 3,
          filename: 'clip.wav',
          wpm: 20,
          keyType: 'straight',
        ),
      );

  test('CSV preserves quotes, commas, newlines and Unicode with metadata', () {
    final csv = exportCommsMessages([
      entry(text: 'Hello, "world"\r\n\u00e9'),
    ], CommsExportFormat.csv);
    expect(csv, startsWith('"timestamp_utc","direction","type","channel"'));
    expect(
      csv,
      contains('"2026-10-31T12:30:00.000Z","sent","BSS","Local","N0CALL","CQ"'),
    );
    expect(
      csv,
      contains('"Hello, ""world""\r\n\u00e9","0.0","-122.5","3","clip.wav"'),
    );
    expect(csv, contains('"20","straight","success","1"'));
    expect(csv, endsWith('\r\n'));
  });

  test('exports chronologically and preserves equal-time display order', () {
    final csv = exportCommsMessages([
      entry(
        id: 'later',
        text: 'Later',
        at: time.add(const Duration(seconds: 1)),
      ),
      entry(id: 'first', text: 'First'),
      entry(id: 'second', text: 'Second'),
    ], CommsExportFormat.csv);
    expect(csv.indexOf('"First"'), lessThan(csv.indexOf('"Second"')));
    expect(csv.indexOf('"Second"'), lessThan(csv.indexOf('"Later"')));
  });

  test('TXT contains readable metadata and unmodified multiline text', () {
    final txt = exportCommsMessages([
      entry(text: 'First line\nSecond line'),
    ], CommsExportFormat.txt);
    expect(txt, startsWith('[2026-10-31T12:30:00.000Z] SENT\n'));
    expect(txt, contains('source: N0CALL\ndestination: CQ\n'));
    expect(txt, contains('First line\nSecond line\n\n'));
  });

  test(
    'media captions and filenames are preserved without embedding media',
    () {
      final message = ChatMessage(
        id: 'picture',
        route: 'SSTV',
        senderCallsign: '',
        message: '',
        time: time,
        isSender: false,
        tag: CommsMessageDetails(
          encoding: 'Picture',
          time: time,
          channel: 'Local',
          isReceived: true,
          text: 'Robot 36',
          imagePath: '/images/picture.png',
        ),
      );
      final csv = exportCommsMessages([message], CommsExportFormat.csv);
      expect(csv, contains('"Robot 36"'));
      expect(csv, contains('"/images/picture.png"'));
    },
  );

  test('messages without details and empty exports are supported', () {
    final message = ChatMessage(
      id: 'plain',
      route: '',
      senderCallsign: 'OTHER',
      message: '',
      time: time,
      isSender: false,
    );
    expect(
      exportCommsMessages([message], CommsExportFormat.csv),
      contains('"received","","","OTHER","",""'),
    );
    expect(
      exportCommsMessages([], CommsExportFormat.csv),
      contains('"timestamp_utc"'),
    );
    expect(exportCommsMessages([], CommsExportFormat.txt), isEmpty);
  });
}
