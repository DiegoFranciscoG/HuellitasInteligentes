-- ============================================================
-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V3__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- HUELLITAS INTELIGENTES — PostgreSQL 16, Production Ready
-- Neon / Flyway / Spring Boot 3.3 / Hibernate 6 / Railway / Docker compatible
-- Idempotente: reset completo seguro para re-ejecutar.
-- Sin lógica de negocio (motor de reglas vive en Spring Boot).
-- ============================================================

-- ================= RESET =================
DROP TABLE IF EXISTS reporte, auditoria_log, configuracion_general, configuracion_cloud,
  recomendacion_ia, mensaje, comentario, publicacion, notificacion, alerta,
  actuador_comando, regla_automatizacion, sensor_lectura, dispositivo, perro, zona,
  suscripcion, casa, refresh_token, usuario_proveedor, usuario, plan CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_estadisticas_diarias;

DO $$ BEGIN DROP TYPE IF EXISTS rol_usuario; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS proveedor_auth; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS suscripcion_estado; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS tipo_dispositivo; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS categoria_dispositivo; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS estado_dispositivo; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS operador_comparacion; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS accion_tipo; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS comando_actuador; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS origen_comando; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS severidad_alerta; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS canal_notificacion; EXCEPTION WHEN OTHERS THEN NULL; END $$;
DO $$ BEGIN DROP TYPE IF EXISTS estado_notificacion; EXCEPTION WHEN OTHERS THEN NULL; END $$;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ================= ENUMS =================
CREATE TYPE rol_usuario AS ENUM ('ADMINISTRADOR','PROPIETARIO','MIEMBRO');
CREATE TYPE proveedor_auth AS ENUM ('LOCAL','GOOGLE','FACEBOOK');
CREATE TYPE suscripcion_estado AS ENUM ('ACTIVA','CANCELADA','VENCIDA');
CREATE TYPE tipo_dispositivo AS ENUM ('SENSOR','ACTUADOR');
CREATE TYPE categoria_dispositivo AS ENUM (
  'DHT11','MQ135','ULTRASONICO_ALIMENTO','NIVEL_AGUA',
  'VENTILADOR','SERVO_VENTANA','MOTOR_ALIMENTADOR','BOMBA_AGUA');
CREATE TYPE estado_dispositivo AS ENUM ('ACTIVO','INACTIVO','ERROR');
CREATE TYPE operador_comparacion AS ENUM ('>','<','>=','<=','=');
CREATE TYPE accion_tipo AS ENUM ('ALERTA','ACTUADOR');
CREATE TYPE comando_actuador AS ENUM ('ACTIVAR','DESACTIVAR');
CREATE TYPE origen_comando AS ENUM ('MANUAL','REGLA','APP');
CREATE TYPE severidad_alerta AS ENUM ('INFO','ADVERTENCIA','CRITICA');
CREATE TYPE canal_notificacion AS ENUM ('PUSH','EMAIL','WEBSOCKET');
CREATE TYPE estado_notificacion AS ENUM ('PENDIENTE','ENVIADA','FALLIDA');

-- ================= TRIGGER GENÉRICO (housekeeping, no negocio) =================
CREATE OR REPLACE FUNCTION fn_set_updated_at() RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;

