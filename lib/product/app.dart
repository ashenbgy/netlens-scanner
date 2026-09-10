import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'charts.dart';
import 'diagnostics.dart';
import 'models.dart';
import 'recommendations.dart';
import 'signal.dart';
import 'support.dart';
import 'wifi_service.dart';

const ink = Color(0xff191719);
const paper = Color(0xfff2f0ec);
const coral = Color(0xffff4e68);

class AlphaNetScopeApp extends StatefulWidget {
  const AlphaNetScopeApp({super.key, required this.diagnostics});
  final DiagnosticsService diagnostics;

  @override
  State<AlphaNetScopeApp> createState() => _AlphaNetScopeAppState();
}

class _AlphaNetScopeAppState extends State<AlphaNetScopeApp>
    with WidgetsBindingObserver {
  final wifi = WifiSurveyService();
  bool ready = false;
  bool onboarded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        wifi.resume();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        wifi.pause();
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _initialize() async {
    final preferences = await SharedPreferences.getInstance();
    onboarded = preferences.getBool('onboarding_complete') ?? false;
    if (onboarded) await wifi.start();
    if (mounted) setState(() => ready = true);
  }

  Future<void> _completeOnboarding() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('onboarding_complete', true);
    await wifi.start(askPermissions: true);
    if (mounted) setState(() => onboarded = true);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Alpha NetScope',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(seedColor: coral, surface: paper),
    ),
    home: !ready
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : !onboarded
        ? OnboardingScreen(onComplete: _completeOnboarding)
        : ProductShell(wifi: wifi, diagnostics: widget.diagnostics),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    wifi.dispose();
    super.dispose();
  }
}

class ProductShell extends StatefulWidget {
  const ProductShell({
    super.key,
    required this.wifi,
    required this.diagnostics,
  });
  final WifiSurveyService wifi;
  final DiagnosticsService diagnostics;

  @override
  State<ProductShell> createState() => _ProductShellState();
}

