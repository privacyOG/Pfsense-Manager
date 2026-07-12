part of 'network_monitor_screen.dart';

enum _BandwidthUnit { bytes, bits }

const networkMonitorMinimumInterfaceSeconds = 1;
const networkMonitorMinimumStateSeconds = 15;
const networkMonitorStateRefreshMultiplier = 5;
const networkMonitorHistoryWindowSeconds = 120;

Duration networkMonitorInterfacePollInterval(int refreshSeconds) {
  return Duration(
    seconds: math.max(networkMonitorMinimumInterfaceSeconds, refreshSeconds),
  );
}

Duration networkMonitorStatePollInterval(int refreshSeconds) {
  return Duration(
    seconds: math.max(
      networkMonitorMinimumStateSeconds,
      refreshSeconds * networkMonitorStateRefreshMultiplier,
    ),
  );
}

int networkMonitorHistorySampleLimit(
  int refreshSeconds, {
  int historyWindowSeconds = networkMonitorHistoryWindowSeconds,
}) {
  final safeRefresh = math.max(networkMonitorMinimumInterfaceSeconds, refreshSeconds);
  return math.max(12, (historyWindowSeconds / safeRefresh).ceil() + 2);
}

String networkMonitorFormatRate(
  double bytesPerSecond, {
  required bool bits,
}) {
  final unit = bits ? _BandwidthUnit.bits : _BandwidthUnit.bytes;
  return _formatDisplayValue(_displayRate(bytesPerSecond, unit), unit);
}

class NetworkMonitorScreen extends StatefulWidget {
  const NetworkMonitorScreen({super.key});

  @override
  State<NetworkMonitorScreen> createState() => _NetworkMonitorScreenState();
}

class _NetworkMonitorScreenState extends State<NetworkMonitorScreen>
    with WidgetsBindingObserver {
  static const _prefLive = 'networkMonitor.live';
  static const _prefRefreshSeconds = 'networkMonitor.refreshSeconds';
  static const _prefQuickFilter = 'networkMonitor.quickFilter';
  static const _prefBandwidthUnit = 'networkMonitor.bandwidthUnit';

  final _search = TextEditingController();
  final Map<String, _InterfaceCounters> _previousCounters = {};
  final Map<String, _InterfaceRates> _rates = {};
  final Map<String, List<_RateSample>> _interfaceHistory = {};
  final List<_RateSample> _totalHistory = [];

  List<NetworkState> _states = [];
  List<InterfaceStatus> _interfaces = [];
  Object? _error;
  bool _loading = false;
  bool _interfacesRefreshing = false;
  bool _statesRefreshing = false;
  bool _live = true;
  bool _appActive = true;
  bool _preferencesLoaded = false;
  int _refreshSeconds = 3;
  String _quickFilter = 'all';
  _BandwidthUnit _bandwidthUnit = _BandwidthUnit.bits;
  Timer? _interfaceTimer;
  Timer? _stateTimer;
  DateTime? _lastSampleAt;
  DateTime? _lastSuccessfulRefresh;
  int _requestGeneration = 0;
  int? _loadedSessionGeneration;
  String? _loadedProfileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _search.addListener(_onSearchChanged);
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;

    final savedInterval = preferences.getInt(_prefRefreshSeconds) ?? 3;
    final allowedIntervals = const {1, 3, 5, 10};
    final savedUnit = preferences.getString(_prefBandwidthUnit);
    setState(() {
      _live = preferences.getBool(_prefLive) ?? true;
      _refreshSeconds = allowedIntervals.contains(savedInterval)
          ? savedInterval
          : math.max(networkMonitorMinimumInterfaceSeconds, savedInterval);
      _quickFilter = preferences.getString(_prefQuickFilter) ?? 'all';
      _bandwidthUnit =
          savedUnit == 'bytes' ? _BandwidthUnit.bytes : _BandwidthUnit.bits;
      _preferencesLoaded = true;
    });
    _startTimers();
  }

  Future<void> _savePreferences() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_prefLive, _live);
    await preferences.setInt(_prefRefreshSeconds, _refreshSeconds);
    await preferences.setString(_prefQuickFilter, _quickFilter);
    await preferences.setString(
      _prefBandwidthUnit,
      _bandwidthUnit == _BandwidthUnit.bytes ? 'bytes' : 'bits',
    );
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appActive == active) return;
    _appActive = active;
    if (active && _live && mounted) {
      _load();
    }
  }

  void _startTimers() {
    _interfaceTimer?.cancel();
    _stateTimer?.cancel();
    if (!_preferencesLoaded) return;

    _interfaceTimer = Timer.periodic(
      networkMonitorInterfacePollInterval(_refreshSeconds),
      (_) {
        if (mounted) _refreshInterfaces();
      },
    );
    _stateTimer = Timer.periodic(
      networkMonitorStatePollInterval(_refreshSeconds),
      (_) {
        if (mounted) _refreshStates();
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.watch<PfSenseSessionProvider>();
    final profileId = session.selectedProfile?.id;
    final changed = _loadedSessionGeneration != session.sessionGeneration ||
        _loadedProfileId != profileId;

    if (changed) {
      _requestGeneration++;
      _clearLiveData();
      _loadedSessionGeneration = session.sessionGeneration;
      _loadedProfileId = profileId;
      if (session.connected && !_loading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _load(showSpinner: true);
        });
      }
    } else if (_states.isEmpty &&
        _interfaces.isEmpty &&
        session.connected &&
        !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load(showSpinner: true);
      });
    }
  }

  void _commitState(VoidCallback callback) {
    if (!mounted) return;
    setState(callback);
  }

  void _clearLiveData() {
    _states = [];
    _interfaces = [];
    _previousCounters.clear();
    _rates.clear();
    _interfaceHistory.clear();
    _totalHistory.clear();
    _lastSampleAt = null;
    _lastSuccessfulRefresh = null;
    _error = null;
  }

  @override
  void dispose() {
    _requestGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _interfaceTimer?.cancel();
    _stateTimer?.cancel();
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _buildScreen(context);
}
