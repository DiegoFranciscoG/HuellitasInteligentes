-- Migration V10: Actualizaciones de Seguridad, QR y Moderación Inteligente

ALTER TABLE public.usuario ADD COLUMN IF NOT EXISTS debe_cambiar_password BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.qr_login_token ADD COLUMN IF NOT EXISTS tipo VARCHAR(20) NOT NULL DEFAULT 'ACCESO_RAPIDO';

ALTER TABLE public.reporte_moderacion ADD COLUMN IF NOT EXISTS decidido_por VARCHAR(20) DEFAULT 'ADMIN';
ALTER TABLE public.reporte_moderacion ADD COLUMN IF NOT EXISTS motivo_ia TEXT;
ALTER TABLE public.reporte_moderacion ADD COLUMN IF NOT EXISTS confianza_ia NUMERIC(4,3);
ALTER TABLE public.reporte_moderacion ADD COLUMN IF NOT EXISTS revertido BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.reporte_moderacion ALTER COLUMN casa_id DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_reporte_moderacion_estado_decidido ON public.reporte_moderacion (estado, decidido_por);
CREATE INDEX IF NOT EXISTS idx_qr_login_token_expires_used ON public.qr_login_token (expires_at, used);

CREATE OR REPLACE FUNCTION public.fn_cambiar_plan_casa(p_casa_id bigint, p_plan_id bigint)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE 
  v_row suscripcion;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM plan WHERE id = p_plan_id) THEN 
    RAISE EXCEPTION 'PLAN_INVALIDO' USING ERRCODE = 'P0005'; 
  END IF;

  UPDATE suscripcion 
  SET plan_id = p_plan_id, estado = 'ACTIVA'::suscripcion_estado, updated_at = NOW() 
  WHERE casa_id = p_casa_id;

  IF NOT FOUND THEN
    INSERT INTO suscripcion (casa_id, plan_id, estado, fecha_inicio, created_at, updated_at)
    VALUES (p_casa_id, p_plan_id, 'ACTIVA'::suscripcion_estado, CURRENT_DATE, NOW(), NOW())
    RETURNING * INTO v_row;
  ELSE
    SELECT * INTO v_row FROM suscripcion WHERE casa_id = p_casa_id ORDER BY id DESC LIMIT 1;
  END IF;

  RETURN row_to_json(v_row);
END; $function$;
