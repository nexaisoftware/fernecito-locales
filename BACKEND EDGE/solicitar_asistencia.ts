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
const authorizationHeader = (req: Request) =>
  (req.headers.get("Authorization") ?? "").trim();

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
    return { ok: false, status: 403, code: "local_suspended", error: "Este evento no esta disponible" };
  }
  return { ok: true };
}

// ─── Generar codigo_puerta único (8 chars alfanumérico sin ambiguos) ──────────
// Solo se usa en modo AUTO — en manual se genera al aceptar (gestionar_asistencia)
function generarCodigoPuerta(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // sin 0,O,1,I para legibilidad
  let code = "";
  for (let i = 0; i < 8; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

// ─── Ajuste de cupo con compare-and-swap (retry ante concurrencia) ────────────
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
  const maxR  = opciones.maxReintentos ?? 6;

  for (let i = 0; i < maxR; i++) {
    const { data: ev, error: evErr } = await admin
      .from("eventos")
      .select("cupo_lista_usados, cupo_lista_max")
      .eq("id_evento", idEvento)
      .maybeSingle();
    if (evErr || !ev) {
      return { ok: false, code: "event_not_found", error: "Evento no encontrado", detail: evErr?.message };
    }

    const usados  = Number(ev.cupo_lista_usados ?? 0);
    const cupoMax = ev.cupo_lista_max == null ? null : Number(ev.cupo_lista_max);
    let siguiente = usados + delta;

    if (siguiente < 0) {
      if (clamp) siguiente = 0;
      else return { ok: false, code: "list_counter_underflow", error: "cupo_lista_usados no puede ser negativo" };
    }
    // Solo bloquear si validarMax=true Y hay límite definido
    if (opciones.validarMax && cupoMax != null && siguiente > cupoMax) {
      return { ok: false, code: "list_full", error: "No hay cupo disponible" };
    }

    const { data: upd, error: upErr } = await admin
      .from("eventos")
      .update({ cupo_lista_usados: siguiente })
      .eq("id_evento", idEvento)
      .eq("cupo_lista_usados", usados) // CAS
      .select("id_evento")
      .maybeSingle();

    if (upErr) return { ok: false, code: "counter_update_failed", error: "Error al actualizar cupo", detail: upErr.message };
    if (upd)   return { ok: true, usados: siguiente, max: cupoMax };
    // Si no actualizó → otro proceso cambió el valor, reintentar
  }
  return { ok: false, code: "counter_retry_conflict", error: "Conflicto de concurrencia, intentá de nuevo" };
}

// ─── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, code: "method_not_allowed", error: "Metodo no permitido" });
  }

  try {
    const url     = Deno.env.get("SUPABASE_URL") ?? "";
    const anon    = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
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

    // ── Rate limiting (fail-open: si la RPC falla, deja pasar) ─────────────────
    // Anti-spam de solicitudes: 15 solicitudes/min por usuario.
    try {
      const { data: rlOk, error: rlErr } = await admin.rpc("check_rate_limit", {
        p_edge: "solicitar_asistencia",
        p_identifier: `user:${user.id}`,
        p_user_id: user.id,
        p_max: 15,
        p_ventana_segs: 60,
      });
      if (rlErr) {
        console.error("rate_limit_rpc_failed", { edge: "solicitar_asistencia", error: rlErr.message });
      } else if (rlOk === false) {
        return jsonResponse(429, { ok: false, code: "rate_limit_exceeded", error: "Demasiadas solicitudes, esperá un instante y reintentá." });
      }
    } catch (rlException) {
      console.error("rate_limit_exception", { edge: "solicitar_asistencia", error: String(rlException) });
    }

    const bodyRaw = await req.json().catch(() => null);
    if (!isPlainObject(bodyRaw)) {
      return jsonResponse(400, { ok: false, code: "invalid_body", error: "Body invalido" });
    }

    const idEvento = String(bodyRaw["id_evento"] ?? "").trim();
    const idGrupo  = String(bodyRaw["id_grupo"] ?? "").trim() || null;
    if (!idEvento) return jsonResponse(400, { ok: false, code: "missing_id_evento", error: "id_evento requerido" });

    // ── Leer evento ───────────────────────────────────────────────────────────
    const { data: evento, error: evErr } = await admin
      .from("eventos")
      .select("id_evento, id_local, modo_lista, modo_evento, cupo_lista_max, cupo_lista_usados, fecha_inicio, fecha_fin, fecha_fin_jerarquia, permite_squads, estado_publicacion, edad_minima, hora_limite_canje")
      .eq("id_evento", idEvento)
      .maybeSingle();

    if (evErr || !evento) return jsonResponse(404, { ok: false, code: "event_not_found", error: "Evento no encontrado" });
    if (evento.estado_publicacion !== "publicado") {
      return jsonResponse(400, { ok: false, code: "event_not_published", error: "El evento no esta publicado" });
    }
    const estadoLocal = await localActivo(admin, String(evento.id_local));
    if (!estadoLocal.ok) {
      return jsonResponse(estadoLocal.status, { ok: false, code: estadoLocal.code, error: estadoLocal.error });
    }
    // Modo simple (vidriera): el evento es solo informativo, no acepta reservas.
    if (evento.modo_evento === "simple") {
      return jsonResponse(409, { ok: false, code: "event_info_only", error: "Este evento es solo informativo: no tiene reservas ni promos disponibles" });
    }
    // No se puede solicitar después de que empezó el evento
    if (new Date(evento.fecha_inicio).getTime() <= Date.now()) {
      return jsonResponse(400, { ok: false, code: "event_started", error: "El evento ya comenzo, no se puede solicitar lista" });
    }

    // ── Verificar perfil del usuario (edad, cuenta activa) ────────────────────
    const { data: perfilUsuario, error: perfilErr } = await admin
      .from("perfiles_usuarios")
      .select("edad, estado_cuenta")
      .eq("id", user.id)
      .maybeSingle();

    if (perfilErr || !perfilUsuario) {
      return jsonResponse(403, { ok: false, code: "user_profile_not_found", error: "Perfil de usuario no encontrado" });
    }
    if (perfilUsuario.estado_cuenta !== "activa") {
      return jsonResponse(403, { ok: false, code: "account_suspended", error: "Tu cuenta esta suspendida o baneada" });
    }
    if (evento.edad_minima != null) {
      const edad = Number(perfilUsuario.edad ?? 0);
      if (edad < Number(evento.edad_minima)) {
        return jsonResponse(403, {
          ok: false,
          code: "underage",
          error: `Este evento requiere ser mayor de ${evento.edad_minima} años`,
        });
      }
    }

    // ── Resolver miembros (individual o squad) ────────────────────────────────
    let miembros: string[] = [user.id];
    let idReservaGrupal: string | null = null;
    let snapshotSquad: Record<string, unknown> | null = null;

    if (idGrupo) {
      if (!evento.permite_squads) {
        return jsonResponse(400, { ok: false, code: "squad_disabled", error: "Este evento no permite squads" });
      }

      // Verificar que el usuario pertenece al squad
      const { data: pertenencia } = await admin
        .from("miembros_grupos")
        .select("id_miembro")
        .eq("id_grupo", idGrupo)
        .eq("id_miembro", user.id)
        .eq("estado_miembro", "aceptado")
        .maybeSingle();
      if (!pertenencia) {
        return jsonResponse(403, { ok: false, code: "not_group_member", error: "No perteneces a este squad" });
      }

      // Obtener todos los miembros aceptados del squad
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
      snapshotSquad = {
        id_grupo: idGrupo,
        miembros,
        cantidad: miembros.length,
        timestamp: new Date().toISOString(),
      };
    }

    // ── Verificar que ningún miembro ya tenga reserva abierta ─────────────────
    // Para squad: chequeamos todos los UIDs del squad en una sola query
    const { data: reservasExistentes } = await admin
      .from("tokens_asistencia")
      .select("id_token, id_usuario")
      .eq("id_evento", idEvento)
      .in("id_usuario", miembros)
      .in("estado_token", ["pendiente", "aceptada"]);

    if (reservasExistentes && reservasExistentes.length > 0) {
      return jsonResponse(409, {
        ok: false,
        code: "already_reserved",
        error: idGrupo
          ? "Uno o mas miembros del squad ya tienen reserva activa en este evento"
          : "Ya tenes una reserva activa en este evento",
      });
    }

    // ── Lógica por modo_lista ─────────────────────────────────────────────────
    const esAuto   = evento.modo_lista === "auto";
    const cupoMax  = evento.cupo_lista_max == null ? null : Number(evento.cupo_lista_max);
    const cantidad = miembros.length;

    // En AUTO con límite: verificar que el squad completo entra antes de insertar
    if (esAuto && cupoMax != null) {
      const usados = Number(evento.cupo_lista_usados ?? 0);
      if (usados + cantidad > cupoMax) {
        return jsonResponse(409, {
          ok: false,
          code: "list_full",
          error: idGrupo
            ? `No hay suficiente cupo para el squad completo (${cantidad} personas). Quedan ${cupoMax - usados} lugares.`
            : "No hay cupo disponible en este evento",
          cupo_disponible: cupoMax - usados,
          cupo_solicitado: cantidad,
        });
      }
    }

    // ── Calcular fecha_expiracion del token ───────────────────────────────────
    // Si el evento tiene hora_limite_canje, expira ahí. Si no, fecha_fin + 3hs.
    let fechaExpiracion: Date;
    if (evento.hora_limite_canje) {
      fechaExpiracion = new Date(evento.hora_limite_canje);
    } else {
      fechaExpiracion = new Date(new Date(evento.fecha_fin).getTime() + 3 * 60 * 60 * 1000);
    }

    // ── Insertar UN token por solicitud (squad o individual) ──────────────────
    // Un token = una unidad de entrada (squad o persona)
    // El snapshot_squad contiene el detalle de quiénes son
    const estadoInicial = "pendiente"; // siempre pendiente primero
    const codigoPuerta  = esAuto ? generarCodigoPuerta() : null; // solo en auto

    const tokenRow = {
      id_evento:         idEvento,
      id_usuario:        user.id, // quien hizo la solicitud (líder o individuo)
      id_grupo:          idGrupo,
      id_reserva_grupal: idReservaGrupal,
      estado_token:      estadoInicial,
      fecha_expiracion:  fechaExpiracion.toISOString(),
      snapshot_squad:    snapshotSquad,
      codigo_puerta:     codigoPuerta,
    };

    const { data: tokenInsertado, error: insErr } = await admin
      .from("tokens_asistencia")
      .insert(tokenRow)
      .select("id_token")
      .single();

    if (insErr || !tokenInsertado) {
      return jsonResponse(400, {
        ok: false,
        code: "insert_failed",
        error: "No se pudo crear la reserva",
        detail: insErr?.message,
      });
    }

    const idToken = String(tokenInsertado.id_token);

    // ── En AUTO: ajustar cupo y pasar a aceptada ──────────────────────────────
    if (esAuto) {
      // Ajustar cupo (validando máximo para evitar race condition)
      const ajuste = await ajustarCupoLista(admin, idEvento, cantidad, { validarMax: true });
      if (!ajuste.ok) {
        // Rollback: eliminar el token recién insertado
        await admin.from("tokens_asistencia").delete().eq("id_token", idToken);
        return jsonResponse(409, {
          ok: false,
          code: ajuste.code,
          error: ajuste.code === "list_full"
            ? "El cupo se llenó justo ahora, intentá de nuevo"
            : ajuste.error,
        });
      }

      // Pasar a aceptada + registrar fecha_respuesta
      const { error: upErr } = await admin
        .from("tokens_asistencia")
        .update({
          estado_token:    "aceptada",
          fecha_respuesta: new Date().toISOString(),
        })
        .eq("id_token", idToken)
        .eq("estado_token", "pendiente");

      if (upErr) {
        // Rollback cupo y token
        await ajustarCupoLista(admin, idEvento, -cantidad, { validarMax: false, clampMinZero: true });
        await admin.from("tokens_asistencia").delete().eq("id_token", idToken);
        return jsonResponse(500, { ok: false, code: "accept_failed", error: "Error al confirmar la reserva, intentá de nuevo" });
      }

      // Actualizar métricas del evento
      await admin.rpc("increment_metric", {
        p_id_evento: idEvento,
        p_campo: "metric_tokens_emitidos",
        p_delta: 1,
      }).catch(() => {}); // no crítico

      // ── Notif: cupo lleno (modo AUTO, tras este aceptar quedó al tope) ────
      try {
        if (ajuste.max != null && ajuste.usados >= ajuste.max) {
          await admin.rpc("crear_notif_local", {
            p_id_local: evento.id_local,
            p_tipo: "cupo_lleno",
            p_titulo: "¡Lista llena!",
            p_descripcion: `Tu evento llegó al cupo máximo (${ajuste.max} personas).`,
            p_prioridad: "media",
            p_icono_key: "person_3_fill",
            p_cta_texto: "Ver evento",
            p_cta_ruta: "/mis_eventos",
            p_cta_id_ref: idEvento,
            p_payload: { cupo_max: ajuste.max, cupos_usados: ajuste.usados },
            p_dedup_key: `cupo_lleno:${idEvento}`,
          }).catch((e) => console.error("notif cupo_lleno auto falló (no crítico):", e));
        }
      } catch (e) {
        console.error("notif cupo_lleno auto exception (no crítico):", e);
      }
    } else {
      // ── Notif: lista pendiente ≥5 (modo MANUAL) ──────────────────────────
      // Contamos pendientes actuales para este evento y si llegó/superó 5
      // creamos notif (dedupeada eterna por evento — 1 sola vez).
      try {
        const { count: pendientesCount } = await admin
          .from("tokens_asistencia")
          .select("id_token", { count: "exact", head: true })
          .eq("id_evento", idEvento)
          .eq("estado_token", "pendiente");
        if ((pendientesCount ?? 0) >= 5) {
          await admin.rpc("crear_notif_local", {
            p_id_local: evento.id_local,
            p_tipo: "lista_pendiente_5",
            p_titulo: "Tenés solicitudes pendientes",
            p_descripcion: `Hay ${pendientesCount} solicitudes esperando tu aprobación.`,
            p_prioridad: "alta",
            p_icono_key: "list_bullet",
            p_cta_texto: "Administrar listas",
            p_cta_ruta: "/validar",
            p_cta_id_ref: idEvento,
            p_payload: { cantidad: pendientesCount },
            p_dedup_key: `lista_pend5:${idEvento}`,
            // dedup eterno por evento: 1 sola notif por evento
          }).catch((e) => console.error("notif lista_pend5 falló (no crítico):", e));
        }
      } catch (e) {
        console.error("notif lista_pend5 exception (no crítico):", e);
      }
    }

    // ── Respuesta ─────────────────────────────────────────────────────────────
    return jsonResponse(200, {
      ok: true,
      id_token:          idToken,
      estado:            esAuto ? "aceptada" : "pendiente",
      id_reserva_grupal: idReservaGrupal,
      es_squad:          !!idGrupo,
      cantidad_miembros: cantidad,
      codigo_puerta:     esAuto ? codigoPuerta : null,
      fecha_expiracion:  fechaExpiracion.toISOString(),
    });

  } catch (e) {
    console.error("solicitar_asistencia_error", e);
    return jsonResponse(500, { ok: false, code: "internal_error", error: "Error interno del servidor" });
  }
});
