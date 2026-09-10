import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'diagnostics.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});
  final Future<void> Function() onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int page = 0;
  bool finishing = false;

  static const pages = [
    (
      Icons.radar,
      'See your Wi-Fi clearly',
      'Watch your connected signal update every second, chart it as you move around, and see which nearby networks compete for the same channel.',
    ),
    (
      Icons.admin_panel_settings_outlined,
      'Permissions only when needed',
      'Connected signal monitoring needs only Wi-Fi. Nearby scans may require Android Location permission, because Android ties Wi-Fi scan results to location access.',
    ),
    (
      Icons.shield_outlined,
      'Private by design',
      'Nothing is stored beyond your onboarding preference and local crash diagnostics. Nothing is uploaded automatically; you decide what to share.',
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
              ),
              child: const Text('Privacy policy'),
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: controller,
              itemCount: pages.length,
              onPageChanged: (value) => setState(() => page = value),
              itemBuilder: (context, index) {
                final item = pages[index];
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.$1, size: 88, color: const Color(0xffff4e68)),
                      const SizedBox(height: 28),
                      Text(
                        item.$2,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        item.$3,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              pages.length,
              (index) => Container(
                width: index == page ? 24 : 8,
                height: 8,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: index == page
                      ? const Color(0xffff4e68)
                      : Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: FilledButton(
              onPressed: finishing ? null : _next,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
              ),
              child: Text(
                page == pages.length - 1 ? 'Start monitoring' : 'Next',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _next() async {
    if (page < pages.length - 1) {
      await controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
      return;
    }
    setState(() => finishing = true);
    await widget.onComplete();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class InfoPage extends StatelessWidget {
  const InfoPage({super.key, required this.diagnostics});
  final DiagnosticsService diagnostics;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
    children: [
      Text(
        'ALPHA NETSCOPE',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: const Color(0xffff4e68),
          fontWeight: FontWeight.w900,
        ),
      ),
      Text(
        'Privacy & support',
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
      const SizedBox(height: 18),
      const Card(
        child: ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('Permission approach'),
          subtitle: Text(
            'Connected signal: Wi-Fi only\nNearby scan: Android may require Location',
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy policy'),
          subtitle: const Text('Review how on-device data is handled'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('Diagnostics'),
          subtitle: const Text('View, share, or erase local crash reports'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DiagnosticsPage(service: diagnostics),
            ),
          ),
        ),
      ),
      const SizedBox(height: 14),
      const Text(
        'Alpha NetScope does not automatically upload analytics or crash reports.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.black54),
      ),
    ],
  );
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy policy')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        Text('Last updated: 17 September 2026'),
        _PolicySection(
          'Data processed',
          'Alpha NetScope reads Wi-Fi network names, BSSIDs, channels, and signal levels from the device to show live signal strength and nearby networks. These readings are kept in memory only while the app is open.',
        ),
        _PolicySection(
          'Permissions',
          'Wi-Fi access supports connected-signal monitoring. Android may require Location permission and Location services for nearby access-point scans. No other permissions are requested.',
        ),
        _PolicySection(
          'Storage and retention',
          'Only the onboarding preference and diagnostic logs are stored locally in the app’s device storage. They remain until you clear diagnostics, clear app data, or uninstall the app.',
        ),
        _PolicySection(
          'Sharing',
          'Nothing is uploaded automatically. Diagnostic reports leave the app only when you use the share action and choose a destination.',
        ),
        _PolicySection(
          'Crash diagnostics',
          'Uncaught error details and stack traces are saved locally to help troubleshooting. You can inspect, share, or delete these reports from Privacy & support. Reports can contain technical file paths but intentionally exclude Wi-Fi contents.',
        ),
        _PolicySection(
          'Your control',
          'You can deny Location permission and still monitor the connected signal, clear diagnostic reports, and delete app data through device settings.',
        ),
      ],
    ),
  );
}

class _PolicySection extends StatelessWidget {
  const _PolicySection(this.title, this.body);
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(body),
      ],
    ),
  );
}

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key, required this.service});
  final DiagnosticsService service;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  String reports = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final value = await widget.service.readReports();
    if (mounted) setState(() => reports = value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Diagnostics')),
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Reports stay on this device and are never uploaded automatically.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black87,
                borderRadius: BorderRadius.circular(10),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  reports.isEmpty ? 'No crash reports saved.' : reports,
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: reports.isEmpty ? null : _clear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: reports.isEmpty ? null : _share,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Future<void> _clear() async {
    await widget.service.clear();
    await _reload();
  }

  Future<void> _share() async {
    final file = await widget.service.reportFile();
    if (file == null) return;
    await SharePlus.instance.share(
      ShareParams(
        title: 'Alpha NetScope diagnostics',
        files: [XFile(file.path)],
      ),
    );
  }
}
