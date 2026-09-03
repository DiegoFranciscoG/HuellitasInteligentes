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

    -- Actualizar nombre si venía nulo o distinto
    UPDATE usuario SET nombre = COALESCE(p_nombre, nombre), rol = 'PROPIETARIO' WHERE id = p_usuario_id;

    -- Crear casa y zona
    INSERT INTO casa (nombre, direccion, ciudad, latitud, longitud) 
    VALUES (p_casa_nombre, p_direccion, p_ciudad, p_latitud, p_longitud) 
    RETURNING id INTO v_casa_id;
    
    INSERT INTO zona (casa_id, nombre) 
    VALUES (v_casa_id, 'Zona Principal') 
    RETURNING id INTO v_zona_id;

    -- Asociar usuario a la casa
    UPDATE usuario SET casa_id = v_casa_id WHERE id = p_usuario_id RETURNING * INTO v_usuario;

    RETURN (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON;
END;
$$ LANGUAGE plpgsql;
