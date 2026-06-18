class CaptivePortalVoucher {
  const CaptivePortalVoucher({
    required this.code,
    this.minutesRemaining,
    this.used = false,
    this.zone = '',
  });

  final String code;
  final int? minutesRemaining;
  final bool used;
  final String zone;

  factory CaptivePortalVoucher.fromJson(Map<String, dynamic> json) {
    return CaptivePortalVoucher(
      code: (json['voucher'] ?? json['code'] ?? json['username'] ?? '').toString(),
      minutesRemaining: _parseInt(json['minutes_remaining'] ?? json['timeleft']),
      used: json['used'] == true || _parseInt(json['used']) == 1,
      zone: (json['zone'] ?? json['cpzone'] ?? '').toString(),
    );
  }

  static int? _parseInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    return int.tryParse(v.toString());
  }
}
