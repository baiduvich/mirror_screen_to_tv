import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/tv_device.dart';

class DlnaCastService {
  HttpServer? _server;
  File? _currentFile;

  Future<bool> castVideoToDevice(File videoFile, TvDevice device) async {
    print('[DLNA] ════════════════════════════════════════════');
    print('[DLNA] castVideoToDevice() called');
    print('[DLNA] Device: ${device.name}');
    print('[DLNA] Device type: ${device.serviceType}');
    print('[DLNA] Manufacturer: ${device.manufacturer}');
    print('[DLNA] Host: ${device.host}');
    print('[DLNA] AVTransport URL: ${device.avTransportUrl}');
    print('[DLNA] isDlnaCapable: ${device.isDlnaCapable}');
    print('[DLNA] Video file: ${videoFile.path}');

    if (!device.isDlnaCapable) {
      print('[DLNA] ❌ Device is not DLNA capable — avTransportUrl is empty');
      return false;
    }

    try {
      print('[DLNA] Stopping any existing HTTP server...');
      await _stopServer();
      _currentFile = videoFile;

      final fileExists = await videoFile.exists();
      final fileStat = await videoFile.stat();
      print('[DLNA] File exists: $fileExists  size: ${fileStat.size} bytes');

      if (!fileExists) {
        print('[DLNA] ❌ Video file does not exist on disk');
        return false;
      }

      // Find local IP to serve from
      print('[DLNA] Getting local IP address...');
      final localIp = await _getLocalIp();
      print('[DLNA] Local IP: $localIp');
      if (localIp == null) {
        print('[DLNA] ❌ Could not determine local IP address');
        return false;
      }

      // Start HTTP file server
      print('[DLNA] Binding HTTP server on 0.0.0.0:8765...');
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8765);
      print('[DLNA] ✅ HTTP server started on $localIp:8765');

      _server!.listen((req) async {
        print('[HTTP] ─────────────────────────────────────────');
        print('[HTTP] Incoming request: ${req.method} ${req.uri.path}');
        print('[HTTP] From: ${req.connectionInfo?.remoteAddress.address}:${req.connectionInfo?.remotePort}');
        final rangeHeader = req.headers.value('range');
        print('[HTTP] Range header: ${rangeHeader ?? "(none)"}');

        try {
          final file = _currentFile;
          if (file == null || !await file.exists()) {
            print('[HTTP] ❌ File is null or does not exist — returning 404');
            req.response.statusCode = 404;
            await req.response.close();
            return;
          }
          final stat = await file.stat();
          final fileSize = stat.size;
          print('[HTTP] Serving file: ${file.path} ($fileSize bytes)');

          // Detect content type from extension
          final ext = file.path.split('.').last.toLowerCase();
          final contentType = ext == 'mov'
              ? ContentType('video', 'quicktime')
              : ext == 'm4v'
                  ? ContentType('video', 'x-m4v')
                  : ContentType('video', 'mp4');
          print('[HTTP] File extension: .$ext → ContentType: ${contentType.mimeType}');

          // Handle Range requests (required by most Smart TVs)
          if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
            final parts = rangeHeader.substring(6).split('-');
            final start = int.tryParse(parts[0]) ?? 0;
            final end = (parts.length > 1 && parts[1].isNotEmpty)
                ? (int.tryParse(parts[1]) ?? (fileSize - 1))
                : (fileSize - 1);
            final length = end - start + 1;

            print('[HTTP] Range request: bytes=$start-$end  length=$length  fileSize=$fileSize');
            req.response.statusCode = 206;
            req.response.headers
              ..contentType = contentType
              ..contentLength = length
              ..set('Content-Range', 'bytes $start-$end/$fileSize')
              ..set('Accept-Ranges', 'bytes')
              ..set('Access-Control-Allow-Origin', '*');
            await req.response.addStream(file.openRead(start, end + 1));
            print('[HTTP] ✅ 206 Partial Content sent ($length bytes)');
          } else {
            print('[HTTP] Full file request (no range)');
            req.response.statusCode = 200;
            req.response.headers
              ..contentType = contentType
              ..contentLength = fileSize
              ..set('Accept-Ranges', 'bytes')
              ..set('Access-Control-Allow-Origin', '*');
            await req.response.addStream(file.openRead());
            print('[HTTP] ✅ 200 OK sent ($fileSize bytes)');
          }
          await req.response.close();
          print('[HTTP] Response closed cleanly');
        } catch (e) {
          print('[HTTP] ❌ Error serving request: $e');
          try {
            await req.response.close();
          } catch (e2) {
            print('[HTTP] ❌ Error closing response: $e2');
          }
        }
      });

      final videoUrl = 'http://$localIp:8765/video.mp4';
      print('[DLNA] Video will be served at: $videoUrl');

