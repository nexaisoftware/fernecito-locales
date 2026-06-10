-- Perfil de empleado staff + permisos granulares en local_staff
-- Ejecutar en Supabase SQL Editor (o migrar a supabase/migrations/)

-- ── Perfil staff ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS perfiles_staff (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username TEXT UNIQUE,
  nombre TEXT,
  dni TEXT,
  edad INTEGER,
  foto_perfil_url TEXT,
  perfil_completo BOOLEAN NOT NULL DEFAULT FALSE,
  fecha_creacion TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  fecha_actualizacion TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_perfiles_staff_username ON perfiles_staff (LOWER(username));

ALTER TABLE perfiles_staff ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "staff_lee_su_perfil" ON perfiles_staff;
CREATE POLICY "staff_lee_su_perfil" ON perfiles_staff
  FOR SELECT USING (auth.uid() = id);

DROP POLICY IF EXISTS "staff_edita_su_perfil" ON perfiles_staff;
CREATE POLICY "staff_edita_su_perfil" ON perfiles_staff
  FOR INSERT WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "staff_actualiza_su_perfil" ON perfiles_staff;
CREATE POLICY "staff_actualiza_su_perfil" ON perfiles_staff
  FOR UPDATE USING (auth.uid() = id);

-- Dueño del local puede leer perfiles de su staff (lista empleados)
DROP POLICY IF EXISTS "local_lee_perfiles_staff" ON perfiles_staff;
CREATE POLICY "local_lee_perfiles_staff" ON perfiles_staff
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM local_staff ls
      WHERE ls.id_staff = perfiles_staff.id
        AND ls.id_local = auth.uid()
    )
  );

-- ── Permisos por vínculo staff ↔ local ───────────────────────────────────────
ALTER TABLE local_staff
  ADD COLUMN IF NOT EXISTS habilitado_qr_listas BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS habilitado_qr_promos BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS habilitado_qr_pases BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS habilitado_aceptar_listas BOOLEAN NOT NULL DEFAULT TRUE;

-- Staff puede leer sus vínculos activos
DROP POLICY IF EXISTS "staff_lee_sus_vinculos" ON local_staff;
CREATE POLICY "staff_lee_sus_vinculos" ON local_staff
  FOR SELECT USING (auth.uid() = id_staff);
