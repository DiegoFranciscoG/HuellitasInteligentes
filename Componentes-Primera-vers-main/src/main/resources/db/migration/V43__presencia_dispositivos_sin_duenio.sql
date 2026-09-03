-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V43: registra los aparatos que dan señal de vida aunque todavía no tengan dueño.
--
-- Hasta ahora el latido hacía un UPDATE sobre dispositivo, así que una MAC que
-- no estuviera dada de alta simplemente se perdía. El efecto era que un ESP32
-- recién estrenado no aparecía en ninguna pantalla: no había dónde anotar
-- "vi este aparato, todavía no es de nadie", y por lo tanto no había forma de
-- reclamarlo desde la aplicación.
--
-- Esta tabla es el registro de presencia en crudo, independiente de quién sea
-- el dueño. Vive aparte de dispositivo a propósito: dispositivo modela lo que
-- una casa ya adoptó, y esta tabla modela lo que la red está viendo ahora.

CREATE TABLE IF NOT EXISTS dispositivo_presencia (
  mac_address   VARCHAR(17)  PRIMARY KEY,
  modelo        VARCHAR(50),
  ip_local      VARCHAR(45),
  ultimo_latido TIMESTAMPTZ  NOT NULL DEFAULT now(),
  visto_desde   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

COMMENT ON TABLE dispositivo_presencia IS
  'Latidos en crudo del firmware, con dueño o sin él. Alimenta "Buscar en mi red": lo que está aquí y no está en dispositivo es un aparato libre para reclamar.';
COMMENT ON COLUMN dispositivo_presencia.ip_local IS
  'Dirección que el propio aparato reporta. La ESP32-CAM la usa para que el backend sepa a dónde pedirle la foto mientras ambos estén en la misma red.';
COMMENT ON COLUMN dispositivo_presencia.visto_desde IS
  'Primera vez que se vio esta MAC. No se toca en los latidos siguientes.';

CREATE INDEX IF NOT EXISTS idx_presencia_ultimo_latido
  ON dispositivo_presencia (ultimo_latido DESC);

-- ---------------------------------------------------------------------------
-- Dónde guardamos la ruta de captura de una cámara IoT.
--
-- La cámara-celular vinculada por QR no tiene ninguna de estas dos columnas
-- puestas, y debe seguir funcionando exactamente igual: por eso ambas aceptan
-- NULL y nada las exige.
-- ---------------------------------------------------------------------------

ALTER TABLE camara ADD COLUMN IF NOT EXISTS url_captura VARCHAR(255);
ALTER TABLE camara ADD COLUMN IF NOT EXISTS ultima_captura TIMESTAMPTZ;

COMMENT ON COLUMN camara.url_captura IS
  'Ruta absoluta de la que el backend obtiene un JPEG suelto (por ejemplo http://192.168.1.50/capture). NULL en las cámaras que empujan la imagen o en las de celular por WebRTC.';
COMMENT ON COLUMN camara.ultima_captura IS
  'Marca de la última imagen obtenida, para no analizar dos veces el mismo evento.';
