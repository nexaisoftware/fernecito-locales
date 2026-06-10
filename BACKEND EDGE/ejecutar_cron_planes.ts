// Edge: ejecutar_cron_planes
// Invoca manualmente `cron_expirar_y_renovar_planes()` desde el dashboard owner.
// El cron diario corre solo (pg_cron 10:00 UTC); esta edge es para forzar.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

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
    const actorUid = authData.user.id;
    const actorEmail = String(authData.user.email ?? "").toLowerCase();

    if (actorEmail) {
      try {
        await supabaseAdmin.rpc("vincular_owner_si_corresponde", { p_email: actorEmail });
      } catch (e) {
        console.error("vincular_owner falló (no crítico):", e);
      }
    }

    const { data: esOwner, error: ownerError } = await supabaseAdmin.rpc("es_owner_activo", {
      p_uid: actorUid,
    });
    if (ownerError) throw ownerError;
    if (esOwner !== true) {
      return jsonResponse(403, { ok: false, error: "No autorizado" });
    }

    const { data: result, error: cronError } = await supabaseAdmin.rpc(
      "cron_expirar_y_renovar_planes",
    );
    if (cronError) throw cronError;

    return jsonResponse(200, { ok: true, resultado: result });
  } catch (error) {
    console.error("ejecutar_cron_planes_error", error);
    return jsonResponse(500, {
      ok: false,
      error: "Error interno del servidor",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
});
