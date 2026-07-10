part of 'network_monitor_screen.dart';

extension _NetworkMonitorView on _NetworkMonitorScreenState {
  Widget _buildScreen(BuildContext context) {
    final session = context.watch<PfSenseSessionProvider>();
    final query = _search.text.trim().toLowerCase();
    final visible = _states
        .where(_matchesQuickFilter)
        .where((state) {
          if (query.isEmpty) return true;
          return [
            state.source,
            state.destination,
            state.interface,
            state.protocol,
            state.state,
          ].join(' ').toLowerCase().contains(query);
        })
        .toList();

    final totalRates = _totalHistory.isEmpty
        ? const _InterfaceRates(inBps: 0, outBps: 0)
        : _InterfaceRates(
            inBps: _totalHistory.last.inBps,
            outBps: _totalHistory.last.outBps,
          );

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: [
          _summaryCard(rates: totalRates),
          const SizedBox(height: 14),
          _TrafficChartCard(
            title: 'Live throughput',
            subtitle: 'Combined traffic across all reported interfaces',
            history: _totalHistory,
            height: 250,
            unit: _bandwidthUnit,
          ),
          if (_lastSuccessfulRefresh != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last updated ${_formatClock(_lastSuccessfulRefresh!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (!session.connected)
            const _Message(
              icon: Icons.cloud_off_outlined,
              text: 'Disconnected',
            )
          else if (_error != null)
            _Message(icon: Icons.error_outline, text: _error.toString()),
          if (session.connected && _interfaces.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Interface traffic',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            for (var index = 0; index < _interfaces.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _InterfaceTrafficCard(
                  interface: _interfaces[index],
                  rates: _rates[_interfaceLabel(_interfaces[index])],
                  history:
                      _interfaceHistory[_interfaceLabel(_interfaces[index])] ??
                          const [],
                  accent: _interfaceAccent(index),
                  unit: _bandwidthUnit,
                ),
              ),
          ],
          const SizedBox(height: 4),
          _filterControls(),
          const SizedBox(height: 12),
          if (session.connected && !_loading && visible.isEmpty)
            const _Message(
              icon: Icons.travel_explore,
              text: 'No live firewall states reported yet.',
            ),
          if (session.connected)
            for (final state in visible.take(250)) _stateTile(state),
        ],
      ),
    );
  }

  Widget _summaryCard({required _InterfaceRates rates}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const surfaceTop = Color(0xFF17334A);
    const surfaceBottom = Color(0xFF112536);
    const borderColor = Color(0xFF355064);
    const primaryText = Color(0xFFE6EDF5);
    const secondaryText = Color(0xFFA9B8C7);

    return Container(
      key: const Key('network-activity-card'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [surfaceTop, surfaceBottom],
        ),
        border: Border.all(color: borderColor.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.monitor_heart_outlined,
                  color: colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Network Activity',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: primaryText,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _live
                          ? 'Live updates every $_refreshSeconds second${_refreshSeconds == 1 ? '' : 's'}'
                          : 'Live updates paused',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                label: 'Live network updates',
                value: _live ? 'On' : 'Off',
                child: Transform.scale(
                  scale: 0.88,
                  child: Switch(
                    value: _live,
                    onChanged: (value) {
                      setState(() => _live = value);
                      _savePreferences();
                      if (value) _load();
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_BandwidthUnit>(
              key: const Key('bandwidth-unit-selector'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: _BandwidthUnit.bits,
                  label: Text('Bits/s'),
                ),
                ButtonSegment(
                  value: _BandwidthUnit.bytes,
                  label: Text('Bytes/s'),
                ),
              ],
              selected: {_bandwidthUnit},
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                foregroundColor: secondaryText,
                selectedForegroundColor: primaryText,
                selectedBackgroundColor:
                    colorScheme.primary.withValues(alpha: 0.25),
                backgroundColor: Colors.black.withValues(alpha: 0.15),
                side: BorderSide(
                  color: borderColor.withValues(alpha: 0.8),
                ),
              ),
              onSelectionChanged: (values) {
                setState(() => _bandwidthUnit = values.first);
                _savePreferences();
              },
            ),
          ),
          const SizedBox(height: 17),
          Text(
            'Current transfer rate',
            style: theme.textTheme.labelLarge?.copyWith(
              color: secondaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: 'Inbound',
                  value: _formatRate(rates.inBps, _bandwidthUnit),
                  icon: Icons.south_west,
                  color: const Color(0xFF29B6F6),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _MetricTile(
                  label: 'Outbound',
                  value: _formatRate(rates.outBps, _bandwidthUnit),
                  icon: Icons.north_east,
                  color: const Color(0xFFFF9D2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Interface totals',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: secondaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cumulative counters reported by pfSense',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryText.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          InterfaceTrafficTotals(
            interfaces: _interfaces,
            compact: true,
            darkSurface: true,
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Text(
                'Refresh interval',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Flexible(
                child: SegmentedButton<int>(
                  key: const Key('refresh-interval-selector'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1s')),
                    ButtonSegment(value: 3, label: Text('3s')),
                    ButtonSegment(value: 5, label: Text('5s')),
                    ButtonSegment(value: 10, label: Text('10s')),
                  ],
                  selected: {_refreshSeconds},
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    foregroundColor: secondaryText,
                    selectedForegroundColor: primaryText,
                    selectedBackgroundColor:
                        colorScheme.primary.withValues(alpha: 0.25),
                    backgroundColor: Colors.black.withValues(alpha: 0.15),
                    side: BorderSide(
                      color: borderColor.withValues(alpha: 0.8),
                    ),
                  ),
                  onSelectionChanged: (values) {
                    final value = values.first;
                    setState(() {
                      _refreshSeconds = math.max(
                        networkMonitorMinimumInterfaceSeconds,
                        value,
                      );
                      _previousCounters.clear();
                      _rates.clear();
                      _interfaceHistory.clear();
                      _totalHistory.clear();
                      _lastSampleAt = null;
                    });
                    _startTimers();
                    _savePreferences();
                    if (_live) _refreshInterfaces();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterControls() {
    return Column(
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final value in const [
              'all',
              'wan',
              'lan',
              'vpn',
              'tcp',
              'udp',
              'established',
            ])
              ChoiceChip(
                label: Text(value.toUpperCase()),
                selected: _quickFilter == value,
                onSelected: (_) {
                  setState(() => _quickFilter = value);
                  _savePreferences();
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          decoration: const InputDecoration(
            labelText: 'Filter IP, interface, protocol or state',
            prefixIcon: Icon(Icons.search),
          ),
        ),
      ],
    );
  }

  Widget _stateTile(NetworkState state) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.swap_horiz),
        title: Text('${state.source} → ${state.destination}'),
        subtitle: Text(
          '${state.interface} • ${state.protocol.toUpperCase()} • ${state.state}',
        ),
        trailing: Text(_formatBytes(state.bytes)),
      ),
    );
  }

  bool _matchesQuickFilter(NetworkState state) {
    final interface = state.interface.toLowerCase();
    final protocol = state.protocol.toLowerCase();
    final status = state.state.toLowerCase();
    return switch (_quickFilter) {
      'wan' => interface.contains('wan'),
      'lan' => interface.contains('lan'),
      'vpn' => interface.contains('vpn') ||
          interface.contains('ovpn') ||
          interface.contains('ipsec'),
      'tcp' => protocol.contains('tcp'),
      'udp' => protocol.contains('udp'),
      'established' =>
        status.contains('estab') || status.contains('syn_sent'),
      _ => true,
    };
  }

  Color _interfaceAccent(int index) {
    const accents = [
      Color(0xFF29B6F6),
      Color(0xFF66BB6A),
      Color(0xFFAB47BC),
      Color(0xFFFFCA28),
      Color(0xFF26C6DA),
      Color(0xFFEF5350),
    ];
    return accents[index % accents.length];
  }
}
