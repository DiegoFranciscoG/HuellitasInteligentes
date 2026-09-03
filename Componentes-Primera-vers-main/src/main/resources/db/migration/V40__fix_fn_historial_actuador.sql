-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V40: fn_historial_actuador consultaba columnas que no existen.
--
-- La versión de V9 pedía:
--     id, dispositivo_id, comando, parametro, estado, creado_por, created_at, ejecutado_at
-- pero la tabla actuador_comando tiene:
--     id, dispositivo_id, comando, origen, ejecutado_por, ts
--
-- Resultado: toda llamada fallaba con «column "parametro" does not exist», y
-- el endpoint GET /api/huellitas/dispositivo/{id}/actuadores devolvía 500.
-- El historial IoT de actuadores nunca llegó a mostrarse.
--
-- Se corrigen los nombres y se agrega el nombre de quien ejecutó el comando,
-- que es lo que permite distinguir qué hizo cada miembro del hogar. Se
-- conserva la clave "created_at" en el JSON de salida para no romper a los
-- clientes web y móvil, que ya ordenan y muestran por ese campo.

CREATE OR REPLACE FUNCTION fn_historial_actuador(p_dispositivo_id BIGINT, p_limite INT DEFAULT 50)
RETURNS JSON AS $$
DECLARE v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t) ORDER BY t.created_at DESC) INTO v_result
  FROM (
    SELECT ac.id,
           ac.dispositivo_id,
           ac.comando,
           ac.origen,
           ac.ejecutado_por,
           u.nombre AS ejecutado_por_nombre,
           ac.ts    AS created_at
    FROM actuador_comando ac
    LEFT JOIN usuario u ON u.id = ac.ejecutado_por
    WHERE ac.dispositivo_id = p_dispositivo_id
    ORDER BY ac.ts DESC
    LIMIT p_limite
  ) t;
  RETURN COALESCE(v_result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql;
