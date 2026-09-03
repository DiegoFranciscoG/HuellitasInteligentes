-- V50: Agregar codigo_vinculacion a la tabla casa.
-- Es un UUID que identifica la vivienda ante los dispositivos IoT
-- (ESP32 de sensores y ESP32-CAM). El firmware lo manda en X-Device-Code.
-- Se genera una sola vez y es inmutable.

ALTER TABLE casa ADD COLUMN IF NOT EXISTS codigo_vinculacion TEXT;

-- Rellenar las casas existentes con un UUID unico.
UPDATE casa SET codigo_vinculacion = gen_random_uuid()::text
WHERE codigo_vinculacion IS NULL;

-- Ahora hacerla NOT NULL para que todas las nuevas casas tengan uno.
ALTER TABLE casa ALTER COLUMN codigo_vinculacion SET NOT NULL;
