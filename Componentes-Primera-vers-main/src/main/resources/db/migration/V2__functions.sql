-- ============================================================
-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V3__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- HUELLITAS INTELIGENTES — V2: Capa de funciones (auth + búsquedas)
-- Ejecutar DESPUÉS de V1__init_schema.sql
-- Angular/Flutter llaman SOLO estas funciones vía backend (nativeQuery).
-- Motor de reglas IoT (evaluación) permanece en Spring Boot — no aquí.
-- ============================================================
--
-- NOTA (2026-08-22): cuatro funciones definidas en este archivo quedaron
-- huérfanas con el tiempo — una migración posterior agregó un parámetro
-- nuevo con una firma DISTINTA en vez de reemplazar esta, así que Postgres
-- conservó ambas versiones como sobrecargas separadas. V35 ya eliminó las
-- versiones viejas de la base real; este archivo se conserva intacto (no se
-- borra) porque Flyway necesita reproducir exactamente esta secuencia si
-- algún día hay que reconstruir la base desde cero.
--   - fn_registrar_perro(5 args, sin foto)         -> reemplazada por la versión de V21 (agrega p_foto_url)
--   - fn_feed_social(p_limite, p_offset)           -> reemplazada por la versión de V13 (agrega p_usuario_id)
--   - fn_listar_comentarios(p_publicacion_id)      -> reemplazada por la versión de V33 (agrega p_usuario_id)
--   - fn_crear_publicacion(3 args, sin media_type) -> reemplazada por la versión de V11 (agrega p_media_type)
--
-- (La versión de fn_login_oauth definida aquí, de 4 argumentos sin foto,
-- ya no existe como sobrecarga separada — quedó reemplazada limpiamente
-- antes de que V15 introdujera la versión de 5 argumentos.)

-- ================================================================
-- AUTH
-- ================================================================

