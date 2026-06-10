-- Invitaciones de staff (una clave activa por local, generada por el dueño).
-- Ejecutar en Supabase SQL Editor antes de usar generar_clave_vinculacion.

CREATE TABLE IF NOT EXISTS public.staff_invitaciones_local (
  id_local uuid PRIMARY KEY REFERENCES public.perfiles_locales(id) ON DELETE CASCADE,
  clave_hash text NOT NULL,
  expira_en timestamptz NOT NULL,
  creado_en timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.staff_invitaciones_local ENABLE ROW LEVEL SECURITY;

-- Sin policies públicas: lectura/escritura solo vía service_role en edge gestionar_staff.
