-- V17__hotfix_funciones_sql.sql
-- REGLA: CREATE OR REPLACE solamente. No toca migraciones V1-V16.
-- Corrige: fn_solicitar_reset (columna token), fn_resetear_password, fn_resolver_denuncia (enum estados)

-- ==========================================================
-- FIX 1: Garantizar que la columna 'token' existe en password_reset_token
-- Si en Neon existe como 'token_hash', renombrarla. Si no existe ninguna, agregarla.
-- ==========================================================
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'password_reset_token' AND column_name = 'token'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'password_reset_token' AND column_name = 'token_hash'
    ) THEN
      ALTER TABLE public.password_reset_token RENAME COLUMN token_hash TO token;
    ELSE
      ALTER TABLE public.password_reset_token ADD COLUMN token VARCHAR(255) NOT NULL DEFAULT gen_random_uuid()::text;
      BEGIN
        ALTER TABLE public.password_reset_token ADD CONSTRAINT prt_token_unique UNIQUE (token);
      EXCEPTION WHEN duplicate_table THEN NULL;
      END;
    END IF;
  END IF;
END $$;

-- ==========================================================
-- FIX 2: Recrear fn_solicitar_reset con firma de 2 parametros y columna 'token' correcta
-- Elimina todos los overloads posibles antes de recrear
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_solicitar_reset(VARCHAR, VARCHAR, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS public.fn_solicitar_reset(VARCHAR, VARCHAR, INTEGER);
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

  -- Invalidar tokens anteriores no usados del mismo usuario
  UPDATE public.password_reset_token
  SET used = true
  WHERE usuario_id = v_user_id AND used = false;

  -- Insertar nuevo token con expiracion de 1 hora usando tiempo del servidor Postgres
  INSERT INTO public.password_reset_token (token, usuario_id, expiry_date)
  VALUES (p_token, v_user_id, (NOW() AT TIME ZONE 'UTC') + INTERVAL '1 hour');

  RETURN json_build_object('ok', true, 'token', p_token);
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 3: Recrear fn_resetear_password con columna 'token' correcta
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
    AND used = false
    AND expiry_date > (NOW() AT TIME ZONE 'UTC');

  IF NOT FOUND THEN
    RETURN json_build_object('ok', false, 'error', 'Token inválido o expirado');
  END IF;

  UPDATE public.usuario
  SET password_hash = p_new_password
  WHERE id = v_token_row.usuario_id;

  UPDATE public.password_reset_token
  SET used = true
  WHERE id = v_token_row.id;

  RETURN json_build_object('ok', true);
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 4: Asegurar que la tabla reporte_resolucion existe
-- ==========================================================
CREATE TABLE IF NOT EXISTS public.reporte_resolucion (
  id          BIGSERIAL PRIMARY KEY,
  reporte_id  BIGINT NOT NULL REFERENCES public.reporte_moderacion(id) ON DELETE CASCADE,
  admin_id    BIGINT REFERENCES public.usuario(id),
  decision    VARCHAR(50),
  comentario_admin TEXT,
  fecha_resolucion TIMESTAMPTZ DEFAULT now(),
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Indice para evitar resoluciones duplicadas
CREATE UNIQUE INDEX IF NOT EXISTS uq_reporte_resolucion_reporte ON public.reporte_resolucion(reporte_id);

-- ==========================================================
-- FIX 5: Corregir datos historicos con estados en forma incorrecta
-- V15 los grabó como 'RESUELTA'/'RECHAZADA'; el frontend espera 'RESUELTO'/'DESCARTADO'
-- Se envuelve en bloques DO para no fallar si el ENUM no tiene esos valores
-- ==========================================================
DO $$
BEGIN
  UPDATE public.reporte_moderacion SET estado = 'RESUELTO' WHERE estado::text = 'RESUELTA';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nota: no se pudo convertir RESUELTA->RESUELTO (puede que el enum ya sea correcto): %', SQLERRM;
END $$;

DO $$
BEGIN
  UPDATE public.reporte_moderacion SET estado = 'DESCARTADO' WHERE estado::text = 'RECHAZADA';
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Nota: no se pudo convertir RECHAZADA->DESCARTADO: %', SQLERRM;
END $$;

-- ==========================================================
-- FIX 6: Recrear fn_resolver_denuncia con estados RESUELTO/DESCARTADO
-- correctamente escritos para coincidir con el ENUM del sistema y el frontend
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_resolver_denuncia(BIGINT, VARCHAR, BIGINT, TEXT);

CREATE OR REPLACE FUNCTION public.fn_resolver_denuncia(
    p_reporte_id BIGINT,
    p_accion     VARCHAR,
    p_admin_id   BIGINT,
    p_comentario TEXT
)
RETURNS JSON AS $$
DECLARE
    v_reporte       public.reporte_moderacion;
    v_reportado_id  BIGINT;
    v_strikes       INT;
    v_publicacion_id BIGINT;
BEGIN
    SELECT * INTO v_reporte FROM public.reporte_moderacion WHERE id = p_reporte_id;

    IF v_reporte.id IS NULL THEN
        RAISE EXCEPTION 'REPORTE_NO_ENCONTRADO: id=%', p_reporte_id USING ERRCODE = 'P0001';
    END IF;

    v_reportado_id := v_reporte.reportado_id;

    -- Registrar resolución (ON CONFLICT para evitar duplicados)
    INSERT INTO public.reporte_resolucion (reporte_id, admin_id, decision, comentario_admin, fecha_resolucion)
    VALUES (p_reporte_id, p_admin_id, p_accion, p_comentario, now())
    ON CONFLICT (reporte_id) DO UPDATE
      SET decision = EXCLUDED.decision,
          comentario_admin = EXCLUDED.comentario_admin,
          fecha_resolucion = EXCLUDED.fecha_resolucion;

    IF p_accion = 'STRIKE' THEN
        IF v_reportado_id IS NOT NULL THEN
            -- Dar 1 strike al usuario
            UPDATE public.usuario
            SET strikes = COALESCE(strikes, 0) + 1
            WHERE id = v_reportado_id
            RETURNING strikes INTO v_strikes;

            -- Ocultar la publicación vinculada si el motivo la referencia
            IF v_reporte.motivo LIKE 'Reporte de Publicaci%#%' THEN
                BEGIN
                    v_publicacion_id := (regexp_match(v_reporte.motivo, 'Reporte de Publicaci[^#]+#(\d+)'))[1]::BIGINT;
                    IF v_publicacion_id IS NOT NULL THEN
                        UPDATE public.publicacion SET deleted_at = now() WHERE id = v_publicacion_id;
                    END IF;
                EXCEPTION WHEN OTHERS THEN
                    NULL; -- Si el motivo no tiene formato esperado, ignorar
                END;
            END IF;

            -- Regla de los 3 strikes = banear cuenta
            IF COALESCE(v_strikes, 0) >= 3 THEN
                UPDATE public.usuario SET deleted_at = now() WHERE id = v_reportado_id;
            END IF;
        END IF;

        UPDATE public.reporte_moderacion
        SET estado = 'RESUELTO', decidido_por = 'ADMIN'
        WHERE id = p_reporte_id;

    ELSIF p_accion = 'ELIMINAR_SIN_STRIKE' THEN
        IF v_reporte.motivo LIKE 'Reporte de Publicaci%#%' THEN
            BEGIN
                v_publicacion_id := (regexp_match(v_reporte.motivo, 'Reporte de Publicaci[^#]+#(\d+)'))[1]::BIGINT;
                IF v_publicacion_id IS NOT NULL THEN
                    UPDATE public.publicacion SET deleted_at = now() WHERE id = v_publicacion_id;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                NULL;
            END;
        END IF;

        UPDATE public.reporte_moderacion
        SET estado = 'RESUELTO', decidido_por = 'ADMIN'
        WHERE id = p_reporte_id;

    ELSE
        -- DESCARTADO u otro valor
        UPDATE public.reporte_moderacion
        SET estado = 'DESCARTADO', decidido_por = 'ADMIN'
        WHERE id = p_reporte_id;
    END IF;

    -- Auditoría (envuelta en bloque para no romper la transacción principal si la tabla difiere)
    BEGIN
        INSERT INTO public.auditoria_log (usuario_id, accion, entidad, entidad_id, detalle)
        VALUES (p_admin_id, 'RESOLVER_DENUNCIA', 'reporte_moderacion', p_reporte_id,
                json_build_object('accion', p_accion)::text);
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Auditoria no registrada: %', SQLERRM;
    END;

    RETURN json_build_object('ok', true, 'reporte_id', p_reporte_id, 'accion', p_accion);
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 7: Asegurar columna 'strikes' en usuario (por si V15 no se aplicó correctamente)
-- ==========================================================
ALTER TABLE public.usuario ADD COLUMN IF NOT EXISTS strikes INT DEFAULT 0;
