-- V9__fix_fn_mensajes_grupo.sql

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
            u.foto_url AS autor_foto_url
        FROM publicacion_grupo pg
        JOIN usuario u ON u.id = pg.usuario_id
        WHERE pg.grupo_id = p_grupo_id
        ORDER BY pg.created_at ASC
        LIMIT 100
    ) t;

    RETURN COALESCE(v_result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql;

CREATE TABLE IF NOT EXISTS reporte_comunidad (
  id BIGSERIAL PRIMARY KEY,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  tipo VARCHAR(20) NOT NULL DEFAULT 'PUBLICACION',
  referencia_id BIGINT NOT NULL,
  motivo TEXT NOT NULL,
  estado VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION fn_reportar_contenido(
    p_usuario_id BIGINT,
    p_tipo VARCHAR(20),
    p_referencia_id BIGINT,
    p_motivo TEXT
) RETURNS JSON AS $$
BEGIN
    INSERT INTO reporte_comunidad (usuario_id, tipo, referencia_id, motivo)
    VALUES (p_usuario_id, p_tipo, p_referencia_id, p_motivo);
    RETURN json_build_object('status', 'OK', 'message', 'Denuncia enviada a moderación');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_listar_notificaciones(p_usuario_id BIGINT)
RETURNS JSON AS $$
DECLARE v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t) ORDER BY t.id DESC) INTO v_result
  FROM (
    SELECT id, usuario_id, canal, contenido, estado, enviado_at
    FROM notificacion
    WHERE usuario_id = p_usuario_id
    ORDER BY id DESC LIMIT 20
  ) t;
  RETURN COALESCE(v_result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_marcar_notificaciones_leidas(p_usuario_id BIGINT)
RETURNS JSON AS $$
BEGIN
  UPDATE notificacion SET estado = 'ENVIADO' WHERE usuario_id = p_usuario_id;
  RETURN json_build_object('status', 'OK');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_historial_usuario(p_usuario_id BIGINT)
RETURNS JSON AS $$
DECLARE v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t) ORDER BY t.created_at DESC) INTO v_result
  FROM (
    SELECT id, usuario_id, accion, entidad, entidad_id, detalle, ip, created_at
    FROM auditoria_log
    WHERE usuario_id = p_usuario_id OR usuario_id IS NULL
    ORDER BY created_at DESC LIMIT 50
  ) t;
  RETURN COALESCE(v_result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_historial_actuador(p_dispositivo_id BIGINT, p_limite INT DEFAULT 50)
RETURNS JSON AS $$
DECLARE v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t) ORDER BY t.created_at DESC) INTO v_result
  FROM (
    SELECT id, dispositivo_id, comando, parametro, estado, creado_por, created_at, ejecutado_at
    FROM actuador_comando
    WHERE dispositivo_id = p_dispositivo_id
    ORDER BY created_at DESC LIMIT p_limite
  ) t;
  RETURN COALESCE(v_result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql;
