import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifekeeper/data/repository.dart';
import 'package:lifekeeper/main.dart';

import 'test_fonts.dart';

/// Pixel capture of the Add record form per the user's steering: only the
/// bill name and amount show first; every other detail hides inside the
/// "More options" dropdown. Capture lands in render-out/ as a CI artifact.
void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await loadTestFonts();
  });

  Future<Repository> openRepo(WidgetTester tester, String tag) async {
    Directory? dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('lk-editor-render-$tag');
    });
    addTearDown(() => dir!.delete(recursive: true));
    final repo = await tester.runAsync(
      () => Repository.open(factory: databaseFactoryFfi, directory: dir!),
    );
    return repo!;
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

  testWidgets('Add record shows only name and amount, details in dropdown',
      (tester) async {
    final repo = await openRepo(tester, 'collapsed');
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: RecordEditor(repo: repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // First screen: exactly the two fields the user asked for.
    expect(find.text('Bill / record name'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('More options'), findsOneWidget);
    expect(find.text('Due date YYYY-MM-DD'), findsNothing);
    expect(find.text('Notes'), findsNothing);
    await capture(tester, boundary, 'add-record-collapsed');

    // The dropdown reveals the details.
    await tester.tap(find.text('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Due date YYYY-MM-DD'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    await capture(tester, boundary, 'add-record-expanded');
  });
}
