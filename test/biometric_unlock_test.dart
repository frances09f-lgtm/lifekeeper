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
  group('BiometricUnlock storage failures', () {
    test('throwing storage reads as disabled (fail-closed)', () async {
      final bio = BiometricUnlock(flags: _ThrowingFlagStore());
      expect(await bio.enabled(), isFalse);
    });

    test('a failed opt-in write never reports enabled', () async {
      final bio = BiometricUnlock(flags: _ThrowingFlagStore());
      await bio.setEnabled(true); // must not throw
      expect(await bio.enabled(), isFalse);
    });

    test('a working store round-trips the opt-in flag', () async {
      final bio = BiometricUnlock(flags: _MemoryFlagStore());
      expect(await bio.enabled(), isFalse);
      await bio.setEnabled(true);
      expect(await bio.enabled(), isTrue);
      await bio.setEnabled(false);
      expect(await bio.enabled(), isFalse);
    });
  });
}

/// Secure storage that always throws, standing in for a device where the
/// keystore is unavailable (or a plugin-less test environment).
class _ThrowingFlagStore extends BiometricFlagStore {
  @override
  Future<String?> read() => throw StateError('no keystore');
  @override
  Future<void> write() => throw StateError('no keystore');
  @override
  Future<void> clear() => throw StateError('no keystore');
}

class _MemoryFlagStore extends BiometricFlagStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write() async => value = 'true';
  @override
  Future<void> clear() async => value = null;
}
