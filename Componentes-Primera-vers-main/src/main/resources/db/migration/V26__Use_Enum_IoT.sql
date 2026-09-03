-- V26: Ahora que LUZ y PUERTA ya existen en el enum (V25 ya fue commiteado),
-- actualizamos el constraint y corregimos datos históricos.

-- Actualizamos el constraint para permitir las nuevas categorías en actuadores
ALTER TABLE dispositivo DROP CONSTRAINT IF EXISTS chk_tipo_categoria;
ALTER TABLE dispositivo ADD CONSTRAINT chk_tipo_categoria CHECK (
    (tipo = 'SENSOR' AND categoria IN ('DHT11','MQ135','ULTRASONICO_ALIMENTO','NIVEL_AGUA'))
    OR
    (tipo = 'ACTUADOR' AND categoria IN ('VENTILADOR','SERVO_VENTANA','MOTOR_ALIMENTADOR','BOMBA_AGUA','LUZ','PUERTA'))
);

-- Corrección retrospectiva: Si V24 ya había insertado con categorías falsas, las corregimos.
UPDATE dispositivo SET categoria = 'LUZ'   WHERE mac_address IN ('LED_ROOM1', 'LED_ROOM2');
UPDATE dispositivo SET categoria = 'PUERTA' WHERE mac_address IN ('SERVO_ROOM1', 'SERVO_ROOM2');
