class SystemRepository {
  const SystemRepository({
    required this.name,
    required this.url,
    required this.priority,
    this.enabled = true,
  });

  final String name;
  final String url;
  final int priority;
  final bool enabled;
}
