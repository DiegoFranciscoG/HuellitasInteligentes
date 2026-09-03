-- V5__nuevas_funcionalidades.sql

-- ================================================================
-- TABLAS: GRUPOS Y LENGUAJE INCLUSIVO
-- ================================================================
CREATE TABLE grupo (
  id BIGSERIAL PRIMARY KEY,
  nombre VARCHAR(100) NOT NULL UNIQUE,
  descripcion VARCHAR(255),
  creado_por BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE grupo_miembro (
  grupo_id BIGINT NOT NULL REFERENCES grupo(id) ON DELETE CASCADE,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  rol_en_grupo VARCHAR(20) NOT NULL DEFAULT 'MIEMBRO' CHECK (rol_en_grupo IN ('ADMIN','MIEMBRO')),
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (grupo_id, usuario_id)
);

CREATE TABLE publicacion_grupo (
  id BIGSERIAL PRIMARY KEY,
  grupo_id BIGINT NOT NULL REFERENCES grupo(id) ON DELETE CASCADE,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  contenido TEXT NOT NULL,
  imagen_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE lenguaje_inclusivo_sugerencia (
  id BIGSERIAL PRIMARY KEY,
  termino_no_inclusivo VARCHAR(100) NOT NULL UNIQUE,
  termino_sugerido VARCHAR(100) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO lenguaje_inclusivo_sugerencia (termino_no_inclusivo, termino_sugerido) VALUES
  ('los usuarios', 'las personas usuarias'),
  ('los alumnos', 'el estudiantado'),
  ('los niños', 'las infancias'),
  ('los ciudadanos', 'la ciudadanía'),
  ('los trabajadores', 'el personal'),
  ('los dueños', 'quienes poseen mascotas'),
  ('los expertos', 'el equipo experto'),
  ('el hombre', 'la humanidad');

-- ================================================================
-- FUNCIONES CRUD: COMENTARIOS
-- ================================================================
CREATE OR REPLACE FUNCTION fn_editar_comentario(p_comentario_id BIGINT, p_usuario_id BIGINT, p_contenido TEXT) RETURNS JSON AS $$
DECLARE v_row comentario; v_rol rol_usuario; v_autor_id BIGINT; v_created_at TIMESTAMPTZ;
BEGIN
  SELECT usuario_id, created_at INTO v_autor_id, v_created_at FROM comentario WHERE id = p_comentario_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'COMENTARIO_NO_ENCONTRADO' USING ERRCODE = 'P0004'; END IF;

  SELECT rol INTO v_rol FROM usuario WHERE id = p_usuario_id;
  
  IF v_autor_id != p_usuario_id AND v_rol != 'ADMINISTRADOR' THEN
    RAISE EXCEPTION 'NO_AUTORIZADO' USING ERRCODE = 'P0001';
  END IF;
  IF v_rol != 'ADMINISTRADOR' AND v_created_at < (now() - interval '5 minutes') THEN
    RAISE EXCEPTION 'TIEMPO_EDICION_EXPIRADO' USING ERRCODE = 'P0002';
  END IF;

  UPDATE comentario SET contenido = p_contenido WHERE id = p_comentario_id RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_eliminar_comentario(p_comentario_id BIGINT, p_usuario_id BIGINT) RETURNS JSON AS $$
DECLARE v_rol rol_usuario; v_autor_id BIGINT;
BEGIN
  SELECT usuario_id INTO v_autor_id FROM comentario WHERE id = p_comentario_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'COMENTARIO_NO_ENCONTRADO' USING ERRCODE = 'P0004'; END IF;

  SELECT rol INTO v_rol FROM usuario WHERE id = p_usuario_id;
  
  IF v_autor_id != p_usuario_id AND v_rol != 'ADMINISTRADOR' THEN
    RAISE EXCEPTION 'NO_AUTORIZADO' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM comentario WHERE id = p_comentario_id;
  RETURN json_build_object('ok', true);
END; $$ LANGUAGE plpgsql;

-- ================================================================
-- FUNCIONES CRUD: PUBLICACIONES GLOBALES
-- ================================================================
CREATE OR REPLACE FUNCTION fn_editar_publicacion(p_publicacion_id BIGINT, p_usuario_id BIGINT, p_contenido TEXT) RETURNS JSON AS $$
DECLARE v_row publicacion; v_rol rol_usuario; v_autor_id BIGINT; v_created_at TIMESTAMPTZ;
BEGIN
  SELECT usuario_id, created_at INTO v_autor_id, v_created_at FROM publicacion WHERE id = p_publicacion_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PUBLICACION_NO_ENCONTRADA' USING ERRCODE = 'P0004'; END IF;

  SELECT rol INTO v_rol FROM usuario WHERE id = p_usuario_id;
  
  IF v_autor_id != p_usuario_id AND v_rol != 'ADMINISTRADOR' THEN
    RAISE EXCEPTION 'NO_AUTORIZADO' USING ERRCODE = 'P0001';
  END IF;
  IF v_rol != 'ADMINISTRADOR' AND v_created_at < (now() - interval '5 minutes') THEN
    RAISE EXCEPTION 'TIEMPO_EDICION_EXPIRADO' USING ERRCODE = 'P0002';
  END IF;

  UPDATE publicacion SET contenido = p_contenido WHERE id = p_publicacion_id RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_eliminar_publicacion(p_publicacion_id BIGINT, p_usuario_id BIGINT) RETURNS JSON AS $$
DECLARE v_rol rol_usuario; v_autor_id BIGINT;
BEGIN
  SELECT usuario_id INTO v_autor_id FROM publicacion WHERE id = p_publicacion_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PUBLICACION_NO_ENCONTRADA' USING ERRCODE = 'P0004'; END IF;

  SELECT rol INTO v_rol FROM usuario WHERE id = p_usuario_id;
  
  IF v_autor_id != p_usuario_id AND v_rol != 'ADMINISTRADOR' THEN
    RAISE EXCEPTION 'NO_AUTORIZADO' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM publicacion WHERE id = p_publicacion_id;
  RETURN json_build_object('ok', true);
END; $$ LANGUAGE plpgsql;

-- ================================================================
-- FUNCIONES CRUD: GRUPOS Y PUBLICACIONES DE GRUPO
-- ================================================================
CREATE OR REPLACE FUNCTION fn_crear_grupo(p_nombre VARCHAR, p_descripcion VARCHAR, p_creado_por BIGINT) RETURNS JSON AS $$
DECLARE v_row grupo;
BEGIN
  INSERT INTO grupo (nombre, descripcion, creado_por) VALUES (p_nombre, p_descripcion, p_creado_por) RETURNING * INTO v_row;
  INSERT INTO grupo_miembro (grupo_id, usuario_id, rol_en_grupo) VALUES (v_row.id, p_creado_por, 'ADMIN');
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_unirse_grupo(p_grupo_id BIGINT, p_usuario_id BIGINT) RETURNS JSON AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM grupo_miembro WHERE grupo_id = p_grupo_id AND usuario_id = p_usuario_id) THEN
    RETURN json_build_object('ok', true, 'message', 'Ya eres miembro');
  END IF;
  INSERT INTO grupo_miembro (grupo_id, usuario_id, rol_en_grupo) VALUES (p_grupo_id, p_usuario_id, 'MIEMBRO');
  RETURN json_build_object('ok', true);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_salir_grupo(p_grupo_id BIGINT, p_usuario_id BIGINT) RETURNS JSON AS $$
BEGIN
  DELETE FROM grupo_miembro WHERE grupo_id = p_grupo_id AND usuario_id = p_usuario_id;
  RETURN json_build_object('ok', true);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_listar_grupos(p_usuario_id BIGINT) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(g), '[]') FROM (
    SELECT gr.id, gr.nombre, gr.descripcion, 
      (SELECT COUNT(*) FROM grupo_miembro WHERE grupo_id = gr.id) as total_miembros,
      EXISTS(SELECT 1 FROM grupo_miembro gm WHERE gm.grupo_id = gr.id AND gm.usuario_id = p_usuario_id) as es_miembro
    FROM grupo gr ORDER BY gr.created_at DESC
  ) g;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_publicar_en_grupo(p_grupo_id BIGINT, p_usuario_id BIGINT, p_contenido TEXT, p_imagen_url TEXT) RETURNS JSON AS $$
DECLARE v_row publicacion_grupo;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM grupo_miembro WHERE grupo_id = p_grupo_id AND usuario_id = p_usuario_id) THEN
    RAISE EXCEPTION 'NO_ES_MIEMBRO' USING ERRCODE = 'P0001';
  END IF;
  INSERT INTO publicacion_grupo (grupo_id, usuario_id, contenido, imagen_url) VALUES (p_grupo_id, p_usuario_id, p_contenido, p_imagen_url) RETURNING * INTO v_row;
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
  IF v_rol != 'ADMINISTRADOR' AND COALESCE(v_rol_grupo, '') != 'ADMIN' AND v_created_at < (now() - interval '5 minutes') THEN
    RAISE EXCEPTION 'TIEMPO_EDICION_EXPIRADO' USING ERRCODE = 'P0002';
  END IF;

  UPDATE publicacion_grupo SET contenido = p_contenido, updated_at = now() WHERE id = p_publicacion_id RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_eliminar_publicacion_grupo(p_publicacion_id BIGINT, p_usuario_id BIGINT) RETURNS JSON AS $$
