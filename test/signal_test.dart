import 'dart:ui' show PictureRecorder;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alpha_netscope/product/charts.dart';
import 'package:alpha_netscope/product/models.dart';
import 'package:alpha_netscope/product/recommendations.dart';
import 'package:alpha_netscope/product/signal.dart';

WifiNetwork _network(String bssid, int frequency, int rssi) => WifiNetwork(
  ssid: bssid,
  bssid: bssid,
  frequency: frequency,
  channel: frequency == 2484
      ? 14
      : frequency < 2484
      ? ((frequency - 2407) / 5).round()
      : ((frequency - 5000) / 5).round(),
  security: 'WPA2',
  rssi: rssi,
);

void main() {
  test('documented signal grades use the expected thresholds', () {
    expect(signalGrade(-55), 'Excellent');
    expect(signalGrade(-60), 'Good');
    expect(signalGrade(-68), 'Fair');
    expect(signalGrade(-78), 'Poor');
    expect(signalGrade(-90), 'Dead');
    expect(signalPercent(-50), 100);
    expect(signalPercent(-70), 50);
    expect(signalPercent(-95), 0);
  });

  test('bands are derived from frequency', () {
    expect(_network('a', 2437, -50).band, '2.4 GHz');
    expect(_network('b', 5220, -50).band, '5 GHz');
    expect(_network('c', 5975, -50).band, '6 GHz');
  });

  test('crowded 2.4 GHz channel suggests a less crowded one', () {
    final target = _network('target', 2412, -50);
    final advice = adviseChannel(target, [
      target,
      _network('neighbor', 2412, -55),
      _network('neighbor-2', 2417, -60),
    ]);
    // Channel 2 bleeds into channel 6, so 11 is the clear pick.
    expect(advice.coChannelCount, 1);
    expect(advice.suggested, 11);
    expect(advice.summary, contains('channel 11 is less crowded'));
  });

  test('quiet channel does not suggest a change', () {
    final target = _network('target', 2437, -50);
    final advice = adviseChannel(target, [
      target,
      _network('far', 2412, -90),
      _network('other-band', 5220, -40),
    ]);
    expect(advice.coChannelCount, 0);
    expect(advice.suggested, isNull);
    expect(advice.summary, contains('low overlap'));
  });

  test('5 GHz co-channel neighbours recommend auto channel', () {
    final target = _network('target', 5220, -50);
    final advice = adviseChannel(target, [target, _network('n', 5220, -60)]);
    expect(advice.coChannelCount, 1);
    expect(advice.suggested, isNull);
    expect(advice.summary, contains('automatic channel selection'));
  });

  test('signal history keeps only the trailing window', () {
    final network = _network('a', 2437, -50);
    for (var second = 0; second < 10; second++) {
      network.addSample(-50 - second, second * 1000, windowMs: 4000);
    }
    expect(network.rssi, -59);
    expect(network.lastSeen, 9000);
    // Five in-window samples plus one older so the line enters from the edge.
    expect(network.history.length, 6);
    expect(network.history.first.time, 4000);
  });

  test('session stats track min, max and average until reset', () {
    final stats = SessionStats();
    expect(stats.average, isNull);
    for (final rssi in [-50, -70, -60]) {
      stats.add(rssi);
    }
    expect(stats.min, -70);
    expect(stats.max, -50);
    expect(stats.average, -60);
    stats.reset();
    expect(stats.count, 0);
    expect(stats.min, isNull);
  });

  test('centre channel follows the reported centre frequency', () {
    final wide = _network('wide', 5180, -50)
      ..widthMhz = 80
      ..centerFrequency = 5210;
    expect(wide.channel, 36);
    expect(wide.centerChannel, 42);
    expect(_network('narrow', 5180, -50).centerChannel, 36);
  });

  test('charts paint without throwing for every band', () {
    final now = DateTime.now().millisecondsSinceEpoch;
    final networks = [
      _network('a', 2412, -45)..addSample(-45, now, windowMs: 180000),
      _network('b', 5180, -60)
        ..widthMhz = 80
        ..centerFrequency = 5210,
      _network('c', 5975, -80),
    ];
    networks.first.addSample(-48, now - 30000, windowMs: 180000);
    const size = Size(320, 200);
    SignalHistoryChart(
      networks,
      now: now,
      window: const Duration(minutes: 3),
    ).paint(Canvas(PictureRecorder()), size);
    for (final band in ['2.4 GHz', '5 GHz', '6 GHz']) {
      ChannelUsageChart(
        networks,
        band: band,
        highlight: 'a',
      ).paint(Canvas(PictureRecorder()), size);
    }
  });
}
