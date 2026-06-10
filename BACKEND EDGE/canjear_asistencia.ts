import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });
const isObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);

// Canje / rechazo de token de asistencia en puerta (app Locales).
//
// Body que envía la app (locales_qr_validar → ServicioEdgesEventos):
//   codigo_puerta  — 8 chars
//   id_local       — UUID del local
//   id_evento      — UUID del evento (recomendado, evita ambigüedad)
//   accion         — "validar" | "rechazar" (default: validar)
//
// Compat legacy (QR completo del usuario):
//   uid_usuario + codigo_puerta + id_evento + id_local

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, code: "method_not_allowed", error: "Metodo no permitido" });
  }

  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!url || !anon || !service) {
      return jsonResponse(500, { ok: false, code: "server_config_missing", error: "Configuracion incompleta" });
    }

    const header = (req.headers.get("Authorization") ?? "").trim();
    if (!header) {
      return jsonResponse(401, { ok: false, code: "missing_authorization", error: "Authorization requerido" });
    }

    const auth = createClient(url, anon, { global: { headers: { Authorization: header } } });
    const { data: { user }, error: authError } = await auth.auth.getUser();
    if (authError || !user) {
      return jsonResponse(401, { ok: false, code: "invalid_jwt", error: "No autenticado", detail: authError?.message });
    }

    const admin = createClient(url, service);
    const body = await req.json().catch(() => null);
    if (!isObject(body)) {
      return jsonResponse(400, { ok: false, code: "invalid_body", error: "Body invalido" });
    }

    const accion = String(body["accion"] ?? "validar").trim().toLowerCase();
    if (accion !== "validar" && accion !== "rechazar") {
      return jsonResponse(400, { ok: false, code: "invalid_accion", error: "accion debe ser 'validar' o 'rechazar'" });
    }

    const codigoPuerta = String(body["codigo_puerta"] ?? body["clave_ingreso"] ?? "").trim().toUpperCase();
    const idLocalBody = String(body["id_local"] ?? "").trim();
    const idEventoBody = String(body["id_evento"] ?? "").trim();
    const uidUsuario = String(body["uid_usuario"] ?? "").trim();

    if (!codigoPuerta) {
      return jsonResponse(400, { ok: false, code: "missing_clave", error: "codigo_puerta requerido" });
    }
    if (!idLocalBody) {
      return jsonResponse(400, { ok: false, code: "missing_local", error: "id_local requerido" });
    }

    // ── Rate limiting (fail-open: si la RPC falla, deja pasar) ────────────────
    // Por user: 300 req/min (bouncer real hace ~5/min → 60x más holgado).
    // Por código: 5 intentos del mismo codigo_puerta en 30s (anti brute-force).
    try {
      const { data: rlUser, error: rlErr } = await admin.rpc("check_rate_limit", {
        p_edge: "canjear_asistencia",
        p_identifier: `user:${user.id}`,
        p_user_id: user.id,
        p_max: 300,
        p_ventana_segs: 60,
      });
      if (rlErr) {
        console.error("rate_limit_rpc_failed", { edge: "canjear_asistencia", scope: "user", error: rlErr.message });
      } else if (rlUser === false) {
        return jsonResponse(429, { ok: false, code: "rate_limit_exceeded", error: "Demasiados intentos, esperá un instante y reintentá." });
      }
      const { data: rlCodigo, error: rlCodErr } = await admin.rpc("check_rate_limit", {
        p_edge: "canjear_asistencia",
        p_identifier: `code:${codigoPuerta}`,
        p_user_id: user.id,
        p_max: 5,
        p_ventana_segs: 30,
      });
      if (rlCodErr) {
        console.error("rate_limit_rpc_failed", { edge: "canjear_asistencia", scope: "code", error: rlCodErr.message });
      } else if (rlCodigo === false) {
        return jsonResponse(429, { ok: false, code: "rate_limit_code", error: "Este código fue intentado demasiadas veces. Esperá 30s." });
      }
    } catch (rlException) {
      console.error("rate_limit_exception", { edge: "canjear_asistencia", error: String(rlException) });
    }

    // ── Buscar token ─────────────────────────────────────────────────────────
    let tokenQuery = admin
      .from("tokens_asistencia")
      .select("id_token, id_evento, id_usuario, estado_token, fecha_expiracion, snapshot_squad")
      .eq("codigo_puerta", codigoPuerta);

    if (idEventoBody) tokenQuery = tokenQuery.eq("id_evento", idEventoBody);
    if (uidUsuario) tokenQuery = tokenQuery.eq("id_usuario", uidUsuario);

    const { data: token, error: tokErr } = await tokenQuery.maybeSingle();

    if (tokErr) {
      return jsonResponse(500, {
        ok: false,
        code: "token_query_failed",
        error: "Error al buscar el token",
        detail: tokErr.message,
      });
    }
    if (!token) {
      if (idEventoBody) {
        const { data: otroEvento } = await admin
          .from("tokens_asistencia")
          .select("id_evento")
          .eq("codigo_puerta", codigoPuerta)
          .neq("id_evento", idEventoBody)
          .limit(1)
          .maybeSingle();
        if (otroEvento) {
          return jsonResponse(403, {
            ok: false,
            code: "wrong_event",
            error: "Este pase pertenece a otro evento",
          });
        }
      }
      return jsonResponse(404, {
        ok: false,
        code: "token_not_found",
        error: "No se encontró un pase con ese código",
      });
    }

    if (idEventoBody && String(token.id_evento) !== idEventoBody) {
      return jsonResponse(403, {
        ok: false,
        code: "wrong_event",
        error: "Este pase pertenece a otro evento",
      });
    }

    // ── Evento + ventana de canje ────────────────────────────────────────────
    const { data: evento, error: evErr } = await admin
      .from("eventos")
      .select("id_local, titulo_evento, fecha_inicio, fecha_fin, hora_limite_canje")
      .eq("id_evento", token.id_evento)
      .maybeSingle();

    if (evErr || !evento) {
      return jsonResponse(404, { ok: false, code: "event_not_found", error: "Evento no encontrado" });
    }

    if (idLocalBody !== String(evento.id_local)) {
      return jsonResponse(403, {
        ok: false,
        code: "invalid_local_target",
        error: "id_local no coincide con el evento del pase",
      });
    }

    const esOwner = String(evento.id_local) === user.id;
    let esStaff = false;
    let staffPermisos: { habilitado_qr_pases?: boolean } | null = null;
    if (!esOwner) {
      const { data: staff } = await admin
        .from("local_staff")
        .select("id_staff, habilitado_qr_pases")
        .eq("id_local", evento.id_local)
        .eq("id_staff", user.id)
        .eq("activo", true)
        .maybeSingle();
      esStaff = !!staff;
      staffPermisos = staff;
    }
    if (!esOwner && !esStaff) {
      return jsonResponse(403, { ok: false, code: "forbidden_actor", error: "No autorizado para canjear" });
    }
    // Chequeo de permiso granular: staff sin habilitado_qr_pases no canjea pases
    if (esStaff && staffPermisos?.habilitado_qr_pases === false) {
      return jsonResponse(403, {
        ok: false,
        code: "permission_denied",
        error: "No tenés permiso para canjear pases en este local",
      });
    }

    const now = Date.now();
    if (evento.hora_limite_canje) {
      if (now > new Date(evento.hora_limite_canje).getTime()) {
        return jsonResponse(400, {
          ok: false,
          code: "canje_expired",
          error: "El tiempo límite para canjear este evento ya pasó",
        });
      }
    } else {
      const limiteDefault = new Date(evento.fecha_fin).getTime() + 3 * 60 * 60 * 1000;
      if (now > limiteDefault) {
        return jsonResponse(400, {
          ok: false,
          code: "canje_expired",
          error: "El tiempo límite para canjear este evento ya pasó",
        });
      }
    }

    // ── Estado del token ─────────────────────────────────────────────────────
    if (token.estado_token === "canjeada") {
      return jsonResponse(409, { ok: false, code: "already_canjeado", error: "Este token ya fue canjeado" });
    }
    if (token.estado_token === "rechazada") {
      return jsonResponse(409, { ok: false, code: "already_rechazado", error: "Este token fue rechazado" });
    }
    if (token.estado_token === "expirada" || token.estado_token === "cancelada") {
      return jsonResponse(409, {
        ok: false,
        code: "invalid_state",
        error: `Estado inválido: ${token.estado_token}`,
      });
    }
    if (token.estado_token !== "aceptada") {
      return jsonResponse(409, {
        ok: false,
        code: "invalid_state",
        error: `Solo se pueden canjear pases aceptados (estado: ${token.estado_token})`,
      });
    }

    if (new Date(token.fecha_expiracion).getTime() < now) {
      return jsonResponse(409, { ok: false, code: "expired_token", error: "El token está expirado" });
    }

    const fechaAccion = new Date().toISOString();
    const estadoFinal = accion === "rechazar" ? "rechazada" : "canjeada";

    const { error: upErr } = await admin
      .from("tokens_asistencia")
      .update({
        estado_token: estadoFinal,
        canjeado_por: user.id,
        ...(accion === "validar" ? { fecha_canje: fechaAccion } : {}),
      })
      .eq("id_token", token.id_token)
      .eq("estado_token", "aceptada");

    if (upErr) {
      return jsonResponse(400, {
        ok: false,
        code: "update_failed",
        error: "No se pudo actualizar el token",
        detail: upErr.message,
      });
    }

    if (accion === "validar") {
      await admin.rpc("increment_metric", {
        p_id_evento: token.id_evento,
        p_campo: "metric_canjeos",
        p_delta: 1,
      }).catch(() => {});
    }

    // Enriquecer respuesta (no crítico): si falla, igual devolvemos 200 porque el UPDATE ya aplicó.
    let miembros: string[] = [];
    let cantidadPersonas = 1;
    let perfil: Record<string, unknown> | null = null;
    try {
      const snap = token.snapshot_squad;
      if (isObject(snap) && Array.isArray(snap["miembros"])) {
        const uids = (snap["miembros"] as unknown[])
          .map((m) => (typeof m === "string" ? m : ""))
          .filter(Boolean);
        const cantRaw = snap["cantidad"];
        cantidadPersonas =
          typeof cantRaw === "number" && cantRaw > 0 ? cantRaw : uids.length > 0 ? uids.length : 1;
        if (uids.length > 0) {
          const { data: perfilesSquad } = await admin
            .from("perfiles_usuarios")
            .select("id, nombre, username")
            .in("id", uids);
          const porId = new Map<string, string>();
          for (const p of perfilesSquad ?? []) {
            const nombre =
              (p.nombre as string | null)?.trim() ||
              (p.username as string | null)?.trim() ||
              "";
            if (p.id && nombre) porId.set(String(p.id), nombre);
          }
          miembros = uids.map((id) => porId.get(id) ?? id);
        }
      }

      const { data: perfilRow } = await admin
        .from("perfiles_usuarios")
        .select("id, nombre, username, foto_perfil_url")
        .eq("id", token.id_usuario)
        .maybeSingle();
      if (perfilRow && isObject(perfilRow)) perfil = perfilRow;
    } catch (postErr) {
      console.warn("canjear_asistencia_post_update", postErr);
    }

    return jsonResponse(200, {
      ok: true,
      accion,
      id_token: token.id_token,
      estado: estadoFinal,
      es_squad: cantidadPersonas > 1 || miembros.length > 1,
      cantidad_personas: cantidadPersonas,
      miembros,
      canjeado_por: user.id,
      fecha_canje: accion === "validar" ? fechaAccion : null,
      usuario: {
        id: token.id_usuario,
        nombre_usuario: (perfil?.nombre as string | null) ?? (perfil?.username as string | null) ?? null,
        nombre: (perfil?.nombre as string | null) ?? null,
        username: (perfil?.username as string | null) ?? null,
        foto_perfil_url: (perfil?.foto_perfil_url as string | null) ?? null,
      },
      evento: {
        id_evento: token.id_evento,
        titulo_evento: evento.titulo_evento,
        fecha_inicio: evento.fecha_inicio,
        fecha_fin: evento.fecha_fin,
      },
    });
  } catch (e) {
    const detalle = e instanceof Error ? `${e.name}: ${e.message}` : String(e);
    console.error("canjear_asistencia_error", detalle, e);
    return jsonResponse(500, {
      ok: false,
      code: "internal_error",
      error: "Error interno del servidor",
      detail: detalle,
    });
  }
});