DECLARE v_rol rol_usuario; v_autor_id BIGINT; v_rol_grupo VARCHAR;
BEGIN
  SELECT usuario_id INTO v_autor_id FROM publicacion_grupo WHERE id = p_publicacion_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PUBLICACION_NO_ENCONTRADA' USING ERRCODE = 'P0004'; END IF;

  SELECT rol INTO v_rol FROM usuario WHERE id = p_usuario_id;
  SELECT rol_en_grupo INTO v_rol_grupo FROM grupo_miembro WHERE grupo_id = (SELECT grupo_id FROM publicacion_grupo WHERE id = p_publicacion_id) AND usuario_id = p_usuario_id;
  
  IF v_autor_id != p_usuario_id AND v_rol != 'ADMINISTRADOR' AND COALESCE(v_rol_grupo, '') != 'ADMIN' THEN
    RAISE EXCEPTION 'NO_AUTORIZADO' USING ERRCODE = 'P0001';
  END IF;

  DELETE FROM publicacion_grupo WHERE id = p_publicacion_id;
  RETURN json_build_object('ok', true);
END; $$ LANGUAGE plpgsql;

-- ================================================================
-- LENGUAJE INCLUSIVO 
-- ================================================================
CREATE OR REPLACE FUNCTION fn_listar_sugerencias_inclusivas() RETURNS JSON AS $$
  SELECT COALESCE(json_agg(l), '[]') FROM lenguaje_inclusivo_sugerencia l;
