library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ModoAppLocalesTipo { local, staff }

/// Distingue si la sesión activa opera como dueño de local o como staff.
class ModoAppLocales {
  ModoAppLocales._();
  static final ModoAppLocales instancia = ModoAppLocales._();

  static const _prefsKey = 'modo_app_locales';

  final ValueNotifier<ModoAppLocalesTipo> modo =
      ValueNotifier<ModoAppLocalesTipo>(ModoAppLocalesTipo.local);

  bool get esStaff => modo.value == ModoAppLocalesTipo.staff;
  bool get esLocal => modo.value == ModoAppLocalesTipo.local;

  Future<void> cargar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      modo.value =
          raw == 'staff' ? ModoAppLocalesTipo.staff : ModoAppLocalesTipo.local;
    } catch (e) {
      debugPrint('⚠️ ModoAppLocales.cargar: $e');
    }
  }

  void establecerStaff() {
    if (modo.value == ModoAppLocalesTipo.staff) return;
    modo.value = ModoAppLocalesTipo.staff;
    unawaited(_persistir(ModoAppLocalesTipo.staff));
  }

  void establecerLocal() {
    if (modo.value == ModoAppLocalesTipo.local) return;
    modo.value = ModoAppLocalesTipo.local;
    unawaited(_persistir(ModoAppLocalesTipo.local));
  }

  Future<void> _persistir(ModoAppLocalesTipo value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        value == ModoAppLocalesTipo.staff ? 'staff' : 'local',
      );
    } catch (e) {
      debugPrint('⚠️ ModoAppLocales._persistir: $e');
    }
  }
}
