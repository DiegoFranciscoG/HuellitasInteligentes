-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V32: los grupos ya tenían fn_eliminar_grupo y fn_transferir_admin_grupo
-- (el admin puede eliminar el grupo o pasarle la administración a otro
-- miembro), pero no había forma de expulsar a un miembro puntual ni de
-- listar quiénes son los miembros para elegir a quién expulsar o a quién
-- transferir la administración. Estas dos funciones cierran ese hueco,
-- reusando exactamente la misma verificación de permisos que ya usan
-- fn_eliminar_grupo/fn_transferir_admin_grupo (creador del grupo, rol ADMIN
-- dentro del grupo, o administrador de la plataforma).

CREATE OR REPLACE FUNCTION fn_miembros_grupo(p_grupo_id BIGINT) RETURNS JSON AS $$
BEGIN
    RETURN (
        SELECT COALESCE(json_agg(m ORDER BY m.rol_en_grupo DESC, m.joined_at ASC), '[]'::json) FROM (
            SELECT
                u.id,
                u.nombre,
                u.email,
                u.foto_url,
                gm.rol_en_grupo,
                gm.joined_at
            FROM grupo_miembro gm
            JOIN usuario u ON u.id = gm.usuario_id
            WHERE gm.grupo_id = p_grupo_id
        ) m
    );
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_expulsar_miembro_grupo(p_grupo_id BIGINT, p_admin_id BIGINT, p_usuario_id BIGINT) RETURNS JSON AS $$
DECLARE v_creado_por BIGINT; v_rol_grupo VARCHAR;
BEGIN
    SELECT creado_por INTO v_creado_por FROM grupo WHERE id = p_grupo_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'GRUPO_NO_ENCONTRADO' USING ERRCODE = 'P0004';
    END IF;

    IF p_usuario_id = v_creado_por THEN
        RAISE EXCEPTION 'NO_SE_PUEDE_EXPULSAR_AL_CREADOR' USING ERRCODE = 'P0002';
    END IF;

    SELECT rol_en_grupo INTO v_rol_grupo FROM grupo_miembro WHERE grupo_id = p_grupo_id AND usuario_id = p_admin_id;

    IF v_creado_por != p_admin_id AND COALESCE(v_rol_grupo, '') != 'ADMIN' AND NOT EXISTS (
        SELECT 1 FROM usuario WHERE id = p_admin_id AND rol = 'ADMINISTRADOR'
    ) THEN
        RAISE EXCEPTION 'NO_AUTORIZADO' USING ERRCODE = 'P0001';
    END IF;

    DELETE FROM grupo_miembro WHERE grupo_id = p_grupo_id AND usuario_id = p_usuario_id;

    RETURN json_build_object('ok', true);
END; $$ LANGUAGE plpgsql;
