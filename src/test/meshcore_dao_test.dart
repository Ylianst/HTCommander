import 'package:flutter_test/flutter_test.dart';
import 'package:htcommander/meshcore/meshcore_message.dart';
import 'package:htcommander/services/db/app_database_io.dart';
import 'package:htcommander/services/db/meshcore_dao.dart';

MeshCoreMessage _msg(int t, String peer, {bool out = false, String text = 'x'}) =>
    MeshCoreMessage(
      time: DateTime.fromMillisecondsSinceEpoch(t),
      senderTime: t ~/ 1000,
      kind: MeshCoreKind.user,
      peer: peer,
      outgoing: out,
      sender: 'Alice',
      text: text,
      pathLen: 2,
      snr: -3.25,
      state: out ? MeshCoreDelivery.pending : MeshCoreDelivery.received,
    );

void main() {
  late AppDatabase db;

  setUp(() async {
    db = await AppDatabase.openInMemory();
  });

  tearDown(() async {
    await AppDatabase.close();
  });

  test('round-trips messages oldest first', () async {
    final a = _msg(2000, 'aa', text: 'second');
    final b = _msg(1000, 'aa', text: 'first');
    a.id = await db.meshcore.insert(a);
    b.id = await db.meshcore.insert(b);
    final rows = await db.meshcore.recent(10);
    expect(rows.map((m) => m.text), ['first', 'second']);
    expect(rows.first.snr, -3.25);
    expect(rows.first.pathLen, 2);
    expect(rows.first.id, b.id);
  });

  test('updates delivery state and ack tag', () async {
    final m = _msg(1000, 'aa', out: true);
    m.id = await db.meshcore.insert(m);
    await db.meshcore.updateState(m.id, MeshCoreDelivery.delivered, 0xFFFFFFFF);
    final row = (await db.meshcore.recent(1)).single;
    expect(row.state, MeshCoreDelivery.delivered);
    expect(row.ackTag, 0xFFFFFFFF);
    expect(row.outgoing, isTrue);
  });

  test('clears one conversation or everything, and enforces a limit', () async {
    for (var i = 0; i < 5; i++) {
      await db.meshcore.insert(_msg(1000 + i, i.isEven ? 'aa' : 'bb'));
    }
    await db.meshcore.clear(kind: MeshCoreKind.user, peer: 'bb');
    expect((await db.meshcore.recent(10)).map((m) => m.peer).toSet(), {'aa'});
    await db.meshcore.enforceLimit(2);
    expect((await db.meshcore.recent(10)).length, 2);
    await db.meshcore.clear();
    expect(await db.meshcore.recent(10), isEmpty);
  });

  test('schema creation is idempotent for upgrades', () async {
    await MeshCoreDao.createSchema(db.db);
    expect(await db.meshcore.recent(1), isEmpty);
  });

  test('JSON form used across windows round-trips', () {
    final m = _msg(1234, 'cc', out: true)..ackTag = 42;
    final back = MeshCoreMessage.fromJson(m.toJson());
    expect(back.toJson(), m.toJson());
  });

  test('only incoming direct messages notify', () {
    expect(isDirectMessageToUs(_msg(1, 'aa')), isTrue);
    expect(isDirectMessageToUs(_msg(1, 'aa', out: true)), isFalse);
    final group = MeshCoreMessage(
      time: DateTime.now(),
      senderTime: 1,
      kind: MeshCoreKind.group,
      peer: 'chan',
      outgoing: false,
      sender: 'Bob',
      text: 'hi all',
      state: MeshCoreDelivery.received,
    );
    expect(isDirectMessageToUs(group), isFalse);
  });
}
