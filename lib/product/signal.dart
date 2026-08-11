import 'package:flutter/material.dart';

Color signalColor(double rssi) {
  if (rssi >= -55) return const Color(0xffb8e02d);
  if (rssi >= -65) return const Color(0xff11c5c7);
  if (rssi >= -72) return const Color(0xffffc23c);
  if (rssi >= -82) return const Color(0xffff6c55);
  return const Color(0xff8c4250);
}

String signalGrade(int rssi) {
  if (rssi >= -55) return 'Excellent';
  if (rssi >= -65) return 'Good';
  if (rssi >= -72) return 'Fair';
  if (rssi >= -82) return 'Poor';
  return 'Dead';
}

/// Rough 0–100 quality from RSSI; -90 dBm and below is 0, -50 and above is 100.
int signalPercent(int rssi) => ((rssi + 90) * 2.5).clamp(0, 100).round();
