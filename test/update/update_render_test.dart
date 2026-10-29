import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifekeeper/data/repository.dart';
import 'package:lifekeeper/main.dart';
import 'package:lifekeeper/update/app_update.dart';

import '../test_fonts.dart';

/// Pixel captures of the in-app update flow for release evidence: the
/// Settings "App updates" entry point and the update-available dialog.
/// Captures land in render-out/ as CI artifacts.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await loadTestFonts();
  });

  Future<Repository> openRepo(WidgetTester tester, String tag) async {
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('lk_update_render_$tag'),
    );
    addTearDown(() async {
      if (await dir!.exists()) await dir.delete(recursive: true);
    });
    final repo = await tester.runAsync(
      () => Repository.open(factory: databaseFactoryFfi, directory: dir!),
    );
    return repo!;
  }

  Future<void> idle(WidgetTester tester, [int n = 12]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 40)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

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

  testWidgets('Settings shows the App updates section', (tester) async {
    final repo = await openRepo(tester, 'settings');
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final k = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: k,
        child: LifeKeeper(repo: repo, enforceLock: false),
      ),
    );
    await idle(tester, 20);
    await tester.tap(find.text('Settings').last);
    await idle(tester, 10);
    await tester.scrollUntilVisible(
      find.text('App updates'),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await idle(tester, 4);
    expect(find.text('App updates'), findsOneWidget);
    expect(find.text('Check for updates'), findsOneWidget);
    await capture(tester, k, 'settings-app-updates');
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => repo.db.close());
  });

  testWidgets('Update available dialog renders version, notes and actions', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const info = UpdateInfo(
      version: '1.1.6',
      notes: 'Add record shows only name and amount first.\nIn-app updates.',
      apkUrl: 'https://github.com/x/LifeKeeper-arm64.apk',
      pageUrl: 'https://github.com/x/releases/tag/v1.1.5',
    );
    final k = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: RepaintBoundary(
          key: k,
          child: Scaffold(
            body: Center(
              child: UpdateDialog(info: info, checker: UpdateChecker()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Software Update'), findsOneWidget);
    expect(find.text('LifeKeeper 1.1.6 is available'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    await capture(tester, k, 'update-dialog-available');
  });
}
