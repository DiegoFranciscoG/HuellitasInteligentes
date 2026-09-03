-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V33:
-- 1) Denunciar publicaciones de grupo — antes solo se podía denunciar en el
--    feed principal; fn_reportar_publicacion buscaba el autor en la tabla
--    `publicacion`, que no tiene relación con `publicacion_grupo`, así que
--    no servía para grupos (y podría haber atribuido la denuncia al autor
--    equivocado si coincidía el id). Esta función es su equivalente real
--    para `publicacion_grupo`.
-- 2) Restaura la ventana de edición de 5 minutos en publicaciones,
--    comentarios y publicaciones de grupo (se había quitado antes; el
--    usuario ahora pide que después de 5 minutos ya no se pueda editar,
--    solo eliminar).
-- 3) "Eliminar para mí": una tabla genérica de ocultamiento por usuario,
--    reutilizable para publicación/comentario/publicación de grupo, más el
--    filtro correspondiente en las tres funciones que listan contenido.

CREATE OR REPLACE FUNCTION fn_reportar_publicacion_grupo(p_publicacion_id BIGINT, p_usuario_id BIGINT, p_motivo TEXT) RETURNS JSON AS $$
DECLARE v_row reporte_moderacion; v_reportado BIGINT;
BEGIN
  SELECT usuario_id INTO v_reportado FROM publicacion_grupo WHERE id = p_publicacion_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PUBLICACION_NO_ENCONTRADA' USING ERRCODE = 'P0004';
  END IF;

  INSERT INTO reporte_moderacion (reportador_id, reportado_id, motivo, estado)
  VALUES (p_usuario_id, v_reportado, 'Reporte de publicación de grupo #' || p_publicacion_id || ': ' || p_motivo, 'PENDIENTE')
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_editar_publicacion(p_publicacion_id BIGINT, p_usuario_id BIGINT, p_contenido TEXT) RETURNS JSON AS $$
DECLARE v_row publicacion; v_rol rol_usuario; v_autor_id BIGINT; v_created_at TIMESTAMPTZ;
BEGIN
  SELECT usuario_id, created_at INTO v_autor_id, v_created_at FROM publicacion WHERE id = p_publicacion_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PUBLICACION_NO_ENCONTRADA' USING ERRCODE = 'P0004'; END IF;

  SELECT rol INTO v_rol FROM usuario WHERE id = p_usuario_id;

  IF v_autor_id != p_usuario_id AND v_rol != 'ADMINISTRADOR' THEN
    RAISE EXCEPTION 'NO_AUTORIZADO' USING ERRCODE = 'P0001';
  END IF;
  IF v_autor_id = p_usuario_id AND v_created_at < now() - INTERVAL '5 minutes' THEN
    RAISE EXCEPTION 'TIEMPO_EDICION_EXPIRADO' USING ERRCODE = 'P0003';
  END IF;

  UPDATE publicacion SET contenido = p_contenido WHERE id = p_publicacion_id RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_editar_comentario(p_comentario_id BIGINT, p_usuario_id BIGINT, p_contenido TEXT) RETURNS JSON AS $$
DECLARE v_row comentario; v_rol rol_usuario; v_autor_id BIGINT; v_created_at TIMESTAMPTZ;
BEGIN
  SELECT usuario_id, created_at INTO v_autor_id, v_created_at FROM comentario WHERE id = p_comentario_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'COMENTARIO_NO_ENCONTRADO' USING ERRCODE = 'P0004'; END IF;

  SELECT rol INTO v_rol FROM usuario WHERE id = p_usuario_id;

  IF v_autor_id != p_usuario_id AND v_rol != 'ADMINISTRADOR' THEN
    RAISE EXCEPTION 'NO_AUTORIZADO' USING ERRCODE = 'P0001';
  END IF;
  IF v_autor_id = p_usuario_id AND v_created_at < now() - INTERVAL '5 minutes' THEN
    RAISE EXCEPTION 'TIEMPO_EDICION_EXPIRADO' USING ERRCODE = 'P0003';
  END IF;

  UPDATE comentario SET contenido = p_contenido WHERE id = p_comentario_id RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_editar_publicacion_grupo(p_publicacion_id BIGINT, p_usuario_id BIGINT, p_contenido TEXT) RETURNS JSON AS $$
