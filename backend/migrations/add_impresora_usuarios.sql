-- Impresora asignada al usuario (0 = ninguna; ver pedidos de esa impresora en pantalla servicio).
ALTER TABLE `usuarios`
  ADD COLUMN `impresora` INT UNSIGNED NOT NULL DEFAULT 0 AFTER `activo`;
