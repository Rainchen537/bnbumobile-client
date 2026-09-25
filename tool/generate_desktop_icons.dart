import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

const _macIconSizes = <int>[16, 32, 64, 128, 256, 512, 1024];
const _windowsIconSizes = <int>[16, 24, 32, 48, 64, 128, 256];
const _resizedAppIcons = <({String path, int size})>[
  (path: 'android/app/src/main/res/mipmap-mdpi/ic_launcher.png', size: 48),
  (path: 'android/app/src/main/res/mipmap-hdpi/ic_launcher.png', size: 72),
  (path: 'android/app/src/main/res/mipmap-xhdpi/ic_launcher.png', size: 96),
  (path: 'android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png', size: 144),
  (path: 'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png', size: 192),
  (path: 'android/app/src/main/res/drawable/ic_notification.png', size: 96),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@1x.png',
    size: 20,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@2x.png',
    size: 40,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-20x20@3x.png',
    size: 60,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@1x.png',
    size: 29,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@2x.png',
    size: 58,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-29x29@3x.png',
    size: 87,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@1x.png',
    size: 40,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@2x.png',
    size: 80,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-40x40@3x.png',
    size: 120,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@2x.png',
    size: 120,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-60x60@3x.png',
    size: 180,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@1x.png',
    size: 76,
  ),
  (
    path: 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-76x76@2x.png',
    size: 152,
  ),
  (
    path:
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-83.5x83.5@2x.png',
    size: 167,
  ),
  (
    path:
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
    size: 1024,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-48x48@2x.png',
    size: 48,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-55x55@2x.png',
    size: 55,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-58x58@2x.png',
    size: 58,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-87x87@3x.png',
    size: 87,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-80x80@2x.png',
    size: 80,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-88x88@2x.png',
    size: 88,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-100x100@2x.png',
    size: 100,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-172x172@2x.png',
    size: 172,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-196x196@2x.png',
    size: 196,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-216x216@2x.png',
    size: 216,
  ),
  (
    path:
        'apple/BnbuWatchApp/Assets.xcassets/AppIcon.appiconset/Icon-Watch-1024x1024@1x.png',
    size: 1024,
  ),
  (path: 'web/favicon.png', size: 16),
  (path: 'web/icons/Icon-192.png', size: 192),
  (path: 'web/icons/Icon-512.png', size: 512),
  (path: 'web/icons/Icon-maskable-192.png', size: 192),
  (path: 'web/icons/Icon-maskable-512.png', size: 512),
];
const _macIconCanvasSize = 1024;
const _macIconFrameSize = 824;
const _macIconSuperellipsePower = 4.6;
const _maskSamplesPerAxis = 4;

