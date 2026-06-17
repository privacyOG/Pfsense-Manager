import 'package:pfsense_manager/services/pin_verifier.dart';

class MemoryPinVerifierStore implements PinVerifierStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String verifier) async {
    value = verifier;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}
