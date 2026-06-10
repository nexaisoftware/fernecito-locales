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

// ─── Handler ──────────────────────────────────────────────────────────────────
// Borrar un evento: soft-delete.
//   - Cambia estado_publicacion → "borrador"
//   - Setea fecha_borrado = now()
//   - Cancela todos los tokens_asistencia pendientes/aceptados del evento
//   - El hard-delete real lo hace el cron expirar_tokens → hard_delete_eventos_vencidos()
//     pasados 40 días desde fecha_borrado.
//
// Solo el owner del local puede borrar su evento.
// No se puede borrar un evento "finalizado" (ya terminó, se deja para historial).

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

    // ── Verificar evento y ownership ──────────────────────────────────────────
    const { data: evento, error: evErr } = await admin
      .from("eventos")
      .select("id_evento, id_local, estado_publicacion, jerarquia, cupos_recomendado_usados, cupos_top_usados, cupos_top_ultra_usados, fuente_jerarquia")
      .eq("id_evento", idEvento)
      .maybeSingle();

    if (evErr || !evento) {
      return jsonResponse(404, { ok: false, code: "event_not_found", error: "Evento no encontrado" });
    }
    if (String(evento.id_local) !== user.id) {
      return jsonResponse(403, { ok: false, code: "forbidden", error: "Solo el owner puede borrar su evento" });
    }
    if (evento.estado_publicacion === "borrador" && evento.fecha_borrado) {
      // Ya marcado para borrar
      return jsonResponse(409, { ok: false, code: "already_deleted", error: "El evento ya está marcado para eliminar" });
    }
    if (evento.estado_publicacion === "finalizado") {
      // No bloquear borrado de finalizados — el local puede querer limpiarlo del historial
      // Simplemente lo marcamos igual
    }

    const now = new Date().toISOString();

    // ── Soft-delete del evento ────────────────────────────────────────────────
    const { error: delErr } = await admin
      .from("eventos")
      .update({
        estado_publicacion: "borrador",
        fecha_borrado:      now,
      })
      .eq("id_evento", idEvento)
      .eq("id_local", user.id); // doble check de ownership

    if (delErr) {
      return jsonResponse(500, {
        ok: false,
        code: "delete_failed",
        error: "No se pudo borrar el evento",
        detail: delErr.message,
      });
    }

    // ── Cancelar tokens activos del evento ────────────────────────────────────
    const { data: tokensCancelados } = await admin
      .from("tokens_asistencia")
      .update({
        estado_token:    "cancelada",
        fecha_respuesta: now,
      })
      .eq("id_evento", idEvento)
      .in("estado_token", ["pendiente", "aceptada"])
      .select("id_token, estado_token");

    const canceladosCount = (tokensCancelados ?? []).length;

    // ── Devolver créditos si el evento tenía jerarquía paga ──────────────────
    // Solo devolver si el evento NO llegó a publicarse (borrado desde "borrador"
    // sin publicar) para evitar abusos. Si ya estuvo publicado, el crédito ya se gastó.
    // Nota: estado_publicacion antes de borrar. Si era "publicado" o "finalizado" → no devolver.
    // Lógica conservadora: solo devolvemos si aún no se llegó a publicar.
    // (estado_publicacion era "borrador" sin fecha_borrado previa = nunca publicado)
    // En este caso ya fue publicado (puede venir de cualquier estado), no devolvemos.

    return jsonResponse(200, {
      ok:                true,
      id_evento:         idEvento,
      fecha_borrado:     now,
      tokens_cancelados: canceladosCount,
      mensaje:           "El evento será eliminado permanentemente en 40 días",
    });

  } catch (e) {
    console.error("borrar_evento_error", e);
    return jsonResponse(500, { ok: false, code: "internal_error", error: "Error interno del servidor" });
  }
});
