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
  testWidgets('First run: empty Home uses the full card layout, light theme', (
    tester,
  ) async {
    sqfliteFfiInit();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('lk_empty'),
    );
    final repo = await tester.runAsync(
      () => Repository.open(factory: databaseFactoryFfi, directory: dir!),
    );
    await tester.pumpWidget(LifeKeeper(repo: repo!, enforceLock: false));
    await settle(tester, find.byKey(const Key('home-add-first')));
    expect(find.byKey(const Key('home-total')), findsOneWidget);
    expect(find.text('No bills yet · ₹0 a day'), findsOneWidget);
    expect(find.text('Add your first bill'), findsOneWidget);
    expect(find.text('No records match these filters'), findsNothing);
    // No example bills, suggestions or placeholder amounts on a fresh install.
    for (final fake in [
      'Popular to add',
      'Start here',
      'Scan a bill',
      'Track a free trial',
      'Jio recharge',
      'Netflix',
      'Electricity',
      'Car insurance',
    ]) {
      expect(find.text(fake), findsNothing, reason: fake);
    }
    expect(find.textContaining('Demo'), findsNothing);
    expect(find.textContaining('Jio'), findsNothing);
    expect(find.textContaining('₹799'), findsNothing);
    // A dark phone still gets the light sage look unless the user picks dark.
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(() async {
      await repo.db.close();
      await dir!.delete(recursive: true);
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

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
    await settle(tester, find.text('Add your first bill'));
    expect(find.byKey(const Key('home-total')), findsOneWidget);
    expect(find.byTooltip('Scan bill'), findsOneWidget);
    expect(find.byTooltip('Quick add'), findsOneWidget);
    expect(find.text('Calendar'), findsOneWidget);
    await tester.tap(find.byTooltip('Add expense'));
    await settle(tester, find.text('Bill / record name'));
    expect(find.text('Add expense'), findsOneWidget);
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
      // Mark paid runs real SQLite I/O; keep pumping until the alert clears.
      for (
        var i = 0;
        i < 100 && find.text('Electricity is overdue').evaluate().isNotEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
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
