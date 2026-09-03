-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V38: ahora que CAMARA ya existe en el enum (V37 quedó commiteada), se amplía
-- el constraint y se registra el servomotor que orienta la cámara.
--
-- Sin esta fila, Servo3Service.registrarComando('SERVO_CAMARA', ...) no falla
-- pero tampoco guarda nada: el INSERT ... SELECT no encuentra dispositivo y
-- afecta cero filas, así que el historial de la cámara quedaría vacío.

ALTER TABLE dispositivo DROP CONSTRAINT IF EXISTS chk_tipo_categoria;
ALTER TABLE dispositivo ADD CONSTRAINT chk_tipo_categoria CHECK (
    (tipo = 'SENSOR' AND categoria IN ('DHT11','MQ135','ULTRASONICO_ALIMENTO','NIVEL_AGUA'))
    OR
    (tipo = 'ACTUADOR' AND categoria IN ('VENTILADOR','SERVO_VENTANA','MOTOR_ALIMENTADOR','BOMBA_AGUA','LUZ','PUERTA','CAMARA'))
);

DO $$
DECLARE
  v_casa_id BIGINT;
  v_zona_id BIGINT;
BEGIN
  -- Misma casa que sembró V24.
  SELECT c.id INTO v_casa_id
  FROM casa c
  JOIN usuario u ON c.propietario_id = u.id
  WHERE u.email = 'diego.granda.est@tecazuay.edu.ec'
  LIMIT 1;

  IF v_casa_id IS NULL THEN
    -- Sin esa casa no hay dónde colgar el dispositivo; no insertamos nada.
    RETURN;
  END IF;

  -- La cámara vive en la zona de confort, la misma que la sala 1 de V24.
  SELECT id INTO v_zona_id
  FROM zona
  WHERE casa_id = v_casa_id AND (nombre ILIKE '%sala%' OR nombre ILIKE '%confort%')
  LIMIT 1;

  IF v_zona_id IS NULL THEN
    INSERT INTO zona (casa_id, nombre, descripcion)
    VALUES (v_casa_id, 'Zona de Confort (Hab 1)', 'Sala 1')
    RETURNING id INTO v_zona_id;
  END IF;

  PERFORM fn_registrar_dispositivo(v_zona_id, 'SERVO_CAMARA', 'ACTUADOR', 'CAMARA', 'Servo de Cámara');
END $$;
