-- ============================================================================
-- RLS: permitir que el dueño del local lea perfiles de usuarios que solicitaron
-- lista en sus eventos (necesario para bottom sheets en LocalesValidar / Listas y Pases).
-- ============================================================================
-- PROBLEMA: Si perfiles_usuarios solo permite SELECT de la propia fila,
-- el JOIN embebido y el batch .from('perfiles_usuarios').inFilter('id', ...)
-- devuelven vacío → la app muestra "Usuario", avatar placeholder, "Individual".
--
-- EJECUTAR EN: Supabase Dashboard → SQL Editor
-- ============================================================================

ALTER TABLE perfiles_usuarios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "local_lee_perfiles_solicitantes" ON perfiles_usuarios;
CREATE POLICY "local_lee_perfiles_solicitantes" ON perfiles_usuarios
  FOR SELECT
  TO authenticated
  USING (
    id IN (
      SELECT ta.id_usuario
      FROM tokens_asistencia ta
      INNER JOIN eventos e ON e.id_evento = ta.id_evento
      WHERE e.id_local = auth.uid()
    )
  );

-- Verificar:
-- SELECT policyname, cmd FROM pg_policies WHERE tablename = 'perfiles_usuarios';
