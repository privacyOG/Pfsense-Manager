import 'package:flutter/widgets.dart';

class AppStrings {
  final Locale locale;

  const AppStrings(this.locale);

  static const supportedLocales = [
    Locale('en'),
    Locale('ar'),
    Locale('es'),
    Locale('fr'),
    Locale('de'),
  ];

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings)!;
  }

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  static const _values = <String, Map<String, String>>{
    'en': {
      'appTitle': 'pfSense Manager',
      'profiles': 'Profiles',
      'dashboard': 'Dashboard',
      'rules': 'Rules',
      'logs': 'Logs',
      'services': 'Services',
      'system': 'System',
      'vpn': 'VPN',
      'settings': 'Settings',
      'addProfile': 'Add profile',
      'editProfile': 'Edit profile',
      'name': 'Name',
      'host': 'Host',
      'port': 'Port',
      'username': 'Username',
      'apiKey': 'API key or password',
      'https': 'HTTPS',
      'selfSigned': 'Allow self-signed certificate',
      'save': 'Save',
      'cancel': 'Cancel',
      'connect': 'Connect',
      'disconnect': 'Disconnect',
      'import': 'Import',
      'export': 'Export',
      'cpu': 'CPU',
      'memory': 'Memory',
      'uptime': 'Uptime',
      'gateway': 'Gateway',
      'refresh': 'Refresh',
      'offline': 'Offline or unreachable',
      'search': 'Search',
      'all': 'All',
      'pass': 'Pass',
      'block': 'Block',
      'reject': 'Reject',
      'start': 'Start',
      'stop': 'Stop',
      'restart': 'Restart',
      'reboot': 'Reboot firewall',
      'confirm': 'Confirm',
      'darkMode': 'Dark mode',
      'language': 'Language',
      'autoLock': 'Auto-lock',
      'minutes': 'minutes',
      'unlock': 'Unlock',
      'locked': 'Session locked',
      'empty': 'Nothing to show yet',
      'delete': 'Delete',
      'enabled': 'Enabled',
      'disabled': 'Disabled',
      'openvpn': 'OpenVPN',
      'tailscale': 'Tailscale',
    },
    'ar': {
      'appTitle': 'مدير pfSense',
      'profiles': 'الملفات',
      'dashboard': 'اللوحة',
      'rules': 'القواعد',
      'logs': 'السجلات',
      'services': 'الخدمات',
      'system': 'النظام',
      'vpn': 'VPN',
      'settings': 'الإعدادات',
      'addProfile': 'إضافة ملف',
      'save': 'حفظ',
      'cancel': 'إلغاء',
      'connect': 'اتصال',
      'disconnect': 'قطع الاتصال',
      'search': 'بحث',
      'darkMode': 'الوضع الداكن',
      'language': 'اللغة',
      'autoLock': 'القفل التلقائي',
      'unlock': 'فتح',
      'locked': 'الجلسة مقفلة',
    },
    'es': {
      'appTitle': 'pfSense Manager',
      'profiles': 'Perfiles',
      'dashboard': 'Panel',
      'rules': 'Reglas',
      'logs': 'Registros',
      'services': 'Servicios',
      'system': 'Sistema',
      'vpn': 'VPN',
      'settings': 'Ajustes',
      'addProfile': 'Agregar perfil',
      'save': 'Guardar',
      'cancel': 'Cancelar',
      'connect': 'Conectar',
      'disconnect': 'Desconectar',
      'search': 'Buscar',
      'darkMode': 'Modo oscuro',
      'language': 'Idioma',
      'autoLock': 'Bloqueo automático',
      'unlock': 'Desbloquear',
      'locked': 'Sesión bloqueada',
    },
    'fr': {
      'appTitle': 'pfSense Manager',
      'profiles': 'Profils',
      'dashboard': 'Tableau',
      'rules': 'Regles',
      'logs': 'Journaux',
      'services': 'Services',
      'system': 'Systeme',
      'vpn': 'VPN',
      'settings': 'Reglages',
      'addProfile': 'Ajouter un profil',
      'save': 'Enregistrer',
      'cancel': 'Annuler',
      'connect': 'Connecter',
      'disconnect': 'Deconnecter',
      'search': 'Rechercher',
      'darkMode': 'Mode sombre',
      'language': 'Langue',
      'autoLock': 'Verrouillage auto',
      'unlock': 'Deverrouiller',
      'locked': 'Session verrouillee',
    },
    'de': {
      'appTitle': 'pfSense Manager',
      'profiles': 'Profile',
      'dashboard': 'Dashboard',
      'rules': 'Regeln',
      'logs': 'Protokolle',
      'services': 'Dienste',
      'system': 'System',
      'vpn': 'VPN',
      'settings': 'Einstellungen',
      'addProfile': 'Profil hinzufugen',
      'save': 'Speichern',
      'cancel': 'Abbrechen',
      'connect': 'Verbinden',
      'disconnect': 'Trennen',
      'search': 'Suchen',
      'darkMode': 'Dunkelmodus',
      'language': 'Sprache',
      'autoLock': 'Automatische Sperre',
      'unlock': 'Entsperren',
      'locked': 'Sitzung gesperrt',
    },
  };

  String t(String key) {
    return _values[locale.languageCode]?[key] ?? _values['en']![key] ?? key;
  }
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppStrings.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    );
  }

  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale);

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}
