import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });
const isPlainObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const authorizationHeader = (req: Request) =>
  (req.headers.get("Authorization") ?? "").trim();

// ─── Campos editables ─────────────────────────────────────────────────────────
// Solo se editan campos no-críticos. La jerarquía no se puede cambiar post-publi.
// No se puede cambiar id_local, id_evento, ni campos de créditos/cuotas.
const CAMPOS_EDITABLES = new Set([
  "titulo_evento",
  "descripcion_evento",
  "fecha_inicio",
  "fecha_fin",
  "hora_limite_canje",
  "cupo_lista_max",     // nullable = sin límite
  "modo_lista",         // "auto" | "manual"
  "permite_squads",
  "edad_minima",
  "ciudad_evento",
  "provincia_evento",
  "url_flyer",
  "precio_entrada",
  "dresscode",
  "lineup",
  "sponsors",
  "estado_publicacion", // solo para publicar/despublicar (borrador → publicado o viceversa)
]);

type ModoLista = "auto" | "manual";

function esModoLista(v: unknown): v is ModoLista {
  return v === "auto" || v === "manual";
}

// ─── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, code: "method_not_allowed", error: "Metodo no permitido" });
  }

  try {
    const url     = Deno.env.get("SUPABASE_URL") ?? "";
    const anon    = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!url || !anon || !service) {
      return jsonResponse(500, { ok: false, code: "server_config_missing", error: "Configuracion incompleta" });
    }

    const header = authorizationHeader(req);
    if (!header) {
      return jsonResponse(401, { ok: false, code: "missing_authorization", error: "Authorization requerido" });
    }

    const auth = createClient(url, anon, { global: { headers: { Authorization: header } } });
    const { data: { user }, error: authError } = await auth.auth.getUser();
    if (authError || !user) {
      return jsonResponse(401, { ok: false, code: "invalid_jwt", error: "No autenticado", detail: authError?.message });
    }

    const admin = createClient(url, service);

    const bodyRaw = await req.json().catch(() => null);
    if (!isPlainObject(bodyRaw)) {
      return jsonResponse(400, { ok: false, code: "invalid_body", error: "Body invalido" });
    }

    const idEvento = String(bodyRaw["id_evento"] ?? "").trim();
    if (!idEvento) {
      return jsonResponse(400, { ok: false, code: "missing_id_evento", error: "id_evento requerido" });
    }

    // ── Verificar ownership ───────────────────────────────────────────────────
    const { data: evento, error: evErr } = await admin
      .from("eventos")
      .select("id_local, estado_publicacion, jerarquia, fecha_inicio, fecha_fin, modo_lista, fecha_borrado")
      .eq("id_evento", idEvento)
      .maybeSingle();

    if (evErr || !evento) {
      return jsonResponse(404, { ok: false, code: "event_not_found", error: "Evento no encontrado" });
    }
    if (String(evento.id_local) !== user.id) {
      return jsonResponse(403, { ok: false, code: "forbidden", error: "Solo el owner puede editar su evento" });
    }
    // finalizado = no editable. borrador con fecha_borrado = ya borrado.
    // cancelado SÍ es editable (solo para volver a publicar).
    if (evento.estado_publicacion === "finalizado") {
      return jsonResponse(400, {
        ok: false,
        code: "event_not_editable",
        error: "No se puede editar un evento finalizado",
      });
    }
    if (evento.estado_publicacion === "borrador" && evento.fecha_borrado) {
      return jsonResponse(400, {
        ok: false,
        code: "event_deleted",
        error: "El evento fue eliminado y no puede editarse",
      });
    }

    // ── Construir patch validado ──────────────────────────────────────────────
    const patch: Record<string, unknown> = {};

    for (const [key, value] of Object.entries(bodyRaw)) {
      if (key === "id_evento") continue; // ya lo usamos
      if (!CAMPOS_EDITABLES.has(key)) continue; // ignorar campos no editables

      // Validaciones específicas
      if (key === "modo_lista") {
        if (!esModoLista(value)) {
          return jsonResponse(400, {
            ok: false,
            code: "invalid_modo_lista",
            error: "modo_lista debe ser 'auto' o 'manual'",
          });
        }
        patch[key] = value;
        continue;
      }

      if (key === "cupo_lista_max") {
        // null = sin límite; número positivo = límite
        if (value === null || value === undefined) {
          patch[key] = null;
        } else {
          const n = Number(value);
          if (!Number.isInteger(n) || n < 1) {
            return jsonResponse(400, {
              ok: false,
              code: "invalid_cupo_lista_max",
              error: "cupo_lista_max debe ser un entero positivo o null",
            });
          }
          patch[key] = n;
        }
        continue;
      }

      if (key === "estado_publicacion") {
        // Permite: publicado (re-publicar un cancelado), cancelado (despublicar manualmente)
        // No permite bajar a borrador desde publicado ni tocar finalizado.
        const valorEstado = String(value);
        const estadosPermitidos = ["publicado", "cancelado"];
        if (!estadosPermitidos.includes(valorEstado)) {
          return jsonResponse(400, {
            ok: false,
            code: "invalid_estado_publicacion",
            error: "estado_publicacion solo puede cambiarse a 'publicado' o 'cancelado'",
          });
        }
        // No se puede re-publicar un evento cuya fecha_fin_publicacion ya pasó
        if (valorEstado === "publicado" && evento.estado_publicacion === "cancelado") {
          // Recalcular fecha_fin_publicacion al re-publicar
          const ahora = new Date();
          const treintaDias = new Date(ahora.getTime() + 30 * 24 * 60 * 60 * 1000);
          const fechaFinEvento = evento.fecha_fin ? new Date(String(evento.fecha_fin)) : treintaDias;
          const nuevaFechaFinPub = fechaFinEvento < treintaDias ? fechaFinEvento : treintaDias;
          if (nuevaFechaFinPub < ahora) {
            return jsonResponse(400, {
              ok: false,
              code: "event_expired",
              error: "El evento ya finalizó y no puede volver a publicarse",
            });
          }
          patch["fecha_fin_publicacion"] = nuevaFechaFinPub.toISOString();
        }
        patch[key] = value;
        continue;
      }

      if (key === "fecha_inicio" || key === "fecha_fin") {
        const d = new Date(String(value));
        if (isNaN(d.getTime())) {
          return jsonResponse(400, {
            ok: false,
            code: `invalid_${key}`,
            error: `${key} no es una fecha válida`,
          });
        }
        patch[key] = d.toISOString();
        continue;
      }

      if (key === "hora_limite_canje") {
        if (value === null || value === undefined || value === "") {
          patch[key] = null;
        } else {
          const d = new Date(String(value));
          if (isNaN(d.getTime())) {
            return jsonResponse(400, {
              ok: false,
              code: "invalid_hora_limite_canje",
              error: "hora_limite_canje no es una fecha válida",
            });
          }
          patch[key] = d.toISOString();
        }
        continue;
      }

      if (key === "edad_minima") {
        if (value === null || value === undefined) {
          patch[key] = null;
        } else {
          const n = Number(value);
          if (!Number.isInteger(n) || n < 0 || n > 99) {
            return jsonResponse(400, {
              ok: false,
              code: "invalid_edad_minima",
              error: "edad_minima debe ser un entero entre 0 y 99",
            });
          }
          patch[key] = n;
        }
        continue;
      }

      if (key === "permite_squads") {
        patch[key] = Boolean(value);
        continue;
      }

      if (key === "precio_entrada") {
        if (value === null || value === undefined) {
          patch[key] = null;
        } else {
          const n = Number(value);
          if (isNaN(n) || n < 0) {
            return jsonResponse(400, {
              ok: false,
              code: "invalid_precio_entrada",
              error: "precio_entrada debe ser un número positivo o null",
            });
          }
          patch[key] = n;
        }
        continue;
      }

      // Campos texto: ciudad_evento, provincia_evento, titulo_evento, descripcion_evento,
      //               url_flyer, dresscode, lineup, sponsors
      if (value === null || value === undefined || value === "") {
        patch[key] = null;
      } else {
        patch[key] = String(value).trim();
      }
    }

    if (Object.keys(patch).length === 0) {
      return jsonResponse(400, {
        ok: false,
        code: "no_fields_to_update",
        error: "No hay campos válidos para actualizar",
      });
    }

    // Validar coherencia de fechas si ambas se envían
    const fechaInicio = patch["fecha_inicio"] ?? evento.fecha_inicio;
    const fechaFin    = patch["fecha_fin"];
    if (fechaFin && fechaInicio && new Date(String(fechaFin)) <= new Date(String(fechaInicio))) {
      return jsonResponse(400, {
        ok: false,
        code: "invalid_date_range",
        error: "fecha_fin debe ser posterior a fecha_inicio",
      });
    }

    // ── Aplicar patch ─────────────────────────────────────────────────────────
    patch["fecha_actualizacion"] = new Date().toISOString();

    const { data: updated, error: upErr } = await admin
      .from("eventos")
      .update(patch)
      .eq("id_evento", idEvento)
      .eq("id_local", user.id)
      .select("id_evento, titulo_evento, descripcion_evento, estado_publicacion, modo_lista, cupo_lista_max, ciudad_evento, provincia_evento, hora_limite_canje")
      .single();

    if (upErr || !updated) {
      return jsonResponse(500, {
        ok: false,
        code: "update_failed",
        error: "No se pudo actualizar el evento",
        detail: upErr?.message,
      });
    }

    return jsonResponse(200, {
      ok:      true,
      evento:  updated,
      campos_actualizados: Object.keys(patch).filter((k) => k !== "fecha_actualizacion"),
    });

  } catch (e) {
    console.error("editar_evento_error", e);
    return jsonResponse(500, { ok: false, code: "internal_error", error: "Error interno del servidor" });
  }
});
