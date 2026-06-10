-- ============================================================================
-- Función para que la app Locales sepa si un email ya está registrado
-- (evita falso positivo al crear cuenta con email existente)
-- ============================================================================
--
-- EJECUTAR EN: Supabase Dashboard → SQL Editor
--
-- La función solo devuelve true/false; no expone datos del usuario.
-- ============================================================================

-- Crear función que consulta auth.users (solo existencia del email)
CREATE OR REPLACE FUNCTION public.email_ya_registrado(p_email text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users WHERE email = nullif(trim(p_email), '')
  );
$$;

-- Permitir que la app (anon y authenticated) llame a la función
GRANT EXECUTE ON FUNCTION public.email_ya_registrado(text) TO anon;
GRANT EXECUTE ON FUNCTION public.email_ya_registrado(text) TO authenticated;

COMMENT ON FUNCTION public.email_ya_registrado(text) IS
  'Devuelve true si el email ya existe en auth.users. Usado por frontend_locales antes de signUp.';

-- ============================================================================
-- NOTA: Si Supabase da error de permisos al leer auth.users, probá ejecutar
-- como superuser o usar una Edge Function que llame a auth.admin.getUserByEmail.
-- ============================================================================
