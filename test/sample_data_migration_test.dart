import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifekeeper/data/repository.dart';
import 'package:lifekeeper/domain/record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 1.1.5 removes sample/demo rows that older versions could have written,
/// and must never touch anything the person added.
void main() {
  late Directory dir;
  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('lk_sample_purge');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// A database exactly as 1.0.0 to 1.1.4 left it (schema version 1).
  Future<void> writeV1Database(
    List<Map<String, dynamic>> records,
    List<Map<String, Object?>> payments,
  ) async {
    final db = await databaseFactoryFfi.openDatabase(
      Repository.pathIn(dir),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute(
            'CREATE TABLE IF NOT EXISTS records (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL, due TEXT, status TEXT NOT NULL, category TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS payments (id INTEGER PRIMARY KEY AUTOINCREMENT, recordId INTEGER NOT NULL, occurrence TEXT NOT NULL, paidAt TEXT NOT NULL, amount INTEGER, currency TEXT NOT NULL, title TEXT NOT NULL, category TEXT NOT NULL, UNIQUE(recordId,occurrence))',
          );
          await db.execute(
            'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    for (final r in records) {
      final data = Map<String, dynamic>.from(r)..remove('id');
      await db.insert('records', {
        'id': r['id'],
        'data': jsonEncode(data),
        'due': data['due'],
        'status': data['status'] ?? 'active',
        'category': data['category'] ?? 'Bill',
      });
    }
    for (final p in payments) {
      await db.insert('payments', p);
    }
    await db.insert('settings', {'key': 'theme', 'value': jsonEncode('dark')});
    await db.close();
  }

  Map<String, Object?> payment(
    int id,
    int recordId,
    String title,
    int amount,
  ) => {
    'id': id,
    'recordId': recordId,
    'occurrence': '2026-10-0$id',
    'paidAt': '2026-10-0${id}T10:00:00',
    'amount': amount,
    'currency': 'INR',
    'title': title,
    'category': 'Bill',
  };

  // What the old "Add labeled demo records" button wrote.
  final seededBill = {
    'id': 1,
    'title': 'Demo electricity bill',
    'category': 'Bill',
    'amount': 125000,
    'repeat': 'monthly',
    'due': '2026-10-31',
    'currency': 'INR',
    'demo': true,
    'status': 'active',
    'reminders': [7, 3, 1, 0],
  };
  final seededWarranty = {
    'id': 2,
    'title': 'Demo warranty',
    'category': 'Warranty',
    'due': '2026-11-17',
    'currency': 'INR',
    'demo': true,
    'status': 'active',
  };
  // The old "SMS bill demo" chip's pre-filled example, saved untouched.
  final smsSample = {
    'id': 3,
    'title': 'Jio',
    'issuer': 'Jio',
    'amount': 79900,
    'due': '2026-11-25',
    'account': '123456789',
    'currency': 'INR',
    'category': 'Bill',
    'status': 'active',
    'notes': 'Pasted text / SMS demo, review before saving',
  };
  // Things the person added: none of these may be touched.
  final userJio = {
    'id': 10,
    'title': 'Jio',
    'amount': 79900,
    'due': '2026-11-05',
    'currency': 'INR',
    'category': 'Bill',
    'status': 'active',
    'repeat': 'monthly',
  };
  final userPastedOwnSms = {
    'id': 11,
    'title': 'Jio',
    'amount': 59900,
    'due': '2026-11-12',
    'account': '7700112233',
    'currency': 'INR',
    'category': 'Bill',
    'status': 'active',
    'notes': 'Pasted text / SMS demo, review before saving',
  };
  final userNamedDemo = {
    'id': 12,
    'title': 'Demo electricity bill',
    'amount': 125000,
    'due': '2026-11-02',
    'currency': 'INR',
    'category': 'Bill',
    'status': 'active',
  };
  final userNetflix = {
    'id': 13,
    'title': 'Netflix',
    'amount': 64900,
    'due': '2026-11-09',
    'currency': 'INR',
    'category': 'Subscription',
    'status': 'active',
    'repeat': 'monthly',
  };

  test(
    'Upgrade removes only sample rows; user rows and payments survive',
    () async {
      await writeV1Database(
        [
          seededBill,
          seededWarranty,
          smsSample,
          userJio,
          userPastedOwnSms,
          userNamedDemo,
          userNetflix,
        ],
        [
          payment(1, 1, 'Demo electricity bill', 125000), // seeded, paid
          payment(
            2,
            99,
            'Demo electricity bill',
            125000,
          ), // seeded, record gone
          payment(3, 10, 'Jio', 79900), // user
          payment(4, 13, 'Netflix', 64900), // user
          payment(5, 12, 'Demo electricity bill', 125000), // user's own record
          payment(6, 98, 'Old gym', 150000), // user, record deleted
        ],
      );

      final repo = await Repository.open(
        factory: databaseFactoryFfi,
        directory: dir,
      );
      expect(await repo.db.getVersion(), schemaVersion);
      final left = await repo.records();
      expect(left.map((r) => r.id).toList()..sort(), [10, 11, 12, 13]);
      expect(left.any((r) => r.flag('demo')), isFalse);
      // User rows are byte-for-byte what they were.
      expect(left.firstWhere((r) => r.id == 10).amount, 79900);
      expect(left.firstWhere((r) => r.id == 11).text('account'), '7700112233');
      expect(left.firstWhere((r) => r.id == 13).title, 'Netflix');
      final pays = await repo.payments();
      expect(pays.map((p) => p['id']).toList()..sort(), [3, 4, 5, 6]);
      expect((await repo.settings())['theme'], 'dark');
      await repo.close();

      // Reopening (and a second engine opening) changes nothing more.
      final again = await Repository.open(
        factory: databaseFactoryFfi,
        directory: dir,
      );
      expect((await again.records()).map((r) => r.id).toList()..sort(), [
        10,
        11,
        12,
        13,
      ]);
      expect((await again.payments()).length, 4);
      await again.close();
    },
  );

  test('Upgrade of a database with only user rows changes nothing', () async {
    await writeV1Database(
      [userJio, userNetflix],
      [payment(3, 10, 'Jio', 79900)],
    );
    final repo = await Repository.open(
      factory: databaseFactoryFfi,
      directory: dir,
    );
    expect((await repo.records()).map((r) => r.title).toList()..sort(), [
      'Jio',
      'Netflix',
    ]);
    expect((await repo.payments()).single['title'], 'Jio');
    await repo.close();
  });

  test('Fresh install has schema 2 and no rows at all', () async {
    final repo = await Repository.open(
      factory: databaseFactoryFfi,
      directory: dir,
    );
    expect(await repo.db.getVersion(), schemaVersion);
    expect(await repo.records(), isEmpty);
    expect(await repo.payments(), isEmpty);
    // New records saved by the person are kept on the next open.
    await repo.save(AdminRecord({'title': 'Rent', 'amount': 1500000}));
    await repo.close();
    final again = await Repository.open(
      factory: databaseFactoryFfi,
      directory: dir,
    );
    expect((await again.records()).single.title, 'Rent');
    await again.close();
  });

  test(
    'Restoring an old backup drops its sample rows, keeps the rest',
    () async {
      final repo = await Repository.open(
        factory: databaseFactoryFfi,
        directory: dir,
      );
      Map<String, dynamic> asBackupRecord(Map<String, dynamic> r) => {
        'id': r['id'],
        'data': Map<String, dynamic>.from(r)..remove('id'),
      };
      await repo.restore({
        'format': 1,
        'records': [
          asBackupRecord(seededBill),
          asBackupRecord(smsSample),
          asBackupRecord(userJio),
        ],
        'payments': [
          payment(1, 1, 'Demo electricity bill', 125000),
          payment(3, 10, 'Jio', 79900),
        ],
        'settings': <String, dynamic>{},
        'files': <String, dynamic>{},
      });
      expect((await repo.records()).map((r) => r.id), [10]);
      expect((await repo.payments()).single['id'], 3);
      await repo.close();
    },
  );

  test('isSampleRecord matches only what LifeKeeper itself created', () {
    expect(isSampleRecord(seededBill), isTrue);
    expect(isSampleRecord(seededWarranty), isTrue);
    expect(isSampleRecord(smsSample), isTrue);
    for (final r in [userJio, userPastedOwnSms, userNamedDemo, userNetflix]) {
      expect(isSampleRecord(r), isFalse, reason: '${r['id']}');
    }
  });
}
