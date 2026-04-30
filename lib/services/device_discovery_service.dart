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
    print('[SCAN] ════════════════════════════════════════════');
    print('[SCAN] startScan() called');
    print('[SCAN] Platform: ${Platform.operatingSystem}');
    _isScanning = true;
    _devices = [];
    _error = null;
    notifyListeners();

    final found = <TvDevice>[];
    final seenNames = <String>{};

    print('[SCAN] Starting mDNS + SSDP in parallel...');
    final stopwatch = Stopwatch()..start();

    await Future.wait([
      _scanMdns(found, seenNames),
      _scanSsdp(found, seenNames),
    ]);

    stopwatch.stop();
    print('[SCAN] Both scans finished in ${stopwatch.elapsedMilliseconds}ms');
    print('[SCAN] Total devices found: ${found.length}');
    for (final d in found) {
      print('[SCAN]   → ${d.name} (${d.serviceType}) host=${d.host} dlna=${d.isDlnaCapable}');
    }

    _devices = found;
    _isScanning = false;
    notifyListeners();
    print('[SCAN] ════════════════════════════════════════════');
  }

  // ── mDNS (finds Apple TV, Chromecast) ──────────────────────────────────────
  Future<void> _scanMdns(List<TvDevice> found, Set<String> seen) async {
    print('[mDNS] Starting mDNS scan...');
    final serviceTypes = [
      ('_airplay._tcp', 'AirPlay'),
      ('_googlecast._tcp', 'Chromecast'),
    ];
    try {
      final client = MDnsClient();
      print('[mDNS] MDnsClient created, starting...');
      await client.start();
      print('[mDNS] MDnsClient started successfully');

      for (final (service, type) in serviceTypes) {
        print('[mDNS] Scanning for $service ($type)...');
        int ptrCount = 0;
        try {
          await for (final PtrResourceRecord ptr in client
              .lookup<PtrResourceRecord>(
                ResourceRecordQuery.serverPointer('$service.local'),
              )
              .timeout(const Duration(seconds: 4),
                  onTimeout: (s) => s.close())) {
            ptrCount++;
            print('[mDNS] PTR #$ptrCount found: ${ptr.domainName}');
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
              print('[mDNS] SRV resolved: host=$host port=$port');
              break;
            }
            final name = ptr.domainName
                .replaceAll('.$service.local', '')
                .replaceAll('._airplay._tcp.local', '')
                .replaceAll('._googlecast._tcp.local', '')
                .trim();
            print('[mDNS] Device name: "$name"  seen=${seen.contains(name)}');
            if (name.isNotEmpty && !seen.contains(name)) {
              seen.add(name);
              found.add(TvDevice(
                name: name,
                serviceType: type,
                host: host,
                port: port,
                manufacturer: type == 'AirPlay' ? 'Apple' : 'Google',
              ));
              print('[mDNS] ✅ Added $type device: $name');
            } else {
              print('[mDNS] ⚠️ Skipped (empty or duplicate): "$name"');
            }
          }
          print('[mDNS] Done scanning $service — found $ptrCount PTR records');
        } catch (e) {
          print('[mDNS] ❌ Error scanning $service: $e');
        }
      }
      client.stop();
      print('[mDNS] MDnsClient stopped. Total devices from mDNS: ${found.length}');
    } catch (e) {
      print('[mDNS] ❌ Fatal mDNS error: $e');
    }
  }

  // ── SSDP (finds Samsung, LG, Sony, and other UPnP/DLNA TVs) ───────────────
  Future<void> _scanSsdp(List<TvDevice> found, Set<String> seen) async {
    print('[SSDP] Starting SSDP scan...');
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
      print('[SSDP] Binding UDP socket on anyIPv4:0...');
      final socket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.multicastHops = 4;
      print('[SSDP] Socket bound. Sending M-SEARCH to $multicastAddr:$ssdpPort...');

      final msgBytes = Uint8List.fromList(searchMsg.codeUnits);
      final sent = socket.send(msgBytes, InternetAddress(multicastAddr), ssdpPort);
      print('[SSDP] M-SEARCH sent: $sent bytes');

      int responseCount = 0;
      final timer = Timer(const Duration(seconds: 4), () {
        print('[SSDP] 4s timer fired — closing socket. Responses so far: $responseCount');
        socket.close();
      });

      await for (final event in socket) {
        if (event == RawSocketEvent.read) {
          final dg = socket.receive();
          if (dg != null) {
            responseCount++;
            final resp = String.fromCharCodes(dg.data);
            final loc = _header(resp, 'LOCATION');
            final srv = _header(resp, 'SERVER') ?? '';
            final usn = _header(resp, 'USN') ?? '';
            print('[SSDP] Response #$responseCount from ${dg.address.address}');
            print('[SSDP]   SERVER: $srv');
            print('[SSDP]   USN: $usn');
            print('[SSDP]   LOCATION: $loc');
            if (loc != null && !locationsSeen.contains(loc)) {
              locationsSeen.add(loc);
              locationQueue
                  .add({'location': loc, 'server': srv, 'ip': dg.address.address});
              print('[SSDP]   → Queued for description fetch');
            } else if (loc == null) {
              print('[SSDP]   ⚠️ No LOCATION header in response');
            } else {
              print('[SSDP]   ⚠️ Already seen this location, skipping');
            }
          }
        }
      }
      timer.cancel();
      print('[SSDP] Socket closed. Total unique locations: ${locationQueue.length}');
    } catch (e) {
      print('[SSDP] ❌ SSDP socket error: $e');
    }

    // Fetch UPnP device descriptions in parallel (max 6)
    final batch = locationQueue.take(6).toList();
    print('[SSDP] Fetching device descriptions for ${batch.length} locations...');
    await Future.wait(batch.map((item) => _fetchDeviceDescription(
          item['location']!,
          item['server']!,
          item['ip']!,
          found,
          seen,
        )));
    print('[SSDP] All description fetches done.');
  }

  Future<void> _fetchDeviceDescription(
    String locationUrl,
    String serverHeader,
    String ip,
    List<TvDevice> found,
    Set<String> seen,
  ) async {
    print('[DESC] Fetching description from: $locationUrl');
    try {
      final resp = await http
          .get(Uri.parse(locationUrl))
          .timeout(const Duration(seconds: 3));
      print('[DESC] HTTP ${resp.statusCode} for $locationUrl (${resp.body.length} bytes)');
      if (resp.statusCode != 200) {
        print('[DESC] ❌ Non-200 status, skipping');
        return;
      }

      final xml = resp.body;
      final name = _xmlTag(xml, 'friendlyName') ?? ip;
      final manufacturer = _xmlTag(xml, 'manufacturer') ?? '';
      final modelName = _xmlTag(xml, 'modelName') ?? '';
      final deviceType = _xmlTag(xml, 'deviceType') ?? '';
      print('[DESC] friendlyName: "$name"');
      print('[DESC] manufacturer: "$manufacturer"');
      print('[DESC] modelName: "$modelName"');
      print('[DESC] deviceType: "$deviceType"');

      // Find AVTransport control URL for DLNA casting
      String avTransportUrl = '';
      final serviceBlocks = _allBetween(xml, '<service>', '</service>');
      print('[DESC] Found ${serviceBlocks.length} <service> blocks');
      for (int i = 0; i < serviceBlocks.length; i++) {
        final block = serviceBlocks[i];
        final serviceId = _xmlTag(block, 'serviceId') ?? '';
        final serviceType = _xmlTag(block, 'serviceType') ?? '';
        print('[DESC]   Service[$i]: id=$serviceId type=$serviceType');
        if (block.contains('AVTransport')) {
          final ctrlPath = _xmlTag(block, 'controlURL') ?? '';
          print('[DESC]   → AVTransport block found! controlURL="$ctrlPath"');
          if (ctrlPath.isNotEmpty) {
            // Build absolute URL from location base
            final base = Uri.parse(locationUrl);
            final ctrl = ctrlPath.startsWith('/')
                ? '${base.scheme}://${base.host}:${base.port}$ctrlPath'
                : '${base.scheme}://${base.host}:${base.port}/$ctrlPath';
            avTransportUrl = ctrl;
            print('[DESC]   → AVTransport URL: $avTransportUrl');
          } else {
            print('[DESC]   ⚠️ AVTransport block has empty controlURL');
          }
          break;
        }
      }

      if (avTransportUrl.isEmpty) {
        print('[DESC] ⚠️ No AVTransport URL found — device will be UPnP only (no DLNA cast)');
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
        print('[DESC] ✅ Added device: "$name" (${avTransportUrl.isNotEmpty ? "DLNA" : "UPnP"})');
      } else {
        print('[DESC] ⚠️ Duplicate device name "$name", skipping');
      }
    } catch (e) {
      print('[DESC] ❌ Error fetching $locationUrl: $e');
    }
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
