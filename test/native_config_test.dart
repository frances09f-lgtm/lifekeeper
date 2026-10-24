import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Native permissions, receivers and private signing are configured', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('ScheduledNotificationReceiver'));
    expect(manifest, contains('ActionBroadcastReceiver'));
    expect(manifest, contains('SystemReceiver'));
    expect(manifest, contains('TIMEZONE_CHANGED'));
    expect(manifest, contains('RECEIVE_BOOT_COMPLETED'));
    expect(manifest, contains('INTERNET" tools:node="remove'));
    expect(manifest, isNot(contains('READ_SMS')));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('privateRelease'));
    expect(gradle, isNot(contains('getByName("debug")')));
  });
}
