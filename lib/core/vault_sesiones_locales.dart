/// Vault de sesiones multi-cuenta para locales (switch estilo Instagram).
///
/// Guarda N cuentas (cada una con su refresh token + cache de perfil) en
/// almacenamiento seguro: Keychain/Keystore en nativo, localStorage en web
/// (paridad con la sesión única que Supabase ya persiste hoy).
///
/// Seguridad:
/// - Solo hay UNA sesión GoTrue activa a la vez. Edges/RLS usan el JWT actual
///   (`auth.uid()`); un token de A nunca autoriza mutaciones sobre B.
/// - El vault solo guarda refresh tokens (no passwords). `cambiarA` valida
///   `session.user.id == uid` tras `setSession`.
/// - Cerrar una cuenta (`salirDe`/`quitar`) no debe re-crearla vía
///   `actualizarTokenActivo`. Logout total (staff / vault vacío) sí vacía.
/// - En web, XSS same-origin puede leer localStorage (igual que la sesión
///   Supabase). Mitigación: CSP, no inyectar HTML crudo.
///
/// Cada cuenta sigue siendo *ella misma* cuando está activa → no se toca nada
/// del contrato `perfiles_locales.id = auth.uid()`, RLS, edges ni storage.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cuenta_guardada.dart';
import 'supabase_client.dart';

enum ResultadoCambioCuenta { ok, yaActiva, noEncontrada, requiereRelogin, error }

enum ResultadoSalirCuenta {
  cambioAOtra,
  sinCuentas,
  requiereRelogin,
}

class VaultSesionesLocales {
  static final VaultSesionesLocales _instancia = VaultSesionesLocales._();
  factory VaultSesionesLocales() => _instancia;
  VaultSesionesLocales._();