-- Registro propietario: crea usuario + casa + zona en 1 transacción atómica
CREATE OR REPLACE FUNCTION fn_registrar_propietario(
  p_email VARCHAR, p_password VARCHAR, p_nombre VARCHAR,
  p_casa_nombre VARCHAR, p_direccion VARCHAR
) RETURNS JSON AS $$
DECLARE v_usuario usuario; v_casa casa; v_zona1 zona; v_zona2 zona;
BEGIN
  IF EXISTS (SELECT 1 FROM usuario WHERE email = p_email AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'EMAIL_YA_REGISTRADO' USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO usuario (email, password_hash, nombre, rol)
  VALUES (p_email, crypt(p_password, gen_salt('bf')), p_nombre, 'PROPIETARIO')
  RETURNING * INTO v_usuario;

  INSERT INTO casa (propietario_id, nombre, direccion)
  VALUES (v_usuario.id, p_casa_nombre, p_direccion)
  RETURNING * INTO v_casa;

  UPDATE usuario SET casa_id = v_casa.id WHERE id = v_usuario.id RETURNING * INTO v_usuario;

  -- 2 zonas fijas, igual al hardware ESP32 ya implementado
  INSERT INTO zona (casa_id, nombre, descripcion)
  VALUES (v_casa.id, 'Sala 1', 'Descanso y Confort') RETURNING * INTO v_zona1;
  INSERT INTO zona (casa_id, nombre, descripcion)
  VALUES (v_casa.id, 'Sala 2', 'Alimentación') RETURNING * INTO v_zona2;

  INSERT INTO suscripcion (casa_id, plan_id)
  VALUES (v_casa.id, (SELECT id FROM plan WHERE nombre = 'FREE'));

  INSERT INTO configuracion_cloud (casa_id) VALUES (v_casa.id);

  RETURN json_build_object(
    'usuario', (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON,
    'casa', row_to_json(v_casa),
    'zonas', json_build_array(row_to_json(v_zona1), row_to_json(v_zona2))
  );
END; $$ LANGUAGE plpgsql;

-- Invitar miembro (máx 1 por casa — la DB lo garantiza vía índice único)
CREATE OR REPLACE FUNCTION fn_invitar_miembro(
  p_casa_id BIGINT, p_email VARCHAR, p_password VARCHAR, p_nombre VARCHAR
) RETURNS JSON AS $$
DECLARE v_usuario usuario;
BEGIN
  IF EXISTS (SELECT 1 FROM usuario WHERE email = p_email AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'EMAIL_YA_REGISTRADO' USING ERRCODE = 'unique_violation';
  END IF;
  IF EXISTS (SELECT 1 FROM usuario WHERE casa_id = p_casa_id AND rol = 'MIEMBRO' AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'CASA_YA_TIENE_MIEMBRO' USING ERRCODE = 'unique_violation';
  END IF;

  INSERT INTO usuario (email, password_hash, nombre, rol, casa_id)
  VALUES (p_email, crypt(p_password, gen_salt('bf')), p_nombre, 'MIEMBRO', p_casa_id)
  RETURNING * INTO v_usuario;

  RETURN (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON;
END; $$ LANGUAGE plpgsql;

-- Login local (email + password)
CREATE OR REPLACE FUNCTION fn_login(p_email VARCHAR, p_password VARCHAR) RETURNS JSON AS $$
DECLARE v_usuario usuario;
BEGIN
  SELECT * INTO v_usuario FROM usuario
  WHERE email = p_email AND activo = true AND deleted_at IS NULL;

  IF NOT FOUND OR v_usuario.password_hash IS NULL
     OR v_usuario.password_hash <> crypt(p_password, v_usuario.password_hash) THEN
    RAISE EXCEPTION 'CREDENCIALES_INVALIDAS' USING ERRCODE = '28P01';
  END IF;

  INSERT INTO auditoria_log (usuario_id, accion, entidad, entidad_id)
  VALUES (v_usuario.id, 'LOGIN', 'usuario', v_usuario.id);

  RETURN (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON;
END; $$ LANGUAGE plpgsql;

-- Login/registro OAuth (Google/Facebook) — nunca duplica usuario
CREATE OR REPLACE FUNCTION fn_login_oauth(
  p_proveedor proveedor_auth, p_proveedor_uid VARCHAR, p_email VARCHAR, p_nombre VARCHAR
) RETURNS JSON AS $$
DECLARE v_usuario_id BIGINT; v_usuario usuario;
BEGIN
  -- 1) ¿Ya vinculado por este proveedor?
  SELECT usuario_id INTO v_usuario_id FROM usuario_proveedor
  WHERE proveedor = p_proveedor AND proveedor_uid = p_proveedor_uid;

  -- 2) ¿Existe usuario con ese email (login local previo)? → vincular
  IF v_usuario_id IS NULL THEN
    SELECT id INTO v_usuario_id FROM usuario WHERE email = p_email AND deleted_at IS NULL;
    IF v_usuario_id IS NOT NULL THEN
      INSERT INTO usuario_proveedor (usuario_id, proveedor, proveedor_uid)
      VALUES (v_usuario_id, p_proveedor, p_proveedor_uid);
    END IF;
  END IF;

  -- 3) No existe: crear usuario nuevo (rol MIEMBRO por defecto; se asigna PROPIETARIO al registrar casa)
  IF v_usuario_id IS NULL THEN
    INSERT INTO usuario (email, nombre, rol) VALUES (p_email, p_nombre, 'MIEMBRO')
    RETURNING id INTO v_usuario_id;
    INSERT INTO usuario_proveedor (usuario_id, proveedor, proveedor_uid)
    VALUES (v_usuario_id, p_proveedor, p_proveedor_uid);
  END IF;

  SELECT * INTO v_usuario FROM usuario WHERE id = v_usuario_id;

  INSERT INTO auditoria_log (usuario_id, accion, entidad, entidad_id)
  VALUES (v_usuario_id, 'LOGIN_OAUTH', 'usuario', v_usuario_id);

  RETURN (row_to_json(v_usuario)::JSONB - 'password_hash')::JSON;
END; $$ LANGUAGE plpgsql;

-- ================================================================
-- PERRO / DISPOSITIVO (altas simples)
-- ================================================================

CREATE OR REPLACE FUNCTION fn_registrar_perro(
  p_casa_id BIGINT, p_nombre VARCHAR, p_raza VARCHAR, p_fecha_nacimiento DATE, p_peso NUMERIC
) RETURNS JSON AS $$
DECLARE v_row perro;
BEGIN
  INSERT INTO perro (casa_id, nombre, raza, fecha_nacimiento, peso)
  VALUES (p_casa_id, p_nombre, p_raza, p_fecha_nacimiento, p_peso)
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_registrar_dispositivo(
  p_zona_id BIGINT, p_mac VARCHAR, p_tipo tipo_dispositivo, p_categoria categoria_dispositivo, p_modelo VARCHAR
) RETURNS JSON AS $$
DECLARE v_row dispositivo;
BEGIN
  IF EXISTS (SELECT 1 FROM dispositivo WHERE mac_address = p_mac AND deleted_at IS NULL) THEN
    RAISE EXCEPTION 'MAC_YA_REGISTRADA' USING ERRCODE = 'unique_violation';
  END IF;
  INSERT INTO dispositivo (zona_id, mac_address, tipo, categoria, modelo)
  VALUES (p_zona_id, p_mac, p_tipo, p_categoria, p_modelo)
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_crear_regla(
  p_casa_id BIGINT, p_nombre VARCHAR, p_sensor_id BIGINT, p_operador operador_comparacion,
  p_umbral NUMERIC, p_actuador_id BIGINT, p_accion_tipo accion_tipo, p_mensaje VARCHAR
) RETURNS JSON AS $$
DECLARE v_row regla_automatizacion;
BEGIN
  INSERT INTO regla_automatizacion (casa_id, nombre, dispositivo_sensor_id, operador, valor_umbral,
    dispositivo_actuador_id, accion_tipo, mensaje_alerta)
  VALUES (p_casa_id, p_nombre, p_sensor_id, p_operador, p_umbral, p_actuador_id, p_accion_tipo, p_mensaje)
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

-- Ingesta de lectura IoT: SOLO inserta (evaluación de reglas la hace Spring Boot tras leer la respuesta)
CREATE OR REPLACE FUNCTION fn_ingesta_lectura(p_mac VARCHAR, p_valor NUMERIC, p_unidad VARCHAR) RETURNS JSON AS $$
DECLARE v_dispositivo_id BIGINT; v_row sensor_lectura;
BEGIN
  SELECT id INTO v_dispositivo_id FROM dispositivo WHERE mac_address = p_mac AND deleted_at IS NULL;
  IF v_dispositivo_id IS NULL THEN
    RAISE EXCEPTION 'DISPOSITIVO_NO_REGISTRADO' USING ERRCODE = 'P0002';
  END IF;
  INSERT INTO sensor_lectura (dispositivo_id, valor, unidad) VALUES (v_dispositivo_id, p_valor, p_unidad)
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

-- ================================================================
-- BÚSQUEDAS EXTENSAS (el motivo de esta capa: 1 función = 0 código de query en Angular/Flutter)
-- ================================================================

-- Dashboard completo casa (propietario y miembro consumen el MISMO contrato JSON)
CREATE OR REPLACE FUNCTION fn_dashboard_casa(p_casa_id BIGINT) RETURNS JSON AS $$
  SELECT json_build_object(
    'casa', (SELECT row_to_json(c) FROM casa c WHERE c.id = p_casa_id),
    'perros', (SELECT COALESCE(json_agg(p), '[]') FROM perro p WHERE p.casa_id = p_casa_id AND p.deleted_at IS NULL),
    'zona', (SELECT row_to_json(z) FROM zona z WHERE z.casa_id = p_casa_id),
    'dispositivos', (SELECT COALESCE(json_agg(json_build_object(
        'id', d.id, 'categoria', d.categoria, 'tipo', d.tipo, 'estado', d.estado,
        'ultima_conexion', d.ultima_conexion,
        'ultimo_valor', v.valor, 'ultimo_valor_ts', v.ts
      )), '[]')
      FROM dispositivo d
      JOIN zona z ON z.id = d.zona_id
      LEFT JOIN vista_ultimo_estado_dispositivo v ON v.dispositivo_id = d.id
      WHERE z.casa_id = p_casa_id AND d.deleted_at IS NULL),
    'alertas_pendientes', (SELECT COALESCE(json_agg(a ORDER BY a.ts DESC), '[]')
      FROM alerta a WHERE a.casa_id = p_casa_id AND a.leida = false),
    'suscripcion', (SELECT row_to_json(s) FROM suscripcion s WHERE s.casa_id = p_casa_id)
  );
$$ LANGUAGE sql STABLE;

-- Historial de sensor con filtro de fechas + paginación (búsqueda extensa típica)
CREATE OR REPLACE FUNCTION fn_historial_sensor(
  p_dispositivo_id BIGINT, p_desde TIMESTAMPTZ, p_hasta TIMESTAMPTZ, p_limite INT DEFAULT 200, p_offset INT DEFAULT 0
) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(t), '[]') FROM (
    SELECT valor, unidad, ts FROM sensor_lectura
    WHERE dispositivo_id = p_dispositivo_id AND ts BETWEEN p_desde AND p_hasta
    ORDER BY ts DESC LIMIT p_limite OFFSET p_offset
  ) t;
$$ LANGUAGE sql STABLE;

-- Historial diario agregado (usa la materialized view, cero cálculo en backend)
CREATE OR REPLACE FUNCTION fn_historial_diario(p_dispositivo_id BIGINT, p_dias INT DEFAULT 30) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(m ORDER BY m.dia DESC), '[]')
  FROM mv_estadisticas_diarias m
  WHERE m.dispositivo_id = p_dispositivo_id AND m.dia >= (CURRENT_DATE - p_dias);
$$ LANGUAGE sql STABLE;

-- Listado de dispositivos con filtros opcionales (tipo/categoria/estado) — 1 función cubre N pantallas
CREATE OR REPLACE FUNCTION fn_buscar_dispositivos(
  p_casa_id BIGINT, p_tipo tipo_dispositivo DEFAULT NULL,
  p_categoria categoria_dispositivo DEFAULT NULL, p_estado estado_dispositivo DEFAULT NULL
) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(d), '[]') FROM (
    SELECT dp.* FROM dispositivo dp
    JOIN zona z ON z.id = dp.zona_id
    WHERE z.casa_id = p_casa_id AND dp.deleted_at IS NULL
      AND (p_tipo IS NULL OR dp.tipo = p_tipo)
      AND (p_categoria IS NULL OR dp.categoria = p_categoria)
      AND (p_estado IS NULL OR dp.estado = p_estado)
    ORDER BY dp.id
  ) d;
