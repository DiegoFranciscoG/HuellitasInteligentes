-- V35__eliminar_versiones_huerfanas_de_funciones.sql
--
-- Mismo patron que V34: estas 5 funciones tienen dos versiones cada una,
-- de cuando alguien agrego un parametro nuevo con CREATE OR REPLACE usando
-- una firma distinta en vez de reemplazar la funcion original. A diferencia
-- de V34, ninguna de estas es ambigua (cada version tiene una cantidad
-- distinta de argumentos, asi que Postgres siempre sabe cual usar), pero la
-- version vieja de cada una quedo huerfana: no la llama ningun controlador
-- Java (AuthRepository, SocialRepository, PerroRepository usan siempre la
-- version nueva) ni ninguna otra funcion SQL. Es limpieza preventiva —
-- mientras existan, cualquier cambio futuro que iguale la cantidad de
-- argumentos entre las dos versiones repetiria el mismo bug de
-- fn_resetear_password.

DROP FUNCTION IF EXISTS public.fn_crear_publicacion(bigint, text, text);
DROP FUNCTION IF EXISTS public.fn_feed_social(integer, integer);
DROP FUNCTION IF EXISTS public.fn_listar_comentarios(bigint);
DROP FUNCTION IF EXISTS public.fn_registrar_perro(bigint, character varying, character varying, date, numeric);
DROP FUNCTION IF EXISTS public.fn_solicitar_reset(character varying, text, integer);
