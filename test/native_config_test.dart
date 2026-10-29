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
    // In-app updates (user request): the app checks GitHub for a newer
    // release from Settings and hands the APK to the system installer.
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, isNot(contains('INTERNET" tools:node="remove')));
    expect(manifest, contains('REQUEST_INSTALL_PACKAGES'));
    expect(manifest, isNot(contains('READ_SMS')));
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('privateRelease'));
    expect(gradle, isNot(contains('getByName("debug")')));
  });
}
