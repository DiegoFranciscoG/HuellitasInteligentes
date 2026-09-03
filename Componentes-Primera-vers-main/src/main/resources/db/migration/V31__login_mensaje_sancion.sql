-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V31: fn_login distinguía "contraseña incorrecta" de "cuenta sancionada por
-- 3 strikes" o "cuenta bloqueada" con el mismo error genérico
-- (CREDENCIALES_INVALIDAS), porque el WHERE original excluía de entrada a
-- cualquier fila con activo=false o deleted_at, así que ni siquiera llegaba
-- a comparar la contraseña. Ahora primero valida la contraseña contra
-- CUALQUIER fila con ese email, y solo después decide con qué motivo
-- exacto se rechaza el acceso, para que el usuario sancionado sepa que fue
-- por los 3 strikes y no piense que escribió mal su contraseña.

CREATE OR REPLACE FUNCTION fn_login(p_email VARCHAR, p_password VARCHAR) RETURNS JSON AS $$
DECLARE v_usuario usuario;
BEGIN
  SELECT * INTO v_usuario FROM usuario WHERE email = p_email;

  IF NOT FOUND OR v_usuario.password_hash IS NULL
     OR v_usuario.password_hash <> crypt(p_password, v_usuario.password_hash) THEN
    RAISE EXCEPTION 'CREDENCIALES_INVALIDAS' USING ERRCODE = '28P01';
  END IF;

  IF COALESCE(v_usuario.strikes, 0) >= 3 THEN
    RAISE EXCEPTION 'CUENTA_SANCIONADA' USING ERRCODE = '28P02';
  END IF;

  IF v_usuario.activo = false OR v_usuario.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'CUENTA_BLOQUEADA' USING ERRCODE = '28P03';
  END IF;

  INSERT INTO auditoria_log (usuario_id, accion, entidad, entidad_id)
  VALUES (v_usuario.id, 'LOGIN', 'usuario', v_usuario.id);

  RETURN (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON;
END; $$ LANGUAGE plpgsql;
