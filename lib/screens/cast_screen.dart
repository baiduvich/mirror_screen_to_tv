import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../models/tv_device.dart';
import '../services/device_discovery_service.dart';

class CastScreen extends StatefulWidget {
  const CastScreen({super.key});
  @override
  State<CastScreen> createState() => _CastScreenState();
}

class _CastScreenState extends State<CastScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  bool _autoScanDone = false;

  static const _brands = [
    _Brand('Apple TV', Icons.tv, 'Apple'),
    _Brand('Samsung', Icons.smart_screen, 'Samsung'),
    _Brand('LG', Icons.live_tv, 'LG'),
    _Brand('Sony', Icons.tv_outlined, 'Sony'),
    _Brand('Chromecast', Icons.cast, 'Chromecast'),
    _Brand('Fire TV', Icons.local_fire_department, 'FireTV'),
    _Brand('Roku', Icons.stream, 'Roku'),
    _Brand('Other TV', Icons.devices_other, 'Other'),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim =
        Tween<double>(begin: 0.35, end: 1.0).animate(_pulseController);
    _checkAutoScan();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkAutoScan() async {
    if (_autoScanDone) return;
    _autoScanDone = true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('auto_scan') ?? true) {
      if (mounted) {
        context.read<DeviceDiscoveryService>().startScan();
      }
    }
  }

  void _showBrandGuide(String brand) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BrandGuideSheet(brand: brand),
    );
  }

  void _showDeviceGuide(TvDevice device) {
    _showBrandGuide(device.displayBrand);
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<DeviceDiscoveryService>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mirror to TV'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed:
                svc.isScanning ? null : () => svc.startScan(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Brand picker section ───────────────────────────────────
              const Text(
                'Select Your TV',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Get step-by-step instructions for your TV',
                style:
                    TextStyle(color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.85,
                ),
                itemCount: _brands.length,
                itemBuilder: (_, i) => _BrandCard(
                  brand: _brands[i],
                  onTap: () => _showBrandGuide(_brands[i].id),
                ),
              ),

              const SizedBox(height: 28),

              // ── Scan section ──────────────────────────────────────────
              Row(
                children: [
                  const Text(
                    'Nearby Devices',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (svc.isScanning)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.primary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                svc.isScanning
                    ? 'Scanning your Wi-Fi network...'
                    : svc.devices.isEmpty
                        ? 'No devices found — select your TV above for manual setup'
                        : '${svc.devices.length} device(s) found on your network',
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),

              if (svc.isScanning) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: FadeTransition(
                      opacity: _pulseAnim,
                      child: const Icon(Icons.cast,
                          size: 56, color: AppTheme.primary),
                    ),
                  ),
                ),
              ] else if (svc.devices.isNotEmpty) ...[
                ...svc.devices
                    .map((d) => _DeviceCard(
                          device: d,
                          onConnect: () => _showDeviceGuide(d),
                        )),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: AppTheme.primary.withValues(alpha: 0.8),
                          size: 20),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Tap your TV brand above to get personalized setup instructions.',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Brand card widget ──────────────────────────────────────────────────────────

class _Brand {
  final String label;
  final IconData icon;
  final String id;
  const _Brand(this.label, this.icon, this.id);
}

class _BrandCard extends StatelessWidget {
  final _Brand brand;
  final VoidCallback onTap;
  const _BrandCard({required this.brand, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.divider, width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(brand.icon, color: AppTheme.primary, size: 26),
            const SizedBox(height: 6),
            Text(
              brand.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Device card widget ─────────────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final TvDevice device;
  final VoidCallback onConnect;
  const _DeviceCard({required this.device, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              ),
              child: Icon(
                device.serviceType == 'AirPlay'
                    ? Icons.tv
                    : device.serviceType == 'Chromecast'
                        ? Icons.cast
                        : Icons.smart_screen,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    [
                      device.displayBrand,
                      if (device.isDlnaCapable) '· DLNA',
                    ].join(' '),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: onConnect,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: Size.zero,
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: const Text('Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Brand guide bottom sheet ───────────────────────────────────────────────────

class _BrandGuideSheet extends StatelessWidget {
  final String brand;
  const _BrandGuideSheet({required this.brand});

  static Map<String, _GuideData> get _guides => {
        'Apple': const _GuideData(
          title: 'Mirror to Apple TV',
          subtitle: 'Uses AirPlay — built into your iPhone',
          steps: [
            _Step(Icons.swipe_down, 'Open Control Center',
                'Swipe down from the top-right corner of your iPhone screen'),
            _Step(Icons.screen_share, 'Tap Screen Mirroring',
                'Look for the icon with two overlapping rectangles'),
            _Step(Icons.tv, 'Select your Apple TV',
                'Your Apple TV will appear in the list — tap it'),
            _Step(Icons.check_circle_outline, 'Done!',
                'Your screen is now mirroring to your Apple TV'),
          ],
        ),
        'Apple TV': const _GuideData(
          title: 'Mirror to Apple TV',
          subtitle: 'Uses AirPlay — built into your iPhone',
          steps: [
            _Step(Icons.swipe_down, 'Open Control Center',
                'Swipe down from the top-right corner of your iPhone screen'),
            _Step(Icons.screen_share, 'Tap Screen Mirroring',
                'Look for the icon with two overlapping rectangles'),
            _Step(Icons.tv, 'Select your Apple TV',
                'Your Apple TV will appear in the list — tap it'),
            _Step(Icons.check_circle_outline, 'Done!',
                'Your screen is now mirroring to your Apple TV'),
          ],
        ),
        'Samsung': const _GuideData(
          title: 'Mirror to Samsung TV',
          subtitle: 'Uses Smart View / Screen Mirroring',
          steps: [
            _Step(Icons.swipe_down, 'Open Control Center',
                'Swipe down from the top-right corner of your iPhone'),
            _Step(Icons.screen_share, 'Tap Screen Mirroring',
                'Tap the Screen Mirroring button in Control Center'),
            _Step(Icons.smart_screen, 'Select your Samsung TV',
                'Your Samsung TV appears in the list — tap to connect'),
            _Step(Icons.check_circle_outline, 'Accept on TV',
                'A prompt may appear on your Samsung TV — select Allow'),
          ],
        ),
        'LG': const _GuideData(
          title: 'Mirror to LG TV',
          subtitle: 'Uses Screen Share / AirPlay 2 (newer models)',
          steps: [
            _Step(Icons.settings, 'Enable Screen Share on LG TV',
                'On your LG TV: Settings → All Settings → Connection → Screen Share → Screen Share ON'),
            _Step(Icons.swipe_down, 'Open Control Center on iPhone',
                'Swipe down from the top-right corner'),
            _Step(Icons.screen_share, 'Tap Screen Mirroring',
                'Tap the Screen Mirroring icon'),
            _Step(Icons.tv, 'Select your LG TV',
                'Your LG TV appears — tap it to start mirroring'),
          ],
        ),
        'Sony': const _GuideData(
          title: 'Mirror to Sony TV',
          subtitle: 'Uses Screen Mirroring or AirPlay',
          steps: [
            _Step(Icons.settings, 'Enable Screen Mirroring on Sony TV',
                'Press the Home button on your Sony remote → Settings → Device Preferences → Screen Mirroring'),
            _Step(Icons.swipe_down, 'Open Control Center on iPhone',
                'Swipe down from the top-right corner'),
            _Step(Icons.screen_share, 'Tap Screen Mirroring',
                'Tap the Screen Mirroring button'),
            _Step(Icons.check_circle_outline, 'Select Sony TV',
                'Choose your Sony TV from the list and confirm on the TV if prompted'),
          ],
        ),
        'Chromecast': const _GuideData(
          title: 'Mirror to Chromecast',
          subtitle: 'Uses Google Home or Safari casting',
          steps: [
            _Step(Icons.download, 'Install Google Home',
                "Download the Google Home app from the App Store if you don't have it"),
            _Step(Icons.open_in_new, 'Open Google Home',
                'Open the Google Home app and sign in with your Google account'),
            _Step(Icons.cast, 'Tap your Chromecast device',
                'Find your Chromecast in the app and tap it'),
            _Step(Icons.phone_iphone, 'Cast my screen',
                'Tap "Cast my screen" to mirror your iPhone to Chromecast'),
          ],
        ),
        'FireTV': const _GuideData(
          title: 'Mirror to Fire TV',
          subtitle: 'Uses Display Mirroring',
          steps: [
            _Step(Icons.settings, 'Enable Display Mirroring on Fire TV',
                'On Fire TV: Settings → Display & Sounds → Enable Display Mirroring'),
            _Step(Icons.swipe_down, 'Open Control Center on iPhone',
                'Swipe down from the top-right corner of your screen'),
            _Step(Icons.screen_share, 'Tap Screen Mirroring',
                'Tap the Screen Mirroring button in Control Center'),
            _Step(Icons.tv, 'Select Fire TV',
                'Your Fire TV stick will appear in the list — tap it'),
          ],
        ),
        'Roku': const _GuideData(
          title: 'Mirror to Roku',
          subtitle: 'Uses Screen Mirroring (Roku 4 or newer)',
          steps: [
            _Step(Icons.settings, 'Enable Mirroring on Roku',
                'On Roku: Settings → System → Screen Mirroring → Screen Mirroring Mode → Always Allow'),
            _Step(Icons.swipe_down, 'Open Control Center on iPhone',
                'Swipe down from the top-right corner'),
            _Step(Icons.screen_share, 'Tap Screen Mirroring',
                'Select Screen Mirroring from Control Center'),
            _Step(Icons.tv, 'Select your Roku device',
                'Your Roku will appear in the list — tap to start mirroring'),
          ],
        ),
        'Other': const _GuideData(
          title: 'Mirror to Your TV',
          subtitle: 'Using AirPlay (built into iPhone)',
          steps: [
            _Step(Icons.wifi, 'Same Wi-Fi network',
                'Make sure your iPhone and TV are on the same Wi-Fi network'),
            _Step(Icons.swipe_down, 'Open Control Center',
                'Swipe down from the top-right corner of your iPhone'),
            _Step(Icons.screen_share, 'Tap Screen Mirroring',
                'Tap the Screen Mirroring button (two overlapping rectangles)'),
            _Step(Icons.tv, 'Select your TV',
                'Your TV will appear if it supports AirPlay or Miracast — tap it to start'),
          ],
        ),
      };

  @override
  Widget build(BuildContext context) {
    final guide = _guides[brand] ?? _guides['Other']!;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          bottom: bottomInset + 24,
          left: 20,
          right: 20,
          top: 12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(guide.title,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            Text(guide.subtitle,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.divider),
            const SizedBox(height: 8),
            ...guide.steps.asMap().entries.map((e) => _StepRow(
                  step: e.value,
                  number: e.key + 1,
                )),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideData {
  final String title, subtitle;
  final List<_Step> steps;
  const _GuideData(
      {required this.title, required this.subtitle, required this.steps});
}

class _Step {
  final IconData icon;
  final String title, subtitle;
  const _Step(this.icon, this.title, this.subtitle);
}

class _StepRow extends StatelessWidget {
  final _Step step;
  final int number;
  const _StepRow({required this.step, required this.number});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Icon(step.icon, color: AppTheme.primary, size: 22),
              ),
              Container(
                width: 17,
                height: 17,
                decoration: const BoxDecoration(
                    color: AppTheme.primary, shape: BoxShape.circle),
                child: Center(
                  child: Text('$number',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(step.subtitle,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
