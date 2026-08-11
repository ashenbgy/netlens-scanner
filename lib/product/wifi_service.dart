import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:wifi_scan/wifi_scan.dart';

import 'models.dart';

/// How much signal history each network keeps for the chart.
const historyWindow = Duration(minutes: 3);

/// Android 9+ allows foreground apps four scans per two minutes; anything
/// faster is silently refused, so we don't ask more often than this.
const scanInterval = Duration(seconds: 30);

class WifiSurveyService extends ChangeNotifier {
  static const _device = MethodChannel('alpha_netscope/device');
  final List<WifiNetwork> networks = [];
  final SessionStats session = SessionStats();
  StreamSubscription<List<WiFiAccessPoint>>? _subscription;
  Timer? _scanTimer;
  Timer? _signalTimer;
  String status = 'Starting continuous signal monitor';
  bool scanning = false;
  bool throttled = false;
  DateTime? nextScanAt;
  bool _busy = false;
  String? _connectedBssid;

  /// The network this device is currently joined to, if its RSSI is readable.
  WifiNetwork? get connected =>
      networks.where((network) => network.bssid == _connectedBssid).firstOrNull;

  /// Short line for the Networks header about when the next scan happens.
  String get scanHint {
    final next = nextScanAt;
    if (!scanning || next == null) return '';
    final seconds = next.difference(DateTime.now()).inSeconds.clamp(0, 999);
    return throttled
        ? 'Scan throttled by Android · retry in ${seconds}s'
        : 'Next scan in ${seconds}s';
  }

