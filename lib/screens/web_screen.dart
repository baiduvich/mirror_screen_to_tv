import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../core/theme.dart';
import 'package:provider/provider.dart';
import '../services/device_discovery_service.dart';

class WebScreen extends StatefulWidget {
  const WebScreen({super.key});
  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = true;
  String _currentUrl = 'https://www.youtube.com';

  static const _shortcuts = [
    ('YouTube', 'https://www.youtube.com', Icons.play_circle_outline),
    ('Netflix', 'https://www.netflix.com', Icons.movie_outlined),
    ('Twitch', 'https://www.twitch.tv', Icons.live_tv),
    ('Vimeo', 'https://vimeo.com', Icons.video_library_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.background)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _isLoading = p < 100);
        },
        onPageStarted: (url) {
          if (mounted) {
            setState(() {
              _currentUrl = url;
              _urlController.text = url;
            });
          }
        },
        onPageFinished: (url) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _currentUrl = url;
              _urlController.text = url;
            });
          }
        },
      ))
      ..loadRequest(Uri.parse(_currentUrl));

    _urlController.text = _currentUrl;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _loadUrl(String input) {
    String url = input.trim();
    if (!url.startsWith('http')) url = 'https://$url';
    _controller.loadRequest(Uri.parse(url));
    FocusScope.of(context).unfocus();
  }

  void _showMirrorGuide() {
    final svc = context.read<DeviceDiscoveryService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
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
            const Text('Cast Web to TV',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 4),
            const Text('Mirror this browser to your TV in seconds',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            const Divider(color: AppTheme.divider),
            const SizedBox(height: 8),
            _mirrorStep(1, Icons.swipe_down, 'Open Control Center',
                'Swipe down from the top-right corner of your iPhone'),
            _mirrorStep(2, Icons.screen_share, 'Tap Screen Mirroring',
                'Tap the icon with two overlapping rectangles'),
            _mirrorStep(3, Icons.tv, 'Select your TV',
                'Your TV will appear in the list — tap it to start'),
            _mirrorStep(4, Icons.open_in_new, 'Everything mirrors',
                'Whatever is on your iPhone screen now shows on the TV'),
            const SizedBox(height: 16),
            if (svc.devices.isNotEmpty) ...[
              Text(
                '${svc.devices.length} TV(s) found on your network:',
                style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 6),
              ...svc.devices.map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.tv,
                            color: AppTheme.primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            d.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppTheme.textPrimary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 8),
            ],
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it'),
            ),
          ],
        ),
        ),
      ),
    );
  }

  Widget _mirrorStep(int n, IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$n',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                Text(sub,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: InputBorder.none,
                    hintText: 'Enter URL...',
                    hintStyle:
                        TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                  textInputAction: TextInputAction.go,
                  keyboardType: TextInputType.url,
                  onSubmitted: _loadUrl,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cast, color: AppTheme.primary),
            tooltip: 'Mirror to TV',
            onPressed: _showMirrorGuide,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_isLoading)
              const LinearProgressIndicator(
                backgroundColor: AppTheme.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),

            // Shortcut row
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.md, vertical: 4),
                children: _shortcuts
                    .map(
                      (s) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => _loadUrl(s.$2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Icon(s.$3,
                                    size: 14, color: AppTheme.primary),
                                const SizedBox(width: 5),
                                Text(s.$1,
                                    style: const TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),

            // Navigation row
            Container(
              height: 36,
              color: AppTheme.surface,
              child: Row(
                children: [
                  _NavBtn(Icons.arrow_back_ios_new, () => _controller.goBack()),
                  _NavBtn(Icons.arrow_forward_ios, () => _controller.goForward()),
                  _NavBtn(Icons.refresh, () => _controller.reload()),
                  const Spacer(),
                  _NavBtn(Icons.home_outlined,
                      () => _loadUrl('https://www.youtube.com')),
                ],
              ),
            ),

            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavBtn(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 18, color: AppTheme.textSecondary),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
    );
  }
}