  static const _clave = 'vault_cuentas_locales_v1';
  static const int _maxCuentas = 5;

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    webOptions: WebOptions(),
  );

  SupabaseClient get _sb => ServicioSupabase().cliente;

  String? get uidActivo => _sb.auth.currentUser?.id;

  // ── Lectura ──────────────────────────────────────────────────────────────
  Future<List<CuentaGuardada>> listar() async {
    try {
      final raw = await _storage.read(key: _clave);
      if (raw == null || raw.isEmpty) return <CuentaGuardada>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <CuentaGuardada>[];
      final cuentas = <CuentaGuardada>[];
      for (final item in decoded) {
        if (item is Map) {
          final c = CuentaGuardada.fromJson(Map<String, dynamic>.from(item));
          if (c != null) cuentas.add(c);
        }
      }
      cuentas.sort((a, b) => b.ultimoUso.compareTo(a.ultimoUso));
      return cuentas;
    } catch (e) {
      debugPrint('⚠️ vault.listar: $e');
      return <CuentaGuardada>[];
    }
  }

  Future<int> cantidad() async => (await listar()).length;

  Future<bool> hayVarias() async => (await cantidad()) > 1;

  Future<CuentaGuardada?> buscar(String uid) async {
    for (final c in await listar()) {
      if (c.uid == uid) return c;
    }
    return null;
  }

  // ── Escritura ────────────────────────────────────────────────────────────
  Future<void> _persistir(List<CuentaGuardada> cuentas) async {
    try {
      // Cap: si excede, descarto la menos usada (excepto la activa).
      var lista = [...cuentas];
      if (lista.length > _maxCuentas) {
        lista.sort((a, b) => b.ultimoUso.compareTo(a.ultimoUso));
        final activa = uidActivo;
        lista = lista
            .where((c) => c.uid == activa)
            .followedBy(lista.where((c) => c.uid != activa))
            .take(_maxCuentas)
            .toList();
      }
      final json = jsonEncode(lista.map((c) => c.toJson()).toList());
      await _storage.write(key: _clave, value: json);
    } catch (e) {
      debugPrint('⚠️ vault._persistir: $e');
    }
  }

  Future<void> _upsert(CuentaGuardada cuenta) async {
    final cuentas = List<CuentaGuardada>.of(await listar());
    final idx = cuentas.indexWhere((c) => c.uid == cuenta.uid);
    if (idx >= 0) {
      cuentas[idx] = cuenta;
    } else {
      cuentas.add(cuenta);
    }
    await _persistir(cuentas);
  }

  /// Snapshotea la sesión activa (refresh token + metadata) en el vault.
  /// Llamar tras un login exitoso, y cuando cargás el perfil del local.
  Future<void> guardarActual({
    String? nombreLocal,
    String? localUsername,
    String? fotoPerfilUrl,
    String? email,
  }) async {
    final session = _sb.auth.currentSession;
    final user = session?.user;
    if (session == null || user == null) return;

    final metodo = _metodoDe(user);
    final existente = await buscar(user.id);
    final cuenta = (existente ?? CuentaGuardada(uid: user.id, refreshToken: session.refreshToken ?? ''))
        .copyWith(
      refreshToken: session.refreshToken ?? existente?.refreshToken,
      metodo: metodo,
      email: email ?? user.email ?? existente?.email,
      nombreLocal: nombreLocal ?? existente?.nombreLocal,
      localUsername: localUsername ?? existente?.localUsername,
      fotoPerfilUrl: fotoPerfilUrl ?? existente?.fotoPerfilUrl,
      ultimoUso: DateTime.now().millisecondsSinceEpoch,
      requiereRelogin: false,
    );
    if (cuenta.refreshToken.isEmpty) return;
    await _upsert(cuenta);
  }

  /// Actualiza solo el refresh token de la cuenta activa (listener de rotación).
  Future<void> actualizarTokenActivo() async {
    final session = _sb.auth.currentSession;
    final user = session?.user;
    final refresh = session?.refreshToken;
    if (user == null || refresh == null || refresh.isEmpty) return;
    final existente = await buscar(user.id);
    if (existente == null) return; // NO re-crear si la sacamos del vault
    if (existente.refreshToken == refresh) return;
    await _upsert(existente.copyWith(refreshToken: refresh));
  }

  /// Refresca el cache visual (nombre/username/foto) de una cuenta.
  Future<void> actualizarCache(
    String uid, {
    String? nombreLocal,
    String? localUsername,
    String? fotoPerfilUrl,
  }) async {
    final c = await buscar(uid);
    if (c == null) return;
    await _upsert(c.copyWith(
      nombreLocal: nombreLocal,
      localUsername: localUsername,
      fotoPerfilUrl: fotoPerfilUrl,
    ));
  }

  /// Cambia a otra cuenta guardada reanudando su sesión (sin contraseña).
  Future<ResultadoCambioCuenta> cambiarA(
    String uid, {
    bool preservarActiva = true,
  }) async {
    if (uid == uidActivo) return ResultadoCambioCuenta.yaActiva;
    final cuenta = await buscar(uid);
    if (cuenta == null) return ResultadoCambioCuenta.noEncontrada;
    if (cuenta.requiereRelogin || cuenta.refreshToken.isEmpty) {
      return ResultadoCambioCuenta.requiereRelogin;
    }

    if (preservarActiva) {
      await actualizarTokenActivo();
    }

    try {
      final res = await _sb.auth.setSession(cuenta.refreshToken);
      final session = res.session;
      if (session == null || session.user.id != uid) {
        await _upsert(cuenta.copyWith(requiereRelogin: true));
        return ResultadoCambioCuenta.requiereRelogin;
      }
      final nuevoRefresh = session.refreshToken ?? cuenta.refreshToken;
      await _upsert(cuenta.copyWith(
        refreshToken: nuevoRefresh,
        ultimoUso: DateTime.now().millisecondsSinceEpoch,
        requiereRelogin: false,
      ));
      return ResultadoCambioCuenta.ok;
    } on AuthException catch (e) {
      debugPrint('⚠️ vault.cambiarA authException: ${e.message}');
      await _upsert(cuenta.copyWith(requiereRelogin: true));
      return ResultadoCambioCuenta.requiereRelogin;
    } catch (e) {
      debugPrint('⚠️ vault.cambiarA: $e');
      return ResultadoCambioCuenta.error;
    }
  }

  /// Saca [uid] del vault. Si era la activa, intenta saltar a otra guardada.
  Future<ResultadoSalirCuenta> salirDe(String uid) async {
    await quitar(uid);

    final restantes = await listar();
    if (restantes.isEmpty) return ResultadoSalirCuenta.sinCuentas;

    if (uidActivo != null && uidActivo != uid) {
      return ResultadoSalirCuenta.cambioAOtra;
    }

    for (final c in restantes) {
      final res = await cambiarA(c.uid, preservarActiva: false);
      if (res == ResultadoCambioCuenta.ok) {
        return ResultadoSalirCuenta.cambioAOtra;
      }
    }
    return ResultadoSalirCuenta.requiereRelogin;
  }

  Future<CuentaGuardada?> primeraParaRelogin() async {
    final cuentas = await listar();
    if (cuentas.isEmpty) return null;
    for (final c in cuentas) {
      if (c.requiereRelogin) return c;
    }
    return cuentas.first;
  }

  /// Quita una cuenta del vault (no cierra su sesión en el server).
  Future<void> quitar(String uid) async {
    final cuentas = List<CuentaGuardada>.of(await listar());
    cuentas.removeWhere((c) => c.uid == uid);
    await _persistir(cuentas);
  }

  /// Vacía el vault completo.
  Future<void> vaciar() async {
    try {
      await _storage.delete(key: _clave);
    } catch (e) {
      debugPrint('⚠️ vault.vaciar: $e');
    }
  }

  String _metodoDe(User user) {
    final prov = (user.appMetadata['provider'] ?? '').toString().toLowerCase();
    if (prov.contains('google')) return 'google';
    if (prov.contains('email')) return 'email';
    return 'otro';
  }
}
