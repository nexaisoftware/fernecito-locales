import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { assertCuentaLocalActiva } from "../_shared/cuenta_activa.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };

const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

const isPlainObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const hasOwn = (obj: Record<string, unknown>, key: string): boolean =>
  Object.prototype.hasOwnProperty.call(obj, key);

const normalizeOptionalString = (value: unknown): string | null | undefined => {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
};

const isValidUrl = (value: string): boolean => {
  try {
    const parsed = new URL(value);
    return parsed.protocol === "http:" || parsed.protocol === "https:";
  } catch {
    return false;
  }
};

const normalizeUsername = (value: string): string =>
  value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]/g, "");

const editableFields = new Set([
  "nombre_local",
  "local_username",
  "direccion",
  "provincia",
  "ciudad",
  "rubro",
  "foto_perfil_url",
  "url_foto_banner",
  "foto_local_1",
  "foto_local_2",
  "foto_local_3",
  "foto_local_4",
  "foto_local_5",
  "url_maps",
  "url_website",
  "url_tiktok",
  "url_instagram",
  "descripcion_local",
]);

const urlFields = new Set([
  "foto_perfil_url",
  "url_foto_banner",
  "foto_local_1",
  "foto_local_2",
  "foto_local_3",
  "foto_local_4",
  "foto_local_5",
  "url_maps",
  "url_website",
  "url_tiktok",
  "url_instagram",
]);

const buildSafePayload = (perfilRaw: Record<string, unknown>): Record<string, unknown> => {
  const payload: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(perfilRaw)) {
    if (!editableFields.has(key)) continue;

    if (key === "rubro") {
      if (value === null) {
        payload[key] = [];
        continue;
      }
      if (!Array.isArray(value)) continue;
      const rubros = value
        .map((item) => (typeof item === "string" ? item.trim() : ""))
        .filter((item) => item.length > 0)
        .slice(0, 10);
      payload[key] = rubros;
      continue;
    }

    if (key === "local_username") {
      if (typeof value !== "string") continue;
      const normalized = normalizeUsername(value);
      if (normalized.length > 0) payload[key] = normalized;
      continue;
    }

    const normalized = normalizeOptionalString(value);
    if (normalized !== undefined) payload[key] = normalized;
  }
  return payload;
};