DECLARE v_row publicacion_grupo; v_rol rol_usuario; v_autor_id BIGINT; v_created_at TIMESTAMPTZ; v_rol_grupo VARCHAR;
BEGIN
  SELECT usuario_id, created_at INTO v_autor_id, v_created_at FROM publicacion_grupo WHERE id = p_publicacion_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PUBLICACION_NO_ENCONTRADA' USING ERRCODE = 'P0004'; END IF;

  SELECT rol INTO v_rol FROM usuario WHERE id = p_usuario_id;
  SELECT rol_en_grupo INTO v_rol_grupo FROM grupo_miembro WHERE grupo_id = (SELECT grupo_id FROM publicacion_grupo WHERE id = p_publicacion_id) AND usuario_id = p_usuario_id;

  IF v_autor_id != p_usuario_id AND v_rol != 'ADMINISTRADOR' AND COALESCE(v_rol_grupo, '') != 'ADMIN' THEN
    RAISE EXCEPTION 'NO_AUTORIZADO' USING ERRCODE = 'P0001';
  END IF;
  IF v_autor_id = p_usuario_id AND v_created_at < now() - INTERVAL '5 minutes' THEN
    RAISE EXCEPTION 'TIEMPO_EDICION_EXPIRADO' USING ERRCODE = 'P0003';
  END IF;

  UPDATE publicacion_grupo SET contenido = p_contenido, updated_at = now() WHERE id = p_publicacion_id RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

-- "Eliminar para mí": el contenido sigue existiendo para todos los demás,
-- solo se oculta en las listas que ve este usuario. `tipo` distingue entre
-- las tres tablas de contenido reutilizando la misma tabla genérica.
CREATE TABLE IF NOT EXISTS contenido_oculto (
    usuario_id BIGINT NOT NULL REFERENCES usuario(id),
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('PUBLICACION', 'COMENTARIO', 'PUBLICACION_GRUPO')),
    contenido_id BIGINT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (usuario_id, tipo, contenido_id)
);

CREATE OR REPLACE FUNCTION fn_ocultar_contenido(p_usuario_id BIGINT, p_tipo VARCHAR, p_contenido_id BIGINT) RETURNS JSON AS $$
BEGIN
  INSERT INTO contenido_oculto (usuario_id, tipo, contenido_id)
  VALUES (p_usuario_id, p_tipo, p_contenido_id)
  ON CONFLICT (usuario_id, tipo, contenido_id) DO NOTHING;
  RETURN json_build_object('ok', true);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_feed_social(p_usuario_id BIGINT, p_limite INTEGER DEFAULT 20, p_offset INTEGER DEFAULT 0) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(f), '[]') FROM (
    SELECT
      p.id, p.contenido, p.imagen_url, p.created_at, p.media_type,
      u.nombre     AS autor_nombre,
      u.foto_url   AS autor_foto_url,
      p.usuario_id,
      (SELECT COUNT(*) FROM public.comentario c
       WHERE c.publicacion_id = p.id AND c.deleted_at IS NULL) AS total_comentarios,
      (SELECT COUNT(*) FROM public.publicacion_reaccion pr
       WHERE pr.publicacion_id = p.id) AS likes_count,
      EXISTS(SELECT 1 FROM public.publicacion_reaccion pr
             WHERE pr.publicacion_id = p.id AND pr.usuario_id = p_usuario_id) AS liked_by_me,
      (SELECT COALESCE(json_agg(json_build_object(
               'tipo', pr.tipo, 'usuario_id', pr.usuario_id)), '[]')
       FROM public.publicacion_reaccion pr WHERE pr.publicacion_id = p.id) AS reacciones
    FROM public.publicacion p
    JOIN public.usuario u ON u.id = p.usuario_id
    WHERE p.deleted_at IS NULL
      AND u.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM contenido_oculto co WHERE co.usuario_id = p_usuario_id AND co.tipo = 'PUBLICACION' AND co.contenido_id = p.id)
    ORDER BY p.created_at DESC
    LIMIT p_limite OFFSET p_offset
  ) f
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_listar_comentarios(p_publicacion_id BIGINT, p_usuario_id BIGINT DEFAULT NULL) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(json_build_object(
    'id', c.id,
    'contenido', c.contenido,
    'created_at', c.created_at,
    'autor', u.nombre,
    'usuario_id', c.usuario_id,
    'foto_url', u.foto_url
  ) ORDER BY c.created_at ASC), '[]')
  FROM public.comentario c
  JOIN public.usuario u ON u.id = c.usuario_id
  WHERE c.publicacion_id = p_publicacion_id
    AND c.deleted_at IS NULL
    AND (p_usuario_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM contenido_oculto co WHERE co.usuario_id = p_usuario_id AND co.tipo = 'COMENTARIO' AND co.contenido_id = c.id
    ));
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_mensajes_grupo(p_grupo_id BIGINT, p_usuario_id BIGINT) RETURNS JSON AS $$
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
          AND NOT EXISTS (SELECT 1 FROM contenido_oculto co WHERE co.usuario_id = p_usuario_id AND co.tipo = 'PUBLICACION_GRUPO' AND co.contenido_id = pg.id)
        ORDER BY pg.created_at ASC
        LIMIT 100
    ) t;

    RETURN COALESCE(v_result, '[]'::JSON);
END; $$ LANGUAGE plpgsql;
