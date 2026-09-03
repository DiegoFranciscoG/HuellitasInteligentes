-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V46: fn_listar_notificaciones (V9) selecciona una lista explícita de
-- columnas que nunca incluyó `tipo` —ni siquiera después de que V45 dejara
-- esa columna documentada—, así que aunque el backend SÍ guarda el tipo al
-- insertar (avisos masivos, diagnóstico manual, moderación), la campanita
-- del usuario nunca lo recibía de vuelta: llegaba `tipo: null` siempre,
-- sin importar qué se hubiera guardado. Eso rompía en silencio cualquier
-- intento de pintar una notificación distinto según su categoría.

CREATE OR REPLACE FUNCTION fn_listar_notificaciones(p_usuario_id bigint)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t) ORDER BY t.id DESC) INTO v_result
  FROM (
    SELECT id, usuario_id, canal, contenido, estado, tipo, enviado_at
    FROM notificacion
    WHERE usuario_id = p_usuario_id
    ORDER BY id DESC LIMIT 20
  ) t;
  RETURN COALESCE(v_result, '[]'::JSON);
END;
$function$;
