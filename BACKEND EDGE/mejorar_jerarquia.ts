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

// Orden de jerarquias: menor -> mayor
const JERARQUIA_ORDEN: Record<string, number> = {
  gratis: 0,
  normal: 1,
  recomendado_fernecito: 2,
  top: 3,
  top_ultra: 4,
};

// Solo estas jerarquias consumen creditos para posicionamiento
const CREDITO_POR_NIVEL: Record<string, "cupos_recomendado" | "cupos_top_cartelera" | "cupos_top_ultra"> = {
  recomendado_fernecito: "cupos_recomendado",
  top: "cupos_top_cartelera",
  top_ultra: "cupos_top_ultra",
};

// Duración del boost según nivel: top/top_ultra → 10 días, recomendado_fernecito → 15 días.
// Siempre acotado por la fecha_fin del evento (lo que pase primero). Si el evento
// termina antes que el límite del boost, el boost muere con el evento.
const DIAS_BOOST_POR_JERARQUIA: Record<string, number> = {
  recomendado_fernecito: 15,
  top: 10,
  top_ultra: 10,
};

function calcFechaFinJerarquia(fechaFinEventoRaw: unknown, jerarquia: string): string {
  const dias = DIAS_BOOST_POR_JERARQUIA[jerarquia] ?? 10;
  const ahora = new Date();
  const limiteBoost = new Date(ahora.getTime() + dias * 24 * 60 * 60 * 1000);

  if (!fechaFinEventoRaw) return limiteBoost.toISOString();

  const fechaFinEvento = new Date(String(fechaFinEventoRaw));
  if (Number.isNaN(fechaFinEvento.getTime())) return limiteBoost.toISOString();

  return (fechaFinEvento.getTime() < limiteBoost.getTime() ? fechaFinEvento : limiteBoost).toISOString();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, code: "method_not_allowed", error: "Metodo no permitido" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return jsonResponse(500, { ok: false, code: "server_config_missing", error: "Configuracion incompleta" });
    }

    const authHeader = authorizationHeader(req);
    if (!authHeader) {
      return jsonResponse(401, { ok: false, code: "missing_authorization", error: "Authorization requerido" });
    }

    // Cliente autenticado por JWT del local
    const authClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: authData, error: authError } = await authClient.auth.getUser();
    if (authError || !authData.user) {
      return jsonResponse(401, {
        ok: false,
        code: "invalid_jwt",
        error: "No autenticado",
        detail: authError?.message,
      });
    }

    const user = authData.user;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(400, { ok: false, code: "invalid_json", error: "JSON invalido" });
    }

    if (!isPlainObject(body)) {
      return jsonResponse(400, { ok: false, code: "invalid_body", error: "Body invalido" });
    }

    const idEvento = String(body.id_evento ?? "").trim();
    const jerarquiaDestino = String(body.jerarquia_destino ?? "").trim();

    if (!idEvento) {
      return jsonResponse(400, { ok: false, code: "missing_id_evento", error: "id_evento requerido" });
    }
    if (!jerarquiaDestino) {
      return jsonResponse(400, {
        ok: false,
        code: "missing_jerarquia_destino",
        error: "jerarquia_destino requerido",
      });
    }

    if (!(jerarquiaDestino in JERARQUIA_ORDEN)) {
      return jsonResponse(400, {
        ok: false,
        code: "invalid_jerarquia_destino",
        error: `jerarquia_destino invalida: ${jerarquiaDestino}`,
      });
    }

    if (!(jerarquiaDestino in CREDITO_POR_NIVEL)) {
      return jsonResponse(400, {
        ok: false,
        code: "invalid_target_level",
        error: "Solo se puede posicionar en recomendado_fernecito, top o top_ultra",
      });
    }

    // 1) Verificar evento + ownership
    const { data: evento, error: eventoErr } = await admin
      .from("eventos")
      .select("id_evento, id_local, jerarquia, estado_publicacion, titulo_evento, fecha_fin")
      .eq("id_evento", idEvento)
      .maybeSingle();

    if (eventoErr || !evento) {
      return jsonResponse(404, { ok: false, code: "event_not_found", error: "Evento no encontrado" });
    }

    if (String(evento.id_local) !== user.id) {
      return jsonResponse(403, { ok: false, code: "forbidden", error: "No sos el dueno de este evento" });
    }

    if (String(evento.estado_publicacion) !== "publicado") {
      return jsonResponse(400, {
        ok: false,
        code: "event_not_published",
        error: "Solo se pueden posicionar eventos publicados",
      });
    }

    const jerarquiaActual = String(evento.jerarquia ?? "gratis");
    const nivelActual = JERARQUIA_ORDEN[jerarquiaActual] ?? 0;
    const nivelDestino = JERARQUIA_ORDEN[jerarquiaDestino];

    if (nivelDestino <= nivelActual) {
      return jsonResponse(400, {
        ok: false,
        code: "jerarquia_no_puede_bajar",
        error: `No podes bajar ni mantener jerarquia. Actual: ${jerarquiaActual} -> Destino: ${jerarquiaDestino}`,
      });
    }

    // 2) Verificar creditos del perfil
    const campoCredito = CREDITO_POR_NIVEL[jerarquiaDestino];
    const { data: perfil, error: perfilErr } = await admin
      .from("perfiles_locales")
      .select(`local_verificado, ${campoCredito}`)
      .eq("id", user.id)
      .maybeSingle();

    if (perfilErr || !perfil) {
      return jsonResponse(404, {
        ok: false,
        code: "profile_not_found",
        error: "Perfil de local no encontrado",
      });
    }

    if (perfil.local_verificado !== true) {
      return jsonResponse(403, {
        ok: false,
        code: "local_not_verified",
        error: "Necesitas ser local verificado para posicionar eventos",
      });
    }

    const creditosDisponibles = Number(perfil[campoCredito] ?? 0);
    if (!Number.isFinite(creditosDisponibles) || creditosDisponibles <= 0) {
      return jsonResponse(400, {
        ok: false,
        code: "sin_creditos",
        error: `Sin creditos disponibles para ${jerarquiaDestino}. Tenes: ${creditosDisponibles}`,
      });
    }

    // 3) Descontar credito (CAS para concurrencia)
    const { data: perfilActualizado, error: creditoErr } = await admin
      .from("perfiles_locales")
      .update({ [campoCredito]: creditosDisponibles - 1 })
      .eq("id", user.id)
      .eq(campoCredito, creditosDisponibles)
      .select(campoCredito)
      .maybeSingle();

    if (creditoErr || !perfilActualizado) {
      return jsonResponse(409, {
        ok: false,
        code: "credito_concurrencia",
        error: "No se pudo descontar el credito. Puede que otro proceso lo usara al mismo tiempo. Reintenta.",
      });
    }

    // 4) Actualizar jerarquia (doble CAS con jerarquia actual)
    const fechaFinJerarquia = calcFechaFinJerarquia(evento.fecha_fin, jerarquiaDestino);

    const { data: eventoActualizado, error: eventoUpdErr } = await admin
      .from("eventos")
      .update({
        jerarquia: jerarquiaDestino,
        fecha_fin_jerarquia: fechaFinJerarquia,
      })
      .eq("id_evento", idEvento)
      .eq("id_local", user.id)
      .eq("jerarquia", jerarquiaActual)
      .select("id_evento")
      .maybeSingle();

    if (eventoUpdErr || !eventoActualizado) {
      // rollback de credito (CAS para no pisar cambios externos)
      await admin
        .from("perfiles_locales")
        .update({ [campoCredito]: creditosDisponibles })
        .eq("id", user.id)
        .eq(campoCredito, creditosDisponibles - 1);

      return jsonResponse(409, {
        ok: false,
        code: "event_update_conflict",
        error: "No se pudo actualizar la jerarquia del evento. El credito fue restaurado.",
      });
    }

    return jsonResponse(200, {
      ok: true,
      id_evento: idEvento,
      titulo_evento: String(evento.titulo_evento ?? ""),
      jerarquia_anterior: jerarquiaActual,
      jerarquia_nueva: jerarquiaDestino,
      campo_credito: campoCredito,
      creditos_restantes: creditosDisponibles - 1,
      fecha_fin_jerarquia: fechaFinJerarquia,
    });
  } catch (error) {
    console.error("mejorar_jerarquia_error", error);
    return jsonResponse(500, {
      ok: false,
      code: "internal_error",
      error: "Error interno del servidor",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
});
