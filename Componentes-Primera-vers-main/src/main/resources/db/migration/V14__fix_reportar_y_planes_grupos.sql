-- V14__fix_reportar_y_planes_grupos.sql

-- 1. Limpieza de Base64
UPDATE usuario SET foto_url = NULL WHERE foto_url LIKE 'data:image%';
UPDATE perro SET foto_url = NULL WHERE foto_url LIKE 'data:image%';

-- 2. Correccion de fn_reportar_publicacion (quitar creado_por)
CREATE OR REPLACE FUNCTION fn_reportar_publicacion(p_publicacion_id BIGINT, p_usuario_id BIGINT, p_motivo TEXT) RETURNS JSON AS $$
DECLARE 
  v_row reporte_moderacion;
  v_reportado BIGINT;
BEGIN
  SELECT usuario_id INTO v_reportado FROM publicacion WHERE id = p_publicacion_id;
  
  INSERT INTO reporte_moderacion (reportador_id, reportado_id, motivo, estado) 
  VALUES (p_usuario_id, v_reportado, 'Reporte de Publicación #' || p_publicacion_id || ': ' || p_motivo, 'PENDIENTE')
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

-- 3. Fix tabla plan
ALTER TABLE plan ADD COLUMN IF NOT EXISTS precio_oferta NUMERIC(8,2);
ALTER TABLE plan ADD COLUMN IF NOT EXISTS descuento_porcentaje NUMERIC(5,2);
ALTER TABLE plan DROP CONSTRAINT IF EXISTS plan_nombre_check;
ALTER TABLE plan ADD CONSTRAINT chk_plan_nombre_valido CHECK (nombre ~ '^[A-Z0-9_]{2,30}$');

-- 4. Reacciones en grupos
CREATE TABLE IF NOT EXISTS publicacion_grupo_reaccion (
  publicacion_grupo_id BIGINT NOT NULL REFERENCES publicacion_grupo(id) ON DELETE CASCADE,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  tipo VARCHAR(20) NOT NULL DEFAULT 'LIKE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (publicacion_grupo_id, usuario_id)
);

-- Actualizar fn_mensajes_grupo para devolver likes y estado liked_by_me
CREATE OR REPLACE FUNCTION public.fn_mensajes_grupo(
    p_grupo_id   BIGINT,
    p_usuario_id BIGINT
) RETURNS JSON AS $$
DECLARE
    v_result JSON;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM grupo_miembro
        WHERE grupo_id = p_grupo_id AND usuario_id = p_usuario_id
    ) THEN
        RAISE EXCEPTION 'NO_ES_MIEMBRO';
    END IF;

    SELECT json_agg(row_to_json(t) ORDER BY t.created_at ASC)
    INTO v_result
    FROM (
        SELECT
            pg.id,
            pg.grupo_id,
            pg.usuario_id,
            pg.contenido,
            pg.imagen_url,
            pg.created_at,
            u.nombre   AS autor_nombre,
            u.foto_url AS autor_foto_url,
            (SELECT COUNT(*) FROM publicacion_grupo_reaccion pr WHERE pr.publicacion_grupo_id = pg.id) AS likes_count,
            EXISTS(SELECT 1 FROM publicacion_grupo_reaccion pr WHERE pr.publicacion_grupo_id = pg.id AND pr.usuario_id = p_usuario_id) AS liked_by_me,
            (SELECT COALESCE(json_agg(json_build_object('tipo', pr.tipo, 'usuario_id', pr.usuario_id)), '[]') FROM publicacion_grupo_reaccion pr WHERE pr.publicacion_grupo_id = pg.id) AS reacciones
        FROM publicacion_grupo pg
        JOIN usuario u ON u.id = pg.usuario_id
        WHERE pg.grupo_id = p_grupo_id
        ORDER BY pg.created_at ASC
        LIMIT 100
    ) t;

    RETURN COALESCE(v_result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql;

-- Funcion para reaccionar a mensajes de grupo
CREATE OR REPLACE FUNCTION fn_reaccionar_publicacion_grupo(p_publicacion_grupo_id BIGINT, p_usuario_id BIGINT, p_tipo VARCHAR) RETURNS JSON AS $$
DECLARE
  v_row publicacion_grupo_reaccion;
BEGIN
  IF EXISTS (SELECT 1 FROM publicacion_grupo_reaccion WHERE publicacion_grupo_id = p_publicacion_grupo_id AND usuario_id = p_usuario_id) THEN
    DELETE FROM publicacion_grupo_reaccion WHERE publicacion_grupo_id = p_publicacion_grupo_id AND usuario_id = p_usuario_id;
    RETURN json_build_object('ok', true, 'action', 'removed');
  ELSE
    INSERT INTO publicacion_grupo_reaccion (publicacion_grupo_id, usuario_id, tipo) 
    VALUES (p_publicacion_grupo_id, p_usuario_id, COALESCE(p_tipo, 'LIKE'))
    RETURNING * INTO v_row;
    RETURN json_build_object('ok', true, 'action', 'added', 'data', row_to_json(v_row));
  END IF;
END; $$ LANGUAGE plpgsql;
