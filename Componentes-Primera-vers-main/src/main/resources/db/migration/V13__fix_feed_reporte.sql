-- V13__fix_feed_reporte.sql

-- 1. Arreglar fn_feed_social para que devuelva likes, likes de usuario y foto.
CREATE OR REPLACE FUNCTION fn_feed_social(p_usuario_id BIGINT, p_limite INT DEFAULT 20, p_offset INT DEFAULT 0) RETURNS JSON AS $$
  SELECT COALESCE(json_agg(f), '[]') FROM (
    SELECT p.id, p.contenido, p.imagen_url, p.created_at, p.media_type,
      u.nombre AS autor_nombre, u.id AS usuario_id, u.foto_url AS autor_foto_url,
      (SELECT COUNT(*) FROM comentario c WHERE c.publicacion_id = p.id) AS total_comentarios,
      (SELECT COUNT(*) FROM publicacion_reaccion pr WHERE pr.publicacion_id = p.id) AS likes_count,
      EXISTS(SELECT 1 FROM publicacion_reaccion pr WHERE pr.publicacion_id = p.id AND pr.usuario_id = p_usuario_id) AS liked_by_me,
      (SELECT COALESCE(json_agg(json_build_object('tipo', pr.tipo, 'usuario_id', pr.usuario_id)), '[]') FROM publicacion_reaccion pr WHERE pr.publicacion_id = p.id) AS reacciones
    FROM publicacion p JOIN usuario u ON u.id = p.usuario_id
    ORDER BY p.created_at DESC LIMIT p_limite OFFSET p_offset
  ) f;
$$ LANGUAGE sql STABLE;


-- 2. Arreglar fn_reportar_publicacion para insertar en reporte_moderacion y notificar al ADMIN
CREATE OR REPLACE FUNCTION fn_reportar_publicacion(p_publicacion_id BIGINT, p_usuario_id BIGINT, p_motivo TEXT) RETURNS JSON AS $$
DECLARE 
  v_row reporte_moderacion;
  v_reportado BIGINT;
BEGIN
  SELECT usuario_id INTO v_reportado FROM publicacion WHERE id = p_publicacion_id;
  
  INSERT INTO reporte_moderacion (reportador_id, reportado_id, motivo, estado, creado_por) 
  VALUES (p_usuario_id, v_reportado, 'Reporte de Publicación #' || p_publicacion_id || ': ' || p_motivo, 'PENDIENTE', 'SISTEMA')
  RETURNING * INTO v_row;
  RETURN row_to_json(v_row);
END; $$ LANGUAGE plpgsql;
