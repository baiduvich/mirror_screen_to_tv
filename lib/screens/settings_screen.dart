import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _slideshowInterval = 5;
  bool _autoScan = true;
  String _videoQuality = 'High';
  String _appVersion = '';
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _slideshowInterval = prefs.getInt('slideshow_interval') ?? 5;
      _autoScan = prefs.getBool('auto_scan') ?? true;
      _videoQuality = prefs.getString('video_quality') ?? 'High';
      _appVersion = '${info.version} (${info.buildNumber})';
    });
  }

  Future<void> _rateApp() async {
    final InAppReview inAppReview = InAppReview.instance;
    if (await inAppReview.isAvailable()) {
      await inAppReview.requestReview();
    } else {
      await inAppReview.openStoreListing();
    }
  }

  Future<void> _contactUs() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'baid.marouane1@gmail.com',
      query: 'subject=Mirror to TV - Support',
    );
    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final Uri uri = Uri.parse(
      'https://sites.google.com/view/odtconverterreader/home',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Preferences',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SwitchListTile(
              title: const Text('Auto-scan on open'),
              subtitle: const Text('Scan for TVs when app launches'),
              value: _autoScan,
              onChanged: (v) {
                setState(() => _autoScan = v);
                _prefs?.setBool('auto_scan', v);
              },
            ),
            ListTile(
              title: const Text('Slideshow Interval'),
              subtitle: Text('${_slideshowInterval}s per photo'),
              trailing: DropdownButton<int>(
                value: _slideshowInterval,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary),
                underline: const SizedBox.shrink(),
                items: [3, 5, 10]
                    .map(
                      (v) => DropdownMenuItem<int>(
                        value: v,
                        child: Text('${v}s'),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _slideshowInterval = v);
                  _prefs?.setInt('slideshow_interval', v);
                },
              ),
            ),
            ListTile(
              title: const Text('Video Quality'),
              subtitle: const Text('Preferred playback quality'),
              trailing: DropdownButton<String>(
                value: _videoQuality,
                dropdownColor: AppTheme.surface,
                style: const TextStyle(color: AppTheme.textPrimary),
                underline: const SizedBox.shrink(),
                items: ['Medium', 'High']
                    .map(
                      (v) => DropdownMenuItem<String>(
                        value: v,
                        child: Text(v),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _videoQuality = v);
                  _prefs?.setString('video_quality', v);
                },
              ),
            ),
            const Divider(color: AppTheme.divider, indent: 16, endIndent: 16),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('Rate App'),
              onTap: _rateApp,
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Contact Us'),
              onTap: _contactUs,
            ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Privacy Policy'),
              onTap: _openPrivacyPolicy,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 32),
              child: Center(
                child: Text(
                  'Version $_appVersion',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
