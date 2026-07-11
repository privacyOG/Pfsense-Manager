class SystemRepository {
  const SystemRepository({
    this.name,
    this.url,
    this.priority,
    this.enabled,
  });

  final String? name;
  final String? url;
  final int? priority;
  final bool? enabled;

  bool get hasReportedData =>
      name != null || url != null || priority != null || enabled != null;
}
