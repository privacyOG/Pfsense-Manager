import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class PinVerifierStore {
  Future<String?> read();

  Future<void> write(String verifier);

  Future<void> delete();
}

class SecurePinVerifierStore implements PinVerifierStore {
  static const _storageKey = 'app_pin_verifier_v1';
  static const _defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  SecurePinVerifierStore({
    FlutterSecureStorage storage = _defaultStorage,
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _storageKey);

  @override
  Future<void> write(String verifier) =>
      _storage.write(key: _storageKey, value: verifier);

  @override
  Future<void> delete() => _storage.delete(key: _storageKey);
}

const int _pinVerifierIterations = 100000;
const int _pinSaltLength = 16;
const int _pinHashLength = 32;
const String _pinVerifierVersion = 'v1';

Future<String> createPinVerifier(String pin) {
  return Isolate.run(() => _createPinVerifier(pin));
}

Future<bool> verifyPinVerifier(String pin, String encodedVerifier) {
  return Isolate.run(() => _verifyPinVerifier(pin, encodedVerifier));
}

String _createPinVerifier(String pin) {
  final random = Random.secure();
  final salt = List<int>.generate(
    _pinSaltLength,
    (_) => random.nextInt(256),
    growable: false,
  );
  final derived = _pbkdf2Sha256(
    pin: pin,
    salt: salt,
    iterations: _pinVerifierIterations,
    length: _pinHashLength,
  );

  return [
    _pinVerifierVersion,
    _pinVerifierIterations.toString(),
    base64Url.encode(salt),
    base64Url.encode(derived),
  ].join(r'$');
}

bool _verifyPinVerifier(String pin, String encodedVerifier) {
  final parts = encodedVerifier.split(r'$');
  if (parts.length != 4 || parts.first != _pinVerifierVersion) {
    return false;
  }

  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 10000 || iterations > 1000000) {
    return false;
  }

  try {
    final salt = base64Url.decode(parts[2]);
    final expected = base64Url.decode(parts[3]);
    if (salt.length < 16 || expected.length != _pinHashLength) {
      return false;
    }

    final actual = _pbkdf2Sha256(
      pin: pin,
      salt: salt,
      iterations: iterations,
      length: expected.length,
    );
    return _constantTimeEquals(actual, expected);
  } on FormatException {
    return false;
  }
}

List<int> _pbkdf2Sha256({
  required String pin,
  required List<int> salt,
  required int iterations,
  required int length,
}) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  final output = <int>[];
  var blockIndex = 1;

  while (output.length < length) {
    final counter = ByteData(4)..setUint32(0, blockIndex, Endian.big);
    var block = hmac.convert([
      ...salt,
      ...counter.buffer.asUint8List(),
    ]).bytes;
    final accumulated = List<int>.from(block);

    for (var iteration = 1; iteration < iterations; iteration++) {
      block = hmac.convert(block).bytes;
      for (var index = 0; index < accumulated.length; index++) {
        accumulated[index] ^= block[index];
      }
    }

    output.addAll(accumulated);
    blockIndex++;
  }

  return output.sublist(0, length);
}

bool _constantTimeEquals(List<int> first, List<int> second) {
  if (first.length != second.length) return false;

  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}
