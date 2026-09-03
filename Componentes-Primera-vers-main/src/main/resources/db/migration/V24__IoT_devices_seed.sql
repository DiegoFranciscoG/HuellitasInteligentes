-- Seed of IoT devices

DO $$
DECLARE 
  v_casa_id BIGINT;
  v_zona1_id BIGINT;
  v_zona2_id BIGINT;
BEGIN
  -- Buscar la casa del propietario por email real (asegúrate de que este email exista en tu BD)
  SELECT c.id INTO v_casa_id 
  FROM casa c 
  JOIN usuario u ON c.propietario_id = u.id 
  WHERE u.email = 'diego.granda.est@tecazuay.edu.ec' 
  LIMIT 1;

  IF v_casa_id IS NULL THEN
    -- Si no se encuentra la casa de ese dueño, no insertamos nada.
    RETURN;
  END IF;

  -- Obtener o crear zonas de Casa real
  SELECT id INTO v_zona1_id FROM zona WHERE casa_id = v_casa_id AND nombre ILIKE '%sala%' OR nombre ILIKE '%confort%' LIMIT 1;
  IF v_zona1_id IS NULL THEN
    INSERT INTO zona (casa_id, nombre, descripcion) VALUES (v_casa_id, 'Zona de Confort (Hab 1)', 'Sala 1') RETURNING id INTO v_zona1_id;
  END IF;

  SELECT id INTO v_zona2_id FROM zona WHERE casa_id = v_casa_id AND nombre ILIKE '%alimenta%' OR nombre ILIKE '%cocina%' LIMIT 1;
  IF v_zona2_id IS NULL THEN
    INSERT INTO zona (casa_id, nombre, descripcion) VALUES (v_casa_id, 'Zona de Alimentación (Hab 2)', 'Sala 2') RETURNING id INTO v_zona2_id;
  END IF;

  -- Registrar dispositivos con SUS CATEGORÍAS REALES (creadas en V25)
  -- Sala 1
  PERFORM fn_registrar_dispositivo(v_zona1_id, 'LED_ROOM1', 'ACTUADOR', 'LUZ', 'Luz Principal');
  PERFORM fn_registrar_dispositivo(v_zona1_id, 'FAN_ROOM1', 'ACTUADOR', 'VENTILADOR', 'Ventilador Principal');
  PERFORM fn_registrar_dispositivo(v_zona1_id, 'SERVO_ROOM1', 'ACTUADOR', 'PUERTA', 'Puerta Principal');

  -- Sala 2
  PERFORM fn_registrar_dispositivo(v_zona2_id, 'LED_ROOM2', 'ACTUADOR', 'LUZ', 'Luz Comedor');
  PERFORM fn_registrar_dispositivo(v_zona2_id, 'FAN_ROOM2', 'ACTUADOR', 'VENTILADOR', 'Ventilador Comedor');
  PERFORM fn_registrar_dispositivo(v_zona2_id, 'SERVO_ROOM2', 'ACTUADOR', 'PUERTA', 'Ventana Cocina');
  PERFORM fn_registrar_dispositivo(v_zona2_id, 'PUMP_ROOM2', 'ACTUADOR', 'BOMBA_AGUA', 'Bomba Agua');
  PERFORM fn_registrar_dispositivo(v_zona2_id, 'STEPPER_ROOM2', 'ACTUADOR', 'MOTOR_ALIMENTADOR', 'Dispensador Alimento');

END $$;
