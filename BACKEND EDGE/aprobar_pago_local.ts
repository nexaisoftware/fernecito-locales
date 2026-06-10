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
    const actorUid = authData.user.id;
    const actorEmail = String(authData.user.email ?? "").toLowerCase();

    // Vincular owner si corresponde (idempotente)
    try {
      if (actorEmail) {
        await supabaseAdmin.rpc("vincular_owner_si_corresponde", { p_email: actorEmail });
      }
    } catch (e) {
      console.error("vincular_owner_si_corresponde falló (no crítico):", e);
    }

    // Validar que es owner activo
    const { data: esOwner, error: ownerError } = await supabaseAdmin.rpc("es_owner_activo", {
      p_uid: actorUid,
    });
    if (ownerError) throw ownerError;
    if (esOwner !== true) {
      return jsonResponse(403, { ok: false, error: "No autorizado para aprobar pagos" });
    }

    // Rate limit por owner: 120 acciones/min (uso normal del dashboard es mucho menor;
    // protege contra scripts maliciosos si una cuenta owner se ve comprometida).
    try {
      const { data: rlOk, error: rlErr } = await supabaseAdmin.rpc("check_rate_limit", {
        p_edge: "aprobar_pago_local",
        p_identifier: `owner:${actorUid}`,
        p_user_id: actorUid,
        p_max: 120,
        p_ventana_segs: 60,
      });
      if (rlErr) {
        console.error("rate_limit_rpc_failed", { edge: "aprobar_pago_local", error: rlErr.message });
      } else if (rlOk === false) {
        return jsonResponse(429, {
          ok: false,
          code: "rate_limit_exceeded",
          error: "Demasiadas acciones consecutivas. Esperá un instante.",
        });
      }
    } catch (rlException) {
      console.error("rate_limit_exception", { edge: "aprobar_pago_local", error: String(rlException) });
    }

    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(400, { ok: false, error: "JSON invalido" });
    }
    if (!isPlainObject(body)) return jsonResponse(400, { ok: false, error: "Body invalido" });

    const pagoId = String(body.pago_id ?? "").trim();
    const accion = String(body.accion ?? "aprobar").trim().toLowerCase();
    const notas = String(body.notas ?? "").trim() || null;
    if (!pagoId) return jsonResponse(400, { ok: false, error: "pago_id requerido" });
    if (accion !== "aprobar" && accion !== "rechazar") {
      return jsonResponse(400, { ok: false, error: "accion invalida. Usa aprobar o rechazar" });
    }

    if (accion === "rechazar") {
      const { data: rechResult, error: rechError } = await supabaseAdmin.rpc(
        "rechazar_pago_solicitud",
        { p_pago_id: pagoId, p_actor_uid: actorUid, p_motivo: notas },
      );
      if (rechError) throw rechError;

      // Notif al local
      try {
        if (isPlainObject(rechResult) && rechResult.ok === true) {
          const { data: pagoInfo } = await supabaseAdmin
            .from("pagos_pendientes")
            .select("perfil_id, plan_solicitado")
            .eq("id", pagoId)
            .maybeSingle();
          const idLocal = pagoInfo?.perfil_id;
          const planSol = String(pagoInfo?.plan_solicitado ?? "");
          if (idLocal) {
            const desc = notas && notas.length > 0
              ? `Tu pago del plan ${planSol} fue rechazado. Motivo: ${notas}`
              : `Tu pago del plan ${planSol} fue rechazado. Contactá soporte si tenés dudas.`;
            await supabaseAdmin.rpc("crear_notif_local", {
              p_id_local: idLocal,
              p_tipo: "pago_rechazado",
              p_titulo: "Pago rechazado",
              p_descripcion: desc,
              p_prioridad: "alta",
              p_icono_key: "xmark_circle_fill",
              p_cta_texto: "Ver pagos",
              p_cta_ruta: "/compras_pagos",
              p_cta_id_ref: pagoId,
              p_payload: { plan: planSol, notas },
              p_dedup_key: `pago_rechazado:${pagoId}`,
            }).catch((e) => console.error("notif pago_rechazado falló:", e));
          }
        }
      } catch (e) {
        console.error("notif rechazo exception:", e);
      }

      return jsonResponse(200, { ok: true, resultado: rechResult });
    }

    // Aprobar via RPC central (decide si aplica YA o agenda)
    const { data: aprResult, error: aprError } = await supabaseAdmin.rpc(
      "aprobar_pago_solicitud",
      { p_pago_id: pagoId, p_actor_uid: actorUid },
    );
    if (aprError) throw aprError;

    // Persistir notas si vinieron (opcional, no crítico)
    if (notas) {
      await supabaseAdmin
        .from("pagos_pendientes")
        .update({ notas })
        .eq("id", pagoId)
        .catch((e: unknown) => console.error("update notas falló (no crítico):", e));
    }

    // Notificaciones al local según resultado
    try {
      if (isPlainObject(aprResult) && aprResult.ok === true) {
        const tipo = String(aprResult.tipo ?? "");
        const aplicado = aprResult.aplicado_inmediato === true;

        // Obtener perfil_id + plan del pago
        const { data: pagoInfo } = await supabaseAdmin
          .from("pagos_pendientes")
          .select("perfil_id, plan_solicitado")
          .eq("id", pagoId)
          .maybeSingle();
        const idLocal = pagoInfo?.perfil_id;
        const planSol = String(pagoInfo?.plan_solicitado ?? "");

        if (idLocal) {
          // Helper: ejecuta RPC y loggea el error real (supabase NO rejecta la
          // Promise; el error viene como .error en el data response).
          const llamarNotif = async (params: Record<string, unknown>, label: string) => {
            try {
              const { data, error } = await supabaseAdmin.rpc("crear_notif_local", params);
              if (error) {
                console.error(`notif ${label} fallo:`, JSON.stringify(error));
              } else {
                console.log(`notif ${label} creada: ${data}`);
              }
            } catch (e) {
              console.error(`notif ${label} exception:`, e instanceof Error ? e.message : String(e));
            }
          };

          if (aplicado) {
            const venc = String(aprResult.fecha_vencimiento ?? "");
            const fecha = venc.slice(0, 10).split("-").reverse().join("/");
            await llamarNotif({
              p_id_local: idLocal,
              p_tipo: "pago_aprobado",
              p_titulo: "¡Pago aprobado!",
              p_descripcion: `Tu plan ${planSol} está activo hasta el ${fecha}.`,
              p_prioridad: "alta",
              p_icono_key: "checkmark_seal_fill",
              p_cta_texto: "Ver mi cuenta",
              p_cta_ruta: "/administrar_subscripciones",
              p_cta_id_ref: pagoId,
              p_payload: { plan: planSol, vencimiento: venc, tipo },
              p_dedup_key: `pago_aprobado:${pagoId}`,
            }, "pago_aprobado");
          } else {
            const aplica = String(aprResult.aplica_desde ?? "");
            const fechaAplica = aplica.slice(0, 10).split("-").reverse().join("/");
            const titulo = tipo === "downgrade" ? "Downgrade agendado" : "Renovación aprobada";
            const desc = tipo === "downgrade"
              ? `Tu cambio al plan ${planSol} se aplicará el ${fechaAplica} (al vencer el plan actual).`
              : `Tu renovación del plan ${planSol} se aplicará el ${fechaAplica}.`;
            await llamarNotif({
              p_id_local: idLocal,
              p_tipo: "pago_agendado",
              p_titulo: titulo,
              p_descripcion: desc,
              p_prioridad: "media",
              p_icono_key: "clock_fill",
              p_cta_texto: "Ver mi cuenta",
              p_cta_ruta: "/administrar_subscripciones",
              p_cta_id_ref: pagoId,
              p_payload: { plan: planSol, aplica_desde: aplica, tipo },
              p_dedup_key: `pago_agendado:${pagoId}`,
            }, "pago_agendado");
          }
        }
      }
    } catch (e) {
      console.error("notif post-aprobacion exception:", e);
    }

    return jsonResponse(200, { ok: true, resultado: aprResult });
  } catch (error) {
    console.error("aprobar_pago_local_error", error);
    let detail: string;
    if (error instanceof Error) {
      detail = error.message;
    } else if (typeof error === "object" && error !== null) {
      try {
        detail = JSON.stringify(error);
      } catch {
        detail = String(error);
      }
    } else {
      detail = String(error);
    }
    return jsonResponse(500, {
      ok: false,
      error: "Error interno del servidor",
      detail,
    });
  }
});
