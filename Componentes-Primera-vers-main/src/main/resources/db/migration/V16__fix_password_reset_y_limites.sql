-- V16__fix_password_reset_y_limites.sql

-- 1. Fix Restablecer Contraseña (TOKEN_INVALIDO_O_EXPIRADO)
DROP FUNCTION IF EXISTS fn_solicitar_reset(VARCHAR, VARCHAR, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS fn_solicitar_reset(VARCHAR, VARCHAR, INT);

CREATE OR REPLACE FUNCTION fn_solicitar_reset(p_email VARCHAR, p_token VARCHAR) RETURNS JSON AS $$
DECLARE v_user_id BIGINT;
BEGIN
  SELECT id INTO v_user_id FROM usuario WHERE email = p_email;
  IF NOT FOUND THEN RETURN json_build_object('ok', false, 'error', 'Usuario no encontrado'); END IF;
  
  -- Generar con now() + interval '1 hour' para evitar desajustes horarios
  INSERT INTO password_reset_token (token, usuario_id, expiry_date) VALUES (p_token, v_user_id, now() + interval '1 hour');
  
  RETURN json_build_object('ok', true, 'token', p_token);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_resetear_password(p_token VARCHAR, p_new_password VARCHAR) RETURNS JSON AS $$
DECLARE v_token_row password_reset_token;
BEGIN
  SELECT * INTO v_token_row FROM password_reset_token WHERE token = p_token AND not used AND expiry_date > now();
  IF NOT FOUND THEN RETURN json_build_object('ok', false, 'error', 'Token inválido o expirado'); END IF;
  
  UPDATE usuario SET password_hash = p_new_password WHERE id = v_token_row.usuario_id;
  UPDATE password_reset_token SET used = true WHERE id = v_token_row.id;
  
  RETURN json_build_object('ok', true);
END; $$ LANGUAGE plpgsql;

-- 2. Eliminar límite de 5 minutos para Editar/Eliminar
CREATE OR REPLACE FUNCTION fn_editar_comentario(p_comentario_id BIGINT, p_usuario_id BIGINT, p_contenido TEXT) RETURNS JSON AS $$
DECLARE v_row comentario; v_rol rol_usuario; v_autor_id BIGINT; v_created_at TIMESTAMPTZ;
BEGIN
  SELECT usuario_id, created_at INTO v_autor_id, v_created_at FROM comentario WHERE id = p_comentario_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'COMENTARIO_NO_ENCONTRADO' USING ERRCODE = 'P0004'; END IF;

  SELECT rol INTO v_rol FROM usuario WHERE id = p_usuario_id;
  
  IF v_autor_id != p_usuario_id AND v_rol != 'ADMINISTRADOR' THEN
    RAISE EXCEPTION 'NO_AUTORIZADO' USING ERRCODE = 'P0001';
  END IF;
  -- ELIMINADA LA RESTRICCIÓN DE 5 MINUTOS

  UPDATE comentario SET contenido = p_contenido WHERE id = p_comentario_id RETURNING * INTO v_row;
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
  -- ELIMINADA LA RESTRICCIÓN DE 5 MINUTOS

  UPDATE publicacion SET contenido = p_contenido WHERE id = p_publicacion_id RETURNING * INTO v_row;
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
  -- ELIMINADA LA RESTRICCIÓN DE 5 MINUTOS

  UPDATE publicacion_grupo SET contenido = p_contenido, updated_at = now() WHERE id = p_publicacion_id RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;
