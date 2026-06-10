/// Bandera para que AuthGate NO navegue mientras el usuario está en el flujo OTP
/// de recuperación de contraseña (verificar código → nueva contraseña).
library;

bool enFlujoRecuperacionContrasena = false;
