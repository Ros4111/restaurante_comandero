-- Campo servido: '2000-01-01 00:00:00' = pendiente de servir en mesa.
ALTER TABLE `pedido_detalles`
  ADD COLUMN `servido` datetime NOT NULL DEFAULT '2000-01-01 00:00:00' AFTER `hora_pedido`;

ALTER TABLE `pedido_detalles_historico`
  ADD COLUMN `servido` datetime NOT NULL DEFAULT '2000-01-01 00:00:00' AFTER `hora_pedido`;