$$ LANGUAGE sql STABLE;

-- Panel por sala: dispositivos + último valor, igual al dashboard ESP32 ya funcionando
CREATE OR REPLACE FUNCTION fn_panel_zona(p_zona_id BIGINT) RETURNS JSON AS $$
  SELECT json_build_object(
    'zona', (SELECT row_to_json(z) FROM zona z WHERE z.id = p_zona_id),
    'dispositivos', (SELECT COALESCE(json_agg(json_build_object(
        'id', d.id, 'categoria', d.categoria, 'tipo', d.tipo, 'estado', d.estado,
        'ultimo_valor', v.valor, 'ultimo_valor_unidad', v.unidad, 'ultimo_valor_ts', v.ts
      )), '[]')
      FROM dispositivo d
      LEFT JOIN vista_ultimo_estado_dispositivo v ON v.dispositivo_id = d.id
      WHERE d.zona_id = p_zona_id AND d.deleted_at IS NULL)
  );
$$ LANGUAGE sql STABLE;

-- Alertas con filtro + paginación
CREATE OR REPLACE FUNCTION fn_buscar_alertas(
  p_casa_id BIGINT, p_severidad severidad_alerta DEFAULT NULL,
  p_solo_no_leidas BOOLEAN DEFAULT true, p_limite INT DEFAULT 50, p_offset INT DEFAULT 0
) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(a), '[]') FROM (
    SELECT * FROM alerta
    WHERE casa_id = p_casa_id
      AND (p_solo_no_leidas = false OR leida = false)
      AND (p_severidad IS NULL OR severidad = p_severidad)
    ORDER BY ts DESC LIMIT p_limite OFFSET p_offset
  ) a;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_marcar_alerta_leida(p_alerta_id BIGINT) RETURNS VOID AS $$
  UPDATE alerta SET leida = true WHERE id = p_alerta_id;
