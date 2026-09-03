-- V49: Retirar las 4 tablas verificadas como sin uso en codigo Java, Angular,
-- Flutter y funciones SQL. Cada DROP lleva IF EXISTS por seguridad.
--
-- NO TOCAR: sensor_lectura (la usan fn_historial_sensor, fn_ingesta_lectura,
-- vista_ultimo_estado_dispositivo), regla_automatizacion (fn_crear_regla),
-- reporte_comunidad (fn_reportar_contenido), chat_sala_mensaje_reaccion
-- (fn_mensajes_sala_chat), auditoria_log (fn_login, fn_historial_casa),
-- contenido_oculto (fn_feed_social, fn_listar_comentarios).

DROP TABLE IF EXISTS chat_mensaje CASCADE;
DROP TABLE IF EXISTS chat_mensaje_reaccion CASCADE;
DROP TABLE IF EXISTS configuracion_general CASCADE;
DROP TABLE IF EXISTS publicacion_reporte CASCADE;
