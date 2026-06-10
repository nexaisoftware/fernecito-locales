import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), { status, headers: jsonHeaders });
const isPlainObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const authorizationHeader = (req: Request) => (req.headers.get("Authorization") ?? "").trim();

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
    if (opciones.validarMax && cupoMax != null && usadosSiguiente > cupoMax) {
      return { ok: false, code: "list_full", error: "No hay cupo disponible para la lista" };
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
      return jsonResponse(401, {
        ok: false,
        code: "invalid_jwt",
        error: "No autenticado",
        detail: authError?.message,
      });
    }

    const admin = createClient(url, service);
    const body = await req.json().catch(() => null);
    if (!isPlainObject(body)) return jsonResponse(400, { ok: false, code: "invalid_body", error: "Body invalido" });

    const idToken = String(body["id_token"] ?? "");
    const idReserva = String(body["id_reserva_grupal"] ?? "");
    if (!idToken && !idReserva) return jsonResponse(400, { ok: false, code: "missing_target", error: "id_token o id_reserva_grupal requerido" });

    let q = admin
      .from("tokens_asistencia")
      .select("id_token, id_evento, id_usuario, id_reserva_grupal, estado_token");
    q = idToken ? q.eq("id_token", idToken) : q.eq("id_reserva_grupal", idReserva);
    const { data: tokens, error: tokErr } = await q;
    if (tokErr || !tokens || tokens.length === 0) return jsonResponse(404, { ok: false, code: "token_not_found", error: "Reserva no encontrada" });

    if (tokens.some((t) => String(t.id_usuario) !== user.id)) {
      return jsonResponse(403, { ok: false, code: "forbidden_owner", error: "Solo el titular puede cancelar" });
    }

    const cancelables = tokens.filter((t) => ["pendiente", "aceptada"].includes(String(t.estado_token)));
    if (cancelables.length === 0) return jsonResponse(409, { ok: false, code: "not_cancelable", error: "No hay reservas cancelables" });
    const cantidadAceptadasCanceladas = cancelables.filter((t) => String(t.estado_token) === "aceptada").length;

    const ids = cancelables.map((t) => String(t.id_token));
    const idEvento = String(cancelables[0].id_evento);
    const usuarios = [...new Set(cancelables.map((t) => String(t.id_usuario)))];
    const reserva = cancelables[0].id_reserva_grupal ? String(cancelables[0].id_reserva_grupal) : null;

    const { error: upErr } = await admin
      .from("tokens_asistencia")
      .update({ estado_token: "cancelada", fecha_respuesta: new Date().toISOString() })
      .in("id_token", ids);
    if (upErr) return jsonResponse(400, { ok: false, code: "cancel_failed", error: "No se pudo cancelar asistencia", detail: upErr.message });

    if (cantidadAceptadasCanceladas > 0) {
      const ajuste = await ajustarCupoLista(admin, idEvento, -cantidadAceptadasCanceladas, {
        validarMax: false,
        clampMinZero: true,
      });
      if (!ajuste.ok) {
        console.error("cancelar_asistencia_cupo_ajuste_failed", {
          id_evento: idEvento,
          cantidad: cantidadAceptadasCanceladas,
          code: ajuste.code,
          error: ajuste.error,
          detail: ajuste.detail,
        });
        return jsonResponse(409, {
          ok: false,
          code: ajuste.code,
          error: "No se pudo liberar cupo de lista en este momento, intentá de nuevo.",
          detail: ajuste.detail,
        });
      }
    }

    // Cancela promociones activas asociadas al evento para esos usuarios.
    const { data: promoMadre } = await admin.from("promociones").select("id_promocion").eq("id_evento", idEvento);
    const promoIds = (promoMadre ?? []).map((p) => String(p.id_promocion));
    if (promoIds.length > 0) {
      let pq = admin
        .from("tokens_promociones")
        .select("id_token, id_promocion")
        .in("id_promocion", promoIds)
        .eq("estado_token", "activo");
      pq = reserva ? pq.eq("id_reserva_grupal", reserva) : pq.in("id_usuario", usuarios);
      const { data: tokensPromo } = await pq;
      if (tokensPromo && tokensPromo.length > 0) {
        const idsPromo = tokensPromo.map((t) => String(t.id_token));
        await admin
          .from("tokens_promociones")
          .update({ estado_token: "cancelado" })
          .in("id_token", idsPromo);

        const porPromo = new Map<string, number>();
        for (const t of tokensPromo) {
          const idPromo = String(t.id_promocion);
          porPromo.set(idPromo, (porPromo.get(idPromo) ?? 0) + 1);
        }
        for (const [idPromo, cant] of porPromo.entries()) {
          const { data: p } = await admin.from("promociones").select("cupos_usados").eq("id_promocion", idPromo).maybeSingle();
          const usados = Number(p?.cupos_usados ?? 0);
          await admin
            .from("promociones")
            .update({ cupos_usados: Math.max(0, usados - cant), fecha_actualizacion: new Date().toISOString() })
            .eq("id_promocion", idPromo);
        }
      }
    }

    return jsonResponse(200, { ok: true, canceladas: ids.length });
  } catch (e) {
    console.error("cancelar_asistencia_error", e);
    return jsonResponse(500, { ok: false, code: "internal_error", error: "Error interno del servidor" });
  }
});
