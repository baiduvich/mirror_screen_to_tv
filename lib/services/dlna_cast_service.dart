import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/tv_device.dart';

class DlnaCastService {
  HttpServer? _server;
  File? _currentFile;

  Future<bool> castVideoToDevice(File videoFile, TvDevice device) async {
    if (!device.isDlnaCapable) return false;
    try {
      await _stopServer();
      _currentFile = videoFile;

      // Find local IP to serve from
      final localIp = await _getLocalIp();
      if (localIp == null) return false;

      // Start HTTP file server
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8765);
      _server!.listen((req) async {
        try {
          final file = _currentFile;
          if (file == null || !await file.exists()) {
            req.response.statusCode = 404;
            await req.response.close();
            return;
          }
          final stat = await file.stat();
          final fileSize = stat.size;

          // Detect content type from extension
          final ext = file.path.split('.').last.toLowerCase();
          final contentType = ext == 'mov'
              ? ContentType('video', 'quicktime')
              : ext == 'm4v'
                  ? ContentType('video', 'x-m4v')
                  : ContentType('video', 'mp4');

          // Handle Range requests (required by most Smart TVs)
          final rangeHeader = req.headers.value('range');
          if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
            final parts = rangeHeader.substring(6).split('-');
            final start = int.tryParse(parts[0]) ?? 0;
            final end = (parts.length > 1 && parts[1].isNotEmpty)
                ? (int.tryParse(parts[1]) ?? (fileSize - 1))
                : (fileSize - 1);
            final length = end - start + 1;

            req.response.statusCode = 206;
            req.response.headers
              ..contentType = contentType
              ..contentLength = length
              ..set('Content-Range', 'bytes $start-$end/$fileSize')
              ..set('Accept-Ranges', 'bytes')
              ..set('Access-Control-Allow-Origin', '*');
            await req.response.addStream(file.openRead(start, end + 1));
          } else {
            req.response.statusCode = 200;
            req.response.headers
              ..contentType = contentType
              ..contentLength = fileSize
              ..set('Accept-Ranges', 'bytes')
              ..set('Access-Control-Allow-Origin', '*');
            await req.response.addStream(file.openRead());
          }
          await req.response.close();
        } catch (_) {
          try {
            await req.response.close();
          } catch (_) {}
        }
      });

      final videoUrl = 'http://$localIp:8765/video.mp4';

      // SetAVTransportURI
      final setUri = _soapEnvelope(
        'SetAVTransportURI',
        '<InstanceID>0</InstanceID>'
        '<CurrentURI>$videoUrl</CurrentURI>'
        '<CurrentURIMetaData></CurrentURIMetaData>',
      );
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
      if (setResp.statusCode >= 400) return false;

      await Future.delayed(const Duration(milliseconds: 500));

      // Play
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

      return playResp.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop(TvDevice device) async {
    try {
      if (device.isDlnaCapable) {
        final stopBody = _soapEnvelope(
          'Stop',
          '<InstanceID>0</InstanceID>',
        );
        await http.post(
          Uri.parse(device.avTransportUrl),
          headers: {
            'Content-Type': 'text/xml; charset="utf-8"',
            'SOAPAction':
                '"urn:schemas-upnp-org:service:AVTransport:1#Stop"',
          },
          body: stopBody,
        );
      }
    } catch (_) {}
    await _stopServer();
  }

  Future<void> _stopServer() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.contains('en') || name.contains('wlan') || name.contains('wifi')) {
          return iface.addresses.first.address;
        }
      }
      if (interfaces.isNotEmpty) return interfaces.first.addresses.first.address;
    } catch (_) {}
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
