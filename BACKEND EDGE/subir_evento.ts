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

// ─── Tipos ────────────────────────────────────────────────────────────────────

type Jerarquia = "gratis" | "normal" | "recomendado_fernecito" | "top" | "top_ultra";

interface PerfilLocal {
  local_verificado: boolean;
  plan_suscripcion: string | null;
  ciudad: string | null;
  provincia: string | null;
  cupos_recomendado: number;
  cupos_top_cartelera: number;
  cupos_top_ultra: number;
}

// ─── Validación de promo ──────────────────────────────────────────────────────

function promoValida(
  promo: Record<string, unknown>,
  fechaInicioEvento: Date,
  fechaFinEvento: Date,
): string | null {
  const titulo = String(promo["titulo_promocion"] ?? "").trim();
  if (!titulo) return "titulo_promocion requerido";

  const duracionEvento = promo["duracion_evento"] === true;
  let fechaInicio: Date;
  let fechaFin: Date;

  if (duracionEvento) {
    // Hereda fechas del evento automáticamente
    fechaInicio = fechaInicioEvento;
    fechaFin = fechaFinEvento;
  } else {
    const inicioRaw = String(promo["fecha_inicio"] ?? "");
    const finRaw = String(promo["fecha_fin"] ?? "");
    fechaInicio = new Date(inicioRaw);
    fechaFin = new Date(finRaw);
    if (isNaN(fechaInicio.getTime()) || isNaN(fechaFin.getTime()))
      return "fecha_inicio/fecha_fin invalidas";
    if (fechaFin.getTime() <= fechaInicio.getTime())
      return "fecha_fin debe ser mayor a fecha_inicio";
  }

  // Suprimir warning de variable no usada — fechaInicio se usa implícitamente
  void fechaInicio;

  const modoUso = String(promo["modo_uso"] ?? "individual");
  if (modoUso !== "individual" && modoUso !== "squad")
    return "modo_uso invalido";

  const cuposTotalesRaw = promo["cupos_totales"];
  if (cuposTotalesRaw != null) {
    const cuposTotales = Number(cuposTotalesRaw);
    if (!Number.isFinite(cuposTotales) || cuposTotales < 1)
      return "cupos_totales debe ser >= 1";
  }

  if (modoUso === "squad") {
    const min = promo["min_miembros_squad"] == null
      ? null
      : Number(promo["min_miembros_squad"]);
    if (min == null || !Number.isFinite(min) || min < 2)
      return "min_miembros_squad debe ser >= 2 para squads";
    const maxRaw = promo["max_miembros_squad"];
    if (maxRaw != null) {
      const max = Number(maxRaw);
      if (!Number.isFinite(max) || max < min)
        return "max_miembros_squad no puede ser menor al minimo";
    }
  }

  return null;
}

// ─── Validación de evento ─────────────────────────────────────────────────────

function eventoValido(p: Record<string, unknown>): string | null {
  const titulo = String(p["titulo_evento"] ?? p["nombre_evento"] ?? "").trim();
  if (!titulo) return "titulo_evento requerido";

  const fechaInicio = new Date(String(p["fecha_inicio"] ?? ""));
  const fechaFin = new Date(String(p["fecha_fin"] ?? ""));
  if (isNaN(fechaInicio.getTime()) || isNaN(fechaFin.getTime()))
    return "fecha_inicio/fecha_fin invalidas";
  if (fechaFin.getTime() <= fechaInicio.getTime())
    return "fecha_fin debe ser mayor a fecha_inicio";

  const modoLista = String(p["modo_lista"] ?? "auto");
  if (!["auto", "manual"].includes(modoLista))
    return "modo_lista invalido (debe ser 'auto' o 'manual')";

  // cupo_lista_max es opcional — null = ilimitado
  const cupoRaw = p["cupo_lista_max"];
  if (cupoRaw != null) {
    const cupo = Number(cupoRaw);
    if (!Number.isFinite(cupo) || cupo < 1)
      return "cupo_lista_max debe ser >= 1 o null (sin limite)";
  }

  // Si el evento no es en el local, requiere dirección
  const esEnLocal = p["es_en_local"] !== false;
  if (!esEnLocal) {
    const dir = String(p["direccion_evento"] ?? "").trim();
    if (!dir) return "direccion_evento requerida cuando el evento no es en el local";
  }

  return null;
}