  Future<void> start({bool askPermissions = false}) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      status = 'Real Wi-Fi scanning requires Android';
      notifyListeners();
      return;
    }
    scanning = true;
    await _refreshConnectedSignal(notify: false);
    await refresh(askPermissions: askPermissions);
    _startTimers();
  }

  /// Stops periodic polling while the app is backgrounded. Android throttles
  /// background scans anyway, so continuing only wastes battery.
  void pause() {
    _scanTimer?.cancel();
    _signalTimer?.cancel();
    _scanTimer = null;
    _signalTimer = null;
    nextScanAt = null;
  }

  /// Restarts polling after [pause]; a no-op if [start] was never called.
  Future<void> resume() async {
    if (!scanning || _signalTimer != null) return;
    await _refreshConnectedSignal(notify: false);
    await refresh(askPermissions: false);
    _startTimers();
  }

  void resetSession() {
    session.reset();
    notifyListeners();
  }

  void _startTimers() {
    _signalTimer ??= Timer.periodic(const Duration(seconds: 1), (_) async {
      await _refreshConnectedSignal(notify: false);
      notifyListeners(); // also drives the scan countdown
    });
    _scanTimer ??= Timer.periodic(
      scanInterval,
      (_) => refresh(askPermissions: false),
    );
    nextScanAt ??= DateTime.now().add(scanInterval);
  }

  Future<void> refresh({bool askPermissions = true}) async {
    if (!scanning || _busy) return;
    _busy = true;
    try {
      final readable = await WiFiScan.instance.canGetScannedResults(
        askPermissions: askPermissions,
      );
      if (readable != CanGetScannedResults.yes) {
        await _refreshConnectedSignal(notify: false);
        status = networks.isEmpty
            ? _readStatus(readable)
            : 'Live connected signal · updates every second';
        notifyListeners();
        return;
      }
      _subscription ??= WiFiScan.instance.onScannedResultsAvailable.listen(
        _apply,
        onError: (_) {
          status = 'Wi-Fi scan failed — tap refresh';
          notifyListeners();
        },
      );
      final startable = await WiFiScan.instance.canStartScan(
        askPermissions: askPermissions,
      );
      status = 'Scanning…';
      notifyListeners();
      if (startable == CanStartScan.yes) {
        throttled = !await WiFiScan.instance.startScan();
      }
      _apply(await WiFiScan.instance.getScannedResults());
    } catch (_) {
      status = 'Wi-Fi unavailable — enable Wi-Fi and Location';
      notifyListeners();
    } finally {
      _busy = false;
      if (_scanTimer != null) nextScanAt = DateTime.now().add(scanInterval);
    }
  }

  Future<void> _refreshConnectedSignal({bool notify = true}) async {
    if (!scanning || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final reading = await _device.invokeMapMethod<String, dynamic>(
        'getConnectedWifiSignal',
      );
      final rssi = reading?['rssi'] as int?;
      final frequency = reading?['frequency'] as int? ?? 0;
      if (rssi == null || rssi >= 0 || rssi <= -127 || frequency <= 0) return;

      final rawSsid = (reading?['ssid'] as String? ?? '').replaceAll('"', '');
      final rawBssid = (reading?['bssid'] as String? ?? '').toLowerCase();
      final hasIdentity =
          rawBssid.isNotEmpty && rawBssid != '02:00:00:00:00:00';
      WifiNetwork? connected;
      for (final network in networks) {
        if ((hasIdentity && network.bssid.toLowerCase() == rawBssid) ||
            network.bssid == 'connected') {
          connected = network;
          break;
        }
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (connected == null) {
        connected = WifiNetwork(
          ssid: rawSsid.isEmpty || rawSsid == '<unknown ssid>'
              ? 'Connected Wi-Fi'
              : rawSsid,
          bssid: hasIdentity ? rawBssid : 'connected',
          frequency: frequency,
          channel: WifiNetwork.channelFor(frequency),
          security: 'Connected network',
          rssi: rssi,
        );
        networks.insert(0, connected);
      }
      connected.addSample(rssi, now, windowMs: historyWindow.inMilliseconds);
      final linkSpeed = reading?['linkSpeed'] as int? ?? 0;
      if (linkSpeed > 0) connected.linkSpeedMbps = linkSpeed;
      final standard = standardLabel(reading?['standard'] as int?);
      if (standard.isNotEmpty) connected.standard = standard;

      if (_connectedBssid != connected.bssid) session.reset();
      _connectedBssid = connected.bssid;
      session.add(rssi);
      if (networks.length == 1) {
        status = 'Live connected signal · updates every second';
      }
      if (notify) notifyListeners();
    } catch (_) {
      // A few vendors hide connected RSSI; explicit nearby scanning still works.
    }
  }

  void _apply(List<WiFiAccessPoint> results) {
    if (results.isEmpty) {
      status = networks.isEmpty
          ? 'Waiting for scan results…'
          : 'Showing last scan';
      notifyListeners();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final known = {for (final network in networks) network.bssid: network};
    // When Android hides the connected BSSID we track it under a placeholder
    // id; adopt the scan result that matches it so its history isn't lost.
    final placeholder = known['connected'];
    if (placeholder != null) {
      final match = results
          .where(
            (result) =>
                result.frequency == placeholder.frequency &&
                result.ssid == placeholder.ssid,
          )
          .firstOrNull;
      if (match != null) {
        known.remove('connected');
        known[match.bssid] = WifiNetwork(
          ssid: placeholder.ssid,
          bssid: match.bssid,
          frequency: placeholder.frequency,
          channel: placeholder.channel,
          security: placeholder.security,
          rssi: placeholder.rssi,
          standard: placeholder.standard,
          linkSpeedMbps: placeholder.linkSpeedMbps,
        )..history.addAll(placeholder.history);
        _connectedBssid = match.bssid;
      }
    }
    for (final result in results) {
      final network = known.putIfAbsent(
        result.bssid,
        () => WifiNetwork(
          ssid: result.ssid.trim().isEmpty ? 'Hidden network' : result.ssid,
          bssid: result.bssid,
          frequency: result.frequency,
          channel: WifiNetwork.channelFor(result.frequency),
          security: _security(result.capabilities),
          rssi: result.level,
        ),
      );
      network.addSample(
        result.level,
        now,
        windowMs: historyWindow.inMilliseconds,
      );
      network.widthMhz = _widthMhz(result.channelWidth);
      network.centerFrequency = network.widthMhz > 20
          ? (result.centerFrequency0 ?? 0)
          : 0;
      final standard = switch (result.standard) {
        WiFiStandards.legacy => 'Wi-Fi 3',
        WiFiStandards.n => 'Wi-Fi 4',
        WiFiStandards.ac => 'Wi-Fi 5',
        WiFiStandards.ax => 'Wi-Fi 6',
        WiFiStandards.ad => 'WiGig',
        WiFiStandards.unkown => '',
      };
      if (standard.isNotEmpty) network.standard = standard;
    }
    // A single scan often misses networks that are still there, so keep the
    // ones we've seen recently rather than restarting their trace next time.
    final cutoff = now - historyWindow.inMilliseconds;
    final updated =
        known.values
            .where(
              (network) =>
                  network.bssid == _connectedBssid ||
                  network.lastSeen >= cutoff,
            )
            .toList()
          ..sort((a, b) => b.rssi.compareTo(a.rssi));
    networks
      ..clear()
      ..addAll(updated);
    status = 'Live nearby scan · connected signal updates every second';
    notifyListeners();
  }

  String _readStatus(CanGetScannedResults state) => switch (state) {
    CanGetScannedResults.noLocationServiceDisabled => 'Turn on Location',
    CanGetScannedResults.noLocationPermissionDenied =>
      'Location denied — allow it in Android Settings',
    CanGetScannedResults.noLocationPermissionRequired =>
      'Location permission required — tap refresh',
    CanGetScannedResults.noLocationPermissionUpgradeAccuracy =>
      'Precise Location is required',
    CanGetScannedResults.notSupported => 'Wi-Fi scanning is unsupported',
    CanGetScannedResults.yes => 'Live device readings',
  };

  /// Maps Android's `ScanResult.WIFI_STANDARD_*` codes to a label.
  static String standardLabel(int? code) => switch (code) {
    1 => 'Wi-Fi 3',
    4 => 'Wi-Fi 4',
    5 => 'Wi-Fi 5',
    6 => 'Wi-Fi 6',
    7 => 'WiGig',
    8 => 'Wi-Fi 7',
    _ => '',
  };

  static int _widthMhz(WiFiChannelWidth? width) => switch (width) {
    WiFiChannelWidth.mhz20 => 20,
    WiFiChannelWidth.mhz40 => 40,
    WiFiChannelWidth.mhz80 => 80,
    WiFiChannelWidth.mhz160 || WiFiChannelWidth.mhz80Plus80 => 160,
    _ => 0,
  };

  static String _security(String capabilities) {
    final value = capabilities.toUpperCase();
    if (value.contains('SAE') || value.contains('WPA3')) return 'WPA3';
    if (value.contains('WPA2')) return 'WPA2';
    if (value.contains('WPA')) return 'WPA';
    if (value.contains('WEP')) return 'WEP';
    return 'Open';
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _signalTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
