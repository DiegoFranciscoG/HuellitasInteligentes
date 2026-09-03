-- V22__fix_feed_social_deleted_at.sql
-- FIX 1: Agregar deleted_at a publicacion (no existía → fn_resolver_denuncia fallaba silenciosamente)
ALTER TABLE public.publicacion ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- FIX 2: fn_feed_social ahora filtra publicaciones y usuarios eliminados
CREATE OR REPLACE FUNCTION public.fn_feed_social(
    p_usuario_id BIGINT,
    p_limite     INT DEFAULT 20,
    p_offset     INT DEFAULT 0
)
RETURNS JSON AS $$
  SELECT COALESCE(json_agg(f), '[]') FROM (
    SELECT
      p.id, p.contenido, p.imagen_url, p.created_at, p.media_type,
      u.nombre     AS autor_nombre,
      u.foto_url   AS autor_foto_url,
      p.usuario_id,
      (SELECT COUNT(*) FROM public.comentario c
       WHERE c.publicacion_id = p.id AND c.deleted_at IS NULL) AS total_comentarios,
      (SELECT COUNT(*) FROM public.publicacion_reaccion pr
       WHERE pr.publicacion_id = p.id) AS likes_count,
      EXISTS(SELECT 1 FROM public.publicacion_reaccion pr
             WHERE pr.publicacion_id = p.id AND pr.usuario_id = p_usuario_id) AS liked_by_me,
      (SELECT COALESCE(json_agg(json_build_object(
               'tipo', pr.tipo, 'usuario_id', pr.usuario_id)), '[]')
       FROM public.publicacion_reaccion pr WHERE pr.publicacion_id = p.id) AS reacciones
    FROM public.publicacion p
    JOIN public.usuario u ON u.id = p.usuario_id
    WHERE p.deleted_at IS NULL
      AND u.deleted_at IS NULL
    ORDER BY p.created_at DESC
    LIMIT p_limite OFFSET p_offset
  ) f
$$ LANGUAGE sql STABLE;

