-- V21__fix_registrar_propietario_8params_planes_mascotas.sql
-- FIX 1: fn_registrar_propietario con 8 parámetros (Java envía ciudad, latitud, longitud)
-- FIX 2: Agregar ciudad/latitud/longitud a tabla casa (IF NOT EXISTS)
-- FIX 3: Agregar limite_mascotas a planes y definir beneficios claros

-- ==========================================================
-- FIX 1: Agregar columnas ciudad, latitud, longitud a casa (IF NOT EXISTS)
-- ==========================================================
ALTER TABLE public.casa ADD COLUMN IF NOT EXISTS ciudad VARCHAR(80);
ALTER TABLE public.casa ADD COLUMN IF NOT EXISTS latitud NUMERIC(9,6);
ALTER TABLE public.casa ADD COLUMN IF NOT EXISTS longitud NUMERIC(9,6);

-- ==========================================================
-- FIX 2: Agregar limite_mascotas al catálogo de planes
-- FREE y BASICO → max 2 mascotas / PREMIUM → max 4
-- ==========================================================
ALTER TABLE public.plan ADD COLUMN IF NOT EXISTS limite_mascotas INT NOT NULL DEFAULT 2;

UPDATE public.plan SET limite_mascotas = 2 WHERE nombre IN ('FREE', 'BASICO');
UPDATE public.plan SET limite_mascotas = 4 WHERE nombre = 'PREMIUM';

-- Actualizar descripciones de planes con beneficios claros
UPDATE public.plan SET descripcion = 'Monitoreo básico IoT · 3 dispositivos · 2 mascotas · Alertas esenciales · 200MB almacenamiento'
  WHERE nombre = 'FREE';
UPDATE public.plan SET descripcion = 'Historial 30 días · 6 dispositivos · 2 mascotas · Alertas avanzadas · 1GB almacenamiento · Soporte'
  WHERE nombre = 'BASICO';
UPDATE public.plan SET descripcion = 'IA avanzada · 15 dispositivos · 4 mascotas · Alertas prioritarias · 5GB almacenamiento · Soporte 24/7 · Historial ilimitado'
  WHERE nombre = 'PREMIUM';

-- ==========================================================
-- FIX 3: fn_registrar_propietario con 8 parámetros
-- Firma que Java usa: (email, password, nombre, casa_nombre, direccion, ciudad, latitud, longitud)
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_registrar_propietario(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR);
DROP FUNCTION IF EXISTS public.fn_registrar_propietario(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, NUMERIC, NUMERIC);

CREATE OR REPLACE FUNCTION public.fn_registrar_propietario(
    p_email       VARCHAR,
    p_password    VARCHAR,
    p_nombre      VARCHAR,
    p_casa_nombre VARCHAR,
    p_direccion   VARCHAR,
    p_ciudad      VARCHAR  DEFAULT NULL,
    p_latitud     NUMERIC  DEFAULT NULL,
    p_longitud    NUMERIC  DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_usuario public.usuario;
    v_casa    public.casa;
    v_zona1   public.zona;
    v_zona2   public.zona;
BEGIN
    -- Verificar que el email no esté ya registrado (activo O borrado)
    IF EXISTS (SELECT 1 FROM public.usuario WHERE email = p_email) THEN
        RAISE EXCEPTION 'EMAIL_YA_REGISTRADO' USING ERRCODE = 'P0002';
    END IF;

    INSERT INTO public.usuario (email, password_hash, nombre, rol)
    VALUES (p_email, crypt(p_password, gen_salt('bf')), p_nombre, 'PROPIETARIO')
    RETURNING * INTO v_usuario;

    INSERT INTO public.casa (propietario_id, nombre, direccion, ciudad, latitud, longitud)
    VALUES (v_usuario.id, p_casa_nombre, p_direccion, p_ciudad, p_latitud, p_longitud)
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
-- FIX 4: fn_registrar_perro — validar límite de mascotas según plan
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_registrar_perro(BIGINT, VARCHAR, VARCHAR, DATE, NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION public.fn_registrar_perro(
    p_casa_id        BIGINT,
    p_nombre         VARCHAR,
    p_raza           VARCHAR,
    p_fecha_nac      DATE,
    p_peso           NUMERIC,
    p_foto_url       TEXT
)
RETURNS JSON AS $$
DECLARE
    v_perro          public.perro;
    v_total_mascotas INT;
    v_limite         INT;
    v_plan_nombre    VARCHAR;
BEGIN
    -- Contar mascotas activas de la casa
    SELECT COUNT(*) INTO v_total_mascotas
    FROM public.perro WHERE casa_id = p_casa_id AND deleted_at IS NULL;

    -- Obtener límite según plan activo de la casa
    SELECT COALESCE(pl.limite_mascotas, 2), pl.nombre
    INTO v_limite, v_plan_nombre
    FROM public.suscripcion s
    JOIN public.plan pl ON pl.id = s.plan_id
    WHERE s.casa_id = p_casa_id AND s.estado = 'ACTIVA'
    LIMIT 1;

    -- Si no hay suscripción activa usar FREE (2 mascotas)
    IF v_limite IS NULL THEN v_limite := 2; END IF;

    IF v_total_mascotas >= v_limite THEN
        RETURN json_build_object(
            'ok', false,
            'error', 'LIMITE_MASCOTAS_ALCANZADO',
            'message', 'Tu plan ' || COALESCE(v_plan_nombre, 'FREE') ||
                       ' permite máximo ' || v_limite || ' mascota(s). ' ||
                       'Mejora a PREMIUM para registrar hasta 4 mascotas.'
        );
    END IF;

    INSERT INTO public.perro (casa_id, nombre, raza, fecha_nacimiento, peso, foto_url)
    VALUES (p_casa_id, p_nombre, p_raza, p_fecha_nac, p_peso, p_foto_url)
    RETURNING * INTO v_perro;

    RETURN json_build_object('ok', true, 'perro', row_to_json(v_perro));
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 5: fn_editar_perro — también necesita foto_url y peso opcionales
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_editar_perro(BIGINT, VARCHAR, VARCHAR, NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION public.fn_editar_perro(
    p_perro_id  BIGINT,
    p_nombre    VARCHAR,
    p_raza      VARCHAR,
    p_peso      NUMERIC,
    p_foto_url  TEXT
)
RETURNS JSON AS $$
DECLARE v_perro public.perro;
BEGIN
    UPDATE public.perro
    SET nombre         = COALESCE(p_nombre, nombre),
        raza           = COALESCE(p_raza, raza),
        peso           = COALESCE(p_peso, peso),
        foto_url       = CASE WHEN p_foto_url IS NOT NULL AND p_foto_url <> '' THEN p_foto_url ELSE foto_url END,
        updated_at     = now()
    WHERE id = p_perro_id AND deleted_at IS NULL
    RETURNING * INTO v_perro;

    IF NOT FOUND THEN
        RETURN json_build_object('ok', false, 'error', 'Mascota no encontrada');
    END IF;

    RETURN json_build_object('ok', true, 'perro', row_to_json(v_perro));
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
-- FIX 6: fn_eliminar_perro — soft delete
-- ==========================================================
DROP FUNCTION IF EXISTS public.fn_eliminar_perro(BIGINT);

CREATE OR REPLACE FUNCTION public.fn_eliminar_perro(p_perro_id BIGINT)
RETURNS JSON AS $$
BEGIN
    UPDATE public.perro SET deleted_at = now() WHERE id = p_perro_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RETURN json_build_object('ok', false, 'error', 'Mascota no encontrada');
    END IF;
    RETURN json_build_object('ok', true);
END;
$$ LANGUAGE plpgsql;

