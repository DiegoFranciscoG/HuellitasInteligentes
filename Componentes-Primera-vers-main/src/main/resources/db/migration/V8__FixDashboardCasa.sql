CREATE OR REPLACE FUNCTION fn_dashboard_casa(p_casa_id BIGINT) RETURNS JSON AS $$
  SELECT json_build_object(
    'casa', (SELECT row_to_json(c) FROM casa c WHERE c.id = p_casa_id),
    'perros', (SELECT COALESCE(json_agg(p), '[]') FROM perro p WHERE p.casa_id = p_casa_id AND p.deleted_at IS NULL),
    'zona', (SELECT row_to_json(z) FROM zona z WHERE z.casa_id = p_casa_id ORDER BY z.id ASC LIMIT 1),
    'dispositivos', (SELECT COALESCE(json_agg(json_build_object(
        'id', d.id, 'categoria', d.categoria, 'tipo', d.tipo, 'estado', d.estado,
        'ultima_conexion', d.ultima_conexion,
        'ultimo_valor', v.valor, 'ultimo_valor_ts', v.ts
      )), '[]')
      FROM dispositivo d
      JOIN zona z ON z.id = d.zona_id
      LEFT JOIN vista_ultimo_estado_dispositivo v ON v.dispositivo_id = d.id
      WHERE z.casa_id = p_casa_id AND d.deleted_at IS NULL),
    'alertas_pendientes', (SELECT COALESCE(json_agg(a ORDER BY a.ts DESC), '[]')
      FROM alerta a WHERE a.casa_id = p_casa_id AND a.leida = false),
    'suscripcion', (SELECT row_to_json(s) FROM suscripcion s WHERE s.casa_id = p_casa_id LIMIT 1)
  );
$$ LANGUAGE sql STABLE;
