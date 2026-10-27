import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifekeeper/data/repository.dart';
import 'package:lifekeeper/domain/record.dart';
import 'package:lifekeeper/main.dart';

/// Real SQLite I/O completes outside the fake-async zone, so each round
/// lets real futures run and then pumps one frame, until [until] is found.
Future<void> settle(WidgetTester tester, Finder until) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    if (until.evaluate().isNotEmpty) return;
  }
}

void main() {
  testWidgets('Home and add review show real editable fields and navigation', (
    tester,
  ) async {
    sqfliteFfiInit();
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('lk_widget'),
    );
    final repo = await tester.runAsync(
      () => Repository.open(factory: databaseFactoryFfi, directory: dir!),
    );
    await tester.pumpWidget(LifeKeeper(repo: repo!, enforceLock: false));
    await settle(tester, find.text('Next payments'));
    expect(find.text('Next payments'), findsOneWidget);
    expect(find.byKey(const Key('home-total')), findsOneWidget);
    expect(find.text('Scan bill'), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    await tester.tap(find.byTooltip('Add record'));
    await settle(tester, find.text('Bill / record name'));
    expect(find.text('Add record'), findsOneWidget);
    expect(find.text('Bill / record name'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'My bill');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      await repo.db.close();
      await dir!.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets(
    'Subby-style Home: total, overdue alert Mark all paid, Insights',
    (tester) async {
      sqfliteFfiInit();
      final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('lk_widget2'),
      );
      final repo = await tester.runAsync(
        () => Repository.open(factory: databaseFactoryFfi, directory: dir!),
      );
      final today = day(DateTime.now());
      await tester.runAsync(() async {
        await repo!.save(
          AdminRecord({
            'title': 'Electricity',
            'category': 'Bill',
            'amount': 120000,
            'currency': 'INR',
            'due': dateText(today.subtract(const Duration(days: 2))),
          }),
        );
        await repo.save(
          AdminRecord({
            'title': 'Netflix',
            'category': 'Subscription',
            'amount': 64900,
            'currency': 'INR',
            'repeat': 'monthly',
            'due': dateText(today.add(const Duration(days: 3))),
          }),
        );
      });
      await tester.binding.setSurfaceSize(const Size(390, 2400));
      await tester.pumpWidget(LifeKeeper(repo: repo!, enforceLock: false));
      await settle(tester, find.text('Mark paid'));
      expect(find.text('Electricity is overdue'), findsOneWidget);
      expect(find.text('In 3 days'), findsWidgets);
      expect(find.text('Netflix'), findsWidgets);
      await tester.tap(find.widgetWithText(FilledButton, 'Mark paid').first);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await settle(tester, find.text('₹1,200'));
      expect(find.text('Electricity is overdue'), findsNothing);
      expect(find.text('₹1,200'), findsWidgets);
      await tester.tap(find.text('Insights'));
      await settle(tester, find.text('Overview'));
      await tester.tap(find.text('Services'));
      await settle(tester, find.text('Total paid per item'));
      expect(find.text('Total paid per item'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
      await tester.binding.setSurfaceSize(null);
      await tester.runAsync(() async {
        await repo.db.close();
        await dir!.delete(recursive: true);
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
