-- Impresiones / alcance: agregados diarios por local, evento y sección.
-- Ejecutar en Supabase SQL Editor (una vez).
-- id_evento usa UUID cero para visitas de perfil (sin evento).

CREATE TABLE IF NOT EXISTS public.impresiones_diarias (
  id BIGSERIAL PRIMARY KEY,
  id_local UUID NOT NULL REFERENCES public.perfiles_locales(id) ON DELETE CASCADE,
  id_evento UUID NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000',
  seccion TEXT NOT NULL,
  fecha DATE NOT NULL DEFAULT (timezone('America/Argentina/Buenos_Aires', now()))::date,
  conteo INTEGER NOT NULL DEFAULT 0 CHECK (conteo >= 0),
  CONSTRAINT impresiones_diarias_conteo_max CHECK (conteo <= 10000000),
  CONSTRAINT impresiones_diarias_uniq UNIQUE (id_local, id_evento, seccion, fecha)
);

CREATE INDEX IF NOT EXISTS idx_impresiones_local_fecha
  ON public.impresiones_diarias (id_local, fecha DESC);

CREATE INDEX IF NOT EXISTS idx_impresiones_evento_fecha
  ON public.impresiones_diarias (id_evento, fecha DESC)
  WHERE id_evento <> '00000000-0000-0000-0000-000000000000';

ALTER TABLE public.impresiones_diarias ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS impresiones_diarias_select_local ON public.impresiones_diarias;
CREATE POLICY impresiones_diarias_select_local
  ON public.impresiones_diarias
  FOR SELECT
  TO authenticated
  USING (id_local = auth.uid());

CREATE OR REPLACE FUNCTION public.registrar_impresiones_batch(p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  item jsonb;
  v_id_local uuid;
  v_id_evento uuid;
  v_seccion text;
  v_delta int;
  v_fecha date;
  v_procesados int := 0;
  v_sentinel uuid := '00000000-0000-0000-0000-000000000000';
  v_secciones_validas text[] := ARRAY[
    'top', 'top_ultra', 'top_ultra_stories',
    'recomendado_fernecito', 'normal', 'gratis',
    'perfil_local', 'click_evento'
  ];
BEGIN
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'procesados', 0);
  END IF;

  v_fecha := (timezone('America/Argentina/Buenos_Aires', now()))::date;

  FOR item IN SELECT value FROM jsonb_array_elements(p_items) AS t(value)
  LOOP
    BEGIN
      v_id_local := NULLIF(trim(item->>'id_local'), '')::uuid;
      v_seccion := lower(trim(COALESCE(item->>'seccion', '')));
      v_delta := COALESCE((item->>'delta')::int, 1);

      IF v_id_local IS NULL THEN CONTINUE; END IF;
      IF v_delta <= 0 OR v_delta > 500 THEN CONTINUE; END IF;
      IF NOT (v_seccion = ANY (v_secciones_validas)) THEN CONTINUE; END IF;

      IF v_seccion = 'perfil_local' THEN
        v_id_evento := v_sentinel;
        IF NOT EXISTS (SELECT 1 FROM perfiles_locales pl WHERE pl.id = v_id_local) THEN
          CONTINUE;
        END IF;
      ELSE
        v_id_evento := NULLIF(trim(item->>'id_evento'), '')::uuid;
        IF v_id_evento IS NULL OR v_id_evento = v_sentinel THEN CONTINUE; END IF;
        IF NOT EXISTS (
          SELECT 1 FROM eventos e
          WHERE e.id_evento = v_id_evento
            AND e.id_local = v_id_local
            AND e.estado_publicacion = 'publicado'
        ) THEN
          CONTINUE;
        END IF;
      END IF;

      INSERT INTO impresiones_diarias (id_local, id_evento, seccion, fecha, conteo)
      VALUES (v_id_local, v_id_evento, v_seccion, v_fecha, v_delta)
      ON CONFLICT (id_local, id_evento, seccion, fecha)
      DO UPDATE SET conteo = LEAST(
        impresiones_diarias.conteo + EXCLUDED.conteo,
        10000000
      );

      IF v_id_evento <> v_sentinel THEN
        UPDATE eventos
        SET metric_visitas = LEAST(COALESCE(metric_visitas, 0) + v_delta, 10000000)
        WHERE id_evento = v_id_evento;
      END IF;

      v_procesados := v_procesados + 1;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'procesados', v_procesados);
END;
$$;

REVOKE ALL ON FUNCTION public.registrar_impresiones_batch(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.registrar_impresiones_batch(jsonb) TO service_role;
