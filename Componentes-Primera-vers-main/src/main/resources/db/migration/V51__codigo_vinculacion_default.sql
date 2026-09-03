-- V51: Hacer que la base de datos genere el UUID automaticamente para casas nuevas

ALTER TABLE casa ALTER COLUMN codigo_vinculacion SET DEFAULT gen_random_uuid()::text;
