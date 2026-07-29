import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test('brand master uses the app theme palette and flat geometry', () {
    final iconSvg = File('assets/brand/fknotes_icon.svg').readAsStringSync();
    final markSvg = File('assets/brand/fknotes_mark.svg').readAsStringSync();

    for (final color in const [
      '#203442',
      '#587086',
      '#A76649',
      '#F1EEE7',
      '#FAF8F2',
    ]) {
      expect(iconSvg, contains(color));
    }
    expect(iconSvg, isNot(contains('<linearGradient')));
    expect(iconSvg, isNot(contains('<filter')));
    expect(iconSvg, isNot(contains('#B9573D')));
    expect(
      markSvg,
      contains('<rect width="100" height="100" fill="#F1EEE7"/>'),
    );
  });

  test('generated platform icons have their required dimensions', () {
    const expectedSizes = <String, (int, int)>{
      'assets/brand/fknotes_icon.png': (1024, 1024),
      'assets/brand/fknotes_mark.png': (1024, 1024),
      'android/app/src/main/res/drawable-nodpi/splash_wordmark.png': (640, 192),
      'android/app/src/main/res/mipmap-mdpi/ic_launcher.png': (48, 48),
      'android/app/src/main/res/mipmap-hdpi/ic_launcher.png': (72, 72),
      'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png': (96, 96),
      'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png': (144, 144),
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': (192, 192),
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/'
          'Icon-App-1024x1024@1x.png': (
        1024,
        1024,
      ),
      'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage@3x.png': (
        264,
        264,
      ),
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png': (
        16,
        16,
      ),
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png': (
        1024,
        1024,
      ),
      'web/favicon.png': (32, 32),
      'web/icons/Icon-192.png': (192, 192),
      'web/icons/Icon-512.png': (512, 512),
      'web/icons/Icon-maskable-192.png': (192, 192),
      'web/icons/Icon-maskable-512.png': (512, 512),
    };

    for (final MapEntry(key: path, value: size) in expectedSizes.entries) {
      final decoded = image.decodeImage(File(path).readAsBytesSync());
      expect(decoded, isNotNull, reason: '$path should be decodable');
      expect(
        (decoded!.width, decoded.height),
        size,
        reason: '$path should have the platform-required dimensions',
      );
    }
  });

  test('app icon and launch mark use an opaque seamless canvas', () {
    final icon = image.decodePng(
      File('assets/brand/fknotes_icon.png').readAsBytesSync(),
    )!;
    final mark = image.decodePng(
      File('assets/brand/fknotes_mark.png').readAsBytesSync(),
    )!;

    expect(icon.getPixel(0, 0).a, 255);
    expect(mark.getPixel(0, 0).a, 255);
    expect(
      (mark.getPixel(0, 0).r, mark.getPixel(0, 0).g, mark.getPixel(0, 0).b),
      (241, 238, 231),
    );
    expect(mark.getPixel(mark.width ~/ 2, mark.height ~/ 2).a, 255);
  });
}
