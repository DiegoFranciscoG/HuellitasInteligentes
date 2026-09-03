-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V42: enlaza una cámara con el dispositivo IoT que la representa.
--
-- Hasta ahora camara y dispositivo eran dos tablas que no se conocían, así
-- que no había forma de saber si un aparato descubierto en la red ya estaba
-- vinculado como cámara.
--
-- La columna acepta NULL a propósito: la cámara-celular que ya funciona hoy
-- no tiene fila en dispositivo y debe seguir andando igual. Solo las cámaras
-- dadas de alta desde "Buscar en mi red" quedan enlazadas.

ALTER TABLE camara ADD COLUMN IF NOT EXISTS dispositivo_id BIGINT REFERENCES dispositivo(id) ON DELETE SET NULL;
COMMENT ON COLUMN camara.dispositivo_id IS 'Dispositivo IoT que respalda esta cámara. NULL cuando la cámara es un celular vinculado por QR.';

-- Un dispositivo no puede estar vinculado a dos cámaras activas a la vez.
CREATE UNIQUE INDEX IF NOT EXISTS uq_camara_dispositivo_activo
  ON camara (dispositivo_id)
  WHERE dispositivo_id IS NOT NULL AND activo = true;
