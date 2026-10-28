import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifekeeper/data/repository.dart';
import 'package:lifekeeper/domain/record.dart';
import 'package:lifekeeper/main.dart';

import 'test_fonts.dart';
import 'widget_test.dart' as w;

/// Pixel captures of the real Home screen, empty and populated, for the
/// user's design-confirmation request. Fixtures live only in this test's
/// throwaway SQLite database; nothing here touches app code, assets or any
/// production build. Captures land in render-out/ and are uploaded as CI
/// artifacts (android.yml, if-no-files-found: ignore).
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await loadTestFonts();
  });

  Future<void> capture(
    WidgetTester tester,
    GlobalKey boundary,
    String name,
  ) async {
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(data, isNotNull);
      await Directory('render-out').create(recursive: true);
      await File('render-out/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
    });
  }

  Future<Repository> openRepo(WidgetTester tester, String tag) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('lk_render_$tag'),
    );
    addTearDown(() async {
      if (await dir!.exists()) await dir.delete(recursive: true);
    });
    final repo = await tester.runAsync(
      () => Repository.open(factory: databaseFactoryFfi, directory: dir!),
    );
    return repo!;
  }

  void phoneView(WidgetTester tester) {
    tester.view.physicalSize = const Size(780, 1688);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  AdminRecord bill(
    String title,
    String category,
    int paise,
    int daysFromNow, {
    String status = 'active',
  }) => AdminRecord({
    'title': title,
    'category': category,
    'amount': paise,
    'currency': 'INR',
    'repeat': 'monthly',
    'due': dateText(day(DateTime.now()).add(Duration(days: daysFromNow))),
    'status': status,
  });

  testWidgets('render Home empty and populated states', (tester) async {
    phoneView(tester);

    // Empty state.
    final emptyRepo = await openRepo(tester, 'empty');
    final emptyKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: emptyKey,
        child: LifeKeeper(repo: emptyRepo, enforceLock: false),
      ),
    );
    await w.settle(tester, find.byKey(const Key('home-add-first')));
    expect(find.text('No bills yet · ₹0 a day'), findsOneWidget);
    await capture(tester, emptyKey, 'home-empty');
    expect(await tester.runAsync(() => emptyRepo.records()), isEmpty);
    await tester.tap(find.byTooltip('Add expense'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.text('More options'), findsOneWidget);
    await capture(tester, emptyKey, 'add-expense');
    Finder field(String label) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == label,
    );
    await tester.enterText(field('Bill / record name'), 'Lunch');
    await tester.enterText(field('Amount'), '150');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if ((await tester.runAsync(() => emptyRepo.records()))!.isNotEmpty) break;
    }
    await capture(tester, emptyKey, 'add-expense-after-save');
    final saved = await tester.runAsync(() => emptyRepo.records());
    expect(saved, hasLength(1));
    expect(saved!.single.title, 'Lunch');
    expect(saved.single.amount, 15000);
    expect(saved.single.flag('demo'), isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => emptyRepo.db.close());

    // Populated state: realistic fixture bills in the throwaway test db.
    final repo = await openRepo(tester, 'populated');
    await tester.runAsync(() async {
      // Mirror the user's reference "with bills" panel: six active bills
      // totalling Rs 2,938/month, Airtel Fiber overdue since 2026-10-26
      // (red Mark paid card) and an Amazon Prime trial ending in 2 days
      // (yellow Keep it card: Then Rs 299 / save Rs 3,588 a year).
      await repo.save(bill('Airtel Fiber', 'Internet', 79900, -2));
      await repo.save(
        AdminRecord({
          'title': 'Amazon Prime',
          'category': 'Streaming',
          'amount': 29900,
          'currency': 'INR',
          'repeat': 'monthly',
          'due': dateText(day(DateTime.now()).add(const Duration(days: 2))),
          'status': 'active',
          'trialEnd': dateText(
            day(DateTime.now()).add(const Duration(days: 2)),
          ),
          'priceAfterTrial': 29900,
        }),
      );
      await repo.save(bill('Jio', 'Mobile', 49900, 2));
      await repo.save(bill('Netflix', 'Streaming', 64900, 3));
      await repo.save(bill('Spotify', 'Music', 19900, 2));
      await repo.save(bill('Electricity', 'Utilities', 49300, 3));
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: LifeKeeper(repo: repo, enforceLock: false),
      ),
    );
    await w.settle(tester, find.text('Airtel Fiber'));
    expect(find.byKey(const Key('home-total')), findsOneWidget);
    await capture(tester, key, 'home-populated');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => repo.db.close());
  });
}
