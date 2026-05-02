import 'package:flutter_test/flutter_test.dart';
import 'package:mirror_screen_to_tv/models/tv_device.dart';

void main() {
  group('TvDevice.displayBrand', () {
    test('Samsung manufacturer string maps to Samsung', () {
      const d = TvDevice(name: 'x', serviceType: 'DLNA', host: '1.1.1.1', port: 0, manufacturer: 'Samsung Electronics');
      expect(d.displayBrand, equals('Samsung'));
    });

    test('LG manufacturer string maps to LG', () {
      const d = TvDevice(name: 'x', serviceType: 'DLNA', host: '1.1.1.1', port: 0, manufacturer: 'LG Electronics');
      expect(d.displayBrand, equals('LG'));
    });

    test('Sony manufacturer string maps to Sony', () {
      const d = TvDevice(name: 'x', serviceType: 'DLNA', host: '1.1.1.1', port: 0, manufacturer: 'Sony Corporation');
      expect(d.displayBrand, equals('Sony'));
    });

    test('Apple manufacturer string maps to Apple', () {
      const d = TvDevice(name: 'x', serviceType: 'AirPlay', host: '1.1.1.1', port: 7000, manufacturer: 'Apple Inc.');
      expect(d.displayBrand, equals('Apple'));
    });

    test('AirPlay serviceType with no manufacturer maps to Apple TV', () {
      const d = TvDevice(name: 'Living Room', serviceType: 'AirPlay', host: '1.1.1.1', port: 7000);
      expect(d.displayBrand, equals('Apple TV'));
    });

    test('Chromecast serviceType with no manufacturer maps to Chromecast', () {
      const d = TvDevice(name: 'Chromecast Ultra', serviceType: 'Chromecast', host: '1.1.1.1', port: 8009);
      expect(d.displayBrand, equals('Chromecast'));
    });

    test('Unknown manufacturer falls back to manufacturer string', () {
      const d = TvDevice(name: 'x', serviceType: 'DLNA', host: '1.1.1.1', port: 0, manufacturer: 'Vizio');
      expect(d.displayBrand, equals('Vizio'));
    });

    test('Empty manufacturer and unknown serviceType falls back to serviceType', () {
      const d = TvDevice(name: 'x', serviceType: 'UPnP', host: '1.1.1.1', port: 0);
      expect(d.displayBrand, equals('UPnP'));
    });
  });
}
