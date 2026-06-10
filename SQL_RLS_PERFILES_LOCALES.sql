-- ============================================================================
-- RLS para perfiles_locales — permite que usuarios autenticados gestionen su perfil
-- ============================================================================
--
-- Error 42501: "new row violates row-level security policy"
-- Ocurre porque RLS está activo pero no existe política que permita INSERT.
--
-- EJECUTAR EN: Supabase Dashboard → SQL Editor
-- ============================================================================

-- 1. Verificar que RLS está habilitado (ya debería estarlo si recibís el error)
ALTER TABLE perfiles_locales ENABLE ROW LEVEL SECURITY;

-- 2. Política INSERT: el usuario autenticado puede insertar su propia fila
--    (id debe coincidir con auth.uid())
CREATE POLICY "Usuarios pueden insertar su propio perfil"
  ON perfiles_locales
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- 3. Política SELECT: el usuario puede leer su propio perfil
CREATE POLICY "Usuarios pueden leer su propio perfil"
  ON perfiles_locales
  FOR SELECT
  TO authenticated
  USING (auth.uid() = id);

-- 4. Política UPDATE: el usuario puede actualizar su propio perfil
CREATE POLICY "Usuarios pueden actualizar su propio perfil"
  ON perfiles_locales
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- ============================================================================
-- NOTAS
-- ============================================================================
-- Si alguna política ya existe con otro nombre, puede fallar con "already exists".
-- En ese caso, revisá las políticas actuales en:
--   Supabase → Table Editor → perfiles_locales → RLS policies
--
-- Para ver políticas existentes:
--   SELECT * FROM pg_policies WHERE tablename = 'perfiles_locales';
--
-- Para borrar una política (si necesitás reemplazarla):
--   DROP POLICY IF EXISTS "nombre_politica" ON perfiles_locales;
-- ============================================================================
