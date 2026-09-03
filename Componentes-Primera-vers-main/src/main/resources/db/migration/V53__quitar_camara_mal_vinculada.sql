-- V53: la placa de sensores (MAC 5C:01:3B:6D:3A:B0, dispositivo id 13) quedó
-- vinculada como si fuera una cámara WebRTC (camara id 20), pero es la placa
-- de sensores/servos, no tiene cámara de verdad — el video nunca podía
-- conectar. Se desactiva esa cámara fantasma; el dispositivo en sí se deja
-- intacto (sigue siendo un aparato válido de la casa, solo deja de
-- ofrecerse como cámara).
UPDATE camara
SET activo = false
WHERE dispositivo_id = 13
  AND url_stream LIKE 'webrtc:%';
