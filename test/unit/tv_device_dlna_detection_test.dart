import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_screen_to_tv/models/tv_device.dart';

void main() {
  group('TvDevice.isDlnaCapable', () {
    test('returns false when avTransportUrl is empty (default)', () {
      const device = TvDevice(
        name: 'Apple TV',
        serviceType: 'AirPlay',
        host: '192.168.1.50',
        port: 7000,
        manufacturer: 'Apple',
      );
      expect(device.isDlnaCapable, isFalse,
          reason: 'AirPlay device with no avTransportUrl must not be DLNA-capable');
    });

    test('returns false when avTransportUrl is explicitly empty', () {
      const device = TvDevice(
        name: 'Unknown TV',
        serviceType: 'UPnP',
        host: '192.168.1.99',
        port: 0,
        avTransportUrl: '',
      );
      expect(device.isDlnaCapable, isFalse);
    });

    test('returns true when avTransportUrl is non-empty', () {
      const device = TvDevice(
        name: 'Samsung TV',
        serviceType: 'DLNA',
        host: '192.168.1.100',
        port: 0,
        manufacturer: 'Samsung',
        avTransportUrl: 'http://192.168.1.100:7676/upnp/control/AVTransport1',
      );
      expect(device.isDlnaCapable, isTrue,
          reason: 'Device with a non-empty avTransportUrl must be DLNA-capable');
    });

    test('returns true for LG DLNA device', () {
      const device = TvDevice(
        name: 'LG OLED TV',
        serviceType: 'DLNA',
        host: '10.0.0.5',
        port: 0,
        manufacturer: 'LG Electronics',
        avTransportUrl: 'http://10.0.0.5:52235/upnp/control/AVTransport',
      );
      expect(device.isDlnaCapable, isTrue);
    });
  });
}