-- ================= USUARIO =================
CREATE TABLE usuario (
  id BIGSERIAL PRIMARY KEY,
  email VARCHAR(150) NOT NULL,
  password_hash TEXT, -- NULL permitido: usuarios 100% OAuth no tienen password local
  nombre VARCHAR(100) NOT NULL,
  rol rol_usuario NOT NULL,
  casa_id BIGINT, -- FK agregada tras crear casa (dependencia circular)
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  CONSTRAINT uq_usuario_email UNIQUE (email)
);
COMMENT ON TABLE usuario IS 'Identidad única de cada persona. 1 fila = 1 persona, sin importar cuántos proveedores de login use (ver usuario_proveedor).';
CREATE INDEX idx_usuario_activo ON usuario (id) WHERE deleted_at IS NULL;
CREATE TRIGGER trg_usuario_updated BEFORE UPDATE ON usuario
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ================= USUARIO_PROVEEDOR (multi-auth sin duplicados) =================
CREATE TABLE usuario_proveedor (
  id BIGSERIAL PRIMARY KEY,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  proveedor proveedor_auth NOT NULL,
  proveedor_uid VARCHAR(255) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_proveedor_uid UNIQUE (proveedor, proveedor_uid)
);
COMMENT ON TABLE usuario_proveedor IS 'Vincula 1 usuario a N proveedores de login (LOCAL/GOOGLE/FACEBOOK). Evita usuarios duplicados por login social.';
CREATE INDEX idx_usuario_proveedor_usuario ON usuario_proveedor (usuario_id);

-- ================= REFRESH_TOKEN =================
CREATE TABLE refresh_token (
  id BIGSERIAL PRIMARY KEY,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL,
  expira_at TIMESTAMPTZ NOT NULL,
  revocado BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_refresh_token_hash UNIQUE (token_hash)
);
COMMENT ON TABLE refresh_token IS 'Refresh tokens persistidos para permitir revocación de sesiones JWT.';
CREATE INDEX idx_refresh_usuario ON refresh_token (usuario_id) WHERE revocado = false;

-- ================= PLAN (catálogo, administra ADMINISTRADOR) =================
CREATE TABLE plan (
  id BIGSERIAL PRIMARY KEY,
  nombre VARCHAR(30) NOT NULL CHECK (nombre IN ('FREE','BASICO','PREMIUM')),
  precio_mensual NUMERIC(8,2) NOT NULL DEFAULT 0,
  limite_dispositivos INT NOT NULL DEFAULT 5,
  limite_almacenamiento_mb INT NOT NULL DEFAULT 500,
  descripcion VARCHAR(200),
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_plan_nombre UNIQUE (nombre)
);
COMMENT ON TABLE plan IS 'Catálogo de planes SaaS gestionado por el ADMINISTRADOR. Evita repetir precios/límites como texto plano en suscripcion.';
CREATE TRIGGER trg_plan_updated BEFORE UPDATE ON plan
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ================= CASA (1 propietario = 1 casa) =================
CREATE TABLE casa (
  id BIGSERIAL PRIMARY KEY,
  propietario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  nombre VARCHAR(100) NOT NULL,
  direccion VARCHAR(200),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  CONSTRAINT uq_casa_propietario UNIQUE (propietario_id)
);
COMMENT ON TABLE casa IS 'Una casa por propietario. Alcance del MVP: sin multi-house (regla del docente).';
CREATE TRIGGER trg_casa_updated BEFORE UPDATE ON casa
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

ALTER TABLE usuario ADD CONSTRAINT fk_usuario_casa FOREIGN KEY (casa_id) REFERENCES casa(id) ON DELETE SET NULL;
-- Máximo 1 MIEMBRO por casa (regla del docente, forzada por la DB)
CREATE UNIQUE INDEX idx_un_miembro_por_casa ON usuario (casa_id) WHERE rol = 'MIEMBRO' AND deleted_at IS NULL;

-- ================= SUSCRIPCION =================
CREATE TABLE suscripcion (
  id BIGSERIAL PRIMARY KEY,
  casa_id BIGINT NOT NULL REFERENCES casa(id) ON DELETE CASCADE,
  plan_id BIGINT NOT NULL REFERENCES plan(id),
  estado suscripcion_estado NOT NULL DEFAULT 'ACTIVA',
  fecha_inicio DATE NOT NULL DEFAULT CURRENT_DATE,
  fecha_fin DATE,
  metodo_pago VARCHAR(30),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_suscripcion_casa UNIQUE (casa_id)
);
COMMENT ON TABLE suscripcion IS 'Plan SaaS activo de la casa (modelo Freemium).';
CREATE TRIGGER trg_suscripcion_updated BEFORE UPDATE ON suscripcion
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ================= ZONA (2 por casa: Sala 1 Descanso/Confort, Sala 2 Alimentación — hardware real) =================
CREATE TABLE zona (
  id BIGSERIAL PRIMARY KEY,
  casa_id BIGINT NOT NULL REFERENCES casa(id) ON DELETE CASCADE,
  nombre VARCHAR(100) NOT NULL,
  descripcion VARCHAR(200),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_zona_casa_nombre UNIQUE (casa_id, nombre)
);
COMMENT ON TABLE zona IS '2 zonas fijas por casa (Sala 1 y Sala 2), reflejando el hardware ESP32 ya implementado.';