$$ LANGUAGE sql STABLE;

-- ================================================================
-- FUNCIONES CRUD: MASCOTAS Y ADMIN
-- ================================================================
CREATE OR REPLACE FUNCTION fn_editar_perro(p_perro_id BIGINT, p_nombre VARCHAR, p_raza VARCHAR, p_peso NUMERIC, p_foto_url TEXT) RETURNS JSON AS $$
DECLARE v_row perro;
BEGIN
  UPDATE perro SET nombre = COALESCE(p_nombre, nombre), raza = COALESCE(p_raza, raza), peso = COALESCE(p_peso, peso), foto_url = COALESCE(p_foto_url, foto_url), updated_at = now()
  WHERE id = p_perro_id AND deleted_at IS NULL RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_eliminar_perro(p_perro_id BIGINT) RETURNS JSON AS $$
BEGIN
  UPDATE perro SET deleted_at = now() WHERE id = p_perro_id;
  RETURN json_build_object('ok', true);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_listar_planes() RETURNS JSON AS $$
  SELECT COALESCE(json_agg(p ORDER BY precio_mensual ASC), '[]') FROM plan p WHERE activo = true;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_cambiar_plan_casa(p_casa_id BIGINT, p_plan_id BIGINT) RETURNS JSON AS $$
DECLARE v_row suscripcion;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM plan WHERE id = p_plan_id AND activo = true) THEN 
    RAISE EXCEPTION 'PLAN_INVALIDO' USING ERRCODE = 'P0005'; 
  END IF;

  UPDATE suscripcion SET plan_id = p_plan_id, updated_at = now() WHERE casa_id = p_casa_id RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;