class _ProductShellState extends State<ProductShell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      SignalMeterPage(wifi: widget.wifi),
      NetworksPage(wifi: widget.wifi),
      InfoPage(diagnostics: widget.diagnostics),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) => setState(() => tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.show_chart), label: 'Signal'),
          NavigationDestination(icon: Icon(Icons.radar), label: 'Networks'),
          NavigationDestination(icon: Icon(Icons.info_outline), label: 'About'),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, {this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ALPHA NETSCOPE',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: coral,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (subtitle != null)
                Text(subtitle!, style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

class NetworksPage extends StatefulWidget {
  const NetworksPage({super.key, required this.wifi});
  final WifiSurveyService wifi;

  @override
  State<NetworksPage> createState() => _NetworksPageState();
}

class _NetworksPageState extends State<NetworksPage> {
  String? band;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.wifi,
    builder: (context, _) {
      final wifi = widget.wifi;
      final connected = wifi.connected;
      // Follow the connected network's band until the user picks one.
      final activeBand = band ?? connected?.band ?? '2.4 GHz';
      final visible = wifi.networks
          .where((item) => item.band == activeBand)
          .toList();
      final hint = wifi.scanHint;
      final now = DateTime.now().millisecondsSinceEpoch;
      return Column(
        children: [
          _Header(
            'Nearby Wi-Fi',
            subtitle: hint.isEmpty ? wifi.status : '${wifi.status}\n$hint',
            action: IconButton.filled(
              tooltip: 'Scan nearby networks',
              onPressed: () => wifi.refresh(askPermissions: true),
              icon: const Icon(Icons.wifi_find),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '2.4 GHz', label: Text('2.4 GHz')),
                ButtonSegment(value: '5 GHz', label: Text('5 GHz')),
                ButtonSegment(value: '6 GHz', label: Text('6 GHz')),
              ],
              selected: {activeBand},
              showSelectedIcon: false,
              onSelectionChanged: (value) => setState(() => band = value.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 190,
                child: CustomPaint(
                  painter: ChannelUsageChart(
                    visible,
                    band: activeBand,
                    highlight: connected?.bssid,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? _Empty(
                    icon: Icons.wifi_find,
                    text: wifi.networks.isEmpty
                        ? 'No connected signal available. Enable Wi-Fi, or tap scan to discover nearby networks.'
                        : 'No $activeBand networks in the last scan.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final network = visible[index];
                      final isConnected = network.bssid == connected?.bssid;
                      // Missed by the latest scan but kept so its trace
                      // continues; dim it until it shows up again.
                      final missedSeconds =
                          (now - network.lastSeen) ~/ 1000 - 5;
                      final stale =
                          !isConnected &&
                          missedSeconds > scanInterval.inSeconds;
                      final details = [
                        'CH ${network.channel}',
                        if (network.widthMhz > 0) '${network.widthMhz} MHz',
                        if (network.standard.isNotEmpty) network.standard,
                        network.security,
                        if (stale) 'last seen ${missedSeconds}s ago',
                      ].join(' · ');
                      return Card(
                        child: ListTile(
                          enabled: !stale,
                          leading: Icon(
                            isConnected ? Icons.wifi_tethering : Icons.wifi,
                            color: signalColor(network.rssi.toDouble()),
                          ),
                          title: Text(
                            network.ssid,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: isConnected
                                ? const TextStyle(fontWeight: FontWeight.bold)
                                : null,
                          ),
                          subtitle: Text('$details\n${network.bssid}'),
                          isThreeLine: true,
                          trailing: Text(
                            '${network.rssi}\ndBm',
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: radioColor(network.bssid),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
    },
  );
}

class SignalMeterPage extends StatefulWidget {
  const SignalMeterPage({super.key, required this.wifi});
  final WifiSurveyService wifi;

  @override
  State<SignalMeterPage> createState() => _SignalMeterPageState();
}

class _SignalMeterPageState extends State<SignalMeterPage> {
  String band = 'All';
  final Set<String> selected = {};
  bool selectionCustomized = false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.wifi,
    builder: (context, _) {
      final connected = widget.wifi.connected;
      final visible = band == 'All'
          ? widget.wifi.networks
          : widget.wifi.networks.where((item) => item.band == band).toList();
      final defaultIds = visible.take(6).map((item) => item.bssid).toSet();
      final effectiveIds = selectionCustomized ? selected : defaultIds;
      final plotted = visible
          .where((item) => effectiveIds.contains(item.bssid))
          .toList();
      return ListView(
        padding: const EdgeInsets.only(bottom: 10),
        children: [
          const _Header(
            'Signal meter',
            subtitle: 'Live RSSI history while the app is open',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: connected == null
                ? const Card(
                    child: ListTile(
                      leading: Icon(Icons.wifi_off),
                      title: Text('Not connected to Wi-Fi'),
                      subtitle: Text(
                        'Join a network to see its live signal strength.',
                      ),
                    ),
                  )
                : _ConnectedCard(
                    network: connected,
                    session: widget.wifi.session,
                    advice: adviseChannel(connected, widget.wifi.networks),
                    onReset: widget.wifi.resetSession,
                  ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'All', label: Text('All')),
                ButtonSegment(value: '2.4 GHz', label: Text('2.4 GHz')),
                ButtonSegment(value: '5 GHz', label: Text('5 GHz')),
                ButtonSegment(value: '6 GHz', label: Text('6 GHz')),
              ],
              selected: {band},
              showSelectedIcon: false,
              onSelectionChanged: (value) => setState(() => band = value.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 220,
                child: CustomPaint(
                  painter: SignalHistoryChart(
                    plotted,
                    now: DateTime.now().millisecondsSinceEpoch,
                    window: historyWindow,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          for (final item in visible.take(8))
            ListTile(
              leading: Checkbox(
                value: effectiveIds.contains(item.bssid),
                activeColor: radioColor(item.bssid),
                onChanged: (value) => setState(() {
                  if (!selectionCustomized) {
                    selected.addAll(defaultIds);
                    selectionCustomized = true;
                  }
                  value == true
                      ? selected.add(item.bssid)
                      : selected.remove(item.bssid);
                }),
              ),
              title: Text(item.ssid),
              subtitle: Text('${item.band} · ${item.bssid}'),
              trailing: Text(
                '${item.rssi} dBm',
                style: TextStyle(
                  color: radioColor(item.bssid),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({
    required this.network,
    required this.session,
    required this.advice,
    required this.onReset,
  });
  final WifiNetwork network;
  final SessionStats session;
  final ChannelAdvice advice;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final color = signalColor(network.rssi.toDouble());
    return Card(
      color: ink,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              network.ssid,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              [
                network.band,
                'CH ${network.channel}',
                if (network.widthMhz > 0) '${network.widthMhz} MHz',
                if (network.standard.isNotEmpty) network.standard,
                if (network.linkSpeedMbps > 0) '${network.linkSpeedMbps} Mbps',
              ].join(' · '),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${network.rssi}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 52,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'dBm · ${signalGrade(network.rssi)}',
                    style: TextStyle(color: color, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: signalPercent(network.rssi) / 100,
                minHeight: 6,
                color: color,
                backgroundColor: Colors.white12,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat('MIN', session.min),
                _Stat('AVG', session.average),
                _Stat('MAX', session.max),
                const Spacer(),
                IconButton(
                  tooltip: 'Reset session stats',
                  onPressed: session.count == 0 ? null : onReset,
                  icon: const Icon(Icons.restart_alt),
                  color: Colors.white70,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              advice.summary,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          value == null ? '—' : '$value',
          style: TextStyle(
            color: value == null
                ? Colors.white38
                : signalColor(value!.toDouble()),
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: Colors.black38),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
