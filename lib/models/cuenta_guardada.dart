/// Una cuenta de local guardada en el vault multi-cuenta.
///
/// Solo persiste el *refresh token* (secreto mínimo necesario para reanudar la
/// sesión con `auth.setSession`), nunca la contraseña ni el access token de
/// larga vida. El cache de nombre/username/foto es solo para pintar el switcher
/// sin pegarle a la red.
library;

class CuentaGuardada {
  const CuentaGuardada({
    required this.uid,
    required this.refreshToken,
    this.metodo = 'otro',
    this.email,
    this.nombreLocal,
    this.localUsername,
    this.fotoPerfilUrl,
    this.ultimoUso = 0,
    this.requiereRelogin = false,
  });

  /// auth.uid() de la cuenta (= perfiles_locales.id).
  final String uid;

  /// Refresh token para reanudar la sesión sin pedir contraseña.
  final String refreshToken;

  /// 'google' | 'email' | 'otro' — para el fallback de re-login.
  final String metodo;

  final String? email;
  final String? nombreLocal;
  final String? localUsername;
  final String? fotoPerfilUrl;

  /// millisSinceEpoch del último uso (para ordenar el switcher).
  final int ultimoUso;

  /// true si un intento de switch detectó el token vencido/revocado.
  /// Esa cuenta necesita re-login puntual (las demás siguen andando).
  final bool requiereRelogin;

  CuentaGuardada copyWith({
    String? refreshToken,
    String? metodo,
    String? email,
    String? nombreLocal,
    String? localUsername,
    String? fotoPerfilUrl,
    int? ultimoUso,
    bool? requiereRelogin,
  }) {
    return CuentaGuardada(
      uid: uid,
      refreshToken: refreshToken ?? this.refreshToken,
      metodo: metodo ?? this.metodo,
      email: email ?? this.email,
      nombreLocal: nombreLocal ?? this.nombreLocal,
      localUsername: localUsername ?? this.localUsername,
      fotoPerfilUrl: fotoPerfilUrl ?? this.fotoPerfilUrl,
      ultimoUso: ultimoUso ?? this.ultimoUso,
      requiereRelogin: requiereRelogin ?? this.requiereRelogin,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'refreshToken': refreshToken,
        'metodo': metodo,
        if (email != null) 'email': email,
        if (nombreLocal != null) 'nombreLocal': nombreLocal,
        if (localUsername != null) 'localUsername': localUsername,
        if (fotoPerfilUrl != null) 'fotoPerfilUrl': fotoPerfilUrl,
        'ultimoUso': ultimoUso,
        'requiereRelogin': requiereRelogin,
      };

  static CuentaGuardada? fromJson(Map<String, dynamic> j) {
    final uid = (j['uid'] ?? '').toString();
    final refresh = (j['refreshToken'] ?? '').toString();
    if (uid.isEmpty || refresh.isEmpty) return null;
    return CuentaGuardada(
      uid: uid,
      refreshToken: refresh,
      metodo: (j['metodo'] ?? 'otro').toString(),
      email: (j['email'] as String?)?.trim(),
      nombreLocal: (j['nombreLocal'] as String?)?.trim(),
      localUsername: (j['localUsername'] as String?)?.trim(),
      fotoPerfilUrl: (j['fotoPerfilUrl'] as String?)?.trim(),
      ultimoUso: j['ultimoUso'] is int
          ? j['ultimoUso'] as int
          : int.tryParse('${j['ultimoUso']}') ?? 0,
      requiereRelogin: j['requiereRelogin'] == true,
    );
  }

  /// Nombre a mostrar en el switcher.
  String get displayNombre {
    final n = nombreLocal?.trim();
    if (n != null && n.isNotEmpty) return n;
    final u = localUsername?.trim();
    if (u != null && u.isNotEmpty) return '@$u';
    final e = email?.trim();
    if (e != null && e.isNotEmpty) return e;
    return 'Local';
  }
}
