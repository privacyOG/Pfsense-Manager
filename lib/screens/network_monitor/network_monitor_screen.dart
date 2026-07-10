import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/dashboard.dart';
import '../../models/network_state.dart';
import '../../providers/session_provider.dart';
import '../../widgets/interface_traffic_totals.dart';

part 'network_monitor_state.dart';
part 'network_monitor_polling.dart';
part 'network_monitor_view.dart';
part 'network_monitor_cards.dart';
part 'network_monitor_chart.dart';
part 'network_monitor_support.dart';
