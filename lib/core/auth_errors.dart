/// Helper para traducir errores de autenticación de Supabase (mismo que fernecito_frontend).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

class TraductorErroresAuth {
  static String traducir(dynamic error) {
    if (error is AuthException) return _traducirAuthException(error);
    if (error is PostgrestException) return _traducirPostgrestException(error);
    if (error is String) return _traducirStringError(error.toLowerCase());
    return _traducirStringError(error.toString().toLowerCase());
  }

  static String _traducirAuthException(AuthException error) {
    final message = error.message.toLowerCase();
    final statusCode = error.statusCode;

    if (message.contains('invalid login credentials') ||
        message.contains('invalid credentials') ||
        message.contains('wrong password') ||
        message.contains('incorrect password')) {
      return 'Email o contraseña incorrectos.';
    }
    if (message.contains('email not confirmed') ||
        message.contains('confirm your email') ||
        message.contains('verification required') ||
        (statusCode == '400' && message.contains('email'))) {
      return 'Te falta confirmar tu email. 📩\n\n'
          'Revisá tu bandeja de entrada (y spam) y tocá el enlace de confirmación.\n\n'
          'Después volvé e iniciá sesión.';
    }
    if (message.contains('user already registered') ||
        message.contains('already exists') ||
        message.contains('duplicate')) {
      return 'Ya existe una cuenta con ese email.\n\n'
          'Probá iniciar sesión o recuperá tu contraseña.';
    }
    if (message.contains('invalid email') ||
        message.contains('email format') ||
        message.contains('malformed email')) {
      return 'El formato del email no es válido.';
    }
    if (message.contains('password is too weak') ||
        message.contains('password should be at least') ||
        message.contains('weak password')) {
      return 'La contraseña es muy débil.\n\n'
          'Debe tener al menos 8 caracteres, una letra y un número.';
    }
    if (message.contains('invalid otp') ||
        message.contains('otp_expired') ||
        message.contains('otp has expired') ||
        (message.contains('token') && message.contains('expired'))) {
      return mensajeCodigoInvalidoOExpirado();
    }
    if (message.contains('too many requests') ||
        message.contains('rate limit') ||
        message.contains('try again later') ||
        statusCode == '429') {
      return 'Demasiados intentos.\n\nEsperá un ratito y probá de nuevo.';
    }
    if (message.contains('invalid token') ||
        message.contains('expired') ||
        message.contains('jwt expired') ||
        message.contains('token has expired')) {
      return 'El enlace venció o es inválido.\n\nSolicitá uno nuevo.';
    }
    if (message.contains('unauthorized') ||
        message.contains('not authorized') ||
        statusCode == '401') {
      return 'No tenés autorización para esta acción.';
    }
    if (message.contains('user not found') || message.contains('no user found')) {
      return 'No encontramos una cuenta con ese email.';
    }
    if (message.contains('oauth') || message.contains('provider')) {
      return 'No se pudo conectar con el servicio.\n\nProbá de nuevo en unos segundos.';
    }
    if (statusCode == null || statusCode == '0' || statusCode == 'network') {
      return 'No hay conexión.\n\nRevisá tu internet y probá de nuevo.';
    }
    if (message.isNotEmpty && message.length < 100) return 'Error: $message';
    return 'Ups… algo falló.\n\nProbá de nuevo en unos segundos.';
  }

  static String _traducirPostgrestException(PostgrestException error) {
    final message = error.message.toLowerCase();
    final code = error.code;
    if (code == '23505' ||
        message.contains('duplicate') ||
        message.contains('unique')) {
      if (message.contains('username')) return 'Ese username ya está en uso.\n\nElegí otro.';
      if (message.contains('email')) return 'Ya existe una cuenta con ese email.';
      return 'Ese dato ya está en uso.\n\nProbá con otro.';
    }
    if (code == '42501' ||
        code == 'PGRST301' ||
        message.contains('permission denied') ||
        message.contains('not allowed')) {
      return 'No tenés permisos para esta acción.';
    }
    if (code == 'PGRST116' || message.contains('not found')) {
      return 'No encontramos ese registro.';
    }
    if (message.contains('connection') || message.contains('network')) {
      return 'No hay conexión.\n\nRevisá tu internet y probá de nuevo.';
    }
    return 'Error en la base de datos.\n\nProbá de nuevo en unos segundos.';
  }

