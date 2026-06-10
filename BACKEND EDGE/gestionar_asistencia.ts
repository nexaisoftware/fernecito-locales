import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), { status, headers: jsonHeaders });
const isPlainObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const authorizationHeader = (req: Request) => (req.headers.get("Authorization") ?? "").trim();

// ─── Generar codigo_puerta único (8 chars alfanumérico sin ambiguos) ──────────
function generarCodigoPuerta(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // sin 0,O,1,I para legibilidad
  let code = "";
  for (let i = 0; i < 8; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

// ─── Ajuste de cupo con compare-and-swap ──────────────────────────────────────
type AjusteCupoResultado =
  | { ok: true; usados: number; max: number | null }
  | { ok: false; code: string; error: string; detail?: string };

async function ajustarCupoLista(
  admin: ReturnType<typeof createClient>,
  idEvento: string,
  delta: number,
  opciones: { validarMax: boolean; clampMinZero?: boolean; maxReintentos?: number },
): Promise<AjusteCupoResultado> {
  const clampMinZero = opciones.clampMinZero ?? false;
  const maxReintentos = opciones.maxReintentos ?? 6;

  for (let i = 0; i < maxReintentos; i++) {
    const { data: evento, error: evErr } = await admin
      .from("eventos")
      .select("cupo_lista_usados, cupo_lista_max")
      .eq("id_evento", idEvento)
      .maybeSingle();
    if (evErr || !evento) return { ok: false, code: "event_not_found", error: "Evento no encontrado", detail: evErr?.message };

    const usadosActuales = Number(evento.cupo_lista_usados ?? 0);
    const cupoMax = evento.cupo_lista_max == null ? null : Number(evento.cupo_lista_max);
    let usadosSiguiente = usadosActuales + delta;

    if (usadosSiguiente < 0) {
      if (clampMinZero) usadosSiguiente = 0;
      else return { ok: false, code: "list_counter_underflow", error: "cupo_lista_usados no puede ser negativo" };
    }
    // validarMax=true pero en modo manual el overflow es permitido (ver lógica principal)
    if (opciones.validarMax && cupoMax != null && usadosSiguiente > cupoMax) {
      return { ok: false, code: "list_full", error: "No hay cupo suficiente para aceptar esta reserva" };
    }

    const { data: upData, error: upErr } = await admin
      .from("eventos")
      .update({ cupo_lista_usados: usadosSiguiente })
      .eq("id_evento", idEvento)
      .eq("cupo_lista_usados", usadosActuales)
      .select("id_evento")
      .maybeSingle();
    if (upErr) {
      return { ok: false, code: "list_counter_update_failed", error: "No se pudo actualizar cupo_lista_usados", detail: upErr.message };
    }
    if (upData) return { ok: true, usados: usadosSiguiente, max: cupoMax };
  }

  return { ok: false, code: "counter_retry_conflict", error: "No se pudo confirmar cupos por concurrencia. Intentá nuevamente." };
}

// ─── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse(405, { ok: false, code: "method_not_allowed", error: "Metodo no permitido" });

  try {
    const url = Deno.env.get("SUPABASE_URL") ?? "";
    const anon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!url || !anon || !service) return jsonResponse(500, { ok: false, code: "server_config_missing", error: "Configuracion incompleta" });

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

    const accion    = String(body["accion"] ?? "").toLowerCase();
    const idToken   = String(body["id_token"] ?? "").trim();
    const idReserva = String(body["id_reserva_grupal"] ?? "").trim();

    if (!["aceptar", "rechazar"].includes(accion)) {
      return jsonResponse(400, { ok: false, code: "invalid_action", error: "accion invalida. Usar 'aceptar' o 'rechazar'" });
    }
    if (!idToken && !idReserva) {
      return jsonResponse(400, { ok: false, code: "missing_target", error: "id_token o id_reserva_grupal requerido" });
    }

    // ── Rate limiting (fail-open: si la RPC falla, deja pasar) ────────────────
    // 300 req/min por user (un local acepta ~3-5/min máximo, holgado 60x).
    try {
      const { data: rlUser, error: rlErr } = await admin.rpc("check_rate_limit", {
        p_edge: "gestionar_asistencia",
        p_identifier: `user:${user.id}`,
        p_user_id: user.id,
        p_max: 300,
        p_ventana_segs: 60,
      });
      if (rlErr) {
        console.error("rate_limit_rpc_failed", { edge: "gestionar_asistencia", error: rlErr.message });
      } else if (rlUser === false) {
        return jsonResponse(429, { ok: false, code: "rate_limit_exceeded", error: "Demasiados intentos, esperá un instante y reintentá." });
      }
    } catch (rlException) {
      // Cualquier fallo del rate limit NO debe trabar el flow del local.
      console.error("rate_limit_exception", { edge: "gestionar_asistencia", error: String(rlException) });
    }

    // ── Obtener token(s) ──────────────────────────────────────────────────────
    let query = admin
      .from("tokens_asistencia")
      .select("id_token, id_evento, id_usuario, id_grupo, id_reserva_grupal, estado_token, snapshot_squad");
    query = idToken
      ? query.eq("id_token", idToken)
      : query.eq("id_reserva_grupal", idReserva);

    const { data: tokens, error: tokErr } = await query;
    if (tokErr || !tokens || tokens.length === 0) {
      return jsonResponse(404, { ok: false, code: "tokens_not_found", error: "Reserva no encontrada" });
    }

    const idEvento = String(tokens[0].id_evento);

    // ── Verificar evento y permisos ───────────────────────────────────────────
    const { data: evento, error: evErr } = await admin
      .from("eventos")
      .select("id_local, modo_lista, cupo_lista_max, cupo_lista_usados")
      .eq("id_evento", idEvento)
      .maybeSingle();
    if (evErr || !evento) return jsonResponse(404, { ok: false, code: "event_not_found", error: "Evento no encontrado" });

    const esOwner = String(evento.id_local) === user.id;
    let esStaff = false;
    let staffPermisos: { habilitado_aceptar_listas?: boolean } | null = null;
    if (!esOwner) {
      const { data: staff } = await admin
        .from("local_staff")
        .select("id_staff, habilitado_aceptar_listas")
        .eq("id_local", evento.id_local)
        .eq("id_staff", user.id)
        .eq("activo", true)
        .maybeSingle();
      esStaff = !!staff;
      staffPermisos = staff;
    }
    if (!esOwner && !esStaff) {
      return jsonResponse(403, { ok: false, code: "forbidden_actor", error: "No autorizado para gestionar esta lista" });
    }
    // Chequeo de permiso granular: si es staff y le sacaron el flag, denegar.
    // (owner siempre puede; el flag false solo aplica a staff)
    if (esStaff && staffPermisos?.habilitado_aceptar_listas === false) {
      return jsonResponse(403, {
        ok: false,
        code: "permission_denied",
        error: "No tenés permiso para aceptar/rechazar listas en este local",
      });
    }

    // ── Verificar que todos están pendientes ──────────────────────────────────
    if (tokens.some((t) => t.estado_token !== "pendiente")) {
      return jsonResponse(409, { ok: false, code: "invalid_state", error: "Solo se pueden gestionar reservas pendientes" });
    }

    const ids     = tokens.map((t) => String(t.id_token));
    const cantidad = ids.length; // 1 token = 1 unidad (squad o individuo)

    // ── Calcular cantidad de personas (para métricas y overflow info) ─────────
    // Si es squad, el snapshot_squad.cantidad indica cuántas personas abarca
    let cantidadPersonas = cantidad;
    if (tokens[0].snapshot_squad && typeof tokens[0].snapshot_squad === "object") {
      const snap = tokens[0].snapshot_squad as Record<string, unknown>;
      if (typeof snap["cantidad"] === "number") {
        cantidadPersonas = snap["cantidad"] as number;
      }
    }

    // ── ACEPTAR ───────────────────────────────────────────────────────────────
    if (accion === "aceptar") {
      const cupoMax  = evento.cupo_lista_max == null ? null : Number(evento.cupo_lista_max);
      const usados   = Number(evento.cupo_lista_usados ?? 0);
      const esModeManual = evento.modo_lista === "manual";

      // Overflow: en modo manual el local puede aceptar aun pasando el límite
      const esOverflow = cupoMax != null && (usados + cantidad) > cupoMax;

      if (esOverflow && !esModeManual) {
        // En modo auto nunca debería llegar aquí (solicitar_asistencia bloquea antes)
        // Pero por seguridad bloqueamos en modo auto también
        return jsonResponse(409, {
          ok: false,
          code: "list_full",
          error: "No hay cupo disponible para aceptar esta reserva",
          cupo_disponible: Math.max(0, (cupoMax ?? 0) - usados),
        });
      }

      // Ajustar cupo (sin validar max si es manual overflow)
      const ajuste = await ajustarCupoLista(admin, idEvento, cantidad, {
        validarMax: !esModeManual, // manual siempre pasa, auto valida
        clampMinZero: false,
      });
      if (!ajuste.ok) {
        return jsonResponse(409, {
          ok: false,
          code: ajuste.code === "list_full" ? "list_full" : "list_capacity_retry",
          error: ajuste.code === "list_full"
            ? "No hay cupo disponible en este momento, intentá de nuevo."
            : ajuste.error,
          detail: ajuste.detail,
        });
      }

      // Generar codigo_puerta para cada token aceptado (modo manual)
      // En auto ya se generó al crear. En manual se genera aquí al aceptar.
      const patchBase: Record<string, unknown> = {
        estado_token:    "aceptada",
        fecha_respuesta: new Date().toISOString(),
        respondido_por:  user.id, // tracking: quién aceptó (owner o staff)
      };

      // Para cada token en modo manual, generar su propio codigo_puerta
      // Si es un solo token (case normal), hacemos update masivo con código único
      // Si son múltiples tokens de un mismo id_reserva_grupal, cada uno necesita código único
      if (esModeManual) {
        // Actualizar uno por uno para asignar código único a cada token
        const errores: string[] = [];
        for (const tokId of ids) {
          const { error: upErr } = await admin
            .from("tokens_asistencia")
            .update({
              ...patchBase,
              codigo_puerta: generarCodigoPuerta(),
            })
            .eq("id_token", tokId)
            .eq("estado_token", "pendiente");
          if (upErr) errores.push(tokId);
        }

        if (errores.length > 0) {
          // Rollback cupo
          await ajustarCupoLista(admin, idEvento, -cantidad, { validarMax: false, clampMinZero: true });
          return jsonResponse(500, {
            ok: false,
            code: "accept_failed",
            error: "Error al confirmar una o más reservas, intentá de nuevo",
          });
        }
      } else {
        // Modo auto: codigo_puerta ya existe, solo actualizar estado
        const { error: upErr } = await admin
          .from("tokens_asistencia")
          .update(patchBase)
          .in("id_token", ids)
          .eq("estado_token", "pendiente");

        if (upErr) {
          await ajustarCupoLista(admin, idEvento, -cantidad, { validarMax: false, clampMinZero: true });
          return jsonResponse(400, {
            ok: false,
            code: "update_failed",
            error: "No se pudo actualizar la reserva",
            detail: upErr.message,
          });
        }
      }

      // Actualizar métrica (no crítico)
      await admin.rpc("increment_metric", {
        p_id_evento: idEvento,
        p_campo:     "metric_reservas_aceptadas",
        p_delta:     1,
      }).catch(() => {});

      // ── Notif: cupo lleno ──────────────────────────────────────────────────
      // Si tras este aceptar el cupo quedó completo (sin overflow), avisamos al local.
      try {
        if (ajuste.max != null && ajuste.usados >= ajuste.max && !esOverflow) {
          // Titulo del evento (fetch corto)
          const { data: ev } = await admin
            .from("eventos")
            .select("titulo_evento")
            .eq("id_evento", idEvento)
            .maybeSingle();
          const titulo = ev?.titulo_evento ?? "tu evento";
          await admin.rpc("crear_notif_local", {
            p_id_local: evento.id_local,
            p_tipo: "cupo_lleno",
            p_titulo: "¡Lista llena!",
            p_descripcion: `"${titulo}" llegó al cupo máximo (${ajuste.max} personas).`,
            p_prioridad: "media",
            p_icono_key: "person_3_fill",
            p_cta_texto: "Ver evento",
            p_cta_ruta: "/mis_eventos",
            p_cta_id_ref: idEvento,
            p_payload: { cupo_max: ajuste.max, cupos_usados: ajuste.usados },
            p_dedup_key: `cupo_lleno:${idEvento}`,
            // sin dedup_horas = dedup eterno: 1 sola notif por evento
          }).catch((e) => console.error("notif cupo_lleno falló (no crítico):", e));
        }
      } catch (e) {
        console.error("notif cupo_lleno exception (no crítico):", e);
      }

      return jsonResponse(200, {
        ok:                true,
        accion:            "aceptar",
        cantidad:          cantidad,
        cantidad_personas: cantidadPersonas,
        overflow:          esOverflow,
        cupos_usados:      ajuste.usados,
        cupo_max:          ajuste.max,
      });
    }

    // ── RECHAZAR ──────────────────────────────────────────────────────────────
    const { data: updatedRows, error: upErr } = await admin
      .from("tokens_asistencia")
      .update({
        estado_token:    "rechazada",
        fecha_respuesta: new Date().toISOString(),
        respondido_por:  user.id, // tracking: quién rechazó (owner o staff)
      })
      .in("id_token", ids)
      .eq("estado_token", "pendiente")
      .select("id_token");

    if (upErr) {
      return jsonResponse(400, {
        ok: false,
        code: "update_failed",
        error: "No se pudo rechazar la reserva",
        detail: upErr.message,
      });
    }
    if ((updatedRows ?? []).length !== ids.length) {
      return jsonResponse(409, {
        ok: false,
        code: "stale_pending_state",
        error: "La reserva cambió de estado durante la operación. Intentá de nuevo.",
      });
    }

    return jsonResponse(200, {
      ok:                true,
      accion:            "rechazar",
      cantidad:          cantidad,
      cantidad_personas: cantidadPersonas,
    });

  } catch (e) {
    const detalle = e instanceof Error ? `${e.name}: ${e.message}` : String(e);
    console.error("gestionar_asistencia_error", detalle, e);
    return jsonResponse(500, {
      ok: false,
      code: "internal_error",
      error: "Error interno del servidor",
      detail: detalle,
    });
  }
});
