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
  if (req.method !== "GET") return jsonResponse(405, { ok: false, error: "Metodo no permitido" });

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const authHeader = req.headers.get("Authorization") ?? "";

    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse(401, { ok: false, error: "Token invalido o ausente" });
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey);
    const accessToken = authHeader.replace("Bearer ", "").trim();

    const { data: authData, error: authError } = await supabase.auth.getUser(accessToken);
    if (authError || !authData.user) {
      return jsonResponse(401, { ok: false, error: "No autenticado" });
    }
    const uid = authData.user.id;

    // Buscar generación no entregada de los últimos 5 minutos
    const cincoMinAtras = new Date(Date.now() - 5 * 60 * 1000).toISOString();

    const { data: pendiente } = await supabase
      .from("flyer_generaciones")
      .select("id, urls_generadas, titulo, estilo_nombre, es_retry, generacion_padre_id, retry_usado, created_at, error_mensaje")
      .eq("local_id", uid)
      .eq("entregado", false)
      .gte("created_at", cincoMinAtras)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (!pendiente) {
      return jsonResponse(200, { ok: true, pendiente: null });
    }

    // Si tiene error, no hay nada que recuperar
    if (pendiente.error_mensaje) {
      return jsonResponse(200, { ok: true, pendiente: null });
    }

    return jsonResponse(200, {
      ok: true,
      pendiente: {
        generacion_id: pendiente.id,
        urls: pendiente.urls_generadas,
        titulo: pendiente.titulo,
        estilo_nombre: pendiente.estilo_nombre,
        es_retry: pendiente.es_retry,
        generacion_padre_id: pendiente.generacion_padre_id,
        retry_usado: pendiente.retry_usado,
        created_at: pendiente.created_at,
      },
    });

  } catch (error) {
    console.error("verificar_flyer_pendiente_error", error);
    return jsonResponse(500, { ok: false, error: "Error interno del servidor" });
  }
});
