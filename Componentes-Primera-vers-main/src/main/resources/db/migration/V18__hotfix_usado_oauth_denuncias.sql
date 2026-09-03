-- V18__hotfix_usado_oauth_denuncias.sql
-- FIX 1: columna 'usado' (no 'used') en password_reset_token
-- FIX 2: fn_login_oauth — manejar usuario existente con deleted_at o ya vinculado
-- FIX 3: fn_registrar_propietario — chequear email sin filtro deleted_at
-- FIX 4: veces_reportado counter en reporte_moderacion
-- REGLA: Solo CREATE OR REPLACE / ALTER ADD IF NOT EXISTS. No tocar V1-V17.

-- ==========================================================
-- FIX 1: Recrear fn_solicitar_reset con columna 'usado' correcta
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_solicitar_reset(VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION public.fn_solicitar_reset(p_email VARCHAR, p_token VARCHAR)
RETURNS JSON AS $$
DECLARE
  v_user_id BIGINT;
BEGIN
  SELECT id INTO v_user_id
  FROM public.usuario
  WHERE email = p_email AND deleted_at IS NULL;

  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'error', 'Usuario no encontrado');
  END IF;

  -- Invalidar tokens anteriores pendientes del mismo usuario
  UPDATE public.password_reset_token
  SET usado = true
  WHERE usuario_id = v_user_id AND usado = false;

  -- Insertar nuevo token con expiración de 1 hora (UTC)
  INSERT INTO public.password_reset_token (token, usuario_id, expiry_date)
  VALUES (p_token, v_user_id, (NOW() AT TIME ZONE 'UTC') + INTERVAL '1 hour');

  RETURN json_build_object('ok', true, 'token', p_token);
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 2: Recrear fn_resetear_password con columna 'usado' correcta
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
    AND expiry_date > (NOW() AT TIME ZONE 'UTC');

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
-- FIX 3: Recrear fn_login_oauth — maneja usuarios existentes con deleted_at
-- y evita duplicar proveedor ya vinculado
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_login_oauth(proveedor_auth, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.fn_login_oauth(proveedor_auth, VARCHAR, VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION public.fn_login_oauth(
  p_proveedor    proveedor_auth,
  p_proveedor_uid VARCHAR,
  p_email        VARCHAR,
  p_nombre       VARCHAR,
  p_foto_url     VARCHAR DEFAULT NULL
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

  -- 2) ¿Existe usuario con ese email (login local previo o cuenta baneada)?
  --    SIN filtro deleted_at: si fue baneado, lo restauramos al hacer OAuth
  IF v_usuario_id IS NULL THEN
    SELECT id INTO v_usuario_id
    FROM public.usuario
    WHERE email = p_email
    LIMIT 1;

    IF v_usuario_id IS NOT NULL THEN
      -- Restaurar cuenta si estaba borrada
      UPDATE public.usuario
      SET deleted_at = NULL, activo = true
      WHERE id = v_usuario_id AND deleted_at IS NOT NULL;

      -- Vincular proveedor (ignorar si ya existe)
      INSERT INTO public.usuario_proveedor (usuario_id, proveedor, proveedor_uid)
      VALUES (v_usuario_id, p_proveedor, p_proveedor_uid)
      ON CONFLICT (proveedor, proveedor_uid) DO NOTHING;
    END IF;
  END IF;

  -- 3) No existe: crear usuario nuevo como PROPIETARIO (todos los registrados son propietarios)
  IF v_usuario_id IS NULL THEN
    INSERT INTO public.usuario (email, nombre, rol, foto_url)
    VALUES (p_email, p_nombre, 'PROPIETARIO', p_foto_url)
    ON CONFLICT (email) DO UPDATE
      SET deleted_at = NULL,
          activo = true,
          foto_url = COALESCE(public.usuario.foto_url, EXCLUDED.foto_url)
    RETURNING id INTO v_usuario_id;

    INSERT INTO public.usuario_proveedor (usuario_id, proveedor, proveedor_uid)
    VALUES (v_usuario_id, p_proveedor, p_proveedor_uid)
    ON CONFLICT (proveedor, proveedor_uid) DO NOTHING;
  ELSE
    -- Actualizar foto si aún no tiene
    UPDATE public.usuario
    SET foto_url = COALESCE(foto_url, p_foto_url)
    WHERE id = v_usuario_id;
  END IF;

  SELECT * INTO v_usuario FROM public.usuario WHERE id = v_usuario_id;

  -- Auditoria (no fatal)
  BEGIN
    INSERT INTO public.auditoria_log (usuario_id, accion, entidad, entidad_id)
    VALUES (v_usuario_id, 'LOGIN_OAUTH', 'usuario', v_usuario_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON;
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 4: Recrear fn_registrar_propietario — chequear email SIN deleted_at
-- para evitar que cuentas borrads rompan el INSERT
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_registrar_propietario(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.fn_registrar_propietario(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, NUMERIC, NUMERIC);

CREATE OR REPLACE FUNCTION public.fn_registrar_propietario(
  p_email      VARCHAR,
  p_password   VARCHAR,
  p_nombre     VARCHAR,
  p_casa_nombre VARCHAR,
  p_direccion  VARCHAR
)
RETURNS JSON AS $$
DECLARE
  v_usuario public.usuario;
  v_casa    public.casa;
  v_zona1   public.zona;
  v_zona2   public.zona;
BEGIN
  -- Verificar email sin filtro deleted_at (email es UNIQUE en DB)
  IF EXISTS (SELECT 1 FROM public.usuario WHERE email = p_email) THEN
    RAISE EXCEPTION 'EMAIL_YA_REGISTRADO' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.usuario (email, password_hash, nombre, rol)
  VALUES (p_email, crypt(p_password, gen_salt('bf')), p_nombre, 'PROPIETARIO')
  RETURNING * INTO v_usuario;

  INSERT INTO public.casa (propietario_id, nombre, direccion)
  VALUES (v_usuario.id, p_casa_nombre, p_direccion)
  RETURNING * INTO v_casa;

  UPDATE public.usuario SET casa_id = v_casa.id WHERE id = v_usuario.id RETURNING * INTO v_usuario;

  INSERT INTO public.zona (casa_id, nombre, descripcion)
  VALUES (v_casa.id, 'Sala 1', 'Descanso y Confort') RETURNING * INTO v_zona1;
  INSERT INTO public.zona (casa_id, nombre, descripcion)
  VALUES (v_casa.id, 'Sala 2', 'Alimentación') RETURNING * INTO v_zona2;

  INSERT INTO public.suscripcion (casa_id, plan_id)
  VALUES (v_casa.id, (SELECT id FROM public.plan WHERE nombre = 'FREE'));

  INSERT INTO public.configuracion_cloud (casa_id) VALUES (v_casa.id);

  RETURN json_build_object(
    'usuario', (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON,
    'casa', row_to_json(v_casa),
    'zonas', json_build_array(row_to_json(v_zona1), row_to_json(v_zona2))
  );
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 5: Agregar contador de denuncias a reporte_moderacion
-- ==========================================================
ALTER TABLE public.reporte_moderacion
  ADD COLUMN IF NOT EXISTS veces_reportado INT NOT NULL DEFAULT 1;

-- Índice para ordenar por más denunciados
CREATE INDEX IF NOT EXISTS idx_reporte_veces ON public.reporte_moderacion(veces_reportado DESC)
  WHERE estado::text = 'PENDIENTE';

-- ==========================================================
-- FIX 6: Asegurar que password_reset_token.token tiene UNIQUE (V17 lo intentó)
-- ==========================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'password_reset_token' AND constraint_type = 'UNIQUE'
      AND constraint_name LIKE '%token%'
  ) THEN
    BEGIN
      ALTER TABLE public.password_reset_token ADD CONSTRAINT prt_token_uq UNIQUE (token);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
END $$;
