-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V44: fn_completar_onboarding (V7) nunca escribía casa.propietario_id, columna
-- que es NOT NULL desde la V1. El INSERT reventaba con
-- "null value in column propietario_id violates not-null constraint" cada vez
-- que alguien sin vivienda —un miembro dado de baja, o una cuenta nueva por
-- Google/Facebook— intentaba crear la suya desde el onboarding.
--
-- Esta migración solo pone en un archivo versionado el arreglo que ya está
-- aplicado a mano en la base de Neon (de ahí que el bug no se notara en las
-- pruebas recientes): sin este archivo, una base nueva —la que se levante
-- para DigitalOcean o para que el compañero pruebe en la suya— partiría de
-- V7 sin corregir y el fallo volvería a aparecer.

CREATE OR REPLACE FUNCTION fn_completar_onboarding(
    p_usuario_id BIGINT,
    p_nombre VARCHAR,
    p_casa_nombre VARCHAR,
    p_direccion VARCHAR,
    p_ciudad VARCHAR,
    p_latitud DECIMAL,
    p_longitud DECIMAL
) RETURNS JSON AS $$
DECLARE
    v_casa_id BIGINT;
    v_zona_id BIGINT;
    v_usuario usuario;
BEGIN
    -- Validar que no tenga casa ya
    SELECT * INTO v_usuario FROM usuario WHERE id = p_usuario_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'USUARIO_NO_ENCONTRADO'; END IF;
    IF v_usuario.casa_id IS NOT NULL THEN RAISE EXCEPTION 'USUARIO_YA_TIENE_CASA'; END IF;

    -- Actualizar el usuario a PROPIETARIO
    UPDATE usuario SET nombre = COALESCE(p_nombre, nombre), rol = 'PROPIETARIO' WHERE id = p_usuario_id;

    -- Corregido: incluye propietario_id, columna NOT NULL en casa desde la V1.
    INSERT INTO casa (propietario_id, nombre, direccion, ciudad, latitud, longitud)
    VALUES (p_usuario_id, p_casa_nombre, p_direccion, p_ciudad, p_latitud, p_longitud)
    RETURNING id INTO v_casa_id;

    INSERT INTO zona (casa_id, nombre) VALUES (v_casa_id, 'Zona Principal') RETURNING id INTO v_zona_id;

    -- Vincular la nueva casa al usuario
    UPDATE usuario SET casa_id = v_casa_id WHERE id = p_usuario_id RETURNING * INTO v_usuario;

    RETURN (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON;
END;
$$ LANGUAGE plpgsql;
