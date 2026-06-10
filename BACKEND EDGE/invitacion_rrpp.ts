import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// ═══════════════════════════════════════════════════════════════════════════
// invitacion_rrpp — QR de RRPP / invitación
//
// Acciones:
//   - "generar"  (locales app, staff o dueño): crea/recupera el QR (id_invitacion
//                 opaco) para un evento. Reutilizable sin tope.
//   - "resolver" (users app, quien escanea): valida el QR y devuelve datos del
//                 evento para abrir "ver evento" en modo invitación.
//   - "reservar" (users app): reserva entrando DIRECTO como 'aceptada'. Saltea
//                 lista manual; saltea cupo solo si el RRPP tiene pasar_cupo.
//                 Atribuye la reserva al RRPP (id_rrpp / id_invitacion_rrpp).
// ═══════════════════════════════════════════════════════════════════════════

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

type LocalActivoRes =
  | { ok: true }
  | { ok: false; status: number; code: string; error: string };

async function localActivo(
  admin: ReturnType<typeof createClient>,
  idLocal: string,
): Promise<LocalActivoRes> {
  const { data, error } = await admin
    .from("perfiles_locales")
    .select("estado_cuenta")
    .eq("id", idLocal)
    .maybeSingle();
  if (error || !data) {
    return { ok: false, status: 404, code: "local_not_found", error: "Local no encontrado" };
  }
  if (data.estado_cuenta !== "activa") {
    return { ok: false, status: 403, code: "local_suspended", error: "Este evento no está disponible" };
  }
  return { ok: true };
}

/** Fail-open si check_rate_limit no está disponible. */
async function permitirRateLimit(
  admin: ReturnType<typeof createClient>,
  edge: string,
  identifier: string,
  userId: string,
  max: number,
  ventanaSegs: number,
): Promise<boolean> {
  try {
    const { data, error } = await admin.rpc("check_rate_limit", {
      p_edge: edge,
      p_identifier: identifier,
      p_user_id: userId,
      p_max: max,
      p_ventana_segs: ventanaSegs,
    });
    if (error) {
      console.error("rate_limit_rpc_failed", { edge, identifier, error: error.message });
      return true;
    }
    return data !== false;
  } catch (e) {
    console.error("rate_limit_exception", { edge, identifier, error: String(e) });
    return true;
  }
}

function generarCodigoPuerta(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 8; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return code;
}

// ─── Ajuste de cupo con compare-and-swap (idéntico a solicitar_asistencia) ────
type AjusteCupoRes =
  | { ok: true; usados: number; max: number | null }
  | { ok: false; code: string; error: string; detail?: string };

async function ajustarCupoLista(
  admin: ReturnType<typeof createClient>,
  idEvento: string,
  delta: number,
  opciones: { validarMax: boolean; clampMinZero?: boolean; maxReintentos?: number },
): Promise<AjusteCupoRes> {
  const clamp = opciones.clampMinZero ?? false;
  const maxR = opciones.maxReintentos ?? 6;
  for (let i = 0; i < maxR; i++) {
    const { data: ev, error: evErr } = await admin
      .from("eventos")
      .select("cupo_lista_usados, cupo_lista_max")
      .eq("id_evento", idEvento)
      .maybeSingle();
    if (evErr || !ev) return { ok: false, code: "event_not_found", error: "Evento no encontrado", detail: evErr?.message };
    const usados = Number(ev.cupo_lista_usados ?? 0);
    const cupoMax = ev.cupo_lista_max == null ? null : Number(ev.cupo_lista_max);
    let siguiente = usados + delta;
    if (siguiente < 0) {
      if (clamp) siguiente = 0;
      else return { ok: false, code: "list_counter_underflow", error: "cupo_lista_usados no puede ser negativo" };
    }
    if (opciones.validarMax && cupoMax != null && siguiente > cupoMax) {
      return { ok: false, code: "list_full", error: "No hay cupo disponible" };
    }
    const { data: upd, error: upErr } = await admin
      .from("eventos")
      .update({ cupo_lista_usados: siguiente })
      .eq("id_evento", idEvento)
      .eq("cupo_lista_usados", usados)
      .select("id_evento")
      .maybeSingle();
    if (upErr) return { ok: false, code: "counter_update_failed", error: "Error al actualizar cupo", detail: upErr.message };
    if (upd) return { ok: true, usados: siguiente, max: cupoMax };
  }
  return { ok: false, code: "counter_retry_conflict", error: "Conflicto de concurrencia, intentá de nuevo" };
}

