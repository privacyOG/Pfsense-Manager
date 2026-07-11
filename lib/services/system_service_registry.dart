import '../models/system_service.dart';

class SystemServiceRegistry {
  final Map<int, SystemService> _byId = {};
  final Map<String, List<int>> _idsByName = {};

  void replaceAll(Iterable<SystemService> services) {
    clear();
    for (final service in services) {
      final id = service.id;
      if (id == null) continue;
      _byId[id] = service;
      _idsByName.putIfAbsent(service.name, () => <int>[]).add(id);
    }
  }

  bool containsName(String name) => _idsByName.containsKey(name);

  List<SystemService> findByName(String name) {
    final ids = _idsByName[name] ?? const <int>[];
    return [
      for (final id in ids)
        if (_byId[id] != null) _byId[id]!,
    ];
  }

  Map<String, dynamic> actionDataForName(String name, String action) {
    final matches = findByName(name);
    if (matches.length > 1) {
      throw StateError(
        'Multiple services named "$name" are available. Select the exact service instance.',
      );
    }
    if (matches.isEmpty) {
      return {'name': name, 'action': action};
    }
    return actionDataForInstance(matches.single, action);
  }

  Map<String, dynamic> actionDataForInstance(
    SystemService service,
    String action,
  ) {
    final id = service.id;
    if (id == null) {
      throw StateError(
        'The selected service does not have a pfREST service ID and cannot be controlled safely.',
      );
    }
    return {'id': id, 'name': service.name, 'action': action};
  }

  void clear() {
    _byId.clear();
    _idsByName.clear();
  }
}
