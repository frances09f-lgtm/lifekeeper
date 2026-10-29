import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lifekeeper/update/app_update.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('compareVersions', () {
    test('numeric compare with v prefix and build suffix', () {
      expect(compareVersions('1.1.5', '1.1.4'), greaterThan(0));
      expect(compareVersions('v1.1.4', '1.1.4'), 0);
      expect(compareVersions('1.1.4+8', '1.1.5'), lessThan(0));
      expect(compareVersions('1.2', '1.1.99'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
    });
  });

  const release = '''
    {"tag_name":"v1.1.5","body":"LifeKeeper 1.1.5\\n\\n- in-app updates",
     "html_url":"https://github.com/frances09f-lgtm/lifekeeper/releases/tag/v1.1.5",
     "assets":[{"name":"LifeKeeper-arm64.apk","browser_download_url":"https://github.com/x/LifeKeeper-arm64.apk"},
                {"name":"SHA256SUMS.txt","browser_download_url":"https://github.com/x/SHA256SUMS.txt"}]}''';

  group('fetchLatestDetailed', () {
    UpdateChecker checker(String body, int code, String current) =>
        UpdateChecker(
          client: MockClient((req) async {
            expect(req.url.path, contains('releases/latest'));
            return http.Response(body, code);
          }),
          currentVersion: () async => current,
        );

    test('available on a newer release, picking the apk asset', () async {
      final r = await checker(release, 200, '1.1.4').fetchLatestDetailed();
      expect(r.status, UpdateCheckStatus.updateAvailable);
      expect(r.info!.version, '1.1.5');
      expect(r.info!.notes, contains('in-app updates'));
      expect(r.info!.apkUrl, endsWith('LifeKeeper-arm64.apk'));
      expect(r.info!.pageUrl, contains('/releases/tag/v1.1.5'));
    });

    test('upToDate when not newer', () async {
      final r = await checker(release, 200, '1.1.5').fetchLatestDetailed();
      expect(r.status, UpdateCheckStatus.upToDate);
      expect(r.info, isNull);
    });

    test('failed on http error, bad payload, or missing apk asset', () async {
      for (final c in [
        await checker('rate limited', 403, '1.1.4').fetchLatestDetailed(),
        await checker('{}', 200, '1.1.4').fetchLatestDetailed(),
        await checker(
          '{"tag_name":"v1.1.5","body":"","html_url":"https://x","assets":[]}',
          200,
          '1.1.4',
        ).fetchLatestDetailed(),
      ]) {
        expect(c.status, UpdateCheckStatus.failed);
        expect(c.info, isNull);
      }
    });
  });

  group('download', () {
    test('writes the apk with byte progress', () async {
      final bytes = List<int>.generate(4096, (i) => i % 251);
      final tmp = Directory.systemTemp.createTempSync('lk-update-test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final checker = UpdateChecker(
        client: MockClient.streaming(
          (req, body) async => http.StreamedResponse(
            Stream.value(bytes),
            200,
            contentLength: bytes.length,
          ),
        ),
        cacheDir: () async => tmp,
      );
      const info = UpdateInfo(
        version: '1.1.5',
        notes: '',
        apkUrl: 'https://github.com/x/LifeKeeper-arm64.apk',
        pageUrl: 'https://github.com/x/releases/tag/v1.1.5',
      );
      final progress = <(int, int?)>[];
      final file = await checker.download(
        info,
        onProgress: (r, t) => progress.add((r, t)),
      );
      expect(file.path, contains('lifekeeper-1.1.5.apk'));
      expect(await file.length(), bytes.length);
      expect(await file.readAsBytes(), bytes);
      expect(progress.last, (bytes.length, bytes.length));
    });

    test('throws on a failed download', () async {
      final tmp = Directory.systemTemp.createTempSync('lk-update-test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final checker = UpdateChecker(
        client: MockClient.streaming(
          (req, body) async => http.StreamedResponse(const Stream.empty(), 404),
        ),
        cacheDir: () async => tmp,
      );
      const info = UpdateInfo(
        version: '1.1.5',
        notes: '',
        apkUrl: 'https://github.com/x/missing.apk',
        pageUrl: 'https://github.com/x',
      );
      expect(() => checker.download(info), throwsStateError);
    });
  });

  group('update dialog', () {
    const info = UpdateInfo(
      version: '1.1.5',
      notes: 'Add record shows only name and amount first.\nIn-app updates.',
      apkUrl: 'https://github.com/x/LifeKeeper-arm64.apk',
      pageUrl: 'https://github.com/x/releases/tag/v1.1.5',
    );

    testWidgets('available phase shows version, notes and actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final ctx = tester.element(find.byType(Scaffold));
      final shown = showUpdateDialog(ctx, info, checker: UpdateChecker());
      await tester.pumpAndSettle();
      expect(find.text('Software Update'), findsOneWidget);
      expect(find.text('LifeKeeper 1.1.5 is available'), findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
      expect(
        find.textContaining('Add record shows only name and amount'),
        findsOneWidget,
      );
      expect(find.text('Later'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      await shown;
    });

    testWidgets('update tap downloads, installs and closes', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('lk-update-test');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final apk = File('${tmp.path}/lifekeeper-1.1.5.apk')
        ..writeAsBytesSync(const [1, 2, 3]);
      var installed = '';
      final checker = UpdateChecker(
        currentVersion: () async => '1.1.4',
        installer: (path) async {
          installed = path;
          return 'ok';
        },
        downloader:
            (
              info, {
              void Function(int received, int? total)? onProgress,
              Stream<void>? cancelToken,
            }) async {
              onProgress?.call(3, 3);
              return apk;
            },
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final ctx = tester.element(find.byType(Scaffold));
      final shown = showUpdateDialog(ctx, info, checker: checker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(installed, apk.path);
      expect(find.text('Software Update'), findsNothing);
      await shown;
    });

    testWidgets('install failure shows error with retry and page fallback', (
      tester,
    ) async {
      final checker = UpdateChecker(
        currentVersion: () async => '1.1.4',
        downloader: (
          info, {
          void Function(int received, int? total)? onProgress,
          Stream<void>? cancelToken,
        }) async => throw StateError('installer did not open'),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox())),
      );
      final ctx = tester.element(find.byType(Scaffold));
      final shown = showUpdateDialog(ctx, info, checker: checker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(find.text('Update failed'), findsOneWidget);
      expect(find.textContaining('installer did not open'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Open download page'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      await shown;
    });
  });
}
