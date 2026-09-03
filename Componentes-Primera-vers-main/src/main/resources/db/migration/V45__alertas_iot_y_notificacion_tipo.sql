-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V45: dos cosas.
--
-- 1) notificacion.tipo ya existe en la base de Neon —el código lo usa desde
--    hace tiempo (INSERT INTO notificacion (..., tipo, ...) en AdminController)—
--    pero ninguna migración la creó nunca: alguien la agregó a mano en algún
--    momento. Se captura aquí para que una base nueva (la del compañero, o la
--    de DigitalOcean) no reviente con "column tipo does not exist" la primera
--    vez que se resuelva una denuncia o se mande un aviso masivo.
--
-- 2) alerta.dispositivo_id: hasta ahora una alerta solo podía referirse a una
--    mascota (perro_id). Para poder avisarle al dueño de un aparato IoT que
--    dejó de dar señal, la alerta necesita poder apuntar también a un
--    dispositivo. Queda NULL en las alertas de mascota existentes, que no se
--    tocan.

ALTER TABLE notificacion ADD COLUMN IF NOT EXISTS tipo VARCHAR(50);

ALTER TABLE alerta ADD COLUMN IF NOT EXISTS dispositivo_id BIGINT REFERENCES dispositivo(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_alerta_dispositivo ON alerta (dispositivo_id) WHERE dispositivo_id IS NOT NULL;
