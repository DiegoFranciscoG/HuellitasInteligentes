-- V54: la ESP32-CAM real (MAC ec:64:c9:ac:e5:d8) todavía corre el firmware
-- de fábrica (CameraWebServer sin modificar) porque la placa no acepta
-- grabación de código nuevo por ahora (problema de hardware/USB, no de
-- software). Ese firmware nunca manda latido ni código de vivienda, así
-- que jamás va a aparecer por "Buscar en mi red" — pero SÍ sirve un stream
-- MJPEG normal en su IP local, y tanto la web como la app ya saben mostrar
-- ese tipo de cámara (rama "Red Local", sin WebRTC) con solo tener la URL
-- correcta guardada.
--
-- Se da de alta como un dispositivo nuevo (no se reutiliza el 13, que es
-- la placa de sensores, para no mezclar los dos aparatos) y se crea su
-- cámara apuntando directo al stream. Mientras quien mire esté en la misma
-- red que la cámara (típico durante una demo), esto funciona ya, sin
-- esperar a que la ESP32-CAM se pueda reflashear.
INSERT INTO dispositivo (zona_id, mac_address, tipo, categoria, modelo, ultima_conexion)
SELECT z.id, 'ec:64:c9:ac:e5:d8', 'ACTUADOR'::tipo_dispositivo, 'CAMARA'::categoria_dispositivo,
       'ESP32-CAM OV2640', now()
FROM zona z
WHERE z.casa_id = 16
ORDER BY z.id
LIMIT 1
ON CONFLICT (mac_address) DO NOTHING;

INSERT INTO camara (casa_id, dispositivo_id, nombre, url_stream, activo)
SELECT 16, d.id, 'Cámara ESP32-CAM', 'http://192.168.1.194:81/stream', true
FROM dispositivo d
WHERE d.mac_address = 'ec:64:c9:ac:e5:d8'
  AND NOT EXISTS (SELECT 1 FROM camara c WHERE c.dispositivo_id = d.id);
