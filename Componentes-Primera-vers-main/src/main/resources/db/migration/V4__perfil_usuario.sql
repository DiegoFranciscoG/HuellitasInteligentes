-- V4__perfil_usuario.sql
ALTER TABLE usuario ADD COLUMN IF NOT EXISTS foto_url TEXT;

CREATE OR REPLACE FUNCTION fn_actualizar_perfil(p_usuario_id BIGINT, p_nombre VARCHAR, p_foto_url TEXT)
RETURNS JSON AS $$
DECLARE v_row usuario;
BEGIN
  UPDATE usuario SET nombre = COALESCE(p_nombre, nombre), foto_url = COALESCE(p_foto_url, foto_url)
  WHERE id = p_usuario_id RETURNING * INTO v_row;
  RETURN (row_to_json(v_row)::JSONB - 'password_hash')::JSON;
END; $$ LANGUAGE plpgsql;