$$ LANGUAGE sql;

-- Feed social paginado con contador de comentarios (evita N+1 en Angular/Flutter)
CREATE OR REPLACE FUNCTION fn_feed_social(p_limite INT DEFAULT 20, p_offset INT DEFAULT 0) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(f), '[]') FROM (
    SELECT p.id, p.contenido, p.imagen_url, p.created_at,
      u.nombre AS autor, u.id AS autor_id,
      (SELECT COUNT(*) FROM comentario c WHERE c.publicacion_id = p.id) AS total_comentarios
    FROM publicacion p JOIN usuario u ON u.id = p.usuario_id
    ORDER BY p.created_at DESC LIMIT p_limite OFFSET p_offset
  ) f;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_listar_comentarios(p_publicacion_id BIGINT) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(json_build_object(
    'id', c.id, 'contenido', c.contenido, 'created_at', c.created_at, 'autor', u.nombre
  ) ORDER BY c.created_at ASC), '[]')
  FROM comentario c JOIN usuario u ON u.id = c.usuario_id
  WHERE c.publicacion_id = p_publicacion_id;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_crear_publicacion(p_usuario_id BIGINT, p_contenido TEXT, p_imagen_url TEXT) RETURNS JSON AS $$
DECLARE v_row publicacion;
BEGIN
  INSERT INTO publicacion (usuario_id, contenido, imagen_url) VALUES (p_usuario_id, p_contenido, p_imagen_url)
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_comentar(p_publicacion_id BIGINT, p_usuario_id BIGINT, p_contenido TEXT) RETURNS JSON AS $$
DECLARE v_row comentario;
BEGIN
  INSERT INTO comentario (publicacion_id, usuario_id, contenido) VALUES (p_publicacion_id, p_usuario_id, p_contenido)
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

