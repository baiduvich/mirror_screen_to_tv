import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../core/theme.dart';
import '../models/tv_device.dart';
import '../services/device_discovery_service.dart';
import '../services/dlna_cast_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final AssetEntity entity;

  const VideoPlayerScreen({super.key, required this.entity});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isLoading = true;
  String? _error;

  final _dlnaService = DlnaCastService();
  TvDevice? _castingTo;
  bool _isCasting = false;

  @override
  void initState() {
    super.initState();
    print('[VIDEO] VideoPlayerScreen initState');
    print('[VIDEO] Entity: id=${widget.entity.id} title=${widget.entity.title} type=${widget.entity.type}');
    print('[VIDEO] Duration: ${widget.entity.videoDuration}');
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    print('[VIDEO] _initPlayer() start');
    try {
      print('[VIDEO] Getting file from AssetEntity...');
      final File? file = await widget.entity.file;
      if (file == null) {
        print('[VIDEO] ❌ entity.file returned null — cannot load video');
        if (!mounted) return;
        setState(() {
          _error = 'Could not load video file';
          _isLoading = false;
        });
        return;
      }
      print('[VIDEO] File path: ${file.path}');
      print('[VIDEO] File exists: ${await file.exists()}');
      final stat = await file.stat();
      print('[VIDEO] File size: ${stat.size} bytes  modified: ${stat.modified}');

      print('[VIDEO] Creating VideoPlayerController.file()...');
      _controller = VideoPlayerController.file(file);
      print('[VIDEO] Initializing VideoPlayerController...');
      await _controller!.initialize();

      final value = _controller!.value;
      print('[VIDEO] ✅ VideoPlayerController initialized');
      print('[VIDEO] Duration: ${value.duration}');
      print('[VIDEO] Size: ${value.size.width}x${value.size.height}');
      print('[VIDEO] AspectRatio: ${value.aspectRatio}');
      print('[VIDEO] isInitialized: ${value.isInitialized}');

      _controller!.addListener(() {
        if (mounted) setState(() {});
      });
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });
      print('[VIDEO] Starting playback...');
      _controller!.play();
      print('[VIDEO] play() called');
    } catch (e, stack) {
      print('[VIDEO] ❌ Exception in _initPlayer: $e');
      print('[VIDEO] Stack: $stack');
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load video';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    print('[VIDEO] dispose() called');
    if (_castingTo != null) {
      print('[VIDEO] Stopping DLNA cast for: ${_castingTo!.name}');
      _dlnaService.stop(_castingTo!);
    }
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _castToDevice(TvDevice device) async {
    print('[VIDEO] _castToDevice() called for: ${device.name}');
    print('[VIDEO] Device type: ${device.serviceType}  isDLNA: ${device.isDlnaCapable}');
    final file = await widget.entity.file;
    if (file == null) {
      print('[VIDEO] ❌ Could not get file for casting');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not read video file')));
      return;
    }
    print('[VIDEO] File for cast: ${file.path}');
    setState(() => _isCasting = true);
    print('[VIDEO] Calling DlnaCastService.castVideoToDevice...');
    final success = await _dlnaService.castVideoToDevice(file, device);
    print('[VIDEO] castVideoToDevice returned: $success');
    if (!mounted) return;
    if (success) {
      setState(() {
        _castingTo = device;
        _isCasting = false;
      });
      print('[VIDEO] ✅ Now casting to: ${device.name}');
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Casting to ${device.name}')));
    } else {
      setState(() => _isCasting = false);
      print('[VIDEO] ❌ Cast failed for: ${device.name}');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Could not connect to TV. Make sure it is on the same Wi-Fi.')));
    }
  }

  void _showCastMenu(List<TvDevice> devices) {
    print('[VIDEO] _showCastMenu() — ${devices.length} DLNA device(s)');
    for (final d in devices) {
      print('[VIDEO]   Device: ${d.name} (${d.manufacturer}) avTransport=${d.avTransportUrl}');
    }
    if (devices.length == 1) {
      print('[VIDEO] Only one device, connecting directly to: ${devices.first.name}');
      _castToDevice(devices.first);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Cast to TV',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: devices
                    .map((d) => ListTile(
                          leading: const Icon(Icons.tv,
                              color: AppTheme.primary),
                          title: Text(d.name,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(d.manufacturer,
                              overflow: TextOverflow.ellipsis),
                          onTap: () {
                            print('[VIDEO] User selected device from menu: ${d.name}');
                            Navigator.pop(context);
                            _castToDevice(d);
                          },
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatPosition() {
    if (_controller == null || !_isInitialized) return '0:00 / 0:00';
    final position = _controller!.value.position;
    final duration = _controller!.value.duration;
    return '${_formatDuration(position)} / ${_formatDuration(duration)}';
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.entity.title ?? 'Video',
          style: const TextStyle(color: Colors.white, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Consumer<DeviceDiscoveryService>(
            builder: (_, svc, __) {
              final dlnaDevices = svc.dlnaDevices;
              print('[VIDEO] AppBar rebuild — dlnaDevices: ${dlnaDevices.length}');
              if (dlnaDevices.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: Icon(
                  _castingTo != null ? Icons.cast_connected : Icons.cast,
                  color: _castingTo != null
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                ),
                onPressed:
                    _isCasting ? null : () => _showCastMenu(dlnaDevices),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              color: AppTheme.primary.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: const Row(
                children: [
                  Icon(Icons.cast, color: AppTheme.primary, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tap AirPlay button in player controls to cast to your TV',
                      style: TextStyle(color: AppTheme.primary, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _buildPlayerContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (_error != null) {
      print('[VIDEO] Showing error state: $_error');
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
    }

    if (_isInitialized && _controller != null) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),
          ),
          Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _controller!.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                  onPressed: () {
                    if (_controller!.value.isPlaying) {
                      print('[VIDEO] User paused');
                      _controller!.pause();
                    } else {
                      print('[VIDEO] User resumed');
                      _controller!.play();
                    }
                  },
                ),
                Expanded(
                  child: VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: AppTheme.primary,
                      bufferedColor: AppTheme.primary.withValues(alpha: 0.3),
                      backgroundColor: AppTheme.surfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatPosition(),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ],
      );
    }

    return const Center(
      child: CircularProgressIndicator(color: AppTheme.primary),
    );
  }
}