// ─── Resolver + validar una invitación (devuelve contexto o error) ────────────
type InvitacionCtx = {
  id_invitacion: string;
  id_evento: string;
  id_local: string;
  id_rrpp: string;
  pasar_cupo: boolean;
};
async function resolverInvitacion(
  admin: ReturnType<typeof createClient>,
  idInvitacion: string,
): Promise<{ ok: true; ctx: InvitacionCtx } | { ok: false; status: number; code: string; error: string }> {
  const { data: inv, error } = await admin
    .from("invitaciones_rrpp")
    .select("id_invitacion, id_evento, id_local, id_rrpp, pasar_cupo, activa")
    .eq("id_invitacion", idInvitacion)
    .maybeSingle();
  if (error) return { ok: false, status: 500, code: "invitacion_lookup_failed", error: "Error al validar la invitación" };
  if (!inv) return { ok: false, status: 404, code: "invitacion_not_found", error: "Invitación no encontrada" };
  if (inv.activa !== true) {
    return { ok: false, status: 410, code: "invitacion_revocada", error: "Esta invitación ya no está activa" };
  }

  // Revalidar que el RRPP siga teniendo permiso (el local pudo deshabilitarlo).
  const { data: permiso } = await admin.rpc("puede_emitir_qr_invitacion", {
    p_uid: inv.id_rrpp,
    p_id_evento: inv.id_evento,
  });
  if (!permiso || permiso.puede !== true) {
    return { ok: false, status: 403, code: "invitacion_sin_permiso", error: "El RRPP ya no tiene permiso para invitar a este evento" };
  }

  return {
    ok: true,
    ctx: {
      id_invitacion: String(inv.id_invitacion),
      id_evento: String(inv.id_evento),
      id_local: String(inv.id_local),
      id_rrpp: String(inv.id_rrpp),
      // pasar_cupo efectivo = el snapshot de la invitación Y el permiso vigente.
      pasar_cupo: inv.pasar_cupo === true && permiso.pasar_cupo === true,
    },
  };
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
    if (!header) return jsonResponse(401, { ok: false, code: "missing_authorization", error: "Authorization requerido" });

    const auth = createClient(url, anon, { global: { headers: { Authorization: header } } });
    const { data: { user }, error: authError } = await auth.auth.getUser();
    if (authError || !user) {
      return jsonResponse(401, { ok: false, code: "invalid_jwt", error: "No autenticado", detail: authError?.message });
    }

    const admin = createClient(url, service);
    const body = await req.json().catch(() => null);
    if (!isPlainObject(body)) return jsonResponse(400, { ok: false, code: "invalid_body", error: "Body invalido" });

    const accion = String(body["accion"] ?? "").trim().toLowerCase();

    // ════════════════════════════════════════════════════════════════════════
    // ACCIÓN: generar — staff/dueño crea/recupera el QR de un evento
    // ════════════════════════════════════════════════════════════════════════
    if (accion === "generar") {
      const idEvento = String(body["id_evento"] ?? "").trim();
      if (!idEvento) return jsonResponse(400, { ok: false, code: "missing_id_evento", error: "id_evento requerido" });

      if (!(await permitirRateLimit(admin, "invitacion_rrpp_generar", `user:${user.id}`, user.id, 20, 60))) {
        return jsonResponse(429, { ok: false, code: "rate_limit_exceeded", error: "Demasiados QR generados. Esperá un instante." });
      }

      const { data: permiso, error: permErr } = await admin.rpc("puede_emitir_qr_invitacion", {
        p_uid: user.id,
        p_id_evento: idEvento,
      });
      if (permErr) return jsonResponse(500, { ok: false, code: "perm_check_failed", error: "Error al verificar permiso", detail: permErr.message });
      if (!permiso || permiso.puede !== true) {
        return jsonResponse(403, { ok: false, code: "forbidden", error: "No tenés permiso para generar QR de invitación en este evento" });
      }
      const estadoLocal = await localActivo(admin, String(permiso.id_local));
      if (!estadoLocal.ok) {
        return jsonResponse(estadoLocal.status, { ok: false, code: estadoLocal.code, error: estadoLocal.error });
      }

      const upsertRow = {
        id_evento: idEvento,
        id_local: String(permiso.id_local),
        id_rrpp: user.id,
        tipo: String(permiso.tipo ?? "staff"),
        pasar_cupo: permiso.pasar_cupo === true,
        activa: true,
      };
      const { data: inv, error: upErr } = await admin
        .from("invitaciones_rrpp")
        .upsert(upsertRow, { onConflict: "id_evento,id_rrpp" })
        .select("id_invitacion, tipo, pasar_cupo")
        .single();
      if (upErr || !inv) {
        return jsonResponse(500, { ok: false, code: "upsert_failed", error: "No se pudo generar la invitación", detail: upErr?.message });
      }

      return jsonResponse(200, {
        ok: true,
        id_invitacion: String(inv.id_invitacion),
        tipo: inv.tipo,
        pasar_cupo: inv.pasar_cupo === true,
      });
    }

    // ════════════════════════════════════════════════════════════════════════
    // ACCIÓN: resolver — el usuario escaneó el QR, devolvemos datos del evento
    // ════════════════════════════════════════════════════════════════════════
    if (accion === "resolver") {
      const idInvitacion = String(body["id_invitacion"] ?? "").trim();
      if (!idInvitacion) return jsonResponse(400, { ok: false, code: "missing_id_invitacion", error: "id_invitacion requerido" });

      if (!(await permitirRateLimit(admin, "invitacion_rrpp_resolver", `user:${user.id}`, user.id, 30, 60))) {
        return jsonResponse(429, { ok: false, code: "rate_limit_exceeded", error: "Demasiados intentos. Esperá un instante." });
      }
      if (!(await permitirRateLimit(admin, "invitacion_rrpp_resolver", `inv:${idInvitacion}`, user.id, 15, 60))) {
        return jsonResponse(429, { ok: false, code: "rate_limit_exceeded", error: "Demasiados intentos con esta invitación." });
      }

      const r = await resolverInvitacion(admin, idInvitacion);
      if (!r.ok) return jsonResponse(r.status, { ok: false, code: r.code, error: r.error });

      const { data: evento } = await admin
        .from("eventos")
        .select("id_evento, id_local, titulo_evento, estado_publicacion, fecha_inicio, fecha_fin")
        .eq("id_evento", r.ctx.id_evento)
        .maybeSingle();
      if (!evento) return jsonResponse(404, { ok: false, code: "event_not_found", error: "Evento no encontrado" });
      if (evento.estado_publicacion !== "publicado") {
        return jsonResponse(400, { ok: false, code: "event_not_published", error: "El evento no está disponible" });
      }
      const estadoLocal = await localActivo(admin, String(evento.id_local));
      if (!estadoLocal.ok) {
        return jsonResponse(estadoLocal.status, { ok: false, code: estadoLocal.code, error: estadoLocal.error });
      }
      if (new Date(evento.fecha_fin).getTime() <= Date.now()) {
        return jsonResponse(410, { ok: false, code: "event_ended", error: "El evento ya finalizó" });
      }

      const titulo = evento.titulo_evento ?? null;
      return jsonResponse(200, {
        ok: true,
        id_invitacion: r.ctx.id_invitacion,
        id_evento: r.ctx.id_evento,
        titulo_evento: titulo,
        nombre_evento: titulo,
        pasar_cupo: r.ctx.pasar_cupo,
      });
    }

    // ════════════════════════════════════════════════════════════════════════
    // ACCIÓN: reservar — auto-aceptada vía invitación (solo o squad)
    // ════════════════════════════════════════════════════════════════════════
    if (accion === "reservar") {
      const idInvitacion = String(body["id_invitacion"] ?? "").trim();
      const idGrupo = String(body["id_grupo"] ?? "").trim() || null;
      if (!idInvitacion) return jsonResponse(400, { ok: false, code: "missing_id_invitacion", error: "id_invitacion requerido" });

      if (!(await permitirRateLimit(admin, "invitacion_rrpp_reservar", `user:${user.id}`, user.id, 10, 60))) {
        return jsonResponse(429, { ok: false, code: "rate_limit_exceeded", error: "Demasiados intentos. Esperá un instante." });
      }
      if (!(await permitirRateLimit(admin, "invitacion_rrpp_reservar", `inv:${idInvitacion}`, user.id, 5, 60))) {
        return jsonResponse(429, { ok: false, code: "rate_limit_exceeded", error: "Demasiados intentos con esta invitación." });
      }

      const r = await resolverInvitacion(admin, idInvitacion);
      if (!r.ok) return jsonResponse(r.status, { ok: false, code: r.code, error: r.error });
      const ctx = r.ctx;

      // El RRPP no puede auto-invitarse a su propia lista (evita inflar métricas).
      if (user.id === ctx.id_rrpp) {
        return jsonResponse(400, { ok: false, code: "rrpp_self_invite", error: "No podés usar tu propia invitación de RRPP" });
      }

      // ── Leer evento ──────────────────────────────────────────────────────
      const { data: evento, error: evErr } = await admin
        .from("eventos")
        .select("id_evento, id_local, modo_lista, cupo_lista_max, cupo_lista_usados, fecha_inicio, fecha_fin, permite_squads, estado_publicacion, edad_minima, hora_limite_canje")
        .eq("id_evento", ctx.id_evento)
        .maybeSingle();
      if (evErr || !evento) return jsonResponse(404, { ok: false, code: "event_not_found", error: "Evento no encontrado" });
      if (evento.estado_publicacion !== "publicado") {
        return jsonResponse(400, { ok: false, code: "event_not_published", error: "El evento no está publicado" });
      }
      const estadoLocal = await localActivo(admin, String(evento.id_local));
      if (!estadoLocal.ok) {
        return jsonResponse(estadoLocal.status, { ok: false, code: estadoLocal.code, error: estadoLocal.error });
      }
      if (new Date(evento.fecha_fin).getTime() <= Date.now()) {
        return jsonResponse(410, { ok: false, code: "event_ended", error: "El evento ya finalizó" });
      }

      // ── Perfil del usuario (edad, cuenta activa) ─────────────────────────
      const { data: perfilUsuario, error: perfilErr } = await admin
        .from("perfiles_usuarios")
        .select("edad, estado_cuenta")
        .eq("id", user.id)
        .maybeSingle();
      if (perfilErr || !perfilUsuario) {
        return jsonResponse(403, { ok: false, code: "user_profile_not_found", error: "Perfil de usuario no encontrado" });
      }
      if (perfilUsuario.estado_cuenta !== "activa") {
        return jsonResponse(403, { ok: false, code: "account_suspended", error: "Tu cuenta está suspendida o baneada" });
      }
      if (evento.edad_minima != null && Number(perfilUsuario.edad ?? 0) < Number(evento.edad_minima)) {
        return jsonResponse(403, { ok: false, code: "underage", error: `Este evento requiere ser mayor de ${evento.edad_minima} años` });
      }

      // ── Resolver miembros (individual o squad) ───────────────────────────
      let miembros: string[] = [user.id];
      let idReservaGrupal: string | null = null;
      let snapshotSquad: Record<string, unknown> | null = null;

      if (idGrupo) {
        if (!evento.permite_squads) {
          return jsonResponse(400, { ok: false, code: "squad_disabled", error: "Este evento no permite squads" });
        }
        const { data: pertenencia } = await admin
          .from("miembros_grupos")
          .select("id_miembro")
          .eq("id_grupo", idGrupo)
          .eq("id_miembro", user.id)
          .eq("estado_miembro", "aceptado")
          .maybeSingle();
        if (!pertenencia) return jsonResponse(403, { ok: false, code: "not_group_member", error: "No perteneces a este squad" });

        const { data: filasMiembros, error: miembrosErr } = await admin
          .from("miembros_grupos")
          .select("id_miembro")
          .eq("id_grupo", idGrupo)
          .eq("estado_miembro", "aceptado");
        if (miembrosErr || !filasMiembros || filasMiembros.length === 0) {
          return jsonResponse(400, { ok: false, code: "empty_squad", error: "El squad no tiene miembros aceptados" });
        }
        miembros = filasMiembros.map((m) => String(m.id_miembro));
        idReservaGrupal = crypto.randomUUID();
        snapshotSquad = { id_grupo: idGrupo, miembros, cantidad: miembros.length, timestamp: new Date().toISOString() };
      }

      // ── Ningún miembro con reserva abierta ───────────────────────────────
      const { data: reservasExistentes } = await admin
        .from("tokens_asistencia")
        .select("id_token, id_usuario")
        .eq("id_evento", ctx.id_evento)
        .in("id_usuario", miembros)
        .in("estado_token", ["pendiente", "aceptada"]);
      if (reservasExistentes && reservasExistentes.length > 0) {
        return jsonResponse(409, {
          ok: false,
          code: "already_reserved",
          error: idGrupo
            ? "Uno o más miembros del squad ya tienen reserva activa en este evento"
            : "Ya tenés una reserva activa en este evento",
        });
      }

      const cantidad = miembros.length;
      // validarMax sólo si el RRPP NO puede pasar cupo
      const validarMax = !ctx.pasar_cupo;

      // ── fecha_expiracion ─────────────────────────────────────────────────
      const fechaExpiracion = evento.hora_limite_canje
        ? new Date(evento.hora_limite_canje)
        : new Date(new Date(evento.fecha_fin).getTime() + 3 * 60 * 60 * 1000);

      // ── Insertar token (siempre 'pendiente' primero, igual que AUTO) ─────
      const codigoPuerta = generarCodigoPuerta();
      const { data: tokenInsertado, error: insErr } = await admin
        .from("tokens_asistencia")
        .insert({
          id_evento: ctx.id_evento,
          id_usuario: user.id,
          id_grupo: idGrupo,
          id_reserva_grupal: idReservaGrupal,
          estado_token: "pendiente",
          fecha_expiracion: fechaExpiracion.toISOString(),
          snapshot_squad: snapshotSquad,
          codigo_puerta: codigoPuerta,
          id_invitacion_rrpp: ctx.id_invitacion,
          id_rrpp: ctx.id_rrpp,
        })
        .select("id_token")
        .single();
      if (insErr || !tokenInsertado) {
        return jsonResponse(400, { ok: false, code: "insert_failed", error: "No se pudo crear la reserva", detail: insErr?.message });
      }
      const idToken = String(tokenInsertado.id_token);

      // ── Ajustar cupo (CAS). Si pasar_cupo → no valida el máximo ──────────
      const ajuste = await ajustarCupoLista(admin, ctx.id_evento, cantidad, { validarMax });
      if (!ajuste.ok) {
        await admin.from("tokens_asistencia").delete().eq("id_token", idToken);
        return jsonResponse(409, {
          ok: false,
          code: ajuste.code,
          error: ajuste.code === "list_full" ? "El cupo se llenó, no hay lugar disponible" : ajuste.error,
        });
      }

      // ── Pasar a aceptada (atribuida al RRPP para historial staff) ────────
      const { error: upErr } = await admin
        .from("tokens_asistencia")
        .update({
          estado_token: "aceptada",
          fecha_respuesta: new Date().toISOString(),
          respondido_por: ctx.id_rrpp,
        })
        .eq("id_token", idToken)
        .eq("estado_token", "pendiente");
      if (upErr) {
        await ajustarCupoLista(admin, ctx.id_evento, -cantidad, { validarMax: false, clampMinZero: true });
        await admin.from("tokens_asistencia").delete().eq("id_token", idToken);
        return jsonResponse(500, { ok: false, code: "accept_failed", error: "Error al confirmar la reserva, intentá de nuevo" });
      }

      // Métrica (no crítico)
      await admin.rpc("increment_metric", {
        p_id_evento: ctx.id_evento,
        p_campo: "metric_reservas_aceptadas",
        p_delta: 1,
      }).catch(() => {});
      await admin.rpc("increment_metric", {
        p_id_evento: ctx.id_evento,
        p_campo: "metric_tokens_emitidos",
        p_delta: 1,
      }).catch(() => {});

      return jsonResponse(200, {
        ok: true,
        id_token: idToken,
        estado: "aceptada",
        id_reserva_grupal: idReservaGrupal,
        es_squad: !!idGrupo,
        cantidad_miembros: cantidad,
        codigo_puerta: codigoPuerta,
        fecha_expiracion: fechaExpiracion.toISOString(),
        via_invitacion: true,
      });
    }

    return jsonResponse(400, {
      ok: false,
      code: "invalid_action",
      error: "Accion invalida. Usa: generar, resolver, reservar",
    });
  } catch (e) {
    console.error("invitacion_rrpp_error", e);
    return jsonResponse(500, { ok: false, code: "internal_error", error: "Error interno del servidor" });
  }
});
