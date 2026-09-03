-- V52: reactivar cuentas de ex miembros que quedaron marcadas como si
-- estuvieran baneadas para siempre.
--
-- Antes de que eliminarMiembro() se corrigiera (ver casa_anterior_id en
-- MiembroController), dar de baja a un miembro hacia:
--     UPDATE usuario SET deleted_at = NOW(), activo = false WHERE ...
-- Eso deja la cuenta indistinguible de una baneada por moderación: tanto
-- fn_login como fn_login_oauth cortan con CUENTA_BANEADA/CUENTA_BLOQUEADA
-- en cuanto ven activo=false o deleted_at, así que esa persona no podía
-- volver a registrarse nunca, ni con Google/Facebook ni con nada.
--
-- El código actual de eliminarMiembro() ya hace lo correcto: limpia
-- casa_id, pone rol=PROPIETARIO y deja activo=true/deleted_at=NULL,
-- guardando casa_anterior_id solo para el historial. Esta migración
-- aplica esas mismas reglas a las cuentas que quedaron atascadas con el
-- método viejo. Se identifican por tener casa_anterior_id (ese campo solo
-- lo pone la baja de un miembro; una cuenta baneada por moderación nunca
-- lo tiene), así que no toca ninguna cuenta realmente sancionada.
UPDATE usuario
SET casa_id = NULL,
    rol = 'PROPIETARIO'::rol_usuario,
    activo = true,
    deleted_at = NULL
WHERE casa_anterior_id IS NOT NULL
  AND casa_id IS NOT NULL
  AND (activo = false OR deleted_at IS NOT NULL);
