import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

class CertificateInspection {
  const CertificateInspection({
    required this.sha256Fingerprint,
    required this.subject,
    required this.issuer,
    required this.startValidity,
    required this.endValidity,
  });

  final String sha256Fingerprint;
  final String subject;
  final String issuer;
  final DateTime startValidity;
  final DateTime endValidity;
}

class CertificateInspectionException implements Exception {
  const CertificateInspectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

String sha256FingerprintFromDer(List<int> derBytes) {
  return sha256.convert(derBytes).toString().toUpperCase();
}

String normalizeCertificateFingerprint(String value) {
  return value.replaceAll(RegExp('[^0-9a-fA-F]'), '').toUpperCase();
}

bool isValidCertificateFingerprint(String value) {
  return normalizeCertificateFingerprint(value).length == 64;
}

String formatCertificateFingerprint(String value) {
  final normalized = normalizeCertificateFingerprint(value);
  if (normalized.isEmpty) return '';
  final parts = <String>[];
  for (var index = 0; index < normalized.length; index += 2) {
    final end = index + 2 > normalized.length ? normalized.length : index + 2;
    parts.add(normalized.substring(index, end));
  }
  return parts.join(':');
}

bool certificateFingerprintMatches(
  String expectedFingerprint,
  X509Certificate certificate,
) {
  final expected = normalizeCertificateFingerprint(expectedFingerprint);
  if (expected.length != 64) return false;
  return expected == sha256FingerprintFromDer(certificate.der);
}

Future<CertificateInspection> inspectCertificate({
  required String host,
  required int port,
  Duration timeout = const Duration(seconds: 15),
}) async {
  SecureSocket? socket;
  try {
    socket = await SecureSocket.connect(
      host,
      port,
      onBadCertificate: (_) => true,
      timeout: timeout,
    );
    final certificate = socket.peerCertificate;
    if (certificate == null) {
      throw const CertificateInspectionException(
        'The server did not present a TLS certificate.',
      );
    }
    return CertificateInspection(
      sha256Fingerprint: sha256FingerprintFromDer(certificate.der),
      subject: certificate.subject,
      issuer: certificate.issuer,
      startValidity: certificate.startValidity,
      endValidity: certificate.endValidity,
    );
  } on CertificateInspectionException {
    rethrow;
  } on TimeoutException {
    throw const CertificateInspectionException(
      'Timed out while reading the firewall certificate.',
    );
  } on SocketException catch (error) {
    throw CertificateInspectionException(
      'Unable to read the firewall certificate: ${error.message}',
    );
  } on HandshakeException catch (error) {
    throw CertificateInspectionException(
      'TLS negotiation failed while reading the certificate: ${error.message}',
    );
  } finally {
    socket?.destroy();
  }
}
