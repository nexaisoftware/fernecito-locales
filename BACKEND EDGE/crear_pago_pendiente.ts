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

const PLAN_PRICE_USD: Record<string, number> = {
  standard: 15,
  plus: 35,
  premium: 65,
  pionero: 0,
};

const PLAN_RANK: Record<string, number> = {
  gratis: 0,
  standard: 1,
  plus: 2,
  premium: 3,
  pionero: 3,
};

const planRank = (p: string | null | undefined): number =>
  PLAN_RANK[String(p ?? "gratis").toLowerCase()] ?? 0;

const ALLOWED_MIME = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
]);

const sanitizeFileName = (value: string): string =>
  value
    .trim()
    .replace(/[^a-zA-Z0-9._-]/g, "_")
    .slice(0, 120);

const decodeBase64 = (value: string): Uint8Array => {
  const normalized = value.includes(",") ? value.split(",").pop() ?? "" : value;
  const decoded = atob(normalized);
  const bytes = new Uint8Array(decoded.length);
  for (let i = 0; i < decoded.length; i++) {
    bytes[i] = decoded.charCodeAt(i);
  }
  return bytes;
};

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

    // ── Rate limit: 10 intentos por hora por user (super estricto: cada
    // intento sube un archivo y bloquea storage). Anti doble-tap + anti-DDoS.
    try {
      const { data: rlOk, error: rlErr } = await supabaseAdmin.rpc("check_rate_limit", {
        p_edge: "crear_pago_pendiente",
        p_identifier: `user:${uid}`,
        p_user_id: uid,
        p_max: 10,
        p_ventana_segs: 3600,
      });
      if (rlErr) {
        console.error("rate_limit_rpc_failed", { edge: "crear_pago_pendiente", error: rlErr.message });
      } else if (rlOk === false) {
        return jsonResponse(429, {
          ok: false,
          code: "rate_limit_exceeded",
          error: "Demasiados intentos de pago. Esperá una hora o contactá soporte.",
        });
      }
    } catch (rlException) {
      console.error("rate_limit_exception", { edge: "crear_pago_pendiente", error: String(rlException) });
    }

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(400, { ok: false, error: "JSON invalido" });
    }
    if (!isPlainObject(body)) {
      return jsonResponse(400, { ok: false, error: "Body invalido" });
    }

    const planRaw = String(body.plan_solicitado ?? "").trim().toLowerCase();
    if (!PLAN_PRICE_USD[planRaw] && planRaw !== "pionero") {
      return jsonResponse(400, { ok: false, error: "plan_solicitado invalido" });
    }
    const montoUsd = PLAN_PRICE_USD[planRaw];

    // ── Idempotency key: cliente genera UUID por intención de pago.
    // Si reintenta con el mismo UUID, devolvemos la row existente.
    const clientRequestIdRaw = String(body.client_request_id ?? "").trim();
    const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (!clientRequestIdRaw || !UUID_RE.test(clientRequestIdRaw)) {
      return jsonResponse(400, {
        ok: false,
        code: "missing_client_request_id",
        error: "client_request_id (UUID v4) requerido para idempotencia",
      });
    }
    {
      const { data: existente, error: idemErr } = await supabaseAdmin
        .from("pagos_pendientes")
        .select("id, estado, plan_solicitado, monto_usd, monto_ars, creado_en, tipo_solicitud, plan_anterior")
        .eq("perfil_id", uid)
        .eq("client_request_id", clientRequestIdRaw)
        .maybeSingle();
      if (idemErr) throw idemErr;
      if (existente) {
        // Reintento idempotente: devolvemos la row sin crear duplicado.
        return jsonResponse(200, { ok: true, pago: existente, idempotent_replay: true });
      }
    }

    const cotizacionBlue = Number(body.cotizacion_blue ?? 0);
    const montoArs = Number(body.monto_ars ?? 0);
    // Validar rango razonable: cotización entre $10 y $10.000.000 ARS/USD
    if (!Number.isFinite(cotizacionBlue) || cotizacionBlue <= 10 || cotizacionBlue > 10_000_000) {
      return jsonResponse(400, { ok: false, error: "cotizacion_blue invalida o fuera de rango" });
    }
    // monto_ars es referencial; validar que sea positivo y no absurdo (max ~$65 USD * cotiz max)
    const montoArsMax = PLAN_PRICE_USD["premium"] * 10_000_000;
    if (!Number.isFinite(montoArs) || montoArs <= 0 || montoArs > montoArsMax) {
      return jsonResponse(400, { ok: false, error: "monto_ars invalido o fuera de rango" });
    }

    const mime = String(body.comprobante_mime ?? "").trim().toLowerCase();
    if (!ALLOWED_MIME.has(mime)) {
      return jsonResponse(400, { ok: false, error: "Tipo de comprobante no permitido" });
    }
    // Nota: el mime es declarado por el cliente; se acepta dado que el bucket es privado
    // y solo accesible por admins. La compresión en Flutter ya garantiza que las imágenes
    // sean JPEGs válidos antes de base64-encodear.

    const base64 = String(body.comprobante_base64 ?? "").trim();
    if (!base64) return jsonResponse(400, { ok: false, error: "Falta comprobante_base64" });

    const filenameInput = String(body.comprobante_nombre ?? "comprobante");
    const safeName = sanitizeFileName(filenameInput);
    const bytes = decodeBase64(base64);
    if (bytes.byteLength == 0) {
      return jsonResponse(400, { ok: false, error: "Comprobante vacio" });
    }
    if (bytes.byteLength > 10 * 1024 * 1024) {
      return jsonResponse(400, { ok: false, error: "Comprobante supera 10MB" });
    }

    const { data: perfil, error: perfilError } = await supabaseAdmin
      .from("perfiles_locales")
      .select("local_username, plan_suscripcion, fecha_vencimiento_suscripcion")
      .eq("id", uid)
      .maybeSingle();
    if (perfilError) throw perfilError;
    const localUsername = String(perfil?.local_username ?? "");

    // === Detección automática de tipo_solicitud ===
    const planActualRaw = String(perfil?.plan_suscripcion ?? "gratis").trim().toLowerCase();
    const vencRaw = perfil?.fecha_vencimiento_suscripcion;
    const vencDate = vencRaw ? new Date(String(vencRaw)) : null;
    const planActivo = !!vencDate && vencDate.getTime() > Date.now() &&
      planActualRaw !== "gratis" && planActualRaw !== "";

    let tipoSolicitud: "plan_nuevo" | "upgrade" | "renovacion" | "downgrade";
    if (!planActivo) {
      tipoSolicitud = "plan_nuevo";
    } else {
      const rankActual = planRank(planActualRaw);
      const rankNuevo = planRank(planRaw);
      if (rankNuevo > rankActual) tipoSolicitud = "upgrade";
      else if (rankNuevo < rankActual) tipoSolicitud = "downgrade";
      else tipoSolicitud = "renovacion";
    }

    // Solo una solicitud diferida (renovacion/downgrade) pendiente por local
    if (tipoSolicitud === "renovacion" || tipoSolicitud === "downgrade") {
      const { data: existentes, error: existError } = await supabaseAdmin
        .from("pagos_pendientes")
        .select("id")
        .eq("perfil_id", uid)
        .in("tipo_solicitud", ["renovacion", "downgrade"])
        .in("estado", ["pendiente", "aprobado_pendiente"])
        .limit(1);
      if (existError) throw existError;
      if (existentes && existentes.length > 0) {
        return jsonResponse(409, {
          ok: false,
          error: "Ya tenes una solicitud de renovacion/downgrade pendiente. Esperá a que se procese.",
        });
      }
    }
    // También: una sola solicitud pendiente de cualquier tipo a la vez (anti-spam)
    {
      const { data: anyPending, error: anyErr } = await supabaseAdmin
        .from("pagos_pendientes")
        .select("id")
        .eq("perfil_id", uid)
        .eq("estado", "pendiente")
        .limit(1);
      if (anyErr) throw anyErr;
      if (anyPending && anyPending.length > 0) {
        return jsonResponse(409, {
          ok: false,
          error: "Ya tenés un pago pendiente de aprobación. Esperá la respuesta del equipo.",
        });
      }
    }

    const ts = Date.now();
    const path = `${uid}/${ts}_${safeName}`;
    const { error: uploadError } = await supabaseAdmin.storage
      .from("comprobantes_pagos")
      .upload(path, bytes, {
        upsert: false,
        contentType: mime,
      });
    if (uploadError) throw uploadError;

    const { data: pago, error: pagoError } = await supabaseAdmin
      .from("pagos_pendientes")
      .insert({
        perfil_id: uid,
        local_username: localUsername,
        plan_solicitado: planRaw,
        monto_usd: montoUsd,
        monto_ars: Number(montoArs.toFixed(2)),
        cotizacion_blue: Number(cotizacionBlue.toFixed(2)),
        comprobante_url: path,
        tipo_solicitud: tipoSolicitud,
        plan_anterior: planActivo ? planActualRaw : null,
        client_request_id: clientRequestIdRaw,
      })
      .select("id, estado, plan_solicitado, monto_usd, monto_ars, creado_en, tipo_solicitud, plan_anterior")
      .single();
    if (pagoError) {
      // El archivo ya fue subido al bucket; si el INSERT falla lo eliminamos
      // para evitar archivos huérfanos en storage.
      await supabaseAdmin.storage.from("comprobantes_pagos").remove([path]).catch((cleanupErr) => {
        console.error("crear_pago_pendiente: fallo cleanup de archivo huerfano", cleanupErr);
      });
      // 23505 = unique_violation. Mapeamos a 409 con mensaje claro según índice.
      const pgCode = (pagoError as { code?: string }).code;
      if (pgCode === "23505") {
        const msg = String((pagoError as { message?: string }).message ?? "");
        if (msg.includes("uq_pagos_pendientes_client_request_id")) {
          // Race: dos requests idénticos en paralelo. Releemos la row.
          const { data: existente } = await supabaseAdmin
            .from("pagos_pendientes")
            .select("id, estado, plan_solicitado, monto_usd, monto_ars, creado_en, tipo_solicitud, plan_anterior")
            .eq("perfil_id", uid)
            .eq("client_request_id", clientRequestIdRaw)
            .maybeSingle();
          if (existente) {
            return jsonResponse(200, { ok: true, pago: existente, idempotent_replay: true });
          }
        }
        if (msg.includes("uq_pagos_pendientes_uno_pendiente")) {
          return jsonResponse(409, {
            ok: false,
            code: "ya_tenes_pendiente",
            error: "Ya tenés un pago pendiente de aprobación.",
          });
        }
        if (msg.includes("uq_pagos_pendientes_uno_diferido")) {
          return jsonResponse(409, {
            ok: false,
            code: "ya_tenes_diferido",
            error: "Ya tenés una renovación/downgrade aprobada esperando aplicarse.",
          });
        }
        return jsonResponse(409, {
          ok: false,
          code: "duplicate_request",
          error: "Solicitud duplicada detectada.",
        });
      }
      throw pagoError;
    }

    return jsonResponse(200, { ok: true, pago });
  } catch (error) {
    console.error("crear_pago_pendiente_error", error);
    return jsonResponse(500, {
      ok: false,
      error: "Error interno del servidor",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
});
