import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/handlers/debug_log_handler.dart';
import 'package:htcommander/services/data_broker.dart';
import 'package:htcommander/services/data_broker_client.dart';

void main() {
  late DebugLogHandler handler;
  late DataBrokerClient probe;

  setUp(() {
    DataBroker.reset();
    DataBroker.dispatch(
      deviceId: 1,
      name: 'DebugLogEntries',
      data: [
        {'time': '2026-01-01T00:00:00', 'message': 'seed', 'isError': false},
      ],
    );
    handler = DebugLogHandler()..init();
    probe = DataBrokerClient();
  });

  tearDown(() {
    handler.dispose();
    probe.dispose();
    DataBroker.reset();
  });

  test('bounds retention and only publishes individual appends', () {
    var appends = 0;
    var snapshots = 0;
    probe.subscribe(
      deviceId: 1,
      name: 'DebugLogEntry',
      callback: (_, _, _) => appends++,
    );
    probe.subscribe(
      deviceId: 1,
      name: 'DebugLogEntries',
      callback: (_, _, _) => snapshots++,
    );
    for (var i = 0; i < DebugLogHandler.maxEntries + 3; i++) {
      probe.logInfo('line $i');
    }
    expect(appends, DebugLogHandler.maxEntries + 3);
    expect(snapshots, 0);
    expect(handler.entries, hasLength(DebugLogHandler.maxEntries));
    expect(handler.entries.first['message'], 'line 3');
    probe.dispatch(
      deviceId: 1,
      name: 'RequestDebugLog',
      data: null,
      store: false,
    );
    expect(snapshots, 1);
  });

  test('snapshots are independent and clear is visible to open views', () {
    final before = handler.entries;
    List? snapshot;
    probe.subscribe(
      deviceId: 1,
      name: 'DebugLogEntries',
      callback: (_, _, data) => snapshot = data as List,
    );
    probe.logError('failure');
    expect(before, hasLength(1));
    expect(handler.entries.last['isError'], isTrue);
    probe.dispatch(
      deviceId: 1,
      name: 'ClearDebugLog',
      data: null,
      store: false,
    );
    expect(handler.entries, isEmpty);
    expect(snapshot, isEmpty);
    probe.logInfo('after clear');
    expect(handler.entries.single['message'], 'after clear');
  });
}
