import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:http/http.dart' as http;
import '../models/tv_device.dart';

class DeviceDiscoveryService extends ChangeNotifier {
  List<TvDevice> _devices = [];
  bool _isScanning = false;
  String? _error;

  List<TvDevice> get devices => List.unmodifiable(_devices);
  bool get isScanning => _isScanning;
  String? get error => _error;

  List<TvDevice> get dlnaDevices =>
      _devices.where((d) => d.isDlnaCapable).toList();

  Future<void> startScan() async {
    _isScanning = true;
    _devices = [];
    _error = null;
    notifyListeners();

    final found = <TvDevice>[];
    final seenNames = <String>{};

    await Future.wait([
      _scanMdns(found, seenNames),
      _scanSsdp(found, seenNames),
    ]);

    _devices = found;
    _isScanning = false;
    notifyListeners();
  }

  // ── mDNS (finds Apple TV, Chromecast) ──────────────────────────────────────
  Future<void> _scanMdns(List<TvDevice> found, Set<String> seen) async {
    final serviceTypes = [
      ('_airplay._tcp', 'AirPlay'),
      ('_googlecast._tcp', 'Chromecast'),
    ];
    try {
      final client = MDnsClient();
      await client.start();
      for (final (service, type) in serviceTypes) {
        try {
          await for (final PtrResourceRecord ptr in client
              .lookup<PtrResourceRecord>(
                ResourceRecordQuery.serverPointer('$service.local'),
              )
              .timeout(const Duration(seconds: 4),
                  onTimeout: (s) => s.close())) {
            String host = '';
            int port = 0;
            await for (final SrvResourceRecord srv in client
                .lookup<SrvResourceRecord>(
                  ResourceRecordQuery.service(ptr.domainName),
                )
                .timeout(const Duration(seconds: 2),
                    onTimeout: (s) => s.close())) {
              host = srv.target;
              port = srv.port;
              break;
            }
            final name = ptr.domainName
                .replaceAll('.$service.local', '')
                .replaceAll('._airplay._tcp.local', '')
                .replaceAll('._googlecast._tcp.local', '')
                .trim();
            if (name.isNotEmpty && !seen.contains(name)) {
              seen.add(name);
              found.add(TvDevice(
                name: name,
                serviceType: type,
                host: host,
                port: port,
                manufacturer: type == 'AirPlay' ? 'Apple' : 'Google',
              ));
            }
          }
        } catch (_) {}
      }
      client.stop();
    } catch (_) {}
  }

  // ── SSDP (finds Samsung, LG, Sony, and other UPnP/DLNA TVs) ───────────────
  Future<void> _scanSsdp(List<TvDevice> found, Set<String> seen) async {
    const multicastAddr = '239.255.255.250';
    const ssdpPort = 1900;
    const searchMsg =
        'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 3\r\n'
        'ST: ssdp:all\r\n'
        '\r\n';

    final locationsSeen = <String>{};
    final locationQueue = <Map<String, String>>[];

    try {
      final socket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.multicastHops = 4;

      final msgBytes = Uint8List.fromList(searchMsg.codeUnits);
      socket.send(msgBytes, InternetAddress(multicastAddr), ssdpPort);

      final timer = Timer(const Duration(seconds: 4), socket.close);

      await for (final event in socket) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg != null) {
            final resp = String.fromCharCodes(dg.data);
            final loc = _header(resp, 'LOCATION');
            final srv = _header(resp, 'SERVER') ?? '';
            if (loc != null && !locationsSeen.contains(loc)) {
              locationsSeen.add(loc);
              locationQueue
                  .add({'location': loc, 'server': srv, 'ip': dg.address.address});
            }
          }
        }
      }
      timer.cancel();
    } catch (_) {}

    // Fetch UPnP device descriptions in parallel (max 6)
    final batch = locationQueue.take(6).toList();
    await Future.wait(batch.map((item) => _fetchDeviceDescription(
          item['location']!,
          item['server']!,
          item['ip']!,
          found,
          seen,
        )));
  }

  Future<void> _fetchDeviceDescription(
    String locationUrl,
    String serverHeader,
    String ip,
    List<TvDevice> found,
    Set<String> seen,
  ) async {
    try {
      final resp = await http
          .get(Uri.parse(locationUrl))
          .timeout(const Duration(seconds: 3));
      if (resp.statusCode != 200) return;

      final xml = resp.body;
      final name = _xmlTag(xml, 'friendlyName') ?? ip;
      final manufacturer = _xmlTag(xml, 'manufacturer') ?? '';

      // Find AVTransport control URL for DLNA casting
      String avTransportUrl = '';
      final serviceBlocks = _allBetween(xml, '<service>', '</service>');
      for (final block in serviceBlocks) {
        if (block.contains('AVTransport')) {
          final ctrlPath = _xmlTag(block, 'controlURL') ?? '';
          if (ctrlPath.isNotEmpty) {
            // Build absolute URL from location base
            final base = Uri.parse(locationUrl);
            final ctrl = ctrlPath.startsWith('/')
                ? '${base.scheme}://${base.host}:${base.port}$ctrlPath'
                : '${base.scheme}://${base.host}:${base.port}/$ctrlPath';
            avTransportUrl = ctrl;
          }
          break;
        }
      }

      if (!seen.contains(name)) {
        seen.add(name);
        found.add(TvDevice(
          name: name,
          serviceType: avTransportUrl.isNotEmpty ? 'DLNA' : 'UPnP',
          host: ip,
          port: 0,
          manufacturer: manufacturer,
          avTransportUrl: avTransportUrl,
          locationUrl: locationUrl,
        ));
      }
    } catch (_) {}
  }

  String? _header(String response, String key) {
    for (final line in response.split('\r\n')) {
      if (line.toLowerCase().startsWith('${key.toLowerCase()}:')) {
        return line.substring(line.indexOf(':') + 1).trim();
      }
    }
    return null;
  }

  String? _xmlTag(String xml, String tag) {
    final start = xml.indexOf('<$tag>');
    final end = xml.indexOf('</$tag>');
    if (start == -1 || end == -1) return null;
    return xml.substring(start + tag.length + 2, end).trim();
  }

  List<String> _allBetween(String xml, String open, String close) {
    final result = <String>[];
    int idx = 0;
    while (true) {
      final s = xml.indexOf(open, idx);
      if (s == -1) break;
      final e = xml.indexOf(close, s);
      if (e == -1) break;
      result.add(xml.substring(s + open.length, e));
      idx = e + close.length;
    }
    return result;
  }
}
