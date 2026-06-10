/// Splash nativo idéntico al de fernecito_frontend:
/// fondo violeta #742ED1 + logo centrado (scaleAspectFit / gravity center).
///
/// Genera el logo compuesto, regenera los assets nativos con
/// flutter_native_splash y corrige el fondo blanco heredado del storyboard iOS.
library;

import 'dart:io';

import 'package:image/image.dart' as img;

const _violetaR = 116; // #742ED1
const _violetaG = 46;
const _violetaB = 209;

void main() async {
  _generarLogoCompuesto();
  await _regenerarNativo();
  _corregirFondoBlancoIos();
  _corregirMainStoryboardIos();
  _corregirColorAndroid();
  stdout.writeln('');
  stdout.writeln('Splash nativo = fondo #742ED1 + logo centrado (igual a usuarios).');
  stdout.writeln('Ejecutá: flutter clean && flutter run');
  stdout.writeln('Desinstalá la app antes en iPhone/Android (cache del splash nativo).');
}

/// Logo sobre fondo violeta sólido, ocupando ~42% del canvas (resto violeta).
/// El fondo violeta coincide con `color`, así el logo se ve centrado y mediano.
void _generarLogoCompuesto() {
  const canvasSize = 2048;
  const logoFraction = 0.42;

  final source = img.decodePng(
    File('assets/imagenes/localeslogo.png').readAsBytesSync(),
  );
  if (source == null) {
    stderr.writeln('No se pudo leer assets/imagenes/localeslogo.png');
    exit(1);
  }

  final logoSize = (canvasSize * logoFraction).round();
  final resized = img.copyResize(
    source,
    width: logoSize,
    height: logoSize,
    interpolation: img.Interpolation.average,
  );

  final canvas = img.Image(width: canvasSize, height: canvasSize, numChannels: 3);
  for (var y = 0; y < canvasSize; y++) {
    for (var x = 0; x < canvasSize; x++) {
      canvas.setPixelRgb(x, y, _violetaR, _violetaG, _violetaB);
    }
  }

  final offset = (canvasSize - logoSize) ~/ 2;
  img.compositeImage(canvas, resized, dstX: offset, dstY: offset);

  File('assets/imagenes/localeslogo_splash.png')
      .writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Generado assets/imagenes/localeslogo_splash.png');
}

Future<void> _regenerarNativo() async {
  stdout.writeln('Regenerando assets nativos (flutter_native_splash)...');
  final r = await Process.run(
    'dart',
    ['run', 'flutter_native_splash:create'],
    runInShell: true,
  );
  stdout.write(r.stdout);
  stderr.write(r.stderr);
  if (r.exitCode != 0) {
    stderr.writeln('flutter_native_splash:create falló (${r.exitCode})');
    exit(r.exitCode);
  }
}

/// flutter_native_splash deja el `backgroundColor` del storyboard en blanco
/// (queda detrás del LaunchBackground). Lo forzamos a violeta por las dudas.
void _corregirFondoBlancoIos() {
  final f = File('ios/Runner/Base.lproj/LaunchScreen.storyboard');
  if (!f.existsSync()) return;
  var xml = f.readAsStringSync();
  xml = xml.replaceAll(
    '<color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
    '<color key="backgroundColor" red="0.45490196078431372" green="0.1803921568627451" blue="0.8196078431372549" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
  );
  f.writeAsStringSync(xml);
  stdout.writeln('Storyboard iOS: fondo forzado a violeta.');
}

/// El Main.storyboard (interfaz principal de iOS) tiene fondo blanco por
/// defecto y puede mostrar un frame blanco antes de que Flutter dibuje.
void _corregirMainStoryboardIos() {
  final f = File('ios/Runner/Base.lproj/Main.storyboard');
  if (!f.existsSync()) return;
  var xml = f.readAsStringSync();
  xml = xml.replaceAll(
    '<color key="backgroundColor" white="1" alpha="1" colorSpace="custom" customColorSpace="calibratedWhite"/>',
    '<color key="backgroundColor" red="0.45490196078431372" green="0.1803921568627451" blue="0.8196078431372549" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>',
  );
  f.writeAsStringSync(xml);
  stdout.writeln('Main.storyboard iOS: fondo forzado a violeta.');
}

/// Color del adaptive icon (no del splash) a violeta de marca.
void _corregirColorAndroid() {
  final f = File('android/app/src/main/res/values/colors.xml');
  if (!f.existsSync()) return;
  var xml = f.readAsStringSync();
  xml = xml.replaceAll('#6625C6', '#742ED1').replaceAll('#6625c6', '#742ED1');
  f.writeAsStringSync(xml);
  stdout.writeln('Android colors.xml: ic_launcher_background a #742ED1.');
}
