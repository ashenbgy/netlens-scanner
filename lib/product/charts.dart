import 'package:flutter/material.dart';

import 'models.dart';
import 'signal.dart';

const chartInk = Color(0xff191719);

const _palette = [
  Color(0xff4ee6a8),
  Color(0xffff77b7),
  Color(0xffffd84d),
  Color(0xff5ba7ff),
  Color(0xffc7a1ff),
  Color(0xffff765f),
  Color(0xff55d8e6),
  Color(0xfff6a04d),
];

// FNV-1a over the BSSID so a network keeps its colour across launches;
// String.hashCode isn't guaranteed stable between runs.
Color radioColor(String bssid) {
  var hash = 0x811c9dc5;
  for (final unit in bssid.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return _palette[hash % _palette.length];
}

const _topDbm = -20;
const _bottomDbm = -100;

double _yFor(num rssi, double height) =>
    ((_topDbm - rssi) / (_topDbm - _bottomDbm)).clamp(0, 1) * height;

void _drawDbmGrid(Canvas canvas, Size size) {
  canvas.drawRect(Offset.zero & size, Paint()..color = chartInk);
  final grid = Paint()..color = Colors.white12;
  for (var dbm = -30; dbm >= -90; dbm -= 15) {
    final y = _yFor(dbm, size.height);
    canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    _label(canvas, '$dbm dBm', Offset(4, y - 12));
  }
}

void _label(
  Canvas canvas,
  String text,
  Offset at, {
  Color color = Colors.white38,
  double size = 10,
  bool center = false,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, center ? at.translate(-painter.width / 2, 0) : at);
}

/// RSSI over real time. The x-axis is the trailing [window] ending at [now],
/// so a network polled every second and one scanned every 30 s line up.
class SignalHistoryChart extends CustomPainter {
  SignalHistoryChart(this.networks, {required this.now, required this.window});
  final List<WifiNetwork> networks;
  final int now;
  final Duration window;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    _drawDbmGrid(canvas, size);
    final windowMs = window.inMilliseconds;
    final start = now - windowMs;
    final tick = Paint()..color = Colors.white12;
    for (var minute = 1; minute * 60000 < windowMs; minute++) {
      final x = size.width - minute * 60000 / windowMs * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tick);
      _label(canvas, '-${minute}m', Offset(x, size.height - 14), center: true);
    }
    _label(canvas, 'now', Offset(size.width - 24, size.height - 14));

    for (final network in networks) {
      final points = [
        for (final sample in network.history)
          Offset(
            (sample.time - start) / windowMs * size.width,
            _yFor(sample.rssi, size.height),
          ),
      ];
      if (points.length < 2) continue;
      canvas.drawPath(
        _smoothPath(points),
        Paint()
          ..color = radioColor(network.bssid)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Quadratic curve through the midpoints between samples, so integer-dBm
  /// steps read as one flowing trace rather than a staircase.
  static Path _smoothPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final mid = (points[i] + points[i + 1]) / 2;
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  @override
  bool shouldRepaint(covariant SignalHistoryChart old) => true;
}

/// Classic channel-usage view: one hump per network centred on its channel,
/// as wide as its bandwidth and as tall as its signal.
class ChannelUsageChart extends CustomPainter {
  ChannelUsageChart(this.networks, {required this.band, this.highlight});
  final List<WifiNetwork> networks;
  final String band;
  final String? highlight;

  static const _axes = {
    '2.4 GHz': (min: -1, max: 16, ticks: [1, 3, 5, 7, 9, 11, 13]),
    '5 GHz': (
      min: 30,
      max: 181,
      ticks: [36, 52, 68, 84, 100, 116, 132, 149, 165],
    ),
    '6 GHz': (min: -3, max: 240, ticks: [1, 33, 65, 97, 129, 161, 193, 225]),
  };

  @override
  void paint(Canvas canvas, Size size) {
    _drawDbmGrid(canvas, size);
    final axis = _axes[band] ?? _axes['2.4 GHz']!;
    final span = (axis.max - axis.min).toDouble();
    double xFor(num channel) => (channel - axis.min) / span * size.width;
    final baseline = size.height;

    final tick = Paint()..color = Colors.white12;
    for (final channel in axis.ticks) {
      final x = xFor(channel);
      canvas.drawLine(Offset(x, 0), Offset(x, baseline), tick);
      _label(canvas, '$channel', Offset(x, baseline - 14), center: true);
    }

    final sorted = [...networks]..sort((a, b) => a.rssi.compareTo(b.rssi));
    for (final network in sorted) {
      final width = network.widthMhz > 0 ? network.widthMhz : 20;
      final halfChannels = width / 5 / 2;
      final center = xFor(network.centerChannel);
      final left = xFor(network.centerChannel - halfChannels);
      final right = xFor(network.centerChannel + halfChannels);
      final peak = _yFor(network.rssi, size.height);
      final isHighlight = network.bssid == highlight;
      final color = isHighlight
          ? signalColor(network.rssi.toDouble())
          : radioColor(network.bssid);
      // Two cubics give a flat-topped hump that reads as a channel mask.
      final path = Path()
        ..moveTo(left, baseline)
        ..cubicTo(
          left + (center - left) * .5,
          baseline,
          left + (center - left) * .5,
          peak,
          center,
          peak,
        )
        ..cubicTo(
          right - (right - center) * .5,
          peak,
          right - (right - center) * .5,
          baseline,
          right,
          baseline,
        )
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: isHighlight ? .45 : .22),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isHighlight ? 2.5 : 1.2,
      );
      _label(
        canvas,
        network.ssid,
        Offset(center, peak - 13),
        color: isHighlight ? Colors.white : Colors.white70,
        size: isHighlight ? 11 : 9,
        center: true,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ChannelUsageChart old) => true;
}
