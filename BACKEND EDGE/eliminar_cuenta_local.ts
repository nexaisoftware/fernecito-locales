import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const jsonHeaders = { ...corsHeaders, "Content-Type": "application/json" };

const jsonResponse = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

type DeleteBucketResult = {
  bucket: string;
  removed: number;
};

const chunk = <T>(arr: T[], size: number): T[][] => {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) {
    out.push(arr.slice(i, i + size));
  }
  return out;
};

async function collectIds(
  supabaseAdmin: ReturnType<typeof createClient>,
  table: string,
  idColumn: string,
  filterColumn: string,
  uid: string,
): Promise<string[]> {
  const { data, error } = await supabaseAdmin.from(table).select(idColumn).eq(filterColumn, uid);
  if (error) throw error;
  return (data ?? [])
    .map((row) => String((row as Record<string, unknown>)[idColumn] ?? ""))
    .filter((v) => v.length > 0);
}

async function deleteByIds(
  supabaseAdmin: ReturnType<typeof createClient>,
  table: string,
  idColumn: string,
  ids: string[],
): Promise<number> {
  if (ids.length === 0) return 0;
  let deleted = 0;
  for (const idsChunk of chunk(ids, 200)) {
    const { error } = await supabaseAdmin.from(table).delete().in(idColumn, idsChunk);
    if (error) throw error;
    deleted += idsChunk.length;
  }
  return deleted;
}

async function deleteByColumn(
  supabaseAdmin: ReturnType<typeof createClient>,
  table: string,
  column: string,
  value: string,
): Promise<void> {
  const { error } = await supabaseAdmin.from(table).delete().eq(column, value);
  if (error) throw error;
}

async function deleteFolderInBucket(
  supabaseAdmin: ReturnType<typeof createClient>,
  bucket: string,
  folder: string,
): Promise<DeleteBucketResult> {
  const { data: files, error: listError } = await supabaseAdmin.storage.from(bucket).list(folder, {
    limit: 1000,
    offset: 0,
  });
  if (listError) throw listError;

  if (!files || files.length === 0) {
    return { bucket, removed: 0 };
  }

  const paths = files
    .filter((file) => !!file.name && file.name !== ".emptyFolderPlaceholder")
    .map((file) => `${folder}/${file.name}`);

  if (paths.length === 0) {
    return { bucket, removed: 0 };
  }

  const { error: removeError } = await supabaseAdmin.storage.from(bucket).remove(paths);
  if (removeError) throw removeError;

  return { bucket, removed: paths.length };
}

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

    const uid = authData.user.id;
    const deleted: Record<string, number> = {};

    // 1) Identificar entidades del "mundo local" del usuario.
    const eventIds = await collectIds(supabaseAdmin, "eventos", "id_evento", "id_local", uid);
    const promoIdsByLocal = await collectIds(supabaseAdmin, "promociones", "id_promocion", "id_local", uid);
    const promoIdsByEvent = eventIds.length > 0
      ? await (async () => {
          const ids: string[] = [];
          for (const eventChunk of chunk(eventIds, 200)) {
            const { data, error } = await supabaseAdmin
              .from("promociones")
              .select("id_promocion")
              .in("id_evento", eventChunk);
            if (error) throw error;
            for (const row of data ?? []) {
              const id = String((row as Record<string, unknown>).id_promocion ?? "");
              if (id) ids.push(id);
            }
          }
          return ids;
        })()
      : [];
    const promoIds = Array.from(new Set([...promoIdsByLocal, ...promoIdsByEvent]));

    const asistenciaTokenIds = eventIds.length > 0
      ? await (async () => {
          const ids: string[] = [];
          for (const eventChunk of chunk(eventIds, 200)) {
            const { data, error } = await supabaseAdmin
              .from("tokens_asistencia")
              .select("id_token")
              .in("id_evento", eventChunk);
            if (error) throw error;
            for (const row of data ?? []) {
              const id = String((row as Record<string, unknown>).id_token ?? "");
              if (id) ids.push(id);
            }
          }
          return ids;
        })()
      : [];

    const promoTokenIds = promoIds.length > 0
      ? await (async () => {
          const ids: string[] = [];
          for (const promoChunk of chunk(promoIds, 200)) {
            const { data, error } = await supabaseAdmin
              .from("tokens_promociones")
              .select("id_token")
              .in("id_promocion", promoChunk);
            if (error) throw error;
            for (const row of data ?? []) {
              const id = String((row as Record<string, unknown>).id_token ?? "");
              if (id) ids.push(id);
            }
          }
          return ids;
        })()
      : [];

    // 2) Borrar tablas hijas (orden: dependientes → perfil).
    await deleteByColumn(supabaseAdmin, "invitaciones_rrpp", "id_local", uid);
    deleted.invitaciones_rrpp = 1;

    deleted.tokens_promociones = await deleteByIds(
      supabaseAdmin,
      "tokens_promociones",
      "id_promocion",
      promoIds,
    );

    deleted.tokens_asistencia = await deleteByIds(
      supabaseAdmin,
      "tokens_asistencia",
      "id_evento",
      eventIds,
    );

    deleted.promociones = await deleteByIds(
      supabaseAdmin,
      "promociones",
      "id_promocion",
      promoIds,
    );

    deleted.eventos = await deleteByIds(
      supabaseAdmin,
      "eventos",
      "id_evento",
      eventIds,
    );

    await deleteByColumn(supabaseAdmin, "flyer_generaciones", "local_id", uid);
    deleted.flyer_generaciones = 1;

    await deleteByColumn(supabaseAdmin, "pagos_pendientes", "perfil_id", uid);
    deleted.pagos_pendientes = 1;

    await deleteByColumn(supabaseAdmin, "reviews_locales", "id_local", uid);
    deleted.reviews_locales = 1;

    await deleteByColumn(supabaseAdmin, "locales_soporte", "id_local", uid);
    deleted.locales_soporte = 1;

    await deleteByColumn(supabaseAdmin, "local_staff", "id_local", uid);
    deleted.local_staff = 1;

    await deleteByColumn(supabaseAdmin, "perfiles_locales", "id", uid);
    deleted.perfiles_locales = 1;

    // 3) Borrar media del local.
    const mediaResults: DeleteBucketResult[] = [];
    for (const bucket of ["avatars_locales", "banners_locales", "fotos_locales", "flyers_eventos"]) {
      const result = await deleteFolderInBucket(supabaseAdmin, bucket, uid);
      mediaResults.push(result);
    }

    // 4) Borrar auth.users para poder re-registrarse con el mismo email.
    const { error: deleteAuthError } = await supabaseAdmin.auth.admin.deleteUser(uid);
    if (deleteAuthError) throw deleteAuthError;

    return jsonResponse(200, {
      ok: true,
      id: uid,
      auth_deleted: true,
      media_deleted: mediaResults,
      deleted,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("eliminar_cuenta_local_error", message, error);
    return jsonResponse(500, { ok: false, error: "Error interno del servidor" });
  }
});
