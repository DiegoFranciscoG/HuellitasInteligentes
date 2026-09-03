-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V41: dar de baja a un miembro debe soltarlo de la casa, no matar su cuenta.
--
-- Comportamiento anterior de eliminarMiembro:
--     UPDATE usuario SET deleted_at = NOW(), activo = false WHERE ...
-- Eso dejaba la cuenta inutilizable: fn_login corta con CUENTA_BLOQUEADA en
-- cuanto ve activo=false o deleted_at. Y como casa_id seguía apuntando a la
-- vivienda anterior, la persona quedaba atada a una casa a la que ya no
-- pertenece.
--
-- Comportamiento nuevo: el miembro se desvincula (casa_id = NULL) y pasa a
-- PROPIETARIO sin casa, que es el estado "en espera" que ya maneja el
-- onboarding. Puede iniciar sesión y crear su propia vivienda, pero no ve
-- nada del hogar del que salió, porque todo el aislamiento se resuelve por
-- casa_id.
--
-- Para no perder la auditoría, se guarda de dónde salió en casa_anterior_id
-- y fn_historial_casa pasa a incluir también a los ex miembros. Así el
-- propietario conserva el registro de lo que esa persona hizo mientras
-- formaba parte del hogar, aunque ya no tenga acceso.

ALTER TABLE usuario ADD COLUMN IF NOT EXISTS casa_anterior_id BIGINT REFERENCES casa(id) ON DELETE SET NULL;
COMMENT ON COLUMN usuario.casa_anterior_id IS 'Casa de la que fue dado de baja como miembro. Solo para conservar su rastro en el historial del hogar; no otorga ningún acceso.';

CREATE INDEX IF NOT EXISTS idx_usuario_casa_anterior ON usuario (casa_anterior_id) WHERE casa_anterior_id IS NOT NULL;

-- Los miembros que ya fueron dados de baja con el método viejo conservan su
-- casa_id, así que ya aparecen en el historial. Se les copia el dato para
-- que el criterio sea uniforme de aquí en adelante.
UPDATE usuario
SET casa_anterior_id = casa_id
WHERE rol = 'MIEMBRO' AND casa_id IS NOT NULL AND deleted_at IS NOT NULL AND casa_anterior_id IS NULL;

-- El historial del hogar incluye a los miembros actuales y a los que salieron.
CREATE OR REPLACE FUNCTION fn_historial_casa(p_casa_id BIGINT)
RETURNS JSON AS $$
DECLARE v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t) ORDER BY t.created_at DESC) INTO v_result
  FROM (
    SELECT al.id,
           al.usuario_id,
           u.nombre AS autor_nombre,
           (u.casa_id IS DISTINCT FROM p_casa_id) AS autor_ex_miembro,
           al.accion, al.entidad, al.entidad_id, al.detalle, al.created_at
    FROM auditoria_log al
    JOIN usuario u ON u.id = al.usuario_id
    WHERE u.casa_id = p_casa_id OR u.casa_anterior_id = p_casa_id
    ORDER BY al.created_at DESC LIMIT 100
  ) t;
  RETURN COALESCE(v_result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql;
