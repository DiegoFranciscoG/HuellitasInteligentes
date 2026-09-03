-- V28__buscador_y_hashtags.sql
-- Buscador de publicaciones y hashtags para la Comunidad.
--
-- Decisión de diseño: los hashtags NO se guardan en una tabla aparte. Se
-- derivan del texto de la publicación cada vez que se consultan. Así el
-- contenido es la única fuente de verdad y es imposible que la etiqueta y el
-- texto queden desincronizados (por ejemplo al editar una publicación).
-- Solo se agregan funciones de lectura: no se altera ninguna tabla.

-- Búsqueda por texto libre o por hashtag (#tema). Devuelve exactamente la
-- misma estructura que fn_feed_social para que los clientes reutilicen el
-- mismo código de pintado.
CREATE OR REPLACE FUNCTION public.fn_buscar_publicaciones(
    p_usuario_id BIGINT,
    p_q          TEXT,
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
      AND (
        p_q IS NULL
        OR btrim(p_q) = ''
        OR p.contenido ILIKE '%' || btrim(p_q) || '%'
        OR u.nombre    ILIKE '%' || btrim(p_q) || '%'
      )
    ORDER BY p.created_at DESC
    LIMIT p_limite OFFSET p_offset
  ) f
$$ LANGUAGE sql STABLE;

-- Hashtags más usados, para sugerir temas en el buscador.
CREATE OR REPLACE FUNCTION public.fn_hashtags_populares(p_limite INT DEFAULT 10)
RETURNS JSON AS $$
  SELECT COALESCE(json_agg(t), '[]') FROM (
    SELECT lower(m[1]) AS tag, COUNT(*) AS total
    FROM public.publicacion p,
         LATERAL regexp_matches(p.contenido, '#([A-Za-z0-9_ÁÉÍÓÚÑáéíóúñ]+)', 'g') AS m
    WHERE p.deleted_at IS NULL
      AND p.contenido IS NOT NULL
    GROUP BY lower(m[1])
    ORDER BY COUNT(*) DESC, lower(m[1]) ASC
    LIMIT p_limite
  ) t
$$ LANGUAGE sql STABLE;
