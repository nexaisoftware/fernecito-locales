import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), { status, headers: jsonHeaders });
const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

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

    const idToken = String(body["id_token"] ?? "");
    const idReserva = String(body["id_reserva_grupal"] ?? "");
    if (!idToken && !idReserva) return jsonResponse(400, { ok: false, code: "missing_target", error: "id_token o id_reserva_grupal requerido" });

    let q = admin
      .from("tokens_promociones")
      .select("id_token, id_promocion, id_usuario, estado_token");
    q = idToken ? q.eq("id_token", idToken) : q.eq("id_reserva_grupal", idReserva);
    const { data: tokens, error: tokErr } = await q;
    if (tokErr || !tokens || tokens.length === 0) return jsonResponse(404, { ok: false, code: "token_not_found", error: "Reserva no encontrada" });

    if (tokens.some((t) => String(t.id_usuario) !== user.id)) {
      return jsonResponse(403, { ok: false, code: "forbidden_owner", error: "Solo el titular puede cancelar" });
    }

    const activos = tokens.filter((t) => String(t.estado_token) === "activo");
    if (activos.length === 0) {
      return jsonResponse(409, { ok: false, code: "not_cancelable", error: "No hay promociones activas para cancelar" });
    }

    const ids = activos.map((t) => String(t.id_token));
    const { error: upErr } = await admin.from("tokens_promociones").update({ estado_token: "cancelado" }).in("id_token", ids);
    if (upErr) return jsonResponse(400, { ok: false, code: "cancel_failed", error: "No se pudo cancelar la promocion", detail: upErr.message });

    const porPromo = new Map<string, number>();
    for (const t of activos) {
      const idPromo = String(t.id_promocion);
      porPromo.set(idPromo, (porPromo.get(idPromo) ?? 0) + 1);
    }
    for (const [idPromo, cant] of porPromo.entries()) {
      const { data: p } = await admin.from("promociones").select("cupos_usados").eq("id_promocion", idPromo).maybeSingle();
      const usados = Number(p?.cupos_usados ?? 0);
      await admin
        .from("promociones")
        .update({ cupos_usados: Math.max(0, usados - cant), fecha_actualizacion: new Date().toISOString() })
        .eq("id_promocion", idPromo);
    }

    return jsonResponse(200, { ok: true, canceladas: ids.length });
  } catch (e) {
    console.error("cancelar_promocion_error", e);
    return jsonResponse(500, { ok: false, code: "internal_error", error: "Error interno del servidor" });
  }
});
