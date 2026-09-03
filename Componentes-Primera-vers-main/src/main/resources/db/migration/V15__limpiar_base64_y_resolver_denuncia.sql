-- V15__limpiar_base64_y_resolver_denuncia.sql

-- 1. BUG 5: Drop and recreate fn_login_oauth con 5 parametros
DROP FUNCTION IF EXISTS fn_login_oauth(proveedor_auth, VARCHAR, VARCHAR, VARCHAR);

-- NOTA (2026-08-22): esta version de fn_login_oauth (p_foto_url TEXT, sin
-- default) quedo huerfana cuando V19 introdujo una version con p_foto_url
-- VARCHAR DEFAULT NULL en vez de reemplazar esta (el tipo distinto del
-- ultimo parametro basto para que Postgres las tratara como sobrecargas
-- separadas). V34 ya elimino esta version vieja de la base real; este
-- archivo se conserva intacto (no se borra) porque Flyway necesita
-- reproducir exactamente esta secuencia si algun dia hay que reconstruir
-- la base desde cero.
CREATE OR REPLACE FUNCTION fn_login_oauth(
  p_proveedor proveedor_auth, p_proveedor_uid VARCHAR, p_email VARCHAR, p_nombre VARCHAR, p_foto_url TEXT
) RETURNS JSON AS $$
DECLARE v_usuario_id BIGINT; v_usuario usuario;
BEGIN
  -- 1) ¿Ya vinculado por este proveedor?
  SELECT usuario_id INTO v_usuario_id FROM usuario_proveedor
  WHERE proveedor = p_proveedor AND proveedor_uid = p_proveedor_uid;

  -- 2) ¿Existe usuario con ese email (login local previo)? → vincular
  IF v_usuario_id IS NULL THEN
    SELECT id INTO v_usuario_id FROM usuario WHERE email = p_email AND deleted_at IS NULL;
    IF v_usuario_id IS NOT NULL THEN
      INSERT INTO usuario_proveedor (usuario_id, proveedor, proveedor_uid)
      VALUES (v_usuario_id, p_proveedor, p_proveedor_uid);
    END IF;
  END IF;

  -- 3) No existe: crear usuario nuevo (rol MIEMBRO por defecto; se asigna PROPIETARIO al registrar casa)
  IF v_usuario_id IS NULL THEN
    INSERT INTO usuario (email, nombre, rol, foto_url) VALUES (p_email, p_nombre, 'MIEMBRO', p_foto_url)
    RETURNING id INTO v_usuario_id;
    INSERT INTO usuario_proveedor (usuario_id, proveedor, proveedor_uid)
    VALUES (v_usuario_id, p_proveedor, p_proveedor_uid);
  ELSE
    -- Opcional: Actualizar la foto si ya existe pero está nula
    UPDATE usuario SET foto_url = COALESCE(foto_url, p_foto_url) WHERE id = v_usuario_id;
  END IF;

  SELECT * INTO v_usuario FROM usuario WHERE id = v_usuario_id;

  INSERT INTO auditoria_log (usuario_id, accion, entidad, entidad_id)
  VALUES (v_usuario_id, 'LOGIN_OAUTH', 'usuario', v_usuario_id);

  RETURN (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON;
END; $$ LANGUAGE plpgsql;


-- 2. BUG 4: Limpiar Base64 de las tablas para aligerar la BD y JWT
UPDATE usuario SET foto_url = NULL WHERE foto_url LIKE 'data:image%';
UPDATE publicacion SET imagen_url = NULL WHERE imagen_url LIKE 'data:image%';
-- Actualizar foto de perro si existe la tabla/columna
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'perro' AND column_name = 'foto_url') THEN
    EXECUTE 'UPDATE perro SET foto_url = NULL WHERE foto_url LIKE ''data:image%''';
  END IF;
END $$;


-- 3. BUG 6: Implementar fn_resolver_denuncia y regla de 3 strikes
ALTER TABLE usuario ADD COLUMN IF NOT EXISTS strikes INT DEFAULT 0;

CREATE OR REPLACE FUNCTION fn_resolver_denuncia(
    p_reporte_id BIGINT, p_accion VARCHAR, p_admin_id BIGINT, p_comentario TEXT
) RETURNS JSON AS $$
DECLARE
    v_reporte reporte_moderacion;
    v_reportado_id BIGINT;
    v_strikes INT;
    v_publicacion_id BIGINT;
BEGIN
    SELECT * INTO v_reporte FROM reporte_moderacion WHERE id = p_reporte_id;
    IF v_reporte.id IS NULL THEN
        RAISE EXCEPTION 'REPORTE_NO_ENCONTRADO' USING ERRCODE = 'P0001';
    END IF;
    IF v_reporte.estado != 'PENDIENTE' THEN
        RAISE EXCEPTION 'REPORTE_YA_RESUELTO' USING ERRCODE = 'P0002';
    END IF;

    v_reportado_id := v_reporte.reportado_id;

    -- Registrar resolucion
    INSERT INTO reporte_resolucion (reporte_id, admin_id, decision, comentario_admin, fecha_resolucion)
    VALUES (p_reporte_id, p_admin_id, p_accion, p_comentario, now());

    IF p_accion = 'STRIKE' THEN
        IF v_reportado_id IS NOT NULL THEN
            -- Dar 1 strike al usuario
            UPDATE usuario SET strikes = COALESCE(strikes, 0) + 1 WHERE id = v_reportado_id RETURNING strikes INTO v_strikes;
            
            -- Ocultar publicacion (Extraemos el ID de la publicacion del motivo que dice 'Reporte de Publicación #123: ...')
            IF v_reporte.motivo LIKE 'Reporte de Publicaci%#%' THEN
                v_publicacion_id := (regexp_match(v_reporte.motivo, 'Reporte de Publicaci[^#]+#(\d+)'))[1]::BIGINT;
                IF v_publicacion_id IS NOT NULL THEN
                    UPDATE publicacion SET deleted_at = now() WHERE id = v_publicacion_id;
                END IF;
            END IF;
            
            -- Regla de los 3 strikes = Banear al usuario
            IF v_strikes >= 3 THEN
                UPDATE usuario SET deleted_at = now() WHERE id = v_reportado_id;
            END IF;
        END IF;

        UPDATE reporte_moderacion SET estado = 'RESUELTA', decidido_por = 'ADMIN' WHERE id = p_reporte_id;
        
    ELSIF p_accion = 'ELIMINAR_SIN_STRIKE' THEN
        IF v_reporte.motivo LIKE 'Reporte de Publicaci%#%' THEN
            v_publicacion_id := (regexp_match(v_reporte.motivo, 'Reporte de Publicaci[^#]+#(\d+)'))[1]::BIGINT;
            IF v_publicacion_id IS NOT NULL THEN
                UPDATE publicacion SET deleted_at = now() WHERE id = v_publicacion_id;
            END IF;
        END IF;
        UPDATE reporte_moderacion SET estado = 'RESUELTA', decidido_por = 'ADMIN' WHERE id = p_reporte_id;
        
    ELSE
        UPDATE reporte_moderacion SET estado = 'RECHAZADA', decidido_por = 'ADMIN' WHERE id = p_reporte_id;
    END IF;

    INSERT INTO auditoria_log (usuario_id, accion, entidad, entidad_id, detalle)
    VALUES (p_admin_id, 'RESOLVER_DENUNCIA', 'reporte_moderacion', p_reporte_id, json_build_object('accion', p_accion)::text);

    RETURN json_build_object('ok', true, 'reporte_id', p_reporte_id, 'accion', p_accion);
END; $$ LANGUAGE plpgsql;
