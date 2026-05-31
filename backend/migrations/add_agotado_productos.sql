-- Marca temporal 86 / agotado (distinto de `disponible` del catálogo admin).
ALTER TABLE productos
  ADD COLUMN agotado TINYINT(1) NOT NULL DEFAULT 0 AFTER disponible;
