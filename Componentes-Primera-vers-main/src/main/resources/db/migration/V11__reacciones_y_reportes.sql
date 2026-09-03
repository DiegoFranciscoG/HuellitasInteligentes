-- V11__reacciones_y_reportes.sql

ALTER TABLE publicacion ADD COLUMN media_type VARCHAR(20) DEFAULT 'IMAGE';

-- Tabla de reacciones simples (Me gusta)
CREATE TABLE publicacion_reaccion (
  publicacion_id BIGINT NOT NULL REFERENCES publicacion(id) ON DELETE CASCADE,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (publicacion_id, usuario_id)
);

-- Tabla de reportes para publicaciones
CREATE TABLE publicacion_reporte (
  id BIGSERIAL PRIMARY KEY,
  publicacion_id BIGINT NOT NULL REFERENCES publicacion(id) ON DELETE CASCADE,
  usuario_id BIGINT NOT NULL REFERENCES usuario(id) ON DELETE CASCADE,
  motivo TEXT NOT NULL,
  estado_revision VARCHAR(20) NOT NULL DEFAULT 'PENDIENTE',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Actualizar fn_crear_publicacion para soportar media_type
CREATE OR REPLACE FUNCTION fn_crear_publicacion(p_usuario_id BIGINT, p_contenido TEXT, p_imagen_url TEXT, p_media_type VARCHAR(20) DEFAULT 'IMAGE') RETURNS JSON AS $$
DECLARE v_row publicacion;
BEGIN
  INSERT INTO publicacion (usuario_id, contenido, imagen_url, media_type) 
  VALUES (p_usuario_id, p_contenido, p_imagen_url, p_media_type)
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;

-- Funcion para dar/quitar like (Toggle Like)
CREATE OR REPLACE FUNCTION fn_reaccionar_publicacion(p_publicacion_id BIGINT, p_usuario_id BIGINT) RETURNS BOOLEAN AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM publicacion_reaccion WHERE publicacion_id = p_publicacion_id AND usuario_id = p_usuario_id) THEN
    DELETE FROM publicacion_reaccion WHERE publicacion_id = p_publicacion_id AND usuario_id = p_usuario_id;
    RETURN FALSE; 
  ELSE
    INSERT INTO publicacion_reaccion (publicacion_id, usuario_id) VALUES (p_publicacion_id, p_usuario_id);
    RETURN TRUE; 
  END IF;
END; $$ LANGUAGE plpgsql;

-- Funcion para reportar publicacion
CREATE OR REPLACE FUNCTION fn_reportar_publicacion(p_publicacion_id BIGINT, p_usuario_id BIGINT, p_motivo TEXT) RETURNS JSON AS $$
DECLARE v_row publicacion_reporte;
BEGIN
  INSERT INTO publicacion_reporte (publicacion_id, usuario_id, motivo) 
  VALUES (p_publicacion_id, p_usuario_id, p_motivo)
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;
