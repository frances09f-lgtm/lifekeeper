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

const outDir = String.fromEnvironment('OUT', defaultValue: 'render-out/device');

/// Captures of the real app shell at phone geometry (1080x2400, 420 dpi,
/// status and gesture bar insets) so layout overflows show up in CI.
/// Fixture data lives only in throwaway SQLite databases.
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
      final image = await render.toImage(pixelRatio: 2.625);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(outDir).create(recursive: true);
      await File('$outDir/$name.png').writeAsBytes(data!.buffer.asUint8List());
    });
  }

  Future<void> idle(WidgetTester tester, [int n = 12]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<Repository> openRepo(WidgetTester tester, String tag) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('lk_dev_$tag'),
    );
    return (await tester.runAsync(
      () => Repository.open(factory: databaseFactoryFfi, directory: dir!),
    ))!;
  }

  void device(WidgetTester tester) {
    // Pixel-class phone: 1080x2400 at 420 dpi, edge-to-edge with status bar
    // (24 dp) and gesture bar (24 dp) insets.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    tester.view.padding = const FakeViewPadding(top: 63, bottom: 63);
    tester.view.viewPadding = const FakeViewPadding(top: 63, bottom: 63);
    addTearDown(tester.view.reset);
  }

  testWidgets('device-geometry captures', (tester) async {
    device(tester);
    final emptyRepo = await openRepo(tester, 'empty');
    final k1 = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: k1,
        child: LifeKeeper(repo: emptyRepo, enforceLock: false),
      ),
    );
    await idle(tester, 20);
    await capture(tester, k1, 'home-empty');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => emptyRepo.db.close());

    final repo = await openRepo(tester, 'data');
    await tester.runAsync(() async {
      final today = day(DateTime.now());
      String d(int n) => dateText(today.add(Duration(days: n)));
      AdminRecord bill(
        String t,
        String c,
        int paise,
        int due, {
        Map<String, dynamic> extra = const {},
      }) => AdminRecord({
        'title': t,
        'category': c,
        'amount': paise,
        'currency': 'INR',
        'repeat': 'monthly',
        'due': d(due),
        'status': 'active',
        ...extra,
      });
      await repo.save(bill('Electricity', 'Bill', 124000, -1));
      await repo.save(bill('Jio recharge', 'Bill', 29900, 2));
      await repo.save(bill('Netflix', 'Subscription', 64900, 5));
      await repo.save(
        bill(
          'Amazon Prime',
          'Subscription',
          29900,
          3,
          extra: {'trialEnd': d(3), 'priceAfterTrial': 29900},
        ),
      );
      final now = DateTime.now();
      final hist = [2150, 1890, 2420, 2010, 2260];
      for (var i = 0; i < hist.length; i++) {
        final m = DateTime(now.year, now.month - 5 + i, 12, 10);
        await repo.db.insert('payments', {
          'recordId': 9000 + i,
          'occurrence': dateText(m),
          'paidAt': m.toUtc().toIso8601String(),
          'amount': hist[i] * 100,
          'currency': 'INR',
          'title': 'Phone and power',
          'category': 'Bill',
        });
      }
    });
    final k = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: k,
        child: LifeKeeper(repo: repo, enforceLock: false),
      ),
    );
    await idle(tester, 20);
    await capture(tester, k, 'home-data');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await idle(tester, 8);
    await capture(tester, k, 'home-data-list');
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await idle(tester, 6);
    await tester.tap(find.byTooltip('Add expense'));
    await idle(tester, 10);
    await capture(tester, k, 'add');
    await tester.pageBack();
    await idle(tester, 8);
    for (final t in ['Insights', 'Calendar', 'Settings']) {
      await tester.tap(find.text(t).last);
      await idle(tester, 10);
      await capture(tester, k, t.toLowerCase());
    }
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => repo.db.close());
  });
}
