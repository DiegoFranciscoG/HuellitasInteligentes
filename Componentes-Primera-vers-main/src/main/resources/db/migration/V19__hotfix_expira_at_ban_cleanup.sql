-- V19__hotfix_expira_at_ban_cleanup.sql
-- FIX 1: expiry_date → expira_at (nombre real en Neon) en fn_resetear_password y fn_solicitar_reset
-- FIX 2: fn_login — retornar CUENTA_BANEADA cuando activo=false
-- FIX 3: fn_login_oauth — retornar CUENTA_BANEADA en vez de restaurar cuenta baneada
-- FIX 4: Eliminar usuarios de prueba, conservar solo admin (id=3) y propietario principal (id=18)
-- REGLA: Solo CREATE OR REPLACE. No tocar V1-V18.

-- ==========================================================
-- FIX 1a: fn_solicitar_reset — usar expira_at
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_solicitar_reset(VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION public.fn_solicitar_reset(p_email VARCHAR, p_token VARCHAR)
RETURNS JSON AS $$
DECLARE
  v_user_id BIGINT;
BEGIN
  SELECT id INTO v_user_id
  FROM public.usuario
  WHERE email = p_email AND deleted_at IS NULL AND activo = true;

  IF NOT FOUND THEN
    -- Verificar si existe pero está baneado
    IF EXISTS (SELECT 1 FROM public.usuario WHERE email = p_email AND (deleted_at IS NOT NULL OR activo = false)) THEN
      RETURN json_build_object('ok', false, 'error', 'CUENTA_BANEADA');
    END IF;
    RETURN json_build_object('ok', false, 'error', 'Usuario no encontrado');
  END IF;

  -- Invalidar tokens anteriores pendientes
  UPDATE public.password_reset_token
  SET usado = true
  WHERE usuario_id = v_user_id AND usado = false;

  -- Insertar nuevo token con expiración de 1 hora (UTC)
  INSERT INTO public.password_reset_token (token, usuario_id, expira_at)
  VALUES (p_token, v_user_id, (NOW() AT TIME ZONE 'UTC') + INTERVAL '1 hour');

  RETURN json_build_object('ok', true, 'token', p_token);
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 1b: fn_resetear_password — usar expira_at
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_resetear_password(VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION public.fn_resetear_password(p_token VARCHAR, p_new_password VARCHAR)
RETURNS JSON AS $$
DECLARE
  v_token_row public.password_reset_token;
BEGIN
  SELECT * INTO v_token_row
  FROM public.password_reset_token
  WHERE token = p_token
    AND usado = false
    AND expira_at > (NOW() AT TIME ZONE 'UTC');

  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'error', 'Token inválido o expirado');
  END IF;

  UPDATE public.usuario
  SET password_hash = crypt(p_new_password, gen_salt('bf'))
  WHERE id = v_token_row.usuario_id;

  UPDATE public.password_reset_token
  SET usado = true
  WHERE id = v_token_row.id;

  RETURN json_build_object('ok', true);
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 2: fn_login_oauth — retornar CUENTA_BANEADA si usuario está baneado
-- NO restaurar cuentas baneadas automáticamente
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_login_oauth(proveedor_auth, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.fn_login_oauth(proveedor_auth, VARCHAR, VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION public.fn_login_oauth(
  p_proveedor     proveedor_auth,
  p_proveedor_uid VARCHAR,
  p_email         VARCHAR,
  p_nombre        VARCHAR,
  p_foto_url      VARCHAR DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
  v_usuario_id BIGINT;
  v_usuario    public.usuario;
BEGIN
  -- 1) ¿Ya vinculado por uid de este proveedor?
  SELECT usuario_id INTO v_usuario_id
  FROM public.usuario_proveedor
  WHERE proveedor = p_proveedor AND proveedor_uid = p_proveedor_uid;

  -- 2) ¿Existe usuario con ese email?
  IF v_usuario_id IS NULL THEN
    SELECT id INTO v_usuario_id
    FROM public.usuario
    WHERE email = p_email
    LIMIT 1;
  END IF;

  -- Si existe, verificar que no esté baneado
  IF v_usuario_id IS NOT NULL THEN
    SELECT * INTO v_usuario FROM public.usuario WHERE id = v_usuario_id;
    IF v_usuario.deleted_at IS NOT NULL OR v_usuario.activo = false THEN
      RETURN json_build_object('ok', false, 'error', 'CUENTA_BANEADA',
        'message', 'Tu cuenta ha sido suspendida por infracciones a las normas de la comunidad.');
    END IF;

    -- Vincular proveedor si no estaba vinculado
    INSERT INTO public.usuario_proveedor (usuario_id, proveedor, proveedor_uid)
    VALUES (v_usuario_id, p_proveedor, p_proveedor_uid)
    ON CONFLICT (proveedor, proveedor_uid) DO NOTHING;

    -- Actualizar foto si no tiene
    UPDATE public.usuario
    SET foto_url = COALESCE(foto_url, p_foto_url)
    WHERE id = v_usuario_id;

    SELECT * INTO v_usuario FROM public.usuario WHERE id = v_usuario_id;
  ELSE
    -- 3) No existe: crear usuario nuevo como PROPIETARIO
    INSERT INTO public.usuario (email, nombre, rol, foto_url)
    VALUES (p_email, p_nombre, 'PROPIETARIO', p_foto_url)
    RETURNING * INTO v_usuario;

    v_usuario_id := v_usuario.id;

    INSERT INTO public.usuario_proveedor (usuario_id, proveedor, proveedor_uid)
    VALUES (v_usuario_id, p_proveedor, p_proveedor_uid)
    ON CONFLICT (proveedor, proveedor_uid) DO NOTHING;
  END IF;

  -- Auditoría
  BEGIN
    INSERT INTO public.auditoria_log (usuario_id, accion, entidad, entidad_id)
    VALUES (v_usuario_id, 'LOGIN_OAUTH', 'usuario', v_usuario_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON;
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 3: Limpiar usuarios de prueba
-- ORDEN: publicaciones y comentarios PRIMERO (mientras usuarios existen)
-- para que el trigger fn_trg_auditoria_publicacion no falle por FK en auditoria_log
-- Conservar SOLO: id=3 (admin diegofgz2004) e id=18 (propietario diego.granda.est)
-- ==========================================================
DO $$
BEGIN
  -- 1) Publicaciones primero (usuarios aun existen → trigger auditoria_log OK)
  BEGIN DELETE FROM public.publicacion WHERE usuario_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'pub: %', SQLERRM; END;
  BEGIN DELETE FROM public.comentario WHERE usuario_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'com: %', SQLERRM; END;

  -- 2) Tablas sin CASCADE (orden: dependientes primero)
  BEGIN DELETE FROM public.reporte_resolucion WHERE admin_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.reporte_moderacion WHERE reportado_id NOT IN (3, 18) OR denunciante_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.reporte_comunidad WHERE usuario_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.publicacion_reporte WHERE usuario_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.publicacion_reaccion WHERE usuario_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.grupo_miembro WHERE usuario_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.publicacion_grupo WHERE usuario_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.mensaje WHERE emisor_id NOT IN (3, 18) OR receptor_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.notificacion WHERE usuario_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.refresh_token WHERE usuario_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.usuario_proveedor WHERE usuario_id NOT IN (3, 18); EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN DELETE FROM public.auditoria_log WHERE usuario_id NOT IN (3, 18) AND usuario_id IS NOT NULL; EXCEPTION WHEN OTHERS THEN NULL; END;

  -- 3) Ahora borrar usuarios (publicaciones ya borradas → trigger no dispara)
  DELETE FROM public.usuario WHERE id NOT IN (3, 18);

  RAISE NOTICE 'Limpieza completada. Solo quedan id=3 y id=18.';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Error limpieza usuarios: %', SQLERRM;
END $$;