const validatePayload = (payload: Record<string, unknown>, modo: "basico" | "completo"): string | null => {
  if (hasOwn(payload, "local_username")) {
    const username = String(payload.local_username ?? "");
    if (!/^[a-z0-9_]{3,30}$/.test(username)) {
      return "local_username invalido. Usa 3-30 caracteres [a-z0-9_].";
    }
  }

  for (const field of urlFields) {
    if (!hasOwn(payload, field)) continue;
    const value = payload[field];
    if (value === null) continue;
    if (typeof value !== "string" || !isValidUrl(value)) {
      return `${field} invalido. Debe ser URL http/https.`;
    }
  }

  if (modo === "completo") {
    const requiredStrings = [
      "nombre_local",
      "local_username",
      "direccion",
      "provincia",
      "ciudad",
      "url_maps",
      "foto_perfil_url",
    ];
    for (const key of requiredStrings) {
      const value = payload[key];
      if (typeof value !== "string" || value.trim().length === 0) {
        return `Falta campo obligatorio: ${key}`;
      }
    }

    const rubro = payload.rubro;
    if (!Array.isArray(rubro) || rubro.length === 0) {
      return "Falta campo obligatorio: rubro";
    }

    const fotoLocales = [
      payload.foto_local_1,
      payload.foto_local_2,
      payload.foto_local_3,
      payload.foto_local_4,
      payload.foto_local_5,
    ].filter((item) => typeof item === "string" && item.length > 0);

    if (fotoLocales.length < 1) {
      return "Se requiere al menos 1 foto del local";
    }
  }

  return null;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, error: "Metodo no permitido" });
  }

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
    if (!accessToken) {
      return jsonResponse(401, { ok: false, error: "Token invalido o ausente" });
    }

    const { data: authData, error: authError } = await supabaseAdmin.auth.getUser(accessToken);
    if (authError || !authData.user) {
      return jsonResponse(401, { ok: false, error: "No autenticado" });
    }

    const bloqueo = await assertCuentaLocalActiva(
      supabaseAdmin,
      authData.user.id,
      jsonResponse,
      { permitirSinPerfil: true },
    );
    if (bloqueo) return bloqueo;

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(400, { ok: false, error: "JSON invalido" });
    }
    if (!isPlainObject(body) || !isPlainObject(body.perfil)) {
      return jsonResponse(400, { ok: false, error: "Body invalido. Envia { perfil }" });
    }

    const modo = body.modo === "completo" ? "completo" : "basico";
    const solicitarVerificacion = body.solicitar_verificacion === true;
    const perfilRaw = body.perfil;
    const safePayload = buildSafePayload(perfilRaw);

    if (Object.keys(safePayload).length === 0) {
      return jsonResponse(400, { ok: false, error: "No hay campos validos para guardar" });
    }

    const validationError = validatePayload(safePayload, modo);
    if (validationError) {
      return jsonResponse(400, { ok: false, error: validationError });
    }

    const uid = authData.user.id;

    if (hasOwn(safePayload, "local_username")) {
      const username = String(safePayload.local_username ?? "");
      const { data: duplicate, error: duplicateError } = await supabaseAdmin
        .from("perfiles_locales")
        .select("id")
        .eq("local_username", username)
        .neq("id", uid)
        .maybeSingle();
      if (duplicateError) throw duplicateError;
      if (duplicate) {
        return jsonResponse(409, { ok: false, error: "Ese local_username ya existe" });
      }
    }

    const { data: perfilActual, error: perfilActualError } = await supabaseAdmin
      .from("perfiles_locales")
      .select("id, local_verificado, plan_suscripcion, fecha_verificacion")
      .eq("id", uid)
      .maybeSingle();
    if (perfilActualError) throw perfilActualError;

    const nowIso = new Date().toISOString();

    if (modo === "basico") {
      if (!perfilActual) {
        return jsonResponse(409, {
          ok: false,
          error: "No existe perfil local para editar. Primero completá la creación del perfil.",
        });
      }

      const updatePayload: Record<string, unknown> = {
        ...safePayload,
        fecha_actualizacion: nowIso,
      };
      if (solicitarVerificacion && !perfilActual.local_verificado) {
        updatePayload.plan_suscripcion = "pendiente_verificacion";
      }

      const { error: updateError } = await supabaseAdmin
        .from("perfiles_locales")
        .update(updatePayload)
        .eq("id", uid);

      if (updateError) {
        return jsonResponse(400, {
          ok: false,
          error: "No se pudo actualizar el perfil local",
          detail: updateError.message,
          code: updateError.code,
        });
      }
    } else {
      const upsertPayload: Record<string, unknown> = {
        ...safePayload,
        id: uid,
        fecha_actualizacion: nowIso,
        perfil_local_completo: true,
      };

      if (!perfilActual) {
        upsertPayload.local_verificado = false;
        upsertPayload.fecha_verificacion = null;
        upsertPayload.estado_cuenta = "activa";
        upsertPayload.plan_suscripcion = solicitarVerificacion ? "pendiente_verificacion" : "gratis";
      } else if (solicitarVerificacion && !perfilActual.local_verificado) {
        upsertPayload.plan_suscripcion = "pendiente_verificacion";
      }

      const { error: upsertError } = await supabaseAdmin
        .from("perfiles_locales")
        .upsert(upsertPayload, { onConflict: "id" });

      if (upsertError) {
        return jsonResponse(400, {
          ok: false,
          error: "No se pudo guardar el perfil local",
          detail: upsertError.message,
          code: upsertError.code,
        });
      }
    }

    return jsonResponse(200, {
      ok: true,
      id: uid,
      modo,
      perfil_local_completo: modo === "completo",
    });
  } catch (error) {
    console.error("guardar_perfil_local_error", error);
    return jsonResponse(500, {
      ok: false,
      error: "Error interno del servidor",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
});
