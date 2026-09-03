-- V34__eliminar_funciones_duplicadas_ambiguas.sql
--
-- fn_resetear_password y fn_login_oauth quedaron con dos versiones cada una
-- (probablemente de una migracion vieja que uso CREATE OR REPLACE con una
-- firma de parametros distinta en vez de reemplazar la funcion original).
-- Postgres permite conservar ambas porque tecnicamente son sobrecargas
-- distintas, pero eso vuelve ambigua cualquier llamada con la cantidad de
-- argumentos que coincide con las dos: el driver JDBC no puede decidir cual
-- usar y la llamada falla con "more than one function named ...".
--
-- fn_resetear_password(text, character varying) es la version vieja: hace
-- referencia a la columna password_reset_token.token_hash, que ya no existe
-- (la tabla actual usa la columna "token"). Esto rompe el restablecimiento
-- de contraseña para todos los usuarios reales -- cualquier intento
-- coincide en cantidad de argumentos con la version nueva y Postgres nunca
-- llega a ejecutar ninguna de las dos.
--
-- A diferencia de fn_login_oauth, el origen de esta version vieja no se
-- pudo rastrear en el historial de migraciones presente (V1_init_schema.sql
-- y V3_password_reset.sql, las mas antiguas que tocan este tema, ya usan
-- la columna "token" y el tipo VARCHAR consistentemente) -- es probable que
-- haya sido un cambio manual anterior a que Flyway gestionara este archivo,
-- o que la migracion original que la creo ya no exista en el repositorio.
--
-- fn_login_oauth(proveedor_auth, character varying, character varying,
-- character varying, text) es la version vieja del login con Google/
-- Facebook: no revisa si la cuenta esta baneada y asigna el rol MIEMBRO a
-- los usuarios nuevos (la version actual asigna PROPIETARIO, que es el
-- comportamiento real de la app). No genera el mismo error de ambiguedad
-- en la practica -- Postgres logra resolverla por alguna preferencia de
-- casteo -- pero es exactamente el mismo patron de riesgo, ya inactiva, y
-- conviene eliminarla antes de que un cambio futuro la vuelva ambigua tambien.

DROP FUNCTION IF EXISTS public.fn_resetear_password(text, character varying);

DROP FUNCTION IF EXISTS public.fn_login_oauth(
    proveedor_auth,
    character varying,
    character varying,
    character varying,
    text
);
