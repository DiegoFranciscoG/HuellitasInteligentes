-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V30: estadísticas reales para la barra de la landing pública (antes eran
-- números fijos en el HTML — "500+ Hogares Conectados", etc. — sin relación
-- con los datos reales del sistema).

CREATE OR REPLACE FUNCTION fn_estadisticas_publicas() RETURNS JSON AS $$
  SELECT json_build_object(
    'hogares', (SELECT COUNT(*) FROM casa),
    'dispositivos', (SELECT COUNT(*) FROM dispositivo WHERE deleted_at IS NULL),
    'mascotas', (SELECT COUNT(*) FROM perro WHERE deleted_at IS NULL),
    -- % de dispositivos activos que reportaron en las últimas 24h. Sin
    -- dispositivos registrados no hay nada "caído", así que se reporta 100.
    'actividad_pct', (
      SELECT CASE WHEN COUNT(*) = 0 THEN 100
             ELSE ROUND(100.0 * COUNT(*) FILTER (WHERE ultima_conexion > NOW() - INTERVAL '24 hours') / COUNT(*))
        END
      FROM dispositivo WHERE deleted_at IS NULL
    )
  );
$$ LANGUAGE sql STABLE;