-- ================= PERRO (antes "mascota" — enfoque exclusivo canino) =================
CREATE TABLE perro (
  id BIGSERIAL PRIMARY KEY,
  casa_id BIGINT NOT NULL REFERENCES casa(id) ON DELETE CASCADE,
  nombre VARCHAR(100) NOT NULL,
  raza VARCHAR(80),
  fecha_nacimiento DATE,
  peso NUMERIC(5,2),
  foto_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
COMMENT ON TABLE perro IS 'Mascota exclusiva del sistema: perro. Sin campo especie — fuera de alcance por indicación del docente.';
CREATE INDEX idx_perro_casa ON perro (casa_id) WHERE deleted_at IS NULL;
CREATE TRIGGER trg_perro_updated BEFORE UPDATE ON perro
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ================= DISPOSITIVO (sensor + actuador unificados, sin tabla redundante) =================
CREATE TABLE dispositivo (
  id BIGSERIAL PRIMARY KEY,
  zona_id BIGINT NOT NULL REFERENCES zona(id) ON DELETE CASCADE,
  mac_address VARCHAR(17) NOT NULL,
  tipo tipo_dispositivo NOT NULL,
  categoria categoria_dispositivo NOT NULL,
  modelo VARCHAR(50),
  estado estado_dispositivo NOT NULL DEFAULT 'ACTIVO',
  ultima_conexion TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  CONSTRAINT uq_dispositivo_mac UNIQUE (mac_address),
  CONSTRAINT chk_tipo_categoria CHECK (
    (tipo = 'SENSOR' AND categoria IN ('DHT11','MQ135','ULTRASONICO_ALIMENTO','NIVEL_AGUA'))
    OR
    (tipo = 'ACTUADOR' AND categoria IN ('VENTILADOR','SERVO_VENTANA','MOTOR_ALIMENTADOR','BOMBA_AGUA'))
  )
);
COMMENT ON TABLE dispositivo IS 'Sensores y actuadores de la zona del perro. tipo+categoria evitan una tabla "sensor" separada (redundante, misma cardinalidad 1:N con zona).';
CREATE INDEX idx_dispositivo_zona ON dispositivo (zona_id) WHERE deleted_at IS NULL;
CREATE TRIGGER trg_dispositivo_updated BEFORE UPDATE ON dispositivo
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ================= SENSOR_LECTURA (particionada, sin columna redundante) =================
CREATE TABLE sensor_lectura (
  id BIGSERIAL,
  dispositivo_id BIGINT NOT NULL REFERENCES dispositivo(id) ON DELETE CASCADE,
  valor NUMERIC(10,2) NOT NULL,
  unidad VARCHAR(10),
  ts TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (id, ts)
) PARTITION BY RANGE (ts);
COMMENT ON TABLE sensor_lectura IS 'Telemetría IoT. Sin tipo_metrica: ya está en dispositivo.categoria (elimina redundancia).';

CREATE TABLE sensor_lectura_2026_07 PARTITION OF sensor_lectura FOR VALUES FROM ('2026-07-01') TO ('2026-08-01');
CREATE TABLE sensor_lectura_2026_08 PARTITION OF sensor_lectura FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE sensor_lectura_2026_09 PARTITION OF sensor_lectura FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE sensor_lectura_default PARTITION OF sensor_lectura DEFAULT;

CREATE INDEX idx_lectura_brin ON sensor_lectura USING BRIN (ts);
CREATE INDEX idx_lectura_disp_ts ON sensor_lectura (dispositivo_id, ts DESC);

-- ================= REGLA_AUTOMATIZACION (columnas planas, sin JSONB) =================
CREATE TABLE regla_automatizacion (
  id BIGSERIAL PRIMARY KEY,
  casa_id BIGINT NOT NULL REFERENCES casa(id) ON DELETE CASCADE,
  nombre VARCHAR(100) NOT NULL,
  dispositivo_sensor_id BIGINT NOT NULL REFERENCES dispositivo(id) ON DELETE CASCADE,
  operador operador_comparacion NOT NULL,
  valor_umbral NUMERIC(10,2) NOT NULL,
  dispositivo_actuador_id BIGINT REFERENCES dispositivo(id) ON DELETE SET NULL,
  accion_tipo accion_tipo NOT NULL,
  mensaje_alerta VARCHAR(200),
  activo BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT chk_regla_actuador CHECK (accion_tipo <> 'ACTUADOR' OR dispositivo_actuador_id IS NOT NULL)
);
COMMENT ON TABLE regla_automatizacion IS 'Condición→acción evaluada por Spring Boot (RuleEngineService). La DB solo almacena y valida integridad, no ejecuta la lógica.';
CREATE INDEX idx_regla_casa_activa ON regla_automatizacion (casa_id) WHERE activo = true;
CREATE TRIGGER trg_regla_updated BEFORE UPDATE ON regla_automatizacion
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ================= ACTUADOR_COMANDO (log de accionamientos) =================
CREATE TABLE actuador_comando (
  id BIGSERIAL PRIMARY KEY,
  dispositivo_id BIGINT NOT NULL REFERENCES dispositivo(id) ON DELETE CASCADE,
  comando comando_actuador NOT NULL,
  origen origen_comando NOT NULL,
  ejecutado_por BIGINT REFERENCES usuario(id) ON DELETE SET NULL,
  ts TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE actuador_comando IS 'Trazabilidad de cada activación/desactivación de actuador (manual, por regla o desde la app).';
CREATE INDEX idx_comando_dispositivo ON actuador_comando (dispositivo_id, ts DESC);

-- ================= ALERTA / NOTIFICACION =================
CREATE TABLE alerta (
  id BIGSERIAL PRIMARY KEY,
  casa_id BIGINT NOT NULL REFERENCES casa(id) ON DELETE CASCADE,
  perro_id BIGINT REFERENCES perro(id) ON DELETE SET NULL,
  tipo VARCHAR(50) NOT NULL,
  mensaje TEXT NOT NULL,
  severidad severidad_alerta NOT NULL DEFAULT 'INFO',
  leida BOOLEAN NOT NULL DEFAULT false,
  ts TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE alerta IS 'Avisos generados por reglas de automatización o eventos del sistema.';
CREATE INDEX idx_alerta_casa_leida ON alerta (casa_id, leida);

CREATE TABLE notificacion (
  id BIGSERIAL PRIMARY KEY,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  canal canal_notificacion NOT NULL,
  contenido TEXT NOT NULL,
  estado estado_notificacion NOT NULL DEFAULT 'PENDIENTE',
  enviado_at TIMESTAMPTZ
);
COMMENT ON TABLE notificacion IS 'Entrega de alertas por canal (push/email/websocket).';
CREATE INDEX idx_notificacion_pendiente ON notificacion (usuario_id) WHERE estado = 'PENDIENTE';

-- ================= RED SOCIAL =================
CREATE TABLE publicacion (
  id BIGSERIAL PRIMARY KEY,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  contenido TEXT NOT NULL,
  imagen_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE publicacion IS 'Publicaciones de la red social interna.';
CREATE INDEX idx_publicacion_fecha ON publicacion (created_at DESC);

CREATE TABLE comentario (
  id BIGSERIAL PRIMARY KEY,
  publicacion_id BIGINT NOT NULL REFERENCES publicacion(id) ON DELETE CASCADE,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  contenido TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE comentario IS 'Comentarios sobre publicaciones.';
CREATE INDEX idx_comentario_publicacion ON comentario (publicacion_id);

CREATE TABLE mensaje (
  id BIGSERIAL PRIMARY KEY,
  emisor_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  receptor_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  contenido TEXT NOT NULL,
  leido BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE mensaje IS 'Mensajería directa propietario↔miembro.';
CREATE INDEX idx_mensaje_conversacion ON mensaje (emisor_id, receptor_id, created_at);

-- ================= IA =================
CREATE TABLE recomendacion_ia (
  id BIGSERIAL PRIMARY KEY,
  perro_id BIGINT NOT NULL REFERENCES perro(id) ON DELETE CASCADE,
  tipo VARCHAR(50) NOT NULL,
  contenido TEXT NOT NULL,
  confianza NUMERIC(4,3),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE recomendacion_ia IS 'Sugerencias generadas para el perro (heurísticas en Spring Boot).';
CREATE INDEX idx_recomendacion_perro ON recomendacion_ia (perro_id, created_at DESC);

-- ================= CONFIGURACION (cloud por casa, general por plataforma) =================
CREATE TABLE configuracion_cloud (
  id BIGSERIAL PRIMARY KEY,
  casa_id BIGINT NOT NULL REFERENCES casa(id) ON DELETE CASCADE,
  storage_proveedor VARCHAR(30) NOT NULL DEFAULT 'CLOUDFLARE_R2',
  mqtt_broker VARCHAR(100),
  limite_almacenamiento_mb INT NOT NULL DEFAULT 500,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_config_cloud_casa UNIQUE (casa_id)
);
COMMENT ON TABLE configuracion_cloud IS 'Config de almacenamiento/MQTT por casa — módulo cloud pedido por el docente.';
CREATE TRIGGER trg_config_cloud_updated BEFORE UPDATE ON configuracion_cloud
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TABLE configuracion_general (
  id BIGSERIAL PRIMARY KEY,
  clave VARCHAR(80) NOT NULL,
  valor TEXT NOT NULL,
  descripcion VARCHAR(200),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT uq_config_general_clave UNIQUE (clave)
);
COMMENT ON TABLE configuracion_general IS 'Parámetros globales de la plataforma (clave-valor), gestionados por ADMINISTRADOR. Evita crear una columna nueva por cada parámetro futuro.';
CREATE TRIGGER trg_config_general_updated BEFORE UPDATE ON configuracion_general
  FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

-- ================= AUDITORIA =================
CREATE TABLE auditoria_log (
  id BIGSERIAL PRIMARY KEY,
  usuario_id BIGINT REFERENCES usuario(id) ON DELETE SET NULL,
  accion VARCHAR(50) NOT NULL,
  entidad VARCHAR(50) NOT NULL,
  entidad_id BIGINT,
  detalle JSONB,
  ip VARCHAR(45),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE auditoria_log IS 'Trazabilidad de acciones sensibles (login, cambios de rol, borrados). Solo almacenamiento, sin lógica de evaluación en DB.';
CREATE INDEX idx_auditoria_usuario ON auditoria_log (usuario_id, created_at DESC);
CREATE INDEX idx_auditoria_entidad ON auditoria_log (entidad, entidad_id);

-- ================= REPORTE =================
CREATE TABLE reporte (
  id BIGSERIAL PRIMARY KEY,
  casa_id BIGINT NOT NULL REFERENCES casa(id) ON DELETE CASCADE,
  tipo VARCHAR(50) NOT NULL,
  periodo_inicio DATE NOT NULL,
  periodo_fin DATE NOT NULL,
  url_pdf TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE reporte IS 'Reportes históricos exportados en PDF.';
CREATE INDEX idx_reporte_casa ON reporte (casa_id, created_at DESC);

-- ================= TRIGGER: ultima_conexion (housekeeping, no negocio) =================
CREATE OR REPLACE FUNCTION fn_actualizar_conexion() RETURNS TRIGGER AS $$
BEGIN
  UPDATE dispositivo SET ultima_conexion = NEW.ts WHERE id = NEW.dispositivo_id;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_conexion AFTER INSERT ON sensor_lectura
  FOR EACH ROW EXECUTE FUNCTION fn_actualizar_conexion();

-- ================= VISTAS =================
CREATE OR REPLACE VIEW vista_ultimo_estado_dispositivo AS
SELECT DISTINCT ON (dispositivo_id) dispositivo_id, valor, unidad, ts
FROM sensor_lectura
ORDER BY dispositivo_id, ts DESC;
COMMENT ON VIEW vista_ultimo_estado_dispositivo IS 'Última lectura por dispositivo — evita agregación repetida en Java/Angular.';

CREATE OR REPLACE VIEW vista_dashboard_casa AS
SELECT c.id AS casa_id, c.nombre AS casa_nombre,
  (SELECT COUNT(*) FROM perro p WHERE p.casa_id = c.id AND p.deleted_at IS NULL) AS total_perros,
  (SELECT COUNT(*) FROM alerta a WHERE a.casa_id = c.id AND a.leida = false) AS alertas_pendientes,
  (SELECT COUNT(*) FROM dispositivo d JOIN zona z ON z.id = d.zona_id
     WHERE z.casa_id = c.id AND d.estado = 'ACTIVO' AND d.deleted_at IS NULL) AS dispositivos_activos
FROM casa c WHERE c.deleted_at IS NULL;
COMMENT ON VIEW vista_dashboard_casa IS '1 llamada = 1 pantalla dashboard propietario/miembro.';

CREATE OR REPLACE VIEW vista_admin_resumen AS
SELECT
  (SELECT COUNT(*) FROM casa WHERE deleted_at IS NULL) AS total_casas,
  (SELECT COUNT(*) FROM usuario WHERE activo = true AND deleted_at IS NULL) AS total_usuarios_activos,
  (SELECT COUNT(*) FROM suscripcion WHERE estado = 'ACTIVA') AS suscripciones_activas,
  (SELECT COUNT(*) FROM dispositivo WHERE deleted_at IS NULL) AS total_dispositivos;
COMMENT ON VIEW vista_admin_resumen IS 'Estadísticas globales para el dashboard del ADMINISTRADOR.';

-- ================= MATERIALIZED VIEW =================
CREATE MATERIALIZED VIEW mv_estadisticas_diarias AS
SELECT dispositivo_id, date_trunc('day', ts) AS dia,
       avg(valor) AS promedio, min(valor) AS minimo, max(valor) AS maximo
FROM sensor_lectura
GROUP BY dispositivo_id, date_trunc('day', ts);
COMMENT ON MATERIALIZED VIEW mv_estadisticas_diarias IS 'Agregado diario para gráficas de historial. Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY mv_estadisticas_diarias;';
CREATE UNIQUE INDEX idx_mv_estadisticas ON mv_estadisticas_diarias (dispositivo_id, dia);

-- ================= SEED: solo Administrador =================
INSERT INTO usuario (email, password_hash, nombre, rol, casa_id)
VALUES ('admin@huellitas.com', crypt('Admin#2026', gen_salt('bf')), 'Administrador Plataforma', 'ADMINISTRADOR', NULL);

INSERT INTO plan (nombre, precio_mensual, limite_dispositivos, limite_almacenamiento_mb, descripcion) VALUES
  ('FREE', 0, 3, 200, 'Monitoreo básico y alertas esenciales'),
  ('BASICO', 4.99, 6, 1000, 'Historial extendido y más dispositivos'),
  ('PREMIUM', 9.99, 15, 5000, 'IA avanzada, reportes ilimitados y soporte prioritario');
