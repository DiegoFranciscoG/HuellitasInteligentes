-- V48: Renombrar los servos en la base de datos para que el historial
-- de comandos tambien muestre el nombre correcto.

UPDATE dispositivo SET modelo = 'Ventana Habitaci\u00f3n 1' WHERE id = 8;
UPDATE dispositivo SET modelo = 'Ventana Habitaci\u00f3n 2' WHERE id = 9;
