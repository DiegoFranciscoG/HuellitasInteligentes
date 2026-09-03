-- ADVERTENCIA: Esta migración es gestionada exclusivamente por Flyway. No ejecutar manualmente en DBeaver/Neon SQL Editor. Cualquier cambio de esquema debe hacerse creando un nuevo archivo V(n+1)__descripcion.sql, nunca editando estos archivos ni corriendo DDL suelto.
-- V37: SOLO agrega el valor al enum, igual que hizo V25 con LUZ y PUERTA.
-- PostgreSQL exige que ADD VALUE esté commiteado en su propia transacción
-- ANTES de poder usarlo en un CHECK o en un INSERT, así que el constraint y
-- el sembrado del dispositivo van aparte, en V38.
ALTER TYPE categoria_dispositivo ADD VALUE IF NOT EXISTS 'CAMARA';
