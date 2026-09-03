CREATE TABLE IF NOT EXISTS password_reset_token (
  id BIGSERIAL PRIMARY KEY,
  token VARCHAR(255) NOT NULL UNIQUE,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  expiry_date TIMESTAMPTZ NOT NULL,
  used BOOLEAN NOT NULL DEFAULT FALSE
);

-- NOTA (2026-08-22): esta version de fn_solicitar_reset (3 argumentos, con
-- p_expiry) quedo huerfana cuando V16 introdujo una version de 2 argumentos
-- (sin p_expiry) en vez de reemplazar esta. V35 ya elimino la version vieja
-- de la base real; este archivo se conserva intacto (no se borra) porque
-- Flyway necesita reproducir exactamente esta secuencia si algun dia hay
-- que reconstruir la base desde cero.
CREATE OR REPLACE FUNCTION fn_solicitar_reset(p_email VARCHAR, p_token VARCHAR, p_expiry TIMESTAMPTZ) RETURNS JSON AS $$
DECLARE v_user_id BIGINT;
BEGIN
  SELECT id INTO v_user_id FROM usuario WHERE email = p_email;
  IF NOT FOUND THEN RETURN json_build_object('ok', false, 'error', 'Usuario no encontrado'); END IF;
  INSERT INTO password_reset_token (token, usuario_id, expiry_date) VALUES (p_token, v_user_id, p_expiry);
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
