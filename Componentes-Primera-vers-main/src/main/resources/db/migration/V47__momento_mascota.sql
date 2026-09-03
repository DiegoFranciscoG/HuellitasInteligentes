-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V47: "Momentos de tu mascota" — detección automática de actividad frente a
-- una cámara IoT (ESP32-CAM vía /capture, nunca el celular por WebRTC, que es
-- P2P y el servidor no lo toca), con un fragmento que expira solo a los 3
-- minutos salvo que el dueño lo guarde.
--
-- Las columnas camara.url_captura/ultima_captura ya existían desde V43
-- (pensadas exactamente para esto) pero nadie las usaba todavía: este cambio
-- es el primero que las escribe de verdad.

CREATE TYPE actividad_mascota AS ENUM ('COMIENDO', 'BEBIENDO', 'DURMIENDO', 'JUGANDO', 'NINGUNA_CLARA');

CREATE TABLE momento_mascota (
  id               BIGSERIAL PRIMARY KEY,
  casa_id          BIGINT NOT NULL REFERENCES casa(id) ON DELETE CASCADE,
  camara_id        BIGINT NOT NULL REFERENCES camara(id) ON DELETE CASCADE,
  perro_id         BIGINT REFERENCES perro(id) ON DELETE SET NULL,
  actividad        actividad_mascota NOT NULL,
  confianza        NUMERIC(3,2) NOT NULL,
  claves_fragmento JSONB NOT NULL,
  capturado_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expira_at        TIMESTAMPTZ NOT NULL,
  guardado         BOOLEAN NOT NULL DEFAULT false
);

COMMENT ON TABLE momento_mascota IS
  'Un instante detectado por una cámara IoT (comiendo/bebiendo/etc). claves_fragmento guarda las claves del bucket B2, no URLs firmadas (esas se generan al vuelo y caducan solas); si nadie confirma "guardar" dentro de expira_at, el job de limpieza borra los objetos del bucket y la fila.';
COMMENT ON COLUMN momento_mascota.claves_fragmento IS
  'Array JSON de claves del bucket general (S3Service), 1 a 5 imágenes según la actividad.';
COMMENT ON COLUMN momento_mascota.perro_id IS
  'NULL cuando la cámara no tiene una mascota asignada todavía (camara.perro_id) — se sigue avisando igual, solo que sin poder decir cuál mascota es.';

CREATE INDEX idx_momento_casa ON momento_mascota (casa_id, capturado_at DESC);
CREATE INDEX idx_momento_limpieza ON momento_mascota (expira_at) WHERE guardado = false;
