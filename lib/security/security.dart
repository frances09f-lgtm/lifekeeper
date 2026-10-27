import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

List<int> randomBytes(int count) {
  final random = Random.secure();
  return List<int>.generate(count, (_) => random.nextInt(256));
}

Future<SecretKey> derive(String password, List<int> salt) => Pbkdf2(
  macAlgorithm: Hmac.sha256(),
  iterations: 210000,
  bits: 256,
).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
Future<List<int>> encryptBackup(
  Map<String, dynamic> data,
  String password,
) async {
  if (password.length < 10)
    throw ArgumentError('Use a backup password of at least 10 characters');
  final salt = randomBytes(16);
  final key = await derive(password, salt);
  final algorithm = AesGcm.with256bits();
  final box = await algorithm.encrypt(
    utf8.encode(jsonEncode(data)),
    secretKey: key,
    nonce: algorithm.newNonce(),
  );
  return utf8.encode(
    jsonEncode({
      'version': 1,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'cipher': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    }),
  );
}

Future<Map<String, dynamic>> decryptBackup(
  List<int> bytes,
  String password,
) async {
  if (bytes.length > 150 * 1024 * 1024)
    throw ArgumentError('Backup exceeds 150 MB');
  final envelope = Map<String, dynamic>.from(
    jsonDecode(utf8.decode(bytes)) as Map,
  );
  if (envelope['version'] != 1)
    throw ArgumentError('Unsupported backup encryption');
  final salt = base64Decode(envelope['salt'] as String);
  if (salt.length != 16) throw ArgumentError('Invalid backup salt');
  final key = await derive(password, salt);
  final plain = await AesGcm.with256bits().decrypt(
    SecretBox(
      base64Decode(envelope['cipher'] as String),
      nonce: base64Decode(envelope['nonce'] as String),
      mac: Mac(base64Decode(envelope['mac'] as String)),
    ),
    secretKey: key,
  );
  return Map<String, dynamic>.from(jsonDecode(utf8.decode(plain)) as Map);
}

class PinSecurity {
  final FlutterSecureStorage storage;
  PinSecurity({
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  });
  Future<bool> enabled() async => await storage.read(key: 'pinHash') != null;
  Future<void> set(String pin) async {
    if (!RegExp(r'^\d{6,12}$').hasMatch(pin))
      throw ArgumentError('Use 6 to 12 digits');
    final salt = randomBytes(16);
    final key = await derive(pin, salt);
    await storage.write(key: 'pinSalt', value: base64Encode(salt));
    await storage.write(
      key: 'pinHash',
      value: base64Encode(await key.extractBytes()),
    );
    await storage.delete(key: 'pinAttempts');
    await storage.delete(key: 'pinUntil');
  }

  Future<bool> verify(String pin) async {
    final until = DateTime.tryParse(await storage.read(key: 'pinUntil') ?? '');
    if (until?.isAfter(DateTime.now()) ?? false)
      throw StateError('Too many attempts, try after ${until!.toLocal()}');
    final hash = await storage.read(key: 'pinHash');
    final salt = await storage.read(key: 'pinSalt');
    if (hash == null || salt == null) return true;
    final key = await derive(pin, base64Decode(salt));
    final actual = await key.extractBytes();
    final expected = base64Decode(hash);
    var diff = actual.length ^ expected.length;
    for (var i = 0; i < min(actual.length, expected.length); i++) {
      diff |= actual[i] ^ expected[i];
    }
    if (diff == 0) {
      await storage.delete(key: 'pinAttempts');
      await storage.delete(key: 'pinUntil');
      return true;
    }
    final attempts =
        (int.tryParse(await storage.read(key: 'pinAttempts') ?? '0') ?? 0) + 1;
    await storage.write(key: 'pinAttempts', value: '$attempts');
    if (attempts >= 5)
      await storage.write(
        key: 'pinUntil',
        value: DateTime.now()
            .add(Duration(minutes: min(60, attempts - 4) * 5))
            .toIso8601String(),
      );
    return false;
  }

  Future<void> disable(String pin) async {
    if (!await verify(pin)) throw ArgumentError('Incorrect PIN');
    await storage.deleteAll();
  }
}

/// Fingerprint/face unlock may only be offered on top of the PIN: it is a
/// convenience, never a replacement. All three must hold.
bool biometricUnlockAllowed({
  required bool pinEnabled,
  required bool biometricEnabled,
  required bool deviceSupports,
}) => pinEnabled && biometricEnabled && deviceSupports;

/// Tiny storage seam so tests can fake a throwing/absent secure storage.
class BiometricFlagStore {
  final FlutterSecureStorage storage;
  BiometricFlagStore([
    this.storage = const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  ]);
  Future<String?> read() => storage.read(key: 'biometricUnlock');
  Future<void> write() => storage.write(key: 'biometricUnlock', value: 'true');
  Future<void> clear() => storage.delete(key: 'biometricUnlock');
}

class BiometricUnlock {
  final LocalAuthentication auth;
  final BiometricFlagStore flags;
  BiometricUnlock({LocalAuthentication? auth, BiometricFlagStore? flags})
    : auth = auth ?? LocalAuthentication(),
      flags = flags ?? BiometricFlagStore();

  /// Fail-closed: any storage trouble reads as "not enabled", so a broken
  /// store can never surface the biometric path or unlock anything.
  Future<bool> enabled() async {
    try {
      return await flags.read() == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool on) async {
    try {
      if (on) {
        await flags.write();
      } else {
        await flags.clear();
      }
    } catch (_) {
      // No secure storage (or a test environment): stay disabled.
    }
  }

  Future<bool> deviceSupports() async {
    try {
      return await auth.isDeviceSupported() || await auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// One system prompt. Biometric-only on purpose: the device PIN/pattern
  /// must never substitute for the app PIN, which stays the fallback.
  Future<bool> authenticate() async {
    try {
      return await auth.authenticate(
        localizedReason: 'Unlock LifeKeeper',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
