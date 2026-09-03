-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V39: corrige dos fallos encontrados al probar el historial.
--
-- FALLO 1 — Fuga entre usuarios en el historial personal.
--   fn_historial_usuario (V9) filtraba con:
--       WHERE usuario_id = p_usuario_id OR usuario_id IS NULL
--   Ese "OR usuario_id IS NULL" hacía que toda fila de auditoría sin usuario
--   asociado apareciera en el historial de CUALQUIER usuario. En la base real
--   son 16 filas (inicios de sesión y mensajes de grupo de otras personas),
--   así que cada usuario veía actividad ajena mezclada con la suya.
--
-- FALLO 2 — Los dispositivos IoT nunca se registraron.
--   V24 busca la casa por el correo del propietario y, si no la encuentra,
--   hace RETURN sin insertar nada. Cuando corrió, esa cuenta aún no existía:
--   no sembró nada y Flyway igual marcó la migración como aplicada, así que
--   nunca se reintentó. Resultado: LED_ROOM1, FAN_ROOM1, SERVO_ROOM1 y el
--   resto no existen, y el registrarComando() de LedService, FanService,
--   PumpService, ServoService y Servo2Service viene insertando cero filas en
--   silencio. Por eso el historial de actuadores está vacío.
--
-- Nota de alcance: los identificadores están escritos a mano en los servicios
-- Java ("LED_ROOM1", "FAN_ROOM1"...), así que hoy la capa IoT atiende a una
-- sola vivienda. Sembrar dispositivos para las demás casas no serviría de
-- nada, porque ningún código escribiría en esas filas. Se siembra solo la
-- casa que el código referencia y se deja anotado el límite.

-- ── Fallo 1 ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_historial_usuario(p_usuario_id BIGINT)
RETURNS JSON AS $$
DECLARE v_result JSON;
BEGIN
  SELECT json_agg(row_to_json(t) ORDER BY t.created_at DESC) INTO v_result
  FROM (
    SELECT id, usuario_id, accion, entidad, entidad_id, detalle, ip, created_at
    FROM auditoria_log
    WHERE usuario_id = p_usuario_id
    ORDER BY created_at DESC LIMIT 50
  ) t;
  RETURN COALESCE(v_result, '[]'::JSON);
END;
$$ LANGUAGE plpgsql;

-- ── Fallo 2 ────────────────────────────────────────────────────────────────
-- Se inserta directo y no con fn_registrar_dispositivo, porque esa función
-- lanza MAC_YA_REGISTRADA si el identificador ya existe y abortaría toda la
-- migración. Aquí cada alta va guardada por NOT EXISTS, así la migración
-- puede convivir con lo que V38 ya sembró.
DO $$
DECLARE
  v_casa BIGINT;
  v_zona1 BIGINT;
  v_zona2 BIGINT;
BEGIN
  -- Casa cuyo propietario referencian los servicios Java.
  SELECT c.id INTO v_casa
  FROM casa c JOIN usuario u ON u.id = c.propietario_id
  WHERE u.email = 'diego.granda.est@tecazuay.edu.ec' AND c.deleted_at IS NULL
  LIMIT 1;

  IF v_casa IS NULL THEN
    RAISE NOTICE 'V39: no existe la casa del propietario esperado; no se siembran dispositivos.';
    RETURN;
  END IF;

  SELECT id INTO v_zona1 FROM zona
  WHERE casa_id = v_casa AND (nombre ILIKE '%sala%' OR nombre ILIKE '%confort%') LIMIT 1;
  IF v_zona1 IS NULL THEN
    INSERT INTO zona (casa_id, nombre, descripcion)
    VALUES (v_casa, 'Zona de Confort (Hab 1)', 'Sala 1') RETURNING id INTO v_zona1;
  END IF;

  SELECT id INTO v_zona2 FROM zona
  WHERE casa_id = v_casa AND (nombre ILIKE '%alimenta%' OR nombre ILIKE '%cocina%') LIMIT 1;
  IF v_zona2 IS NULL THEN
    INSERT INTO zona (casa_id, nombre, descripcion)
    VALUES (v_casa, 'Zona de Alimentación (Hab 2)', 'Sala 2') RETURNING id INTO v_zona2;
  END IF;

  INSERT INTO dispositivo (zona_id, mac_address, tipo, categoria, modelo)
  SELECT v.zona, v.mac, v.tipo::tipo_dispositivo, v.cat::categoria_dispositivo, v.modelo
  FROM (VALUES
      (v_zona1, 'LED_ROOM1',     'ACTUADOR', 'LUZ',               'Luz Principal'),
      (v_zona1, 'FAN_ROOM1',     'ACTUADOR', 'VENTILADOR',        'Ventilador Principal'),
      (v_zona1, 'SERVO_ROOM1',   'ACTUADOR', 'PUERTA',            'Puerta Principal'),
      (v_zona2, 'LED_ROOM2',     'ACTUADOR', 'LUZ',               'Luz Comedor'),
      (v_zona2, 'FAN_ROOM2',     'ACTUADOR', 'VENTILADOR',        'Ventilador Comedor'),
      (v_zona2, 'SERVO_ROOM2',   'ACTUADOR', 'PUERTA',            'Ventana Cocina'),
      (v_zona2, 'PUMP_ROOM2',    'ACTUADOR', 'BOMBA_AGUA',        'Bomba Agua'),
      (v_zona2, 'STEPPER_ROOM2', 'ACTUADOR', 'MOTOR_ALIMENTADOR', 'Dispensador Alimento')
  ) AS v(zona, mac, tipo, cat, modelo)
  WHERE NOT EXISTS (
    SELECT 1 FROM dispositivo d WHERE d.mac_address = v.mac
  );
END $$;
