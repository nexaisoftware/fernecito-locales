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

// Canje / cancelación de token de promoción en puerta (app Locales).
//
// Body de la app:
//   token_codigo — 12 chars
//   id_local
//   accion       — "validar" | "rechazar" (rechazar → estado_token "cancelado")

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

    const codigo = String(body["token_codigo"] ?? "").trim().toUpperCase();
    const idLocalBody = String(body["id_local"] ?? "").trim();
    const idEventoBody = String(body["id_evento"] ?? "").trim();
    if (!codigo) {
      return jsonResponse(400, { ok: false, code: "missing_codigo", error: "token_codigo requerido" });
    }
    if (!idLocalBody) {
      return jsonResponse(400, { ok: false, code: "missing_local", error: "id_local requerido" });
    }
    if (!idEventoBody) {
      return jsonResponse(400, { ok: false, code: "missing_event", error: "id_evento requerido" });
    }

    // ── Rate limiting (fail-open: si la RPC falla, deja pasar) ────────────────
    try {
      const { data: rlUser, error: rlErr } = await admin.rpc("check_rate_limit", {
        p_edge: "canjear_promocion",
        p_identifier: `user:${user.id}`,
        p_user_id: user.id,
        p_max: 300,
        p_ventana_segs: 60,
      });
      if (rlErr) {
        console.error("rate_limit_rpc_failed", { edge: "canjear_promocion", scope: "user", error: rlErr.message });
      } else if (rlUser === false) {
        return jsonResponse(429, { ok: false, code: "rate_limit_exceeded", error: "Demasiados intentos, esperá un instante y reintentá." });
      }
      const { data: rlCodigo, error: rlCodErr } = await admin.rpc("check_rate_limit", {
        p_edge: "canjear_promocion",
        p_identifier: `code:${codigo}`,
        p_user_id: user.id,
        p_max: 5,
        p_ventana_segs: 30,
      });
      if (rlCodErr) {
        console.error("rate_limit_rpc_failed", { edge: "canjear_promocion", scope: "code", error: rlCodErr.message });
      } else if (rlCodigo === false) {
        return jsonResponse(429, { ok: false, code: "rate_limit_code", error: "Este código fue intentado demasiadas veces. Esperá 30s." });
      }
    } catch (rlException) {
      console.error("rate_limit_exception", { edge: "canjear_promocion", error: String(rlException) });
    }

    const { data: token, error: tokErr } = await admin
      .from("tokens_promociones")
      .select("id_token, id_promocion, id_usuario, estado_token, fecha_expiracion")
      .eq("token_codigo", codigo)
      .maybeSingle();

    if (tokErr || !token) {
      return jsonResponse(404, { ok: false, code: "token_not_found", error: "Token de promoción no encontrado" });
    }

    const { data: promo } = await admin
      .from("promociones")
      .select("id_promocion, id_local, id_evento, titulo_promocion, descripcion_promocion, fecha_inicio, fecha_fin")
      .eq("id_promocion", token.id_promocion)
      .maybeSingle();

    if (!promo) {
      return jsonResponse(404, { ok: false, code: "promo_not_found", error: "Promoción no encontrada" });
    }

    if (idLocalBody !== String(promo.id_local)) {
      return jsonResponse(403, {
        ok: false,
        code: "invalid_local_target",
        error: "id_local no coincide con la promoción",
      });
    }

    const idEventoPromo = promo.id_evento ? String(promo.id_evento) : "";
    if (idEventoPromo) {
      if (idEventoPromo !== idEventoBody) {
        return jsonResponse(403, {
          ok: false,
          code: "wrong_event",
          error: "Esta promo no corresponde al evento que estás validando",
        });
      }
    }

    const esOwner = String(promo.id_local) === user.id;
    let esStaff = false;
    let staffPermisos: { habilitado_qr_promos?: boolean } | null = null;
    if (!esOwner) {
      const { data: staff } = await admin
        .from("local_staff")
        .select("id_staff, habilitado_qr_promos")
        .eq("id_local", promo.id_local)
        .eq("id_staff", user.id)
        .eq("activo", true)
        .maybeSingle();
      esStaff = !!staff;
      staffPermisos = staff;
    }
    if (!esOwner && !esStaff) {
      return jsonResponse(403, { ok: false, code: "forbidden_actor", error: "No autorizado para canjear" });
    }
    // Chequeo de permiso granular: staff sin habilitado_qr_promos no canjea promos
    if (esStaff && staffPermisos?.habilitado_qr_promos === false) {
      return jsonResponse(403, {
        ok: false,
        code: "permission_denied",
        error: "No tenés permiso para canjear promociones en este local",
      });
    }

    if (token.estado_token === "canjeado") {
      return jsonResponse(409, { ok: false, code: "already_canjeado", error: "Este token ya fue canjeado" });
    }
    if (token.estado_token === "cancelado") {
      return jsonResponse(409, { ok: false, code: "already_cancelado", error: "Este token fue cancelado" });
    }
    if (token.estado_token !== "activo") {
      return jsonResponse(409, {
        ok: false,
        code: "invalid_state",
        error: `Estado inválido: ${token.estado_token}`,
      });
    }

    const now = Date.now();
    if (new Date(token.fecha_expiracion).getTime() < now) {
      return jsonResponse(409, { ok: false, code: "expired_token", error: "El token está expirado" });
    }
    // Canje en puerta: no bloquear por fecha_inicio (local + evento ya validados arriba).
    if (new Date(promo.fecha_fin).getTime() < now) {
      return jsonResponse(409, { ok: false, code: "too_late", error: "La promo ya finalizó" });
    }

    const fechaAccion = new Date().toISOString();
    // Schema: activo | canjeado | expirado | cancelado (no existe "rechazado")
    const estadoFinal = accion === "rechazar" ? "cancelado" : "canjeado";

    const { error: upErr } = await admin
      .from("tokens_promociones")
      .update({
        estado_token: estadoFinal,
        canjeado_por: user.id,
        ...(accion === "validar" ? { fecha_canje: fechaAccion } : {}),
      })
      .eq("id_token", token.id_token)
      .eq("estado_token", "activo");

    if (upErr) {
      return jsonResponse(400, {
        ok: false,
        code: "update_failed",
        error: "No se pudo actualizar el token",
        detail: upErr.message,
      });
    }

    const { data: perfil } = await admin
      .from("perfiles_usuarios")
      .select("id, nombre, username, foto_perfil_url")
      .eq("id", token.id_usuario)
      .maybeSingle();

    let eventoTitulo: string | null = null;
    if (promo.id_evento) {
      const { data: ev } = await admin
        .from("eventos")
        .select("titulo_evento")
        .eq("id_evento", promo.id_evento)
        .maybeSingle();
      eventoTitulo = ev?.titulo_evento ?? null;
    }

    return jsonResponse(200, {
      ok: true,
      accion,
      id_token: token.id_token,
      estado: estadoFinal,
      usuario: {
        id: token.id_usuario,
        nombre_usuario: perfil?.nombre ?? perfil?.username ?? null,
        nombre: perfil?.nombre ?? null,
        username: perfil?.username ?? null,
        foto_perfil_url: perfil?.foto_perfil_url ?? null,
      },
      promo: {
        id_promocion: promo.id_promocion,
        titulo_promocion: promo.titulo_promocion ?? promo.descripcion_promocion ?? null,
        fecha_fin: promo.fecha_fin,
      },
      evento: {
        id_evento: promo.id_evento ?? null,
        titulo_evento: eventoTitulo,
      },
    });
  } catch (e) {
    const detalle = e instanceof Error ? `${e.name}: ${e.message}` : String(e);
    console.error("canjear_promocion_error", detalle, e);
    return jsonResponse(500, {
      ok: false,
      code: "internal_error",
      error: "Error interno del servidor",
      detail: detalle,
    });
  }
});
