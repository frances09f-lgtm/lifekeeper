import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifekeeper/data/repository.dart';
import 'package:lifekeeper/domain/record.dart';
import 'package:lifekeeper/main.dart';
import 'package:lifekeeper/services/notifications.dart';

/// Regression tests for "Database closed" (seen on 1.1.1, fixed in 1.1.2). The notification-action
/// isolate and the boot/time-change receiver run in a second Flutter engine in
/// the same process. sqflite's Android plugin shared ONE native connection per
/// path between engines, so the background engine's close() closed the UI's
/// database. ffi's default single-instance cache reproduces the same sharing.
void main() {
  late Directory dir;
  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('lk_closed');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<Repository> openRepo() =>
      Repository.open(factory: databaseFactoryFfi, directory: dir);

  AdminRecord bill(String title) => AdminRecord({
    'title': title,
    'category': 'Bill',
    'amount': 49900,
    'currency': 'INR',
    'repeat': 'monthly',
    'due': dateText(day(DateTime.now()).add(const Duration(days: 2))),
    'status': 'active',
  });

  test('background opener closing its repo leaves the UI repo open', () async {
    final ui = await openRepo();
    final id = await ui.save(bill('Jio'));
    // Notification action / boot receiver: open, work, close.
    final background = await openRepo();
    expect(identical(background.db, ui.db), isFalse);
    await background.complete(id);
    await background.close();
    expect(ui.db.isOpen, isTrue);
    expect((await ui.records()).single.title, 'Jio');
    expect(await ui.payments(), hasLength(1));
    await ui.close();
  });

  test(
    'notification Mark as paid in a second engine, then UI queries',
    () async {
      final ui = await openRepo();
      final id = await ui.save(bill('Netflix'));
      final background = await openRepo();
      await applyNotificationAction(
        background,
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'complete',
          payload: '$id',
        ),
      );
      await background.close();
      final payments = await ui.payments();
      expect(payments, hasLength(1));
      expect(payments.single['recordId'], id);
      await ui.save(bill('Spotify'));
      expect(await ui.records(), hasLength(2));
      await ui.close();
    },
  );

  test('a handle closed underneath reopens transparently', () async {
    final repo = await openRepo();
    final id = await repo.save(bill('Airtel'));
    await repo.db.close(); // e.g. lock -> unlock, or another engine closed it
    expect((await repo.get(id))!.title, 'Airtel');
    await repo.db.close();
    expect(await repo.complete(id), isTrue); // transaction path
    await repo.db.close();
    await repo.setting('theme', 'light');
    expect((await repo.settings())['theme'], 'light');
    await repo.close();
  });

  test('queries racing a close share one reopen and all succeed', () async {
    final repo = await openRepo();
    await repo.save(bill('Electricity'));
    final before = repo.db;
    await before.close();
    final results = await Future.wait([
      for (var i = 0; i < 20; i++) repo.records(),
      repo.payments(),
      repo.settings(),
    ]);
    expect(results.take(20).every((r) => (r as List).length == 1), isTrue);
    expect(identical(repo.db, before), isFalse);
    expect(repo.db.isOpen, isTrue);
    await repo.close();
  });

  test('natively closed handle (Dart still thinks open): retry once', () async {
    final repo = await openRepo();
    await repo.save(bill('LIC'));
    final other = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await other.close();
    final before = repo.db;
    var calls = 0;
    final rows = await repo.withDatabase((db) {
      calls++;
      // First attempt hits a closed connection, as the UI did in 1.1.1.
      return (calls == 1 ? other : db).query('records');
    });
    expect(calls, 2);
    expect(rows, hasLength(1));
    expect(identical(repo.db, before), isFalse);
    await repo.close();
  });

  test('other DB errors are not retried', () async {
    final repo = await openRepo();
    var calls = 0;
    await expectLater(
      repo.withDatabase((db) {
        calls++;
        return db.query('no_such_table');
      }),
      throwsA(isA<DatabaseException>()),
    );
    expect(calls, 1);
    await repo.close();
  });

  test('data written by 1.1.1 survives the upgrade (same file, schema v1)', () async {
    // Create the file exactly as 1.1.0/1.1.1 did (shared instance, version 1).
    final old = await databaseFactoryFfi.openDatabase(
      Repository.pathIn(dir),
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute(
            'CREATE TABLE records (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL, due TEXT, status TEXT NOT NULL, category TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE payments (id INTEGER PRIMARY KEY AUTOINCREMENT, recordId INTEGER NOT NULL, occurrence TEXT NOT NULL, paidAt TEXT NOT NULL, amount INTEGER, currency TEXT NOT NULL, title TEXT NOT NULL, category TEXT NOT NULL, UNIQUE(recordId,occurrence))',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    await old.insert('records', {
      'data': '{"title":"Rent","category":"Bill","status":"active","amount":1500000,"currency":"INR"}',
      'due': '2026-11-05',
      'status': 'active',
      'category': 'Bill',
    });
    await old.insert('settings', {'key': 'theme', 'value': '"dark"'});
    await old.close();
    final repo = await openRepo();
    expect((await repo.records()).single.title, 'Rent');
    expect((await repo.settings())['theme'], 'dark');
    await repo.close();
  });

  test('friendlyError hides raw database errors', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await db.close();
    Object? error;
    try {
      await db.query('x');
    } catch (e) {
      error = e;
    }
    expect(error, isA<DatabaseException>());
    expect(friendlyError(error!), isNot(contains('DatabaseException')));
    expect(friendlyError(error), contains('Retry'));
    expect(
      friendlyError(ArgumentError('Title is required')),
      contains('Title'),
    );
  });

  testWidgets('UI keeps working after background close and pause/resume', (
    tester,
  ) async {
    final repo = await tester.runAsync(openRepo);
    await tester.runAsync(() => repo!.save(bill('Hotstar')));
    await tester.pumpWidget(LifeKeeper(repo: repo!, enforceLock: false));
    Future<void> settleFor(Finder f) async {
      for (var i = 0; i < 100; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (f.evaluate().isNotEmpty) return;
      }
    }

    await settleFor(find.text('Hotstar'));
    expect(find.text('Hotstar'), findsWidgets);
    // A background engine opens, marks paid and closes; then the UI's own
    // handle is also closed underneath it before the user comes back.
    await tester.runAsync(() async {
      final background = await openRepo();
      await background.setting('reminderTime', 600);
      await background.close();
      await repo.db.close();
    });
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.textContaining('DatabaseException'), findsNothing);
    expect(find.textContaining('database_closed'), findsNothing);
    expect(find.text('Hotstar'), findsWidgets);
    expect(repo.db.isOpen, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(repo.close);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
