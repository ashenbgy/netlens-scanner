class SignalSample {
  const SignalSample(this.time, this.rssi);

  /// Milliseconds since epoch.
  final int time;
  final int rssi;
}

class WifiNetwork {
  WifiNetwork({
    required this.ssid,
    required this.bssid,
    required this.frequency,
    required this.channel,
    required this.security,
    required this.rssi,
    this.centerFrequency = 0,
    this.widthMhz = 0,
    this.standard = '',
    this.linkSpeedMbps = 0,
  });

  final String ssid;
  final String bssid;
  final int frequency;
  final int channel;
  final String security;
  int rssi;

  /// Centre of the occupied bandwidth; equals [frequency] for 20 MHz.
  int centerFrequency;

  /// Channel width in MHz, or 0 when Android did not report it.
  int widthMhz;

  /// Human label such as "Wi-Fi 6", or empty when unknown.
  String standard;

  /// Current link speed for the connected network, or 0 when unknown.
  int linkSpeedMbps;

  final List<SignalSample> history = [];

  /// Milliseconds since epoch of the latest sample, 0 before the first one.
  int lastSeen = 0;

  String get band => bandFor(frequency);

  /// Channel at the centre of the occupied bandwidth.
  int get centerChannel =>
      centerFrequency > 0 ? channelFor(centerFrequency) : channel;

  /// Records a reading and trims history to the trailing [windowMs]. One
  /// sample older than the window is kept so a chart line can enter from
  /// the left edge instead of starting part-way across.
  void addSample(int rssi, int time, {required int windowMs}) {
    this.rssi = rssi;
    lastSeen = time;
    history.add(SignalSample(time, rssi));
    final cutoff = time - windowMs;
    var drop = 0;
    while (drop < history.length && history[drop].time < cutoff) {
      drop++;
    }
    if (drop > 1) history.removeRange(0, drop - 1);
  }

  static String bandFor(int frequency) => frequency >= 5925
      ? '6 GHz'
      : frequency >= 4900
      ? '5 GHz'
      : '2.4 GHz';

  static int channelFor(int frequency) {
    if (frequency == 2484) return 14;
    if (frequency < 2484) return ((frequency - 2407) / 5).round();
    if (frequency >= 5925) return ((frequency - 5950) / 5).round();
    return ((frequency - 5000) / 5).round();
  }
}

/// Min / max / average of the connected signal since the app was opened or
/// the stats were last reset.
class SessionStats {
  int? min;
  int? max;
  int _sum = 0;
  int count = 0;

  int? get average => count == 0 ? null : (_sum / count).round();

  void add(int rssi) {
    min = min == null || rssi < min! ? rssi : min;
    max = max == null || rssi > max! ? rssi : max;
    _sum += rssi;
    count++;
  }

  void reset() {
    min = null;
    max = null;
    _sum = 0;
    count = 0;
  }
}