  static String _traducirStringError(String errorStr) {
    if (errorStr.contains('socket') ||
        errorStr.contains('connection refused') ||
        errorStr.contains('network') ||
        errorStr.contains('no route') ||
        errorStr.contains('host lookup failed') ||
        errorStr.contains('failed host lookup')) {
      return 'No hay conexión.\n\nRevisá tu internet y probá de nuevo.';
    }
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return 'La conexión tardó mucho.\n\nRevisá tu internet y probá de nuevo.';
    }
    if (errorStr.contains('certificate') || errorStr.contains('ssl')) {
      return 'Error de seguridad en la conexión.\n\nVerificá que tu dispositivo tenga la hora correcta.';
    }
    if (errorStr.length < 100 && !errorStr.contains('exception')) {
      return 'Error: $errorStr';
    }
    return 'Ups… algo falló.\n\nProbá de nuevo en unos segundos.';
  }

  static String mensajeSignupExitoso(String email) {
    return '¡Cuenta creada! 🥃\n\n'
        'Te enviamos un email a $email.\n\n'
        'Abrí el enlace para confirmar tu cuenta y después iniciá sesión.';
  }

  static String mensajeRecoveryEnviado() {
    return 'Listo ✅\n\n'
        'Si el correo existe, te va a llegar un email para recuperar tu contraseña.';
  }

  static String mensajeConfirmacionReenviada() {
    return 'Listo ✅\n\nTe reenviamos el email.\n\nRevisá inbox y spam.';
  }

  static String mensajePasswordActualizada() {
    return 'Contraseña actualizada ✅\n\nYa podés entrar con tu nueva clave.';
  }

  /// Mensaje cuando se envía el código OTP de recuperación.
  static String mensajeCodigoEnviado() {
    return 'Te enviamos un código de 8 dígitos a tu email.\n\n'
        'Revisá tu bandeja de entrada y spam.';
  }

  /// Mensaje para código OTP inválido o expirado.
  static String mensajeCodigoInvalidoOExpirado() {
    return 'El código es inválido o venció.\n\n'
        'Solicitá uno nuevo con "Reenviar código".';
  }

  /// Mensaje para app Locales cuando el email ya tiene cuenta (ej. en Fernecito).
  static String mensajeCuentaExistenteEnFernecito() {
    return '¡Ya tenés una cuenta en Fernecito! 🥃\n\n'
        'Iniciá sesión con el mismo email. Si entraste con Google en la app de usuarios, '
        'usá «Continuar con Google» en el login de Locales.';
  }

  /// Mensaje para app Locales cuando falla el login (recordatorio misma cuenta).
  static String mensajeLoginIncorrectoLocales() {
    return 'Email o contraseña incorrectos.\n\n'
        'Si creaste tu cuenta con Google en Fernecito, tocá «Continuar con Google». '
        'Si usás email, probá la misma contraseña de la app de usuarios.';
  }

  /// Indica si el error es "credenciales inválidas" (login fallido).
  static bool esCredencialesInvalidas(dynamic error) {
    if (error is AuthException) {
      final m = error.message.toLowerCase();
      return m.contains('invalid login credentials') ||
          m.contains('invalid credentials') ||
          m.contains('wrong password') ||
          m.contains('incorrect password');
    }
    final s = error.toString().toLowerCase();
    return s.contains('invalid login credentials') ||
        s.contains('invalid credentials') ||
        s.contains('wrong password');
  }

  /// Indica si el error de auth es "usuario ya registrado" (mismo email).
  static bool esCuentaYaRegistrada(dynamic error) {
    if (error is AuthException) {
      final m = error.message.toLowerCase();
      return m.contains('user already registered') ||
          m.contains('already been registered') ||
          m.contains('already exists') ||
          m.contains('duplicate') ||
          m.contains('already registered');
    }
    final s = error.toString().toLowerCase();
    return s.contains('user already registered') ||
        s.contains('already been registered') ||
        s.contains('already exists') ||
        s.contains('duplicate');
  }
}
