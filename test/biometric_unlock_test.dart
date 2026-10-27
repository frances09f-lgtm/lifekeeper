import 'package:flutter_test/flutter_test.dart';
import 'package:lifekeeper/security/security.dart';

void main() {
  group('biometricUnlockAllowed', () {
    test('requires PIN, opt-in and device support together', () {
      expect(
        biometricUnlockAllowed(
          pinEnabled: true,
          biometricEnabled: true,
          deviceSupports: true,
        ),
        isTrue,
      );
    });
    test('never without a PIN lock', () {
      expect(
        biometricUnlockAllowed(
          pinEnabled: false,
          biometricEnabled: true,
          deviceSupports: true,
        ),
        isFalse,
      );
    });
    test('never without the user opt-in', () {
      expect(
        biometricUnlockAllowed(
          pinEnabled: true,
          biometricEnabled: false,
          deviceSupports: true,
        ),
        isFalse,
      );
    });
    test('never on a device without biometrics', () {
      expect(
        biometricUnlockAllowed(
          pinEnabled: true,
          biometricEnabled: true,
          deviceSupports: false,
        ),
        isFalse,
      );
    });
  });
}