-- Mensajería (conversación paginada entre propietario↔miembro)
CREATE OR REPLACE FUNCTION fn_conversacion(p_usuario_id BIGINT, p_otro_id BIGINT, p_limite INT DEFAULT 50) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(m ORDER BY m.created_at ASC), '[]') FROM (
    SELECT * FROM mensaje
    WHERE (emisor_id = p_usuario_id AND receptor_id = p_otro_id)
       OR (emisor_id = p_otro_id AND receptor_id = p_usuario_id)
    ORDER BY created_at DESC LIMIT p_limite
  ) m;
$$ LANGUAGE sql STABLE;

CREATE OR REPLACE FUNCTION fn_enviar_mensaje(p_emisor_id BIGINT, p_receptor_id BIGINT, p_contenido TEXT) RETURNS JSON AS $$
DECLARE v_row mensaje;
BEGIN
  INSERT INTO mensaje (emisor_id, receptor_id, contenido) VALUES (p_emisor_id, p_receptor_id, p_contenido)
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

-- Recomendaciones IA por perro
CREATE OR REPLACE FUNCTION fn_recomendaciones_perro(p_perro_id BIGINT, p_limite INT DEFAULT 10) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(r ORDER BY r.created_at DESC), '[]') FROM (
    SELECT * FROM recomendacion_ia WHERE perro_id = p_perro_id ORDER BY created_at DESC LIMIT p_limite
  ) r;
$$ LANGUAGE sql STABLE;

-- ================================================================
-- PANEL ADMINISTRADOR (búsquedas globales)
-- ================================================================

CREATE OR REPLACE FUNCTION fn_admin_dashboard() RETURNS JSON AS $$
  SELECT json_build_object(
    'resumen', (SELECT row_to_json(v) FROM vista_admin_resumen v),
    'por_plan', (SELECT COALESCE(json_agg(json_build_object('plan', pl.nombre, 'total', cnt)), '[]')
      FROM plan pl LEFT JOIN LATERAL (
        SELECT COUNT(*) AS cnt FROM suscripcion s WHERE s.plan_id = pl.id AND s.estado = 'ACTIVA'
      ) x ON true)
  );
$$ LANGUAGE sql STABLE;

-- Búsqueda de casas con paginación + filtro texto (para el admin)
CREATE OR REPLACE FUNCTION fn_admin_buscar_casas(p_texto VARCHAR DEFAULT NULL, p_limite INT DEFAULT 20, p_offset INT DEFAULT 0)
RETURNS JSON AS $$
  SELECT COALESCE(json_agg(t), '[]') FROM (
    SELECT c.id, c.nombre, u.email AS propietario_email, u.nombre AS propietario_nombre,
      s.estado AS suscripcion_estado, pl.nombre AS plan
    FROM casa c
    JOIN usuario u ON u.id = c.propietario_id
    LEFT JOIN suscripcion s ON s.casa_id = c.id
    LEFT JOIN plan pl ON pl.id = s.plan_id
    WHERE c.deleted_at IS NULL
      AND (p_texto IS NULL OR c.nombre ILIKE '%'||p_texto||'%' OR u.email ILIKE '%'||p_texto||'%')
    ORDER BY c.created_at DESC LIMIT p_limite OFFSET p_offset
  ) t;
$$ LANGUAGE sql STABLE;
