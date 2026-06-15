import 'package:flutter/material.dart';

import '../models/dashboard.dart';

class ThermalSensorsPanel extends StatelessWidget {
  const ThermalSensorsPanel({
    super.key,
    required this.sensors,
    this.fallbackTemperatureC,
  });

  final List<ThermalSensor> sensors;
  final double? fallbackTemperatureC;

  @override
  Widget build(BuildContext context) {
    final values = sensors.isNotEmpty
        ? sensors
        : fallbackTemperatureC == null
            ? const <ThermalSensor>[]
            : [
                ThermalSensor(
                  name: 'System sensor',
                  temperatureC: fallbackTemperatureC!,
                ),
              ];

    final hottest = values.isEmpty
        ? null
        : values.map((sensor) => sensor.temperatureC).reduce(
              (current, next) => current > next ? current : next,
            );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.device_thermostat, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CPU thermal sensors',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  values.isEmpty
                      ? 'Not reported'
                      : '${values.length} sensor${values.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              hottest == null
                  ? 'No thermal telemetry was returned by pfSense.'
                  : 'Hottest reading: ${hottest.toStringAsFixed(1)} °C',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (values.isNotEmpty) ...[
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 900
                      ? 4
                      : constraints.maxWidth >= 600
                          ? 3
                          : constraints.maxWidth >= 360
                              ? 2
                              : 1;
                  final width =
                      (constraints.maxWidth - ((columns - 1) * 10)) / columns;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final sensor in values)
                        SizedBox(
                          width: width,
                          child: ThermalSensorTile(sensor: sensor),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ThermalSensorTile extends StatelessWidget {
  const ThermalSensorTile({super.key, required this.sensor});

  final ThermalSensor sensor;

  @override
  Widget build(BuildContext context) {
    final color = thermalColor(sensor.temperatureC);
    final status = sensor.temperatureC >= 85
        ? 'Critical'
        : sensor.temperatureC >= 75
            ? 'Hot'
            : sensor.temperatureC >= 60
                ? 'Warm'
                : 'Normal';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.34)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.thermostat, color: color, size: 21),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sensor.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${sensor.temperatureC.toStringAsFixed(1)} °C',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

Color thermalColor(double value) {
  if (value >= 85) return Colors.red;
  if (value >= 75) return Colors.redAccent;
  if (value >= 60) return Colors.orangeAccent;
  return const Color(0xFF00C2A8);
}
