import 'package:flutter/material.dart';

/// Navigator raíz compartido por rutas in-app y aperturas desde push.
final GlobalKey<NavigatorState> navigatorKeyLocales =
    GlobalKey<NavigatorState>();
