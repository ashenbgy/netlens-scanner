import 'models.dart';

class ChannelAdvice {
  const ChannelAdvice({
    required this.summary,
    required this.coChannelCount,
    this.suggested,
  });

  final String summary;
  final int coChannelCount;
  final int? suggested;
}

/// Compares [target] against the other networks in the same band that are
/// strong enough to matter (>= -80 dBm). On 2.4 GHz it scores channels 1, 6
/// and 11 by weighted overlap and suggests a switch when one is clearly
/// less congested.
ChannelAdvice adviseChannel(WifiNetwork target, List<WifiNetwork> nearby) {
  final neighbors = nearby.where(
    (item) =>
        item.bssid != target.bssid &&
        item.band == target.band &&
        item.rssi >= -80,
  );
  final coChannel = neighbors
      .where((item) => item.channel == target.channel)
      .length;

  if (target.band != '2.4 GHz') {
    return ChannelAdvice(
      coChannelCount: coChannel,
      summary: coChannel == 0
          ? 'Channel ${target.channel} has no strong co-channel network nearby.'
          : 'Channel ${target.channel} shares airtime with $coChannel nearby network${coChannel == 1 ? '' : 's'}. Enable automatic channel selection on the router.',
    );
  }

  const candidates = [1, 6, 11];
  double score(int candidate) => neighbors.fold<double>(0, (sum, item) {
    final distance = (item.channel - candidate).abs();
    if (distance >= 5) return sum;
    final overlap = (5 - distance) / 5;
    final strength = ((item.rssi + 100) / 50).clamp(.05, 1.0);
    return sum + overlap * strength;
  });

  final scores = {
    for (final candidate in candidates) candidate: score(candidate),
  };
  final best = candidates.reduce((a, b) => scores[a]! <= scores[b]! ? a : b);
  final currentScore = score(target.channel);
  final worthwhileChange =
      best != target.channel &&
      currentScore > 0 &&
      scores[best]! < currentScore * .8;
  final congestion = currentScore >= .5
      ? 'measurable overlap with nearby networks'
      : 'low overlap with nearby networks';
  return ChannelAdvice(
    coChannelCount: coChannel,
    suggested: worthwhileChange ? best : null,
    summary: worthwhileChange
        ? 'Channel ${target.channel} has $congestion; channel $best is less crowded.'
        : 'Channel ${target.channel} has $congestion.',
  );
}
