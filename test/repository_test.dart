import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifekeeper/data/repository.dart';
import 'package:lifekeeper/domain/record.dart';
import 'package:lifekeeper/security/security.dart';

void main() {
  late Directory directory;
  late Repository repo;
  setUp(() async {
    sqfliteFfiInit();
    directory = await Directory.systemTemp.createTemp('lk_test');
    repo = await Repository.open(
      factory: databaseFactoryFfi,
      directory: directory,
    );
  });
  tearDown(() async {
    await repo.db.close();
    await directory.delete(recursive: true);
  });
  test('CRUD persists locally across reopen', () async {
    final id = await repo.save(
      AdminRecord({'title': 'bill', 'due': '2026-11-01', 'amount': 70000}),
    );
    await repo.db.close();
    repo = await Repository.open(
      factory: databaseFactoryFfi,
      directory: directory,
    );
    expect((await repo.get(id))!.amount, 70000);
    await repo.patch(id, {'notes': 'saved note'});
    expect((await repo.get(id))!.text('notes'), 'saved note');
    await repo.delete(id);
    expect(await repo.get(id), isNull);
  });
  test('Completion creates one payment and next anchor occurrence', () async {
    final id = await repo.save(
      AdminRecord({
        'title': 'bill',
        'category': 'Bill',
        'due': '2026-01-31',
        'repeat': 'monthly',
        'amount': 10000,
        'currency': 'INR',
      }),
    );
    expect(await repo.complete(id, at: DateTime(2026, 1, 30)), true);
    expect((await repo.get(id))!.text('due'), '2026-02-28');
    expect((await repo.payments()).length, 1);
    expect(await repo.complete(id, at: DateTime(2026, 2, 27)), true);
    expect((await repo.get(id))!.text('due'), '2026-03-31');
    expect((await repo.payments()).length, 2);
  });
  test('Repeated nonrecurring completion cannot duplicate history', () async {
    final id = await repo.save(
      AdminRecord({'title': 'one', 'due': '2026-11-01'}),
    );
    expect(await repo.complete(id), true);
    expect(await repo.complete(id), false);
    expect((await repo.payments()).length, 1);
  });
  test('Snooze and archive update record, duplicate is independent', () async {
    final id = await repo.save(
      AdminRecord({'title': 'one', 'due': '2026-11-01'}),
    );
    await repo.snooze(id, const Duration(hours: 1));
    expect((await repo.get(id))!.number('snoozeCount'), 1);
    final copy = await repo.duplicate(id);
    expect(copy, isNot(id));
    await repo.patch(id, {'status': 'archived'});
    expect((await repo.get(copy))!.status, 'active');
  });
  test(
    'Encrypted export roundtrip covers records history settings attachments',
    () async {
      final source = File('${directory.path}/sample.png');
      await source.writeAsBytes([1, 2, 3]);
      final attachment = await repo.importAttachment(source.path);
      final id = await repo.save(
        AdminRecord({
          'title': 'bill',
          'category': 'Bill',
          'due': '2026-11-01',
          'attachments': [attachment],
        }),
      );
      await repo.complete(id);
      await repo.setting('theme', 'dark');
      final plain = await repo.exportData();
      final encrypted = await encryptBackup(plain, 'long backup password');
      final decoded = await decryptBackup(encrypted, 'long backup password');
      await repo.clear();
      await repo.restore(decoded);
      expect((await repo.records()).single.title, 'bill');
      expect((await repo.payments()).length, 1);
      expect((await repo.settings())['theme'], 'dark');
      expect(
        await repo
            .file(
              (await repo.records()).single.attachments.single['file']
                  as String,
            )
            .readAsBytes(),
        [1, 2, 3],
      );
    },
  );
  test('Wrong backup password fails authentication', () async {
    final encrypted = await encryptBackup(
      await repo.exportData(),
      'long backup password',
    );
    await expectLater(
      decryptBackup(encrypted, 'wrong password'),
      throwsA(isA<Exception>()),
    );
  });
  test('Invalid restore is transactional and paths cannot escape', () async {
    await repo.save(AdminRecord({'title': 'keep me'}));
    final backup = await repo.exportData();
    backup['records'] = [
      {
        'id': 1,
        'data': {'title': ''},
      },
    ];
    await expectLater(repo.restore(backup), throwsArgumentError);
    expect((await repo.records()).single.title, 'keep me');
    expect(() => repo.file('../bad'), throwsArgumentError);
  });
}