// ─── Determinar jerarquía permitida según plan ────────────────────────────────
// Sin verificar → siempre 'gratis'
// Verificado → puede elegir 'normal' sin créditos
// Con créditos → jerarquías premium

function jerarquiaPermitida(
  jerarquiaSolicitada: string,
  perfil: PerfilLocal,
): { ok: true; jerarquia: Jerarquia; campoCredito: keyof PerfilLocal | null }
 | { ok: false; code: string; error: string } {

  if (!perfil.local_verificado) {
    // Local sin plan: solo gratis sin importar lo que pida
    return { ok: true, jerarquia: "gratis", campoCredito: null };
  }

  if (jerarquiaSolicitada === "gratis" || jerarquiaSolicitada === "normal") {
    return { ok: true, jerarquia: jerarquiaSolicitada as Jerarquia, campoCredito: null };
  }

  if (jerarquiaSolicitada === "recomendado_fernecito") {
    if (perfil.cupos_recomendado < 1) {
      return { ok: false, code: "insufficient_credits", error: "Sin creditos de Recomendado Fernecito" };
    }
    return { ok: true, jerarquia: "recomendado_fernecito", campoCredito: "cupos_recomendado" };
  }

  if (jerarquiaSolicitada === "top") {
    if (perfil.cupos_top_cartelera < 1) {
      return { ok: false, code: "insufficient_credits", error: "Sin creditos de Top Cartelera" };
    }
    return { ok: true, jerarquia: "top", campoCredito: "cupos_top_cartelera" };
  }

  if (jerarquiaSolicitada === "top_ultra") {
    if (perfil.cupos_top_ultra < 1) {
      return { ok: false, code: "insufficient_credits", error: "Sin creditos de Top Ultra" };
    }
    return { ok: true, jerarquia: "top_ultra", campoCredito: "cupos_top_ultra" };
  }

  return { ok: false, code: "invalid_jerarquia", error: "Jerarquia invalida" };
}

// ─── Calcular fecha_fin_jerarquia ─────────────────────────────────────────────
// Duración del boost según nivel:
//   - top / top_ultra        → 10 días
//   - recomendado_fernecito  → 15 días
// Siempre acotado por fecha_fin del evento (lo que pase primero).

const DIAS_BOOST_POR_JERARQUIA: Record<string, number> = {
  recomendado_fernecito: 15,
  top: 10,
  top_ultra: 10,
};

function calcularFechaFinJerarquia(fechaFinEvento: Date, jerarquia: string): string {
  const dias = DIAS_BOOST_POR_JERARQUIA[jerarquia] ?? 10;
  const limiteBoost = new Date(Date.now() + dias * 24 * 60 * 60 * 1000);
  const fin = fechaFinEvento.getTime() < limiteBoost.getTime()
    ? fechaFinEvento
    : limiteBoost;
  return fin.toISOString();
}

