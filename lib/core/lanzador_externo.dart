library;

import 'package:url_launcher/url_launcher.dart';

Future<bool> lanzarExternoConFallback(Uri uri) async {
  final modos = <LaunchMode>[
    LaunchMode.externalApplication,
    LaunchMode.platformDefault,
    if (uri.scheme == 'http' || uri.scheme == 'https')
      LaunchMode.inAppBrowserView,
  ];

  for (final modo in modos) {
    try {
      if (await launchUrl(uri, mode: modo)) return true;
    } catch (_) {
      // Si un modo no esta disponible en el dispositivo, probamos otro.
    }
  }
  return false;
}
