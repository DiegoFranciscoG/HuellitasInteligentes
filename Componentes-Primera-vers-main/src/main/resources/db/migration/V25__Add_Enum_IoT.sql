-- V25: SOLO agrega los valores al enum.
-- PostgreSQL exige que ADD VALUE esté en su propia transacción
-- ANTES de poder usar esos valores en cualquier otra sentencia.
ALTER TYPE categoria_dispositivo ADD VALUE IF NOT EXISTS 'LUZ';
ALTER TYPE categoria_dispositivo ADD VALUE IF NOT EXISTS 'PUERTA';