// ─── Handler principal ────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return jsonResponse(405, { ok: false, code: "method_not_allowed", error: "Metodo no permitido" });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey    = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !anonKey || !serviceKey) {
      return jsonResponse(500, { ok: false, code: "server_config_missing", error: "Configuracion incompleta" });
    }

    const authHeader = authorizationHeader(req);
    if (!authHeader) {
      return jsonResponse(401, { ok: false, code: "missing_authorization", error: "Authorization requerido" });
    }

    // ── Autenticar usuario ────────────────────────────────────────────────────
    const supabaseAuth = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await supabaseAuth.auth.getUser();
    if (authError || !user) {
      return jsonResponse(401, {
        ok: false,
        code: "invalid_jwt",
        error: "No autenticado",
        detail: authError?.message,
      });
    }

    const admin = createClient(supabaseUrl, serviceKey);

    // ── Leer perfil del local ─────────────────────────────────────────────────
    const { data: perfilRaw, error: perfilError } = await admin
      .from("perfiles_locales")
      .select("local_verificado, plan_suscripcion, ciudad, provincia, cupos_recomendado, cupos_top_cartelera, cupos_top_ultra")
      .eq("id", user.id)
      .maybeSingle();

    if (perfilError || !perfilRaw) {
      return jsonResponse(403, {
        ok: false,
        code: "profile_not_found",
        error: "Perfil de local no encontrado",
      });
    }

    const perfil: PerfilLocal = {
      local_verificado:   perfilRaw.local_verificado === true,
      plan_suscripcion:   perfilRaw.plan_suscripcion ?? null,
      ciudad:             perfilRaw.ciudad ?? null,
      provincia:          perfilRaw.provincia ?? null,
      cupos_recomendado:  Number(perfilRaw.cupos_recomendado ?? 0),
      cupos_top_cartelera: Number(perfilRaw.cupos_top_cartelera ?? 0),
      cupos_top_ultra:    Number(perfilRaw.cupos_top_ultra ?? 0),
    };

    // ── Parsear body ──────────────────────────────────────────────────────────
    let body: unknown;
    try { body = await req.json(); } catch {
      return jsonResponse(400, { ok: false, code: "invalid_json", error: "JSON invalido" });
    }
    if (!isPlainObject(body)) {
      return jsonResponse(400, { ok: false, code: "invalid_body", error: "Body invalido" });
    }

    const payloadEventoRaw = body["payload_evento"];
    const promocionesRaw   = body["promociones"] ?? [];

    if (!isPlainObject(payloadEventoRaw)) {
      return jsonResponse(400, { ok: false, code: "missing_payload_evento", error: "payload_evento requerido" });
    }
    if (!Array.isArray(promocionesRaw) || promocionesRaw.some((x) => !isPlainObject(x))) {
      return jsonResponse(400, { ok: false, code: "invalid_promociones", error: "promociones debe ser un arreglo de objetos" });
    }

    // ── Validar evento ────────────────────────────────────────────────────────
    const errorEvento = eventoValido(payloadEventoRaw);
    if (errorEvento) {
      return jsonResponse(400, { ok: false, code: "invalid_event_payload", error: errorEvento });
    }

    const fechaInicioEvento = new Date(String(payloadEventoRaw["fecha_inicio"]));
    const fechaFinEvento    = new Date(String(payloadEventoRaw["fecha_fin"]));

    const diasSemana = ["domingo", "lunes", "martes", "miercoles", "jueves", "viernes", "sabado"];
    const fecha_inicio = payloadEventoRaw["fecha_inicio"];
    const diaSemana = fecha_inicio ? diasSemana[new Date(String(fecha_inicio)).getDay()] : null;

    // ── Validar promociones ───────────────────────────────────────────────────
    const promociones = promocionesRaw as Array<Record<string, unknown>>;
    for (const promo of promociones) {
      const errorPromo = promoValida(promo, fechaInicioEvento, fechaFinEvento);
      if (errorPromo) {
        return jsonResponse(400, { ok: false, code: "invalid_promo_payload", error: errorPromo });
      }
    }

    // ── Determinar jerarquía ──────────────────────────────────────────────────
    const jerarquiaSolicitada = String(payloadEventoRaw["jerarquia"] ?? "gratis");
    const resultadoJerarquia  = jerarquiaPermitida(jerarquiaSolicitada, perfil);
    if (!resultadoJerarquia.ok) {
      return jsonResponse(402, {
        ok: false,
        code: resultadoJerarquia.code,
        error: resultadoJerarquia.error,
        creditos: {
          recomendado: perfil.cupos_recomendado,
          top:         perfil.cupos_top_cartelera,
          top_ultra:   perfil.cupos_top_ultra,
        },
      });
    }

    const jerarquiaFinal = resultadoJerarquia.jerarquia;
    const campoCredito   = resultadoJerarquia.campoCredito;

    // ── Decrementar crédito con compare-and-swap ──────────────────────────────
    // Se hace ANTES de insertar el evento para evitar cobrar sin publicar.
    if (campoCredito) {
      const valorActual = perfil[campoCredito] as number;

      const { data: creditoOk, error: creditoErr } = await admin
        .from("perfiles_locales")
        .update({ [campoCredito]: valorActual - 1 })
        .eq("id", user.id)
        .eq(campoCredito as string, valorActual) // CAS: evita doble gasto concurrente
        .select("id")
        .maybeSingle();

      if (creditoErr || !creditoOk) {
        return jsonResponse(409, {
          ok: false,
          code: "credit_deduction_failed",
          error: "No se pudo descontar el credito. Verificá que tengas creditos disponibles e intentá de nuevo.",
        });
      }
    }

    // ── Ciudad/provincia del evento ───────────────────────────────────────────
    // Si es_en_local=true → usamos la ciudad/provincia del perfil del local.
    // Si es_en_local=false → usamos lo que el local especifique en el body
    //                       (ubicación custom de pantalla_crear_evento.dart),
    //                       con fallback al perfil si vienen vacíos.
    // En cualquier caso, ambos deben terminar con valor: la cartelera filtra
    // estrictamente por ciudad y no muestra eventos sin ubicación.
    const esEnLocal = payloadEventoRaw["es_en_local"] !== false;
    const ciudadEvento = esEnLocal
      ? perfil.ciudad
      : (String(payloadEventoRaw["ciudad_evento"] ?? "").trim() || perfil.ciudad);
    const provinciaEvento = esEnLocal
      ? perfil.provincia
      : (String(payloadEventoRaw["provincia_evento"] ?? "").trim() || perfil.provincia);

    if (!ciudadEvento || !provinciaEvento) {
      // Devolver crédito si ya fue descontado antes de fallar
      if (campoCredito) {
        const valorActual = perfil[campoCredito] as number;
        await admin
          .from("perfiles_locales")
          .update({ [campoCredito]: valorActual })
          .eq("id", user.id);
      }
      return jsonResponse(400, {
        ok: false,
        code: "missing_ubicacion",
        error: "El evento debe tener ciudad y provincia. Completá la ubicación del perfil del local o ingresá una custom al crear el evento.",
      });
    }

    // ── fecha_fin_jerarquia (solo jerarquías de crédito) ──────────────────────
    const fechaFinJerarquia = campoCredito
      ? calcularFechaFinJerarquia(fechaFinEvento, jerarquiaFinal)
      : null;

    // ── fecha_fin_publicacion: min(fecha_fin_evento, now + 30 días) ───────────
    // El evento deja de aparecer en cartelera cuando esto venza.
    const treintaDias = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    const fechaFinPublicacion = fechaFinEvento.getTime() < treintaDias.getTime()
      ? fechaFinEvento
      : treintaDias;

    // ── Payload final seguro (campos del cliente + campos server-side) ─────────
    const modoLista   = String(payloadEventoRaw["modo_lista"] ?? "auto");
    const cupoListaMax = payloadEventoRaw["cupo_lista_max"] != null
      ? Number(payloadEventoRaw["cupo_lista_max"])
      : null;

    const payloadFinal: Record<string, unknown> = {
      titulo_evento:        String(payloadEventoRaw["titulo_evento"] ?? payloadEventoRaw["nombre_evento"] ?? "").trim(),
      descripcion_evento:   payloadEventoRaw["descripcion_evento"] ?? payloadEventoRaw["descripcion"] ?? null,
      url_flyer:            String(payloadEventoRaw["url_flyer"] ?? payloadEventoRaw["flyer_url"] ?? "").trim(),
      edad_minima:          payloadEventoRaw["edad_minima"] ?? null,
      tipo_evento:          String(payloadEventoRaw["tipo_evento"] ?? "evento"),
      permite_squads:       payloadEventoRaw["permite_squads"] !== false,
      fecha_inicio:         fechaInicioEvento.toISOString(),
      fecha_fin:            fechaFinEvento.toISOString(),
      dia_semana:           diaSemana,
      es_en_local:          esEnLocal,
      direccion_evento:     esEnLocal ? null : String(payloadEventoRaw["direccion_evento"] ?? "").trim(),
      url_maps_evento:      payloadEventoRaw["url_maps_evento"] ?? null,
      advertencias_evento:  payloadEventoRaw["advertencias_evento"] ?? null,
      url_compra_entradas:  payloadEventoRaw["url_compra_entradas"] ?? null,
      hora_limite_canje:    payloadEventoRaw["hora_limite_canje"] ?? null,
      modo_lista:           modoLista,
      cupo_lista_max:       cupoListaMax,
      // Server-side — nunca del cliente
      id_local:             user.id,
      cupo_lista_usados:    0,
      jerarquia:            jerarquiaFinal,
      fuente_jerarquia:     campoCredito ? "plan" : (perfil.local_verificado ? "normal" : "gratis"),
      fecha_fin_jerarquia:  fechaFinJerarquia,
      ciudad_evento:        ciudadEvento,
      provincia_evento:     provinciaEvento,
      estado_publicacion:   "publicado",
      fecha_fin_publicacion: fechaFinPublicacion.toISOString(),
      fecha_subida:         new Date().toISOString(),
      tiene_promo:          promociones.length > 0,
      metric_visitas:       0,
      metric_reservas_aceptadas: 0,
      metric_tokens_emitidos:    0,
      metric_canjeos:       0,
    };

    // ── Insertar evento ───────────────────────────────────────────────────────
    const { data: eventoInsertado, error: eventoError } = await admin
      .from("eventos")
      .insert(payloadFinal)
      .select("id_evento")
      .single();

    if (eventoError || !eventoInsertado) {
      // Devolver crédito si falló el insert después de descontarlo
      if (campoCredito) {
        const valorActual = perfil[campoCredito] as number;
        await admin
          .from("perfiles_locales")
          .update({ [campoCredito]: valorActual })
          .eq("id", user.id);
      }
      return jsonResponse(400, {
        ok: false,
        code: "evento_insert_failed",
        error: "No se pudo crear el evento",
        detail: eventoError?.message,
      });
    }

    const idEvento = String(eventoInsertado.id_evento);

    // ── Insertar promociones ──────────────────────────────────────────────────
    if (promociones.length > 0) {
      const promosConIds = promociones.map((promo) => {
        const duracionEvento = promo["duracion_evento"] === true;
        return {
          id_evento:            idEvento,
          id_local:             user.id,
          titulo_promocion:     String(promo["titulo_promocion"] ?? "").trim(),
          descripcion_promocion: promo["descripcion_promocion"] ?? null,
          fecha_inicio:         duracionEvento
            ? fechaInicioEvento.toISOString()
            : String(promo["fecha_inicio"]),
          fecha_fin:            duracionEvento
            ? fechaFinEvento.toISOString()
            : String(promo["fecha_fin"]),
          cupos_totales:        promo["cupos_totales"] ?? null,
          cupos_usados:         0,
          modo_uso:             String(promo["modo_uso"] ?? "individual"),
          min_miembros_squad:   promo["min_miembros_squad"] ?? null,
          max_miembros_squad:   promo["max_miembros_squad"] ?? null,
          estado_promocion:     "activa",
        };
      });

      const { error: promosError } = await admin
        .from("promociones")
        .insert(promosConIds);

      if (promosError) {
        // El evento ya fue creado — loggear pero no fallar
        console.error("subir_evento_promos_insert_failed", {
          id_evento: idEvento,
          error: promosError.message,
        });
      }
    }

    // ── Respuesta ─────────────────────────────────────────────────────────────
    return jsonResponse(200, {
      ok: true,
      id_evento:           idEvento,
      jerarquia:           jerarquiaFinal,
      ciudad_evento:       ciudadEvento,
      provincia_evento:    provinciaEvento,
      fecha_fin_jerarquia: fechaFinJerarquia,
      creditos_restantes:  campoCredito
        ? (perfil[campoCredito] as number) - 1
        : null,
    });

  } catch (error) {
    console.error("subir_evento_error", error);
    return jsonResponse(500, { ok: false, code: "internal_error", error: "Error interno del servidor" });
  }
});
