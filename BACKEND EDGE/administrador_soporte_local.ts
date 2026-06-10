import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

const isPlainObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const isValidCodigo = (value: string): boolean => /^[A-Z]{3}-\d{3}$/.test(value);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { ok: false, error: "Metodo no permitido" });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse(500, { ok: false, error: "Configuracion incompleta del servidor" });
    }
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse(401, { ok: false, error: "Token invalido o ausente" });
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);
    const accessToken = authHeader.replace("Bearer ", "").trim();
    if (!accessToken) return jsonResponse(401, { ok: false, error: "Token invalido o ausente" });

    const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(accessToken);
    if (authError || !authData.user) {
      return jsonResponse(401, { ok: false, error: "No autenticado" });
    }
    const uid = authData.user.id;

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(400, { ok: false, error: "JSON invalido" });
    }
    if (!isPlainObject(body)) {
      return jsonResponse(400, { ok: false, error: "Body invalido" });
    }

    const accion = String(body.accion ?? "get_estado").trim().toLowerCase();
    const codigoRaw = String(body.codigo_antiestafa ?? "").trim().toUpperCase();
    const nowIso = new Date().toISOString();

    const { data: perfil, error: perfilError } = await supabaseAdmin
      .from("perfiles_locales")
      .select("local_username")
      .eq("id", uid)
      .maybeSingle();
    if (perfilError) throw perfilError;
    const localUsername = String(perfil?.local_username ?? "");

    const { data: actual, error: actualError } = await supabaseAdmin
      .from("locales_soporte")
      .select("id_local, codigo_antiestafa, estado_operacion, ultima_operacion")
      .eq("id_local", uid)
      .maybeSingle();
    if (actualError) throw actualError;

    if (accion === "get_estado") {
      return jsonResponse(200, {
        ok: true,
        existe_row: !!actual,
        local_username: localUsername,
        soporte: actual ?? null,
      });
    }

    if (accion !== "abrir" && accion !== "reiniciar") {
      return jsonResponse(400, { ok: false, error: "Accion invalida. Usa: get_estado, abrir o reiniciar" });
    }

    if (!isValidCodigo(codigoRaw)) {
      return jsonResponse(400, { ok: false, error: "codigo_antiestafa invalido. Formato requerido: ABC-123" });
    }

    if (accion === "abrir") {
      const payload = {
        id_local: uid,
        codigo_antiestafa: codigoRaw,
        estado_operacion: "abierta",
        ultima_operacion: nowIso,
      };
      const { error } = await supabaseAdmin.from("locales_soporte").upsert(payload, { onConflict: "id_local" });
      if (error) throw error;
    }

    if (accion === "reiniciar") {
      if (actual) {
        const { error: cerrarError } = await supabaseAdmin
          .from("locales_soporte")
          .update({ estado_operacion: "terminada", ultima_operacion: nowIso })
          .eq("id_local", uid);
        if (cerrarError) throw cerrarError;
      }
      const { error: abrirError } = await supabaseAdmin
        .from("locales_soporte")
        .upsert(
          {
            id_local: uid,
            codigo_antiestafa: codigoRaw,
            estado_operacion: "abierta",
            ultima_operacion: new Date().toISOString(),
          },
          { onConflict: "id_local" },
        );
      if (abrirError) throw abrirError;
    }

    const { data: actualizado, error: actualizadoError } = await supabaseAdmin
      .from("locales_soporte")
      .select("id_local, codigo_antiestafa, estado_operacion, ultima_operacion")
      .eq("id_local", uid)
      .maybeSingle();
    if (actualizadoError) throw actualizadoError;

    return jsonResponse(200, {
      ok: true,
      existe_row: !!actualizado,
      local_username: localUsername,
      soporte: actualizado ?? null,
    });
  } catch (error) {
    console.error("administrador_soporte_local_error", error);
    return jsonResponse(500, {
      ok: false,
      error: "Error interno del servidor",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
});
