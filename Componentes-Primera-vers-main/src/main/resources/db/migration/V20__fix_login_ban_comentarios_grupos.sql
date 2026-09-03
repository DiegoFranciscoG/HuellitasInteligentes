-- V20__fix_login_ban_comentarios_grupos.sql
-- FIX 1: fn_login — diferenciar CUENTA_BANEADA de CREDENCIALES_INVALIDAS
-- FIX 2: comentario — agregar deleted_at para soft-delete
-- FIX 3: fn_listar_comentarios — filtrar comentarios eliminados
-- FIX 4: fn_resolver_denuncia — eliminar comentario al resolver denuncia
-- REGLA: Solo CREATE OR REPLACE / ALTER ADD IF NOT EXISTS. No tocar V1-V19.

-- ==========================================================
-- FIX 1: fn_login — cuenta baneada vs credenciales inválidas
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_login(VARCHAR, VARCHAR);

CREATE OR REPLACE FUNCTION public.fn_login(p_email VARCHAR, p_password VARCHAR)
RETURNS JSON AS $$
DECLARE v_usuario public.usuario;
BEGIN
  -- Buscar usuario SIN filtrar activo/deleted_at para diferenciar el error
  SELECT * INTO v_usuario FROM public.usuario WHERE email = p_email;

  -- Usuario no existe
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CREDENCIALES_INVALIDAS' USING ERRCODE = '28P01';
  END IF;

  -- Usuario existe pero fue baneado / desactivado
  IF v_usuario.deleted_at IS NOT NULL OR v_usuario.activo = false THEN
    RAISE EXCEPTION 'CUENTA_BANEADA: Tu cuenta ha sido suspendida por infracciones a las normas de la comunidad. Si crees que es un error contacta al administrador.' USING ERRCODE = 'P0006';
  END IF;

  -- Credenciales inválidas (password incorrecto)
  IF v_usuario.password_hash IS NULL
     OR v_usuario.password_hash <> crypt(p_password, v_usuario.password_hash) THEN
    RAISE EXCEPTION 'CREDENCIALES_INVALIDAS' USING ERRCODE = '28P01';
  END IF;

  BEGIN
    INSERT INTO public.auditoria_log (usuario_id, accion, entidad, entidad_id)
    VALUES (v_usuario.id, 'LOGIN', 'usuario', v_usuario.id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON;
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 2: Agregar deleted_at a la tabla comentario (soft-delete)
-- ==========================================================
ALTER TABLE public.comentario ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_comentario_no_eliminado ON public.comentario(publicacion_id)
  WHERE deleted_at IS NULL;

-- ==========================================================
-- FIX 3: Recrear fn_listar_comentarios — filtrar eliminados
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_listar_comentarios(BIGINT);

CREATE OR REPLACE FUNCTION public.fn_listar_comentarios(p_publicacion_id BIGINT)
RETURNS JSON AS $$
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
    AND c.deleted_at IS NULL;
$$ LANGUAGE sql STABLE;

-- ==========================================================
-- FIX 4: Recrear fn_resolver_denuncia — también elimina comentarios
-- al resolver una denuncia de contenido
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
    v_reporte        public.reporte_moderacion;
    v_reportado_id   BIGINT;
    v_strikes        INT;
    v_publicacion_id BIGINT;
    v_comentario_id  BIGINT;
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

    IF p_accion IN ('STRIKE', 'ELIMINAR_SIN_STRIKE') THEN
        -- Determinar si es comentario o publicación según el motivo
        IF v_reporte.motivo ILIKE '%comentario%#%' OR v_reporte.motivo ILIKE '%comment%#%' THEN
            BEGIN
                v_comentario_id := (regexp_match(v_reporte.motivo, '#(\d+)'))[1]::BIGINT;
                IF v_comentario_id IS NOT NULL THEN
                    UPDATE public.comentario SET deleted_at = now() WHERE id = v_comentario_id;
                END IF;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        ELSIF v_reporte.motivo ILIKE '%publicaci%#%' OR v_reporte.motivo ILIKE '%post%#%' THEN
            BEGIN
                v_publicacion_id := (regexp_match(v_reporte.motivo, '#(\d+)'))[1]::BIGINT;
                IF v_publicacion_id IS NOT NULL THEN
                    UPDATE public.publicacion SET deleted_at = now() WHERE id = v_publicacion_id;
                END IF;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        ELSE
            -- Intentar borrar publicacion si hay una referenciada en el reporte
            BEGIN
                v_publicacion_id := (regexp_match(v_reporte.motivo, '#(\d+)'))[1]::BIGINT;
                IF v_publicacion_id IS NOT NULL THEN
                    -- Primero intentar eliminar como comentario
                    UPDATE public.comentario SET deleted_at = now()
                    WHERE id = v_publicacion_id AND deleted_at IS NULL;
                    -- Si no afectó ningún comentario, intentar como publicación
                    IF NOT FOUND THEN
                        UPDATE public.publicacion SET deleted_at = now()
                        WHERE id = v_publicacion_id AND deleted_at IS NULL;
                    END IF;
                END IF;
            EXCEPTION WHEN OTHERS THEN NULL;
            END;
        END IF;

        -- Dar strike al usuario reportado
        IF p_accion = 'STRIKE' AND v_reportado_id IS NOT NULL THEN
            UPDATE public.usuario
            SET strikes = COALESCE(strikes, 0) + 1
            WHERE id = v_reportado_id
            RETURNING strikes INTO v_strikes;

            -- 3 strikes = cuenta suspendida
            IF COALESCE(v_strikes, 0) >= 3 THEN
                UPDATE public.usuario
                SET deleted_at = now(), activo = false
                WHERE id = v_reportado_id;
            END IF;
        END IF;

        UPDATE public.reporte_moderacion
        SET estado = 'RESUELTO', decidido_por = 'ADMIN'
        WHERE id = p_reporte_id;

    ELSE
        -- DESCARTADO
        UPDATE public.reporte_moderacion
        SET estado = 'DESCARTADO', decidido_por = 'ADMIN'
        WHERE id = p_reporte_id;
    END IF;

    BEGIN
        INSERT INTO public.auditoria_log (usuario_id, accion, entidad, entidad_id, detalle)
        VALUES (p_admin_id, 'RESOLVER_DENUNCIA', 'reporte_moderacion', p_reporte_id,
                json_build_object('accion', p_accion)::text);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    RETURN json_build_object('ok', true, 'reporte_id', p_reporte_id, 'accion', p_accion);
END;
$$ LANGUAGE plpgsql;