Future<void> main() async {
  if (!Platform.isMacOS) {
    stderr.writeln('This generator requires macOS sips.');
    exitCode = 2;
    return;
  }

  final repository = File.fromUri(Platform.script).parent.parent;
  final source = File('${repository.path}/assets/branding/app_logo.png');
  if (!source.existsSync()) {
    stderr.writeln('Missing canonical BNBU app logo: ${source.path}');
    exitCode = 2;
    return;
  }

  final temporary = await Directory.systemTemp.createTemp('hands-bnbu-icons-');
  try {
    for (final icon in _resizedAppIcons) {
      await _resize(
        source: source,
        output: File('${repository.path}/${icon.path}'),
        size: icon.size,
      );
    }

    final frames = <({int size, Uint8List bytes})>[];
    for (final size in _windowsIconSizes) {
      final output = File('${temporary.path}/app_icon_$size.png');
      await _resize(source: source, output: output, size: size);
      frames.add((size: size, bytes: await output.readAsBytes()));
    }

    final macMaster = File('${temporary.path}/mac_app_icon_1024.png');
    await _writeMacIconMaster(source: source, output: macMaster);
    for (final size in _macIconSizes) {
      final output = File(
        '${repository.path}/macos/Runner/Assets.xcassets/'
        'AppIcon.appiconset/app_icon_$size.png',
      );
      await _resize(source: macMaster, output: output, size: size);
    }

    final windowsIcon = File(
      '${repository.path}/windows/runner/resources/app_icon.ico',
    );
    await windowsIcon.writeAsBytes(_encodeIco(frames), flush: true);
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<void> _writeMacIconMaster({
  required File source,
  required File output,
}) async {
  final decoded = image.decodePng(await source.readAsBytes());
  if (decoded == null) {
    throw StateError('Unable to decode canonical BNBU icon: ${source.path}');
  }

  final frame = image.copyResize(
    decoded,
    width: _macIconFrameSize,
    height: _macIconFrameSize,
    interpolation: image.Interpolation.cubic,
  );
  final canvas = image.Image(
    width: _macIconCanvasSize,
    height: _macIconCanvasSize,
    numChannels: 4,
  );
  final inset = (_macIconCanvasSize - _macIconFrameSize) ~/ 2;
  final halfExtent = _macIconFrameSize / 2;

  for (var y = 0; y < _macIconFrameSize; y += 1) {
    for (var x = 0; x < _macIconFrameSize; x += 1) {
      var coveredSamples = 0;
      for (var sampleY = 0; sampleY < _maskSamplesPerAxis; sampleY += 1) {
        final normalizedY =
            ((y + (sampleY + 0.5) / _maskSamplesPerAxis) - halfExtent) /
            halfExtent;
        final yTerm = math.pow(normalizedY.abs(), _macIconSuperellipsePower);
        for (var sampleX = 0; sampleX < _maskSamplesPerAxis; sampleX += 1) {
          final normalizedX =
              ((x + (sampleX + 0.5) / _maskSamplesPerAxis) - halfExtent) /
              halfExtent;
          final xTerm = math.pow(normalizedX.abs(), _macIconSuperellipsePower);
          if (xTerm + yTerm <= 1) {
            coveredSamples += 1;
          }
        }
      }
      if (coveredSamples == 0) {
        continue;
      }

      final sourcePixel = frame.getPixel(x, y);
      final maskAlpha =
          coveredSamples / (_maskSamplesPerAxis * _maskSamplesPerAxis);
      canvas.setPixelRgba(
        x + inset,
        y + inset,
        sourcePixel.r,
        sourcePixel.g,
        sourcePixel.b,
        sourcePixel.a * maskAlpha,
      );
    }
  }

  await output.writeAsBytes(image.encodePng(canvas), flush: true);
}

Future<void> _resize({
  required File source,
  required File output,
  required int size,
}) async {
  final result = await Process.run('/usr/bin/sips', <String>[
    '-z',
    '$size',
    '$size',
    source.path,
    '--out',
    output.path,
  ]);
  if (result.exitCode != 0) {
    stderr.write(result.stdout);
    stderr.write(result.stderr);
    throw ProcessException('/usr/bin/sips', <String>[source.path]);
  }
}

Uint8List _encodeIco(List<({int size, Uint8List bytes})> frames) {
  final header = ByteData(6 + frames.length * 16)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, frames.length, Endian.little);

  var imageOffset = header.lengthInBytes;
  for (var index = 0; index < frames.length; index += 1) {
    final frame = frames[index];
    final entryOffset = 6 + index * 16;
    header
      ..setUint8(entryOffset, frame.size == 256 ? 0 : frame.size)
      ..setUint8(entryOffset + 1, frame.size == 256 ? 0 : frame.size)
      ..setUint8(entryOffset + 2, 0)
      ..setUint8(entryOffset + 3, 0)
      ..setUint16(entryOffset + 4, 1, Endian.little)
      ..setUint16(entryOffset + 6, 32, Endian.little)
      ..setUint32(entryOffset + 8, frame.bytes.length, Endian.little)
      ..setUint32(entryOffset + 12, imageOffset, Endian.little);
    imageOffset += frame.bytes.length;
  }

  final output = BytesBuilder(copy: false)..add(header.buffer.asUint8List());
  for (final frame in frames) {
    output.add(frame.bytes);
  }
  return output.takeBytes();
}
