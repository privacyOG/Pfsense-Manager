import 'package:flutter_test/flutter_test.dart';
import 'package:pfsense_manager/services/certificate_trust.dart';

void main() {
  test('normalises and formats SHA-256 certificate fingerprints', () {
    const fingerprint =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    expect(
      normalizeCertificateFingerprint('01:23:45:67:89:ab:cd:ef'),
      '0123456789ABCDEF',
    );
    expect(isValidCertificateFingerprint(fingerprint), isTrue);
    expect(
      formatCertificateFingerprint(fingerprint),
      '01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:'
      '01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF',
    );
  });

  test('rejects incomplete certificate fingerprints', () {
    expect(isValidCertificateFingerprint('AA:BB:CC'), isFalse);
    expect(isValidCertificateFingerprint(''), isFalse);
  });

  test('computes a stable SHA-256 fingerprint from DER bytes', () {
    expect(
      sha256FingerprintFromDer(const [1, 2, 3]),
      '039058C6F2C0CB492C533B0A4D14EF77CC0F78ABCCCED5287D84A1A2011CFB81',
    );
  });
}
