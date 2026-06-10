import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};
const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };
const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

// ─── CAS cupo lista ───────────────────────────────────────────────────────────
type AjusteCupoResultado =
  | { ok: true; usados: number; max: number | null }
  | { ok: false; code: string; error: string; detail?: string };

async function ajustarCupoLista(
  admin: ReturnType<typeof createClient>,
  idEvento: string,
  delta: number,
  opciones: { validarMax: boolean; clampMinZero?: boolean; maxReintentos?: number },
): Promise<AjusteCupoResultado> {
  const clampMinZero  = opciones.clampMinZero ?? false;
  const maxReintentos = opciones.maxReintentos ?? 6;

  for (let i = 0; i < maxReintentos; i++) {
    const { data: evento, error: evErr } = await admin
      .from("eventos")
      .select("cupo_lista_usados, cupo_lista_max")
      .eq("id_evento", idEvento)
      .maybeSingle();
    if (evErr || !evento) {
      return { ok: false, code: "event_not_found", error: "Evento no encontrado", detail: evErr?.message };
    }

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

// ─── Handler ──────────────────────────────────────────────────────────────────
// Este endpoint es llamado por pg_cron o cron externo cada 5-10 minutos.
// Acciones:
//   1. Expirar tokens_asistencia vencidos (pendiente/aceptada → expirada)
//      y ajustar cupo de los que estaban aceptados
//   2. Expirar tokens_promociones vencidos y ajustar cupos_usados
//   3. Llamar resetear_jerarquias_vencidas() para bajar jerarquía de
//      eventos cuya fecha_fin_jerarquia ya pasó
//   4. Llamar finalizar_eventos_vencidos() para marcar eventos finalizados
//      (esto además finaliza en cascada las promos 'activa' del evento).
//   NOTA: NO hay borrado físico. Todo el ciclo se maneja por estados.

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, code: "method_not_allowed", error: "Metodo no permitido" });
  }

  try {
    const url     = Deno.env.get("SUPABASE_URL") ?? "";
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!url || !service) {
      return jsonResponse(500, { ok: false, code: "server_config_missing", error: "Configuracion incompleta" });
    }

    // Seguridad opcional para cron externo
    const secretExpected = (Deno.env.get("CRON_SECRET") ?? "").trim();
    if (secretExpected) {
      const secretGot = (req.headers.get("x-cron-secret") ?? "").trim();
      if (secretGot !== secretExpected) {
        return jsonResponse(401, { ok: false, code: "invalid_cron_secret", error: "No autorizado" });
      }
    }

    const admin  = createClient(url, service);
    const nowIso = new Date().toISOString();

    // ── 1. Expirar tokens_asistencia ──────────────────────────────────────────
    // Barremos tanto pendientes como aceptadas que superaron fecha_expiracion
    const { data: asisVencidas } = await admin
      .from("tokens_asistencia")
      .select("id_token, id_evento, estado_token, snapshot_squad")
      .lt("fecha_expiracion", nowIso)
      .in("estado_token", ["pendiente", "aceptada"]);

    const asisIds = (asisVencidas ?? []).map((t) => String(t.id_token));

    if (asisIds.length > 0) {
      await admin
        .from("tokens_asistencia")
        .update({ estado_token: "expirada" })
        .in("id_token", asisIds);

      // Solo las aceptadas liberan cupo (las pendientes nunca lo ocuparon)
      const aceptadas = (asisVencidas ?? []).filter((t) => String(t.estado_token) === "aceptada");

      // Acumular por evento, contando cantidad de tokens (1 token = 1 unidad de cupo)
      const porEvento = new Map<string, number>();
      for (const t of aceptadas) {
        const idEvento = String(t.id_evento);
        porEvento.set(idEvento, (porEvento.get(idEvento) ?? 0) + 1);
      }

      for (const [idEvento, cant] of porEvento.entries()) {
        const ajuste = await ajustarCupoLista(admin, idEvento, -cant, {
          validarMax:   false,
          clampMinZero: true,
        });
        if (!ajuste.ok) {
          console.error("expirar_tokens_list_counter_warning", {
            id_evento: idEvento,
            cant,
            code:      ajuste.code,
            error:     ajuste.error,
            detail:    ajuste.detail,
          });
        }
      }
    }

    // ── 2. Expirar tokens_promociones ─────────────────────────────────────────
    const { data: promoVencidas } = await admin
      .from("tokens_promociones")
      .select("id_token, id_promocion")
      .lt("fecha_expiracion", nowIso)
      .eq("estado_token", "activo");

    const promoIdsToken = (promoVencidas ?? []).map((t) => String(t.id_token));

    if (promoIdsToken.length > 0) {
      await admin
        .from("tokens_promociones")
        .update({ estado_token: "expirado" })
        .in("id_token", promoIdsToken);

      // Liberar cupos_usados de cada promoción
      const porPromo = new Map<string, number>();
      for (const t of promoVencidas ?? []) {
        const idPromo = String(t.id_promocion);
        porPromo.set(idPromo, (porPromo.get(idPromo) ?? 0) + 1);
      }

      for (const [idPromo, cant] of porPromo.entries()) {
        const { data: p } = await admin
          .from("promociones")
          .select("cupos_usados")
          .eq("id_promocion", idPromo)
          .maybeSingle();
        const usados = Number(p?.cupos_usados ?? 0);
        await admin
          .from("promociones")
          .update({
            cupos_usados:       Math.max(0, usados - cant),
            fecha_actualizacion: nowIso,
          })
          .eq("id_promocion", idPromo);
      }
    }

    // ── 3. Resetear jerarquías vencidas ───────────────────────────────────────
    // Baja a "gratis" los eventos cuya fecha_fin_jerarquia ya pasó
    const { error: jerarquiaErr } = await admin.rpc("resetear_jerarquias_vencidas");
    if (jerarquiaErr) {
      console.error("expirar_tokens_jerarquia_reset_warning", jerarquiaErr.message);
    }

    // ── 4. Finalizar eventos vencidos (arrastra el fin de sus promos) ─────────
    const { error: finalizarErr } = await admin.rpc("finalizar_eventos_vencidos");
    if (finalizarErr) {
      console.error("expirar_tokens_finalizar_warning", finalizarErr.message);
    }

    // NOTA: NO existe hard-delete. Nada se borra: el ciclo de vida se gobierna
    // 100% por columnas de estado (eventos.estado_publicacion / promociones.
    // estado_promocion / tokens_*.estado_token) para conservar datos de métricas.

    return jsonResponse(200, {
      ok:                       true,
      asistencias_expiradas:    asisIds.length,
      promociones_expiradas:    promoIdsToken.length,
      jerarquias_reseteadas:    !jerarquiaErr,
      eventos_finalizados:      !finalizarErr,
    });

  } catch (e) {
    console.error("expirar_tokens_error", e);
    return jsonResponse(500, { ok: false, code: "internal_error", error: "Error interno del servidor" });
  }
});
