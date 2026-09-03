-- V36__historial_casa.sql
--
-- Permite que el PROPIETARIO de una casa vea el historial de actividad de
-- todos los miembros de su hogar, no solo el suyo propio. Mismo patron que
-- fn_historial_usuario (V9__fix_fn_mensajes_grupo.sql), agrupando por
-- casa_id en vez de por un unico usuario_id, y agregando el nombre del
-- autor de cada evento para distinguir quien hizo que dentro del hogar.

CREATE OR REPLACE FUNCTION fn_historial_casa(p_casa_id BIGINT)
RETURNS JSON AS $$
DECLARE v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t) ORDER BY t.created_at DESC) INTO v_result
  FROM (
    SELECT al.id, al.usuario_id, u.nombre AS autor_nombre, al.accion, al.entidad, al.entidad_id, al.detalle, al.created_at
    FROM auditoria_log al
    JOIN usuario u ON u.id = al.usuario_id
    WHERE u.casa_id = p_casa_id
    ORDER BY al.created_at DESC LIMIT 100
  ) t;
  RETURN COALESCE(v_result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql;
