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

// ─── Borrar archivos de Storage para una generación ───────────────────────
// Los archivos viven en: flyers-ia/<generacionId>/0.jpg … 3.jpg
// Solo borra archivos que estén en el bucket propio (URLs que contengan /flyers-ia/).

async function borrarDelStorage(
  supabase: ReturnType<typeof createClient>,
  generacionId: string,
  urls: string[],
): Promise<void> {
  // Filtrar solo URLs que son del bucket de Supabase (no URLs externas de Grok)
  const storagePaths: string[] = [];
  for (let i = 0; i < urls.length; i++) {
    const url = urls[i];
    // Detectar si la URL pertenece a nuestro bucket comprobando el path
    if (url.includes("/storage/v1/object/public/flyers-ia/")) {
      storagePaths.push(`${generacionId}/${i}.jpg`);
    }
  }

  if (storagePaths.length === 0) return;

  const { error } = await supabase.storage
    .from("flyers-ia")
    .remove(storagePaths);

  if (error) {
    console.error(`confirmar_entrega_flyer: error al borrar storage para ${generacionId}:`, error.message);
  } else {
    console.log(`confirmar_entrega_flyer: ${storagePaths.length} archivos borrados para ${generacionId}`);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { ok: false, error: "Metodo no permitido" });

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

    let body: unknown;
    try { body = await req.json(); } catch {
      return jsonResponse(400, { ok: false, error: "JSON invalido" });
    }
    if (!isPlainObject(body)) return jsonResponse(400, { ok: false, error: "Body invalido" });

    const generacionId = String(body.generacion_id ?? "").trim();
    if (!generacionId) return jsonResponse(400, { ok: false, error: "generacion_id requerido" });

    // Verificar que la generación pertenece al local
    const { data: gen, error: genError } = await supabase
      .from("flyer_generaciones")
      .select("id, local_id, entregado, urls_generadas")
      .eq("id", generacionId)
      .single();

    if (genError || !gen) return jsonResponse(404, { ok: false, error: "Generacion no encontrada" });
    if (gen.local_id !== uid) return jsonResponse(403, { ok: false, error: "No autorizado" });

    // Si ya estaba entregado, igual intentamos borrar Storage por si quedó algo
    if (gen.entregado) {
      // Borrar en background sin bloquear la respuesta
      borrarDelStorage(supabase, generacionId, gen.urls_generadas ?? []).catch(() => {});
      return jsonResponse(200, { ok: true, ya_entregado: true });
    }

    // Marcar como entregado
    await supabase
      .from("flyer_generaciones")
      .update({ entregado: true })
      .eq("id", generacionId);

    // Borrar archivos del Storage — el dispositivo ya los tiene cacheados localmente
    // Hacemos esto async para no demorar la respuesta al cliente
    borrarDelStorage(supabase, generacionId, gen.urls_generadas ?? []).catch(() => {});

    return jsonResponse(200, { ok: true });

  } catch (error) {
    console.error("confirmar_entrega_flyer_error", error);
    return jsonResponse(500, { ok: false, error: "Error interno del servidor" });
  }
});
