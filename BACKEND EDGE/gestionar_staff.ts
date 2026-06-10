import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });
const isPlainObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === "object" && v !== null && !Array.isArray(v);
const authorizationHeader = (req: Request) => (req.headers.get("Authorization") ?? "").trim();

const CLAVE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CLAVE_LEN = 8;
const CLAVE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function generarClaveVinculacion(): string {
  let code = "";
  for (let i = 0; i < CLAVE_LEN; i++) {
    code += CLAVE_CHARS[Math.floor(Math.random() * CLAVE_CHARS.length)];
  }
  return code;
}

async function sha256Hex(text: string): Promise<string> {
  const data = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function esOwnerLocal(
  admin: ReturnType<typeof createClient>,
  uid: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("perfiles_locales")
    .select("id")
    .eq("id", uid)
    .maybeSingle();
  if (error) throw error;
  return !!data;
}

async function resolverLocalPorUsername(
  admin: ReturnType<typeof createClient>,
  localUsername: string,
): Promise<{ id: string; local_username: string } | null> {
  const username = localUsername.trim().toLowerCase();
  if (!username) return null;
  const { data, error } = await admin
    .from("perfiles_locales")
    .select("id, local_username")
    .ilike("local_username", username)
    .maybeSingle();
  if (error) throw error;
  if (!data?.id) return null;
  return { id: String(data.id), local_username: String(data.local_username ?? username) };
}

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

    const header = authorizationHeader(req);
    if (!header) {
      return jsonResponse(401, { ok: false, code: "missing_authorization", error: "Authorization requerido" });
    }

    const auth = createClient(url, anon, { global: { headers: { Authorization: header } } });
    const { data: { user }, error: authError } = await auth.auth.getUser();
    if (authError || !user) {
      return jsonResponse(401, {
        ok: false,
        code: "invalid_jwt",
        error: "No autenticado",
        detail: authError?.message,
      });
    }

    const admin = createClient(url, service);
    const body = await req.json().catch(() => null);
    if (!isPlainObject(body)) {
      return jsonResponse(400, { ok: false, code: "invalid_body", error: "Body invalido" });
    }

    const accion = String(body["accion"] ?? "").trim().toLowerCase();

    // ── Vincular staff (usuario normal, no owner del local) ───────────────────
    // ── Rate limiting general (fail-open: si la RPC falla, deja pasar) ────────
    // 200 req/min por user en gestionar_staff. Un local owner real toca staff
    // pocas veces por sesión; 200/min es 100x más holgado que el uso normal.
    try {
      const { data: rlGeneral, error: rlErr } = await admin.rpc("check_rate_limit", {
        p_edge: "gestionar_staff",
        p_identifier: `user:${user.id}`,
        p_user_id: user.id,
        p_max: 200,
        p_ventana_segs: 60,
      });
      if (rlErr) {
        console.error("rate_limit_rpc_failed", { edge: "gestionar_staff", scope: "user", error: rlErr.message });
      } else if (rlGeneral === false) {
        return jsonResponse(429, {
          ok: false,
          code: "rate_limit_exceeded",
          error: "Demasiados intentos. Esperá un instante y reintentá.",
        });
      }
    } catch (rlException) {
      console.error("rate_limit_exception", { edge: "gestionar_staff", error: String(rlException) });
    }

    if (accion === "vincular") {
      const localUsername = String(body["local_username"] ?? "").trim();
      const clave = String(body["clave_vinculacion"] ?? body["clave"] ?? "").trim().toUpperCase();
      if (!localUsername || !clave) {
        return jsonResponse(400, {
          ok: false,
          code: "missing_fields",
          error: "local_username y clave_vinculacion son requeridos",
        });
      }
      if (clave.length !== CLAVE_LEN || !/^[A-Z0-9]+$/.test(clave)) {
        return jsonResponse(400, {
          ok: false,
          code: "invalid_clave_format",
          error: "Clave invalida",
        });
      }

      // ── Anti brute-force: máx 5 intentos de vincular por user en 30s ─────
      // La clave es de 8 chars (espacio ~1.1T) — improbable adivinar, pero
      // un atacante podría DDoSear intentos. Esto los frena.
      try {
        const { data: rlVincular, error: rlVErr } = await admin.rpc("check_rate_limit", {
          p_edge: "gestionar_staff",
          p_identifier: `vincular:${user.id}`,
          p_user_id: user.id,
          p_max: 5,
          p_ventana_segs: 30,
        });
        if (rlVErr) {
          console.error("rate_limit_rpc_failed", { edge: "gestionar_staff", scope: "vincular", error: rlVErr.message });
        } else if (rlVincular === false) {
          return jsonResponse(429, {
            ok: false,
            code: "rate_limit_vincular",
            error: "Demasiados intentos de vinculación. Esperá 30 segundos y reintentá.",
          });
        }
      } catch (rlException) {
        console.error("rate_limit_exception", { edge: "gestionar_staff", scope: "vincular", error: String(rlException) });
      }

      const local = await resolverLocalPorUsername(admin, localUsername);
      if (!local) {
        return jsonResponse(404, { ok: false, code: "local_not_found", error: "Local no encontrado" });
      }
      if (local.id === user.id) {
        return jsonResponse(400, {
          ok: false,
          code: "self_link_forbidden",
          error: "No podes vincularte a tu propio local",
        });
      }

      const { data: perfilStaff, error: perfilStaffErr } = await admin
        .from("perfiles_staff")
        .select("id")
        .eq("id", user.id)
        .maybeSingle();
      if (perfilStaffErr) throw perfilStaffErr;

      const { data: perfilUsuario, error: perfilErr } = await admin
        .from("perfiles_usuarios")
        .select("id")
        .eq("id", user.id)
        .maybeSingle();
      if (perfilErr) throw perfilErr;
      if (!perfilStaff && !perfilUsuario) {
        return jsonResponse(403, {
          ok: false,
          code: "not_user_profile",
          error: "Completá tu perfil de staff antes de vincularte a un local",
        });
      }

      const { data: invitacion, error: invErr } = await admin
        .from("staff_invitaciones_local")
        .select("id_local, clave_hash, expira_en")
        .eq("id_local", local.id)
        .maybeSingle();
      if (invErr) {
        return jsonResponse(500, {
          ok: false,
          code: "invitation_table_missing",
          error: "Falta configurar invitaciones de staff en el servidor",
          detail: invErr.message,
        });
      }
      if (!invitacion) {
        return jsonResponse(404, {
          ok: false,
          code: "invitation_not_found",
          error: "No hay clave activa para ese local. Pedile una nueva al dueño.",
        });
      }

      const expira = new Date(String(invitacion.expira_en)).getTime();
      if (Number.isNaN(expira) || Date.now() > expira) {
        return jsonResponse(410, {
          ok: false,
          code: "invitation_expired",
          error: "La clave expiró. Pedile una nueva al dueño del local.",
        });
      }

      const hashEsperado = String(invitacion.clave_hash ?? "");
      const hashRecibido = await sha256Hex(clave);
      if (hashEsperado !== hashRecibido) {
        return jsonResponse(403, {
          ok: false,
          code: "invalid_clave",
          error: "Clave incorrecta",
        });
      }

      const { data: existente, error: existErr } = await admin
        .from("local_staff")
        .select("id_staff, activo")
        .eq("id_local", local.id)
        .eq("id_staff", user.id)
        .maybeSingle();
      if (existErr) throw existErr;

      if (existente) {
        if (existente.activo === true) {
          return jsonResponse(200, {
            ok: true,
            code: "already_linked",
            id_local: local.id,
            local_username: local.local_username,
            message: "Ya formas parte del staff de este local",
          });
        }
        const { error: reactivarErr } = await admin
          .from("local_staff")
          .update({ activo: true })
          .eq("id_local", local.id)
          .eq("id_staff", user.id);
        if (reactivarErr) throw reactivarErr;
      } else {
        // Sin rol_staff: la columna fue droppeada en migración 20260524_staff_v2.
        const { error: insertErr } = await admin.from("local_staff").insert({
          id_local: local.id,
          id_staff: user.id,
          activo: true,
        });
        if (insertErr) throw insertErr;
      }

      await admin.from("staff_invitaciones_local").delete().eq("id_local", local.id);

      return jsonResponse(200, {
        ok: true,
        id_local: local.id,
        local_username: local.local_username,
        message: "Te uniste al staff correctamente",
      });
    }

    // ── desvincular_solo: el staff sale por su cuenta de un local ─────────────
    // No requiere ser owner. Borra la fila local_staff donde el actor es el staff.
    if (accion === "desvincular_solo") {
      const idLocalSalir = String(body["id_local"] ?? "").trim();
      if (!idLocalSalir) {
        return jsonResponse(400, {
          ok: false,
          code: "missing_id_local",
          error: "id_local requerido",
        });
      }
      const { data: existente, error: existErr } = await admin
        .from("local_staff")
        .select("id_staff")
        .eq("id_local", idLocalSalir)
        .eq("id_staff", user.id)
        .maybeSingle();
      if (existErr) throw existErr;
      if (!existente) {
        return jsonResponse(404, {
          ok: false,
          code: "vinculo_not_found",
          error: "No estás vinculado a ese local",
        });
      }
      const { error: delErr } = await admin
        .from("local_staff")
        .delete()
        .eq("id_local", idLocalSalir)
        .eq("id_staff", user.id);
      if (delErr) throw delErr;
      return jsonResponse(200, {
        ok: true,
        accion: "desvincular_solo",
        id_local: idLocalSalir,
      });
    }

    // ── Acciones del owner del local ─────────────────────────────────────────
    const owner = await esOwnerLocal(admin, user.id);
    if (!owner) {
      return jsonResponse(403, {
        ok: false,
        code: "forbidden_actor",
        error: "Solo el dueño del local puede gestionar staff",
      });
    }

    if (accion === "generar_clave_vinculacion") {
      const clave = generarClaveVinculacion();
      const claveHash = await sha256Hex(clave);
      const expiraEn = new Date(Date.now() + CLAVE_TTL_MS).toISOString();

      const { error: upsertErr } = await admin.from("staff_invitaciones_local").upsert(
        {
          id_local: user.id,
          clave_hash: claveHash,
          expira_en: expiraEn,
        },
        { onConflict: "id_local" },
      );
      if (upsertErr) {
        return jsonResponse(500, {
          ok: false,
          code: "invitation_table_missing",
          error: "Falta configurar invitaciones de staff en el servidor",
          detail: upsertErr.message,
        });
      }

      const { data: perfil } = await admin
        .from("perfiles_locales")
        .select("local_username")
        .eq("id", user.id)
        .maybeSingle();

      return jsonResponse(200, {
        ok: true,
        clave_vinculacion: clave,
        local_username: perfil?.local_username ?? null,
        expira_en: expiraEn,
      });
    }

    const idStaff = String(body["id_staff"] ?? "").trim();
    if (!idStaff) {
      return jsonResponse(400, { ok: false, code: "missing_id_staff", error: "id_staff requerido" });
    }

    if (accion === "toggle_activo") {
      const activo = body["activo"] === true || body["activo"] === "true" || body["activo"] === 1;
      const { data, error } = await admin
        .from("local_staff")
        .update({ activo })
        .eq("id_local", user.id)
        .eq("id_staff", idStaff)
        .select("id_staff, activo")
        .maybeSingle();
      if (error) throw error;
      if (!data) {
        return jsonResponse(404, { ok: false, code: "staff_not_found", error: "Empleado no encontrado" });
      }
      return jsonResponse(200, { ok: true, staff: data });
    }

    if (accion === "eliminar") {
      const { error } = await admin
        .from("local_staff")
        .delete()
        .eq("id_local", user.id)
        .eq("id_staff", idStaff);
      if (error) throw error;
      return jsonResponse(200, { ok: true, eliminado: idStaff });
    }

    if (accion === "actualizar_permisos") {
      const patch: Record<string, boolean> = {};
      if (typeof body["habilitado_qr_promos"] === "boolean") {
        patch.habilitado_qr_promos = body["habilitado_qr_promos"];
      }
      if (typeof body["habilitado_qr_pases"] === "boolean") {
        patch.habilitado_qr_pases = body["habilitado_qr_pases"];
      }
      if (typeof body["habilitado_aceptar_listas"] === "boolean") {
        patch.habilitado_aceptar_listas = body["habilitado_aceptar_listas"];
      }
      if (typeof body["habilitado_ver_lista_aceptados"] === "boolean") {
        patch.habilitado_ver_lista_aceptados = body["habilitado_ver_lista_aceptados"];
      }
      if (typeof body["habilitado_qr_invitacion"] === "boolean") {
        patch.habilitado_qr_invitacion = body["habilitado_qr_invitacion"];
      }
      if (typeof body["qr_invitacion_pasar_cupo"] === "boolean") {
        patch.qr_invitacion_pasar_cupo = body["qr_invitacion_pasar_cupo"];
      }
      if (Object.keys(patch).length === 0) {
        return jsonResponse(400, {
          ok: false,
          code: "missing_permissions",
          error: "Enviá al menos un permiso para actualizar",
        });
      }
      const { data, error } = await admin
        .from("local_staff")
        .update(patch)
        .eq("id_local", user.id)
        .eq("id_staff", idStaff)
        .select(
          "id_staff, habilitado_qr_promos, habilitado_qr_pases, habilitado_aceptar_listas, habilitado_ver_lista_aceptados, habilitado_qr_invitacion, qr_invitacion_pasar_cupo",
        )
        .maybeSingle();
      if (error) throw error;
      if (!data) {
        return jsonResponse(404, { ok: false, code: "staff_not_found", error: "Empleado no encontrado" });
      }
      return jsonResponse(200, { ok: true, staff: data });
    }

    return jsonResponse(400, {
      ok: false,
      code: "invalid_action",
      error: "Accion invalida. Usa: generar_clave_vinculacion, toggle_activo, eliminar, vincular, desvincular_solo, actualizar_permisos",
    });
  } catch (error) {
    console.error("gestionar_staff_error", error);
    return jsonResponse(500, {
      ok: false,
      code: "internal_error",
      error: "Error interno del servidor",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
});