      // SetAVTransportURI
      print('[DLNA] Sending SOAP SetAVTransportURI...');
      final setUri = _soapEnvelope(
        'SetAVTransportURI',
        '<InstanceID>0</InstanceID>'
        '<CurrentURI>$videoUrl</CurrentURI>'
        '<CurrentURIMetaData></CurrentURIMetaData>',
      );
      print('[DLNA] Target URL: ${device.avTransportUrl}');
      final setResp = await http
          .post(
            Uri.parse(device.avTransportUrl),
            headers: {
              'Content-Type': 'text/xml; charset="utf-8"',
              'SOAPAction':
                  '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
            },
            body: setUri,
          )
          .timeout(const Duration(seconds: 5));
      print('[DLNA] SetAVTransportURI response: HTTP ${setResp.statusCode}');
      print('[DLNA] SetAVTransportURI body: ${setResp.body.length > 200 ? setResp.body.substring(0, 200) : setResp.body}');
      if (setResp.statusCode >= 400) {
        print('[DLNA] ❌ SetAVTransportURI failed with ${setResp.statusCode}');
        return false;
      }

      print('[DLNA] Waiting 500ms before Play...');
      await Future.delayed(const Duration(milliseconds: 500));

      // Play
      print('[DLNA] Sending SOAP Play...');
      final playBody = _soapEnvelope(
        'Play',
        '<InstanceID>0</InstanceID><Speed>1</Speed>',
      );
      final playResp = await http
          .post(
            Uri.parse(device.avTransportUrl),
            headers: {
              'Content-Type': 'text/xml; charset="utf-8"',
              'SOAPAction':
                  '"urn:schemas-upnp-org:service:AVTransport:1#Play"',
            },
            body: playBody,
          )
          .timeout(const Duration(seconds: 5));
      print('[DLNA] Play response: HTTP ${playResp.statusCode}');
      print('[DLNA] Play body: ${playResp.body.length > 200 ? playResp.body.substring(0, 200) : playResp.body}');

      final success = playResp.statusCode < 400;
      print('[DLNA] Cast result: ${success ? "✅ SUCCESS" : "❌ FAILED"}');
      print('[DLNA] ════════════════════════════════════════════');
      return success;
    } catch (e, stack) {
      print('[DLNA] ❌ Exception in castVideoToDevice: $e');
      print('[DLNA] Stack: $stack');
      return false;
    }
  }

  Future<void> stop(TvDevice device) async {
    print('[DLNA] stop() called for device: ${device.name}');
    try {
      if (device.isDlnaCapable) {
        print('[DLNA] Sending SOAP Stop to ${device.avTransportUrl}...');
        final stopBody = _soapEnvelope(
          'Stop',
          '<InstanceID>0</InstanceID>',
        );
        final resp = await http.post(
          Uri.parse(device.avTransportUrl),
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPAction':
                '"urn:schemas-upnp-org:service:AVTransport:1#Stop"',
          },
          body: stopBody,
        );
        print('[DLNA] Stop response: HTTP ${resp.statusCode}');
      }
    } catch (e) {
      print('[DLNA] ❌ Error sending Stop: $e');
    }
    await _stopServer();
  }

  Future<void> _stopServer() async {
    if (_server != null) {
      print('[DLNA] Closing HTTP server...');
      await _server?.close(force: true);
      _server = null;
      print('[DLNA] HTTP server closed');
    } else {
      print('[DLNA] No HTTP server running');
    }
  }

  Future<String?> _getLocalIp() async {
    print('[DLNA] Scanning network interfaces...');
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      print('[DLNA] Found ${interfaces.length} network interface(s):');
      for (final iface in interfaces) {
        final addrs = iface.addresses.map((a) => a.address).join(', ');
        print('[DLNA]   ${iface.name}: $addrs');
      }

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('en') || name.contains('wlan') || name.contains('wifi')) {
          final ip = iface.addresses.first.address;
          print('[DLNA] Using interface "${iface.name}" → IP: $ip');
          return ip;
        }
      }
      if (interfaces.isNotEmpty) {
        final ip = interfaces.first.addresses.first.address;
        print('[DLNA] No preferred interface found, using first: ${interfaces.first.name} → $ip');
        return ip;
      }
    } catch (e) {
      print('[DLNA] ❌ Error listing network interfaces: $e');
    }
    print('[DLNA] ❌ No network interfaces found');
    return null;
  }

  String _soapEnvelope(String action, String bodyContent) {
    return '<?xml version="1.0" encoding="utf-8"?>'
        '<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" '
        'xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
        '<s:Body>'
        '<u:$action xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">'
        '$bodyContent'
        '</u:$action>'
        '</s:Body>'
        '</s:Envelope>';
  }
}
