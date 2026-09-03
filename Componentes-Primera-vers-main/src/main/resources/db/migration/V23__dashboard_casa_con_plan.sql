-- V23__dashboard_casa_con_plan_y_fix_perros.sql
-- Actualiza fn_dashboard_casa para incluir info del plan (nombre, limite_mascotas)
-- Así el frontend puede mostrar "X de Y mascotas (Plan FREE)" sin llamadas extra

CREATE OR REPLACE FUNCTION public.fn_dashboard_casa(p_casa_id BIGINT)
RETURNS JSON AS $$
  SELECT json_build_object(
    'casa',         (SELECT row_to_json(c) FROM public.casa c WHERE c.id = p_casa_id),
    'perros',       (SELECT COALESCE(json_agg(p), '[]') FROM public.perro p
                     WHERE p.casa_id = p_casa_id AND p.deleted_at IS NULL),
    'zona',         (SELECT row_to_json(z) FROM public.zona z
                     WHERE z.casa_id = p_casa_id ORDER BY z.id ASC LIMIT 1),
    'dispositivos', (SELECT COALESCE(json_agg(json_build_object(
                       'id', d.id, 'categoria', d.categoria, 'tipo', d.tipo,
                       'estado', d.estado, 'ultima_conexion', d.ultima_conexion,
                       'ultimo_valor', v.valor, 'ultimo_valor_ts', v.ts
                     )), '[]')
                     FROM public.dispositivo d
                     JOIN public.zona z ON z.id = d.zona_id
                     LEFT JOIN public.vista_ultimo_estado_dispositivo v ON v.dispositivo_id = d.id
                     WHERE z.casa_id = p_casa_id AND d.deleted_at IS NULL),
    'alertas_pendientes', (SELECT COALESCE(json_agg(a ORDER BY a.ts DESC), '[]')
                     FROM public.alerta a
                     WHERE a.casa_id = p_casa_id AND a.leida = false),
    'suscripcion',  (SELECT row_to_json(s) FROM public.suscripcion s
                     WHERE s.casa_id = p_casa_id LIMIT 1),
    'plan',         (SELECT json_build_object(
                       'id',               pl.id,
                       'nombre',           pl.nombre,
                       'precio_mensual',   pl.precio_mensual,
                       'limite_mascotas',  pl.limite_mascotas,
                       'descripcion',      pl.descripcion
                     )
                     FROM public.suscripcion s
                     JOIN public.plan pl ON pl.id = s.plan_id
                     WHERE s.casa_id = p_casa_id
                     ORDER BY s.id DESC LIMIT 1)
  );
$$ LANGUAGE sql STABLE;
