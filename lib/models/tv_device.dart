class TvDevice {
  final String name;
  final String serviceType; // 'AirPlay', 'Chromecast', 'DLNA', 'Unknown'
  final String host;
  final int port;
  final String manufacturer; // 'Samsung', 'LG', 'Sony', 'Apple', 'Google', ''
  final String avTransportUrl; // Full URL for DLNA UPnP control, '' if not DLNA
  final String locationUrl; // SSDP location URL

  const TvDevice({
    required this.name,
    required this.serviceType,
    required this.host,
    required this.port,
    this.manufacturer = '',
    this.avTransportUrl = '',
    this.locationUrl = '',
  });

  bool get isDlnaCapable => avTransportUrl.isNotEmpty;

  String get displayBrand {
    final m = manufacturer.toLowerCase();
    if (m.contains('samsung')) return 'Samsung';
    if (m.contains('lg')) return 'LG';
    if (m.contains('sony')) return 'Sony';
    if (m.contains('apple')) return 'Apple';
    if (m.contains('google')) return 'Google';
    if (serviceType == 'AirPlay') return 'Apple TV';
    if (serviceType == 'Chromecast') return 'Chromecast';
    return manufacturer.isNotEmpty ? manufacturer : serviceType;
  }
}
