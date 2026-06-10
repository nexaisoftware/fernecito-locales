import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), { status, headers: jsonHeaders });
const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const tokenCodigo = () => crypto.randomUUID().replaceAll("-", "").slice(0, 12).toUpperCase();

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { ok: false, code: "method_not_allowed", error: "Metodo no permitido" });

  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!url || !anon || !service) return jsonResponse(500, { ok: false, code: "server_config_missing", error: "Configuracion incompleta" });

    const header = (req.headers.get("Authorization") ?? "").trim();
    if (!header) return jsonResponse(401, { ok: false, code: "missing_authorization", error: "Authorization requerido" });

    const auth = createClient(url, anon, { global: { headers: { Authorization: header } } });
    const { data: { user }, error: authError } = await auth.auth.getUser();
    if (authError || !user) return jsonResponse(401, { ok: false, code: "invalid_jwt", error: "No autenticado", detail: authError?.message });

    const admin = createClient(url, service);
    const body = await req.json().catch(() => null);
    if (!isObject(body)) return jsonResponse(400, { ok: false, code: "invalid_body", error: "Body invalido" });

    const idPromocion = String(body["id_promocion"] ?? "");
    const idGrupo = String(body["id_grupo"] ?? "").trim() || null;
    if (!idPromocion) return jsonResponse(400, { ok: false, code: "missing_id_promocion", error: "id_promocion requerido" });

    const { data: promo, error: promoErr } = await admin
      .from("promociones")
      .select("id_promocion, id_evento, fecha_inicio, fecha_fin, cupos_totales, cupos_usados, modo_uso, min_miembros_squad, max_miembros_squad, estado_promocion")
      .eq("id_promocion", idPromocion)
      .maybeSingle();
    if (promoErr || !promo) return jsonResponse(404, { ok: false, code: "promo_not_found", error: "Promocion no encontrada" });
    if (promo.estado_promocion !== "activa") return jsonResponse(400, { ok: false, code: "promo_inactive", error: "La promocion no esta activa" });

    const now = Date.now();
    // Reserva: permitida con lista aceptada/canjeada hasta fecha_fin (sin bloquear por fecha_inicio).
    if (new Date(promo.fecha_fin).getTime() < now) {
      return jsonResponse(400, { ok: false, code: "promo_expired", error: "La promo ya finalizo" });
    }

    let miembros: string[] = [user.id];
    let idReservaGrupal: string | null = null;
    let snapshotSquad: Record<string, unknown> | null = null;
    if (idGrupo) {
      if (promo.modo_uso !== "squad") return jsonResponse(400, { ok: false, code: "promo_not_squad", error: "La promo no permite squad" });
      const { data: pertenencia } = await admin
        .from("miembros_grupos")
        .select("id_miembro")
        .eq("id_grupo", idGrupo)
        .eq("id_miembro", user.id)
        .eq("estado_miembro", "aceptado")
        .maybeSingle();
      if (!pertenencia) return jsonResponse(403, { ok: false, code: "not_group_member", error: "No perteneces al squad" });
      const { data: miembrosRows } = await admin
        .from("miembros_grupos")
        .select("id_miembro")
        .eq("id_grupo", idGrupo)
        .eq("estado_miembro", "aceptado");
      miembros = (miembrosRows ?? []).map((m) => String(m.id_miembro));
      if (miembros.length === 0) return jsonResponse(400, { ok: false, code: "group_without_members", error: "El squad no tiene miembros aceptados" });
      if (promo.min_miembros_squad != null && miembros.length < Number(promo.min_miembros_squad)) {
        return jsonResponse(400, { ok: false, code: "group_too_small", error: "El squad no cumple el minimo para esta promo" });
      }
      if (promo.max_miembros_squad != null && miembros.length > Number(promo.max_miembros_squad)) {
        return jsonResponse(400, { ok: false, code: "group_too_large", error: "El squad supera el maximo para esta promo" });
      }
      idReservaGrupal = crypto.randomUUID();
      snapshotSquad = { id_grupo: idGrupo, miembros };
    }

    const { data: rechazadas } = await admin
      .from("tokens_asistencia")
      .select("id_usuario")
      .eq("id_evento", promo.id_evento)
      .in("id_usuario", miembros)
      .eq("estado_token", "rechazada");
    if ((rechazadas ?? []).length > 0) {
      return jsonResponse(403, { ok: false, code: "attendance_rejected", error: "La lista fue rechazada en el local" });
    }

    const { data: asistenciasOk } = await admin
      .from("tokens_asistencia")
      .select("id_usuario")
      .eq("id_evento", promo.id_evento)
      .in("id_usuario", miembros)
      .in("estado_token", ["aceptada", "canjeada"]);
    if ((asistenciasOk ?? []).length !== miembros.length) {
      return jsonResponse(403, { ok: false, code: "attendance_required", error: "Todos los miembros deben tener lista aceptada en el evento" });
    }

    const { data: existentes } = await admin
      .from("tokens_promociones")
      .select("id_token")
      .eq("id_promocion", idPromocion)
      .in("id_usuario", miembros)
      .eq("estado_token", "activo");
    if (existentes && existentes.length > 0) {
      return jsonResponse(409, { ok: false, code: "promo_already_reserved", error: "Ya existe una reserva activa para esta promo" });
    }

    const cuposTotales = promo.cupos_totales == null ? null : Number(promo.cupos_totales);
    const cuposUsados = Number(promo.cupos_usados ?? 0);
    if (cuposTotales != null && cuposUsados + miembros.length > cuposTotales) {
      return jsonResponse(409, { ok: false, code: "promo_full", error: "No hay cupos suficientes en la promo" });
    }

    const expira = new Date(promo.fecha_fin).toISOString();
    const rows = miembros.map((idUsuario) => ({
      id_promocion: idPromocion,
      id_usuario: idUsuario,
      id_grupo: idGrupo,
      id_reserva_grupal: idReservaGrupal,
      token_codigo: tokenCodigo(),
      estado_token: "activo",
      fecha_expiracion: expira,
      snapshot_squad: snapshotSquad,
    }));

    const { error: insErr } = await admin.from("tokens_promociones").insert(rows);
    if (insErr) return jsonResponse(400, { ok: false, code: "insert_failed", error: "No se pudo reservar promo", detail: insErr.message });

    if (cuposTotales != null) {
      const { error: upErr } = await admin
        .from("promociones")
        .update({
          cupos_usados: cuposUsados + rows.length,
          fecha_actualizacion: new Date().toISOString(),
        })
        .eq("id_promocion", idPromocion);
      if (upErr) return jsonResponse(400, { ok: false, code: "counter_update_failed", error: "No se pudo actualizar cupos", detail: upErr.message });
    }

    return jsonResponse(200, { ok: true, id_reserva_grupal: idReservaGrupal, cantidad_tokens: rows.length });
  } catch (e) {
    console.error("reservar_promocion_error", e);
    return jsonResponse(500, { ok: false, code: "internal_error", error: "Error interno del servidor" });
  }
});
