<?php
// backend/api/endpoints/pedidos.php
declare(strict_types=1);

// ── Calcula el precio sin IVA y el porcentaje de IVA de una línea ────────────
// base_imponible del producto + suplementos_sin_iva de opciones no predeterminadas
// Devuelve ['precio' => float, 'porcentaje_IVA' => float]
function _calcularPrecioLinea(PDO $db, int $idProducto, mixed $opcionesElegidas): array {
    $stProd = $db->prepare(
        'SELECT COALESCE(base_imponible, 0), COALESCE(porcentaje_IVA, 0)
           FROM productos WHERE id_producto = ?'
    );
    $stProd->execute([$idProducto]);
    $row = $stProd->fetch(PDO::FETCH_NUM);
    $base   = (float)($row[0] ?? 0);
    $pctIVA = (float)($row[1] ?? 0);

    if (!is_array($opcionesElegidas) || empty($opcionesElegidas)) {
        return ['precio' => round($base, 6), 'porcentaje_IVA' => $pctIVA];
    }

    $stSupl = $db->prepare(
        'SELECT COALESCE(suplemento_sin_iva, 0) FROM productos_opciones
          WHERE id_producto = ? AND id_grupo_opciones = ? AND nombre_opcion = ?'
    );

    $totalSupl = 0.0;
    foreach ($opcionesElegidas as $idGrupo => $opcion) {
        if (!is_array($opcion)) continue;
        $predeterminado = !empty($opcion['predeterminado']);
        if ($predeterminado) continue; // solo suplemento en no predeterminadas
        $nombreOpcion = trim((string)($opcion['nombre'] ?? ''));
        if ($nombreOpcion === '') continue;
        $stSupl->execute([$idProducto, (int)$idGrupo, $nombreOpcion]);
        $totalSupl += (float)($stSupl->fetchColumn() ?? 0);
    }

    return ['precio' => round($base + $totalSupl, 6), 'porcentaje_IVA' => $pctIVA];
}

/**
 * Totales de cabecera: PVP unitario a 2 decimales × cantidad (coherente con ticket).
 */
function _totalesPedidoDesdeDetalles(PDO $db, int $idPedido): array {
    $st = $db->prepare(
        'SELECT precio_sin_IVA, porcentaje_IVA, cantidad FROM pedido_detalles WHERE id_pedido = ?'
    );
    $st->execute([$idPedido]);
    $baseImp = 0.0;
    $impIVA = 0.0;
    foreach ($st->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $pu = (float)$row['precio_sin_IVA'];
        $pct = (float)$row['porcentaje_IVA'];
        $q = max(0, (int)$row['cantidad']);
        if ($q <= 0) {
            continue;
        }
        $factor = 1.0 + $pct / 100.0;
        $pvpUnit = round($pu * $factor, 2);
        $lineTtc = round($pvpUnit * $q, 2);
        $baseLine = round($lineTtc / $factor, 2);
        $ivaLine = round($lineTtc - $baseLine, 2);
        $baseImp += $baseLine;
        $impIVA += $ivaLine;
    }

    return ['base_imponible' => round($baseImp, 2), 'importe_IVA' => round($impIVA, 2)];
}

/** Textos de producto desde BD (el cliente no debe enviarlos al guardar). */
function _textosProductoParaPedido(PDO $db, int $idProducto): array {
    $st = $db->prepare(
        'SELECT nombre_producto_pantalla, texto_imprimir_cocina FROM productos WHERE id_producto = ?'
    );
    $st->execute([$idProducto]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        throw new RuntimeException('Producto no encontrado: ' . $idProducto);
    }
    $nombre = trim((string)($row['nombre_producto_pantalla'] ?? ''));
    $txtCoc = trim((string)($row['texto_imprimir_cocina'] ?? ''));
    if ($nombre === '') {
        $nombre = 'Producto #' . $idProducto;
    }
    if ($txtCoc === '') {
        $txtCoc = $nombre;
    }

    return ['nombre_producto_pantalla' => $nombre, 'texto_imprimir_cocina' => $txtCoc];
}

// ── Obtener pedido completo ────────────────────────────────────
function endpointPedidoGet(array $payload, int $idPedido): void {
    $db = getDB();

    $cab = $db->prepare('SELECT * FROM pedido_cabecera WHERE id_pedido = ?');
    $cab->execute([$idPedido]);
    $cabRow = $cab->fetch();
    if (!$cabRow) jsonError('Pedido no encontrado', 404);

    $det = $db->prepare(
        'SELECT * FROM pedido_detalles WHERE id_pedido = ? ORDER BY orden, orden'
    );
    $det->execute([$idPedido]);
    $detalles = $det->fetchAll();

    // Deserializar JSON de opciones
    foreach ($detalles as &$d) {
        $d['opciones_elegidas'] = $d['opciones_elegidas']
            ? json_decode($d['opciones_elegidas'], true)
            : [];
    }
    unset($d);

    jsonOk(['cabecera' => $cabRow, 'detalles' => $detalles]);
}

// ── Guardar pedido (diff + impresión) ────────────────────────
function endpointPedidoGuardar(array $payload, int $idPedido): void {
    $body  = getBody();
    $lineas = $body['lineas'] ?? [];   // array de líneas enviadas por el móvil
    if (!is_array($lineas)) jsonError('Formato incorrecto');
    $terminalSerie = _terminalSerieDesdeBody($body);
    $nombreCliente = _nombreClienteDesdeBody($body);

    $db = getDB();
    $db->beginTransaction();
    try {
        $huboCambios = false;

        // Leer cabecera con bloqueo
        $st = $db->prepare('SELECT * FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE');
        $st->execute([$idPedido]);
        $cab = $st->fetch();
        if (!$cab) { $db->rollBack(); jsonError('Mesa no encontrada', 404); }

        // Verificar que el usuario tiene el bloqueo vigente
        _verificarBloqueoGuardar($cab, $payload, $terminalSerie);

        // Leer detalles actuales en BD
        $stDet = $db->prepare('SELECT * FROM pedido_detalles WHERE id_pedido = ?');
        $stDet->execute([$idPedido]);
        $detBD = [];
        foreach ($stDet->fetchAll() as $r) $detBD[$r['id_linea']] = $r;

        // Indexar líneas enviadas
        $lineasEnviadas = [];
        $nuevas         = [];
        foreach ($lineas as $l) {
            $lid = isset($l['id_linea']) ? (int)$l['id_linea'] : 0;
            if ($lid > 0) $lineasEnviadas[$lid] = $l;
            else           $nuevas[] = $l;
        }

        $trabajosImpresion = []; // [id_impresora => [lineas_escpos]]

        // ── Detectar borrados ────────────────────────────────
        foreach ($detBD as $lid => $bdRow) {
            if (!isset($lineasEnviadas[$lid])) {
                // Línea borrada
                _registrarCambio($db, $payload['sub'], 'borrar', [
                    'id_pedido' => $idPedido,
                    'id_linea'  => $lid,
                    'producto'  => $bdRow['nombre_producto_pantalla'],
                    'cantidad'  => $bdRow['cantidad'],
                ]);

                // Encolar cancelación en impresora si ya estaba impreso
                if ($bdRow['impreso']) {
                    $idImp = _idImpresora($db, (int)$bdRow['id_producto']);
                    if ($idImp > 0) {
                        $user = $payload['name'];
                        $trabajosImpresion[$idImp][] = _cancelEscPos(
                            $cab['id_mesa'], $bdRow['nombre_producto_pantalla'],
                            $bdRow['cantidad'], $user
                        );
                    }
                }

                $db->prepare('DELETE FROM pedido_detalles WHERE id_linea = ?')
                   ->execute([$lid]);
                $huboCambios = true;
            }
        }

        // ── Detectar modificaciones ──────────────────────────
        foreach ($lineasEnviadas as $lid => $envRow) {
            if (!isset($detBD[$lid])) continue; // línea nueva con id que no existe, ignorar
            $bdRow = $detBD[$lid];
            $changed = false;
            $cambios = [];

            if ((int)$envRow['cantidad'] !== (int)$bdRow['cantidad']) {
                $cambios['cantidad_old'] = $bdRow['cantidad'];
                $cambios['cantidad_new'] = $envRow['cantidad'];
                $changed = true;
            }
            $comentNew = trim($envRow['comentario'] ?? '');
            $comentOld = trim($bdRow['comentario'] ?? '');
            if ($comentNew !== $comentOld) {
                $cambios['comentario_old'] = $comentOld;
                $cambios['comentario_new'] = $comentNew;
                $changed = true;
            }
            // Mover mesa
            $mesaDest = isset($envRow['mover_a_mesa']) ? (int)$envRow['mover_a_mesa'] : 0;
            if ($mesaDest > 0) {
                $destPedidoId = _obtenerOCrearPedido($db, $mesaDest, $payload['sub'], $terminalSerie);
                $maxOrden = _maxOrden($db, $destPedidoId);
                $db->prepare(
                    'UPDATE pedido_detalles SET id_pedido=?, orden=?, impreso=0
                      WHERE id_linea=?'
                )->execute([$destPedidoId, $maxOrden + 1, $lid]);
                _registrarCambio($db, $payload['sub'], 'cambio_mesa', [
                    'id_linea'    => $lid,
                    'mesa_origen' => $cab['id_mesa'],
                    'mesa_dest'   => $mesaDest,
                ]);
                // Imprimir nota de cambio de mesa en impresora del producto
                $idImp = _idImpresora($db, (int)$bdRow['id_producto']);
                if ($idImp > 0) {
                    $trabajosImpresion[$idImp][] = _mesaCambioEscPos(
                        $cab['id_mesa'], $mesaDest,
                        $bdRow['nombre_producto_pantalla'], $bdRow['cantidad'],
                        $payload['name']
                    );
                }
                $huboCambios = true;
                continue; // no actualizar otros campos
            }

            if ($changed) {
                $cambios['id_pedido'] = $idPedido;
                $cambios['id_linea']  = $lid;
                $cambios['producto']  = $bdRow['nombre_producto_pantalla'];
                _registrarCambio($db, $payload['sub'], 'modificar', $cambios);

                $db->prepare(
                    'UPDATE pedido_detalles SET cantidad=?, comentario=? WHERE id_linea=?'
                )->execute([(int)$envRow['cantidad'], $comentNew, $lid]);
                $huboCambios = true;
            }
        }

        // ── Insertar nuevas ──────────────────────────────────
        $maxOrden   = _maxOrden($db, $idPedido);
        $horaPedido = !empty($nuevas) ? date('Y-m-d H:i:s') : null;
        $stIns = $db->prepare(
            'INSERT INTO pedido_detalles
             (id_pedido, id_producto, cantidad, comentario,
              nombre_producto_pantalla, opciones_elegidas, texto_imprimir_cocina, orden,
              precio_sin_IVA, porcentaje_IVA, importe_IVA, impreso, hora_pedido)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,0,?)'
        );
        foreach ($nuevas as $n) {
            $maxOrden++;
            $opcionesDecoded = $n['opciones_elegidas'] ?? null;
            $opcionesJson = $opcionesDecoded !== null
                ? json_encode($opcionesDecoded, JSON_UNESCAPED_UNICODE)
                : null;
            $idProdNuevo = (int)$n['id_producto'];
            $txtProd = _textosProductoParaPedido($db, $idProdNuevo);
            $calc = _calcularPrecioLinea(
                $db,
                $idProdNuevo,
                is_array($opcionesDecoded) ? $opcionesDecoded : []
            );
            $impIVALinea = round($calc['precio'] * $calc['porcentaje_IVA'] / 100, 4);
            $stIns->execute([
                $idPedido,
                $idProdNuevo,
                max(1, (int)($n['cantidad'] ?? 1)),
                trim($n['comentario'] ?? ''),
                $txtProd['nombre_producto_pantalla'],
                $opcionesJson,
                $txtProd['texto_imprimir_cocina'],
                $maxOrden,
                $calc['precio'],
                $calc['porcentaje_IVA'],
                $impIVALinea,
                $horaPedido,
            ]);
            $newId = (int)$db->lastInsertId();
            $huboCambios = true;

            _registrarCambio($db, $payload['sub'], 'añadir', [
                'id_pedido'  => $idPedido,
                'id_linea'   => $newId,
                'producto'   => $txtProd['nombre_producto_pantalla'],
                'cantidad'   => $n['cantidad'],
            ]);

            // Encolar impresión nueva
            $idImp = _idImpresora($db, $idProdNuevo);
            if ($idImp > 0) {
                $lineaEscPos = [
                    'cantidad' => max(1, (int)($n['cantidad'] ?? 1)),
                    'comentario' => trim($n['comentario'] ?? ''),
                    'opciones_elegidas' => is_array($opcionesDecoded) ? $opcionesDecoded : [],
                    'nombre_producto_pantalla' => $txtProd['nombre_producto_pantalla'],
                    'texto_imprimir_cocina' => $txtProd['texto_imprimir_cocina'],
                ];
                $trabajosImpresion[$idImp][] = _nuevaLineaEscPos(
                    $cab['id_mesa'], $lineaEscPos, $payload['name']
                );
                // Marcar como impreso
                $db->prepare('UPDATE pedido_detalles SET impreso=1 WHERE id_linea=?')
                   ->execute([$newId]);
            }
        }

        // ── Encolar trabajos de impresión ─────────────────────
        foreach ($trabajosImpresion as $idImp => $bloques) {
            $escpos = implode('', $bloques);
            $db->prepare(
                'INSERT INTO cola_impresion (id_impresora, id_pedido, contenido_escpos)
                 VALUES (?, ?, ?)'
            )->execute([$idImp, $idPedido, $escpos]);
        }

        // Si el pedido queda sin líneas, eliminar cabecera (mesa abierta sin productos).
        $stCount = $db->prepare('SELECT COUNT(*) AS c FROM pedido_detalles WHERE id_pedido = ?');
        $stCount->execute([$idPedido]);
        $sinLineas = ((int)($stCount->fetch()['c'] ?? 0)) === 0;

        if ($sinLineas) {
            $db->prepare('DELETE FROM pedido_cabecera WHERE id_pedido = ?')
               ->execute([$idPedido]);
        } else {
            // Recalcular totales (PVP unitario a 2 dec. × cantidad, coherente con ticket)
            $tot = _totalesPedidoDesdeDetalles($db, $idPedido);
            $baseImp = $tot['base_imponible'];
            $impIVA  = $tot['importe_IVA'];

            // Al guardar con líneas, liberar bloqueo. Solo tocar hora_ultima_accion si hubo cambios.
            if ($huboCambios) {
                $db->prepare(
                    'UPDATE pedido_cabecera
                        SET hora_ultima_accion = NOW(),
                            id_usuario_bloqueo = 0,
                            terminal_serie_bloqueo = NULL,
                            nombre_cliente = ?,
                            base_imponible = ?,
                            importe_IVA    = ?
                      WHERE id_pedido = ?'
                )->execute([$nombreCliente, $baseImp, $impIVA, $idPedido]);
            } else {
                $db->prepare(
                    'UPDATE pedido_cabecera
                        SET id_usuario_bloqueo = 0,
                            terminal_serie_bloqueo = NULL,
                            nombre_cliente = ?,
                            base_imponible = ?,
                            importe_IVA    = ?
                      WHERE id_pedido = ?'
                )->execute([$nombreCliente, $baseImp, $impIVA, $idPedido]);
            }
        }

        $db->commit();
        jsonOk(['guardado' => true]);
    } catch (Throwable $e) {
        $db->rollBack();
        logEvent('Error guardar pedido ' . $idPedido . ': ' . $e->getMessage(), 'error');
        jsonError('Error interno: ' . $e->getMessage(), 500);
    }
}

// ── Helpers privados ──────────────────────────────────────────
function _verificarBloqueoGuardar(array $cab, array $payload, string $terminalSerie): void {
    if ($payload['rol'] === 'admin') return;
    if (
        ($cab['terminal_serie_bloqueo'] ?? '') !== $terminalSerie ||
        !$cab['hora_bloqueo'] ||
        (strtotime($cab['hora_bloqueo']) + LOCK_TTL) <= time()
    ) {
        jsonError('No tienes el bloqueo activo de esta mesa', 409);
    }
}

function _registrarCambio(PDO $db, int $idUser, string $tipo, array $data): void {
    $db->prepare(
        'INSERT INTO registro_cambios (id_usuario, tipo_accion, json_cambio) VALUES (?,?,?)'
    )->execute([$idUser, $tipo, json_encode($data, JSON_UNESCAPED_UNICODE)]);
}

function _idImpresora(PDO $db, int $idProducto): int {
    $st = $db->prepare('SELECT id_impresora FROM productos WHERE id_producto = ?');
    $st->execute([$idProducto]);
    $row = $st->fetch();
    return $row ? (int)$row['id_impresora'] : 0;
}

function _maxOrden(PDO $db, int $idPedido): int {
    $st = $db->prepare('SELECT MAX(orden) AS m FROM pedido_detalles WHERE id_pedido = ?');
    $st->execute([$idPedido]);
    return (int)($st->fetch()['m'] ?? 0);
}

function _obtenerOCrearPedido(PDO $db, int $idMesa, int $idUser, string $terminalSerie): int {
    $st = $db->prepare('SELECT id_pedido FROM pedido_cabecera WHERE id_mesa = ? LIMIT 1');
    $st->execute([$idMesa]);
    $row = $st->fetch();
    if ($row) return (int)$row['id_pedido'];

    $db->prepare(
        'INSERT INTO pedido_cabecera
         (id_mesa, id_usuario_creacion, id_usuario_bloqueo, hora_bloqueo, hora_ultima_accion, terminal_serie_bloqueo)
         VALUES (?,?,?,NOW(),NULL,?)'
    )->execute([$idMesa, $idUser, $idUser, $terminalSerie]);
    return (int)$db->lastInsertId();
}

function _terminalSerieDesdeBody(array $body): string {
    $terminal = trim((string)($body['terminal_serie'] ?? ''));
    if ($terminal === '') jsonError('Falta terminal_serie', 400);
    if (strlen($terminal) > 120) {
        $terminal = substr($terminal, 0, 120);
    }
    return $terminal;
}

function _nombreClienteDesdeBody(array $body): ?string {
    if (!array_key_exists('nombre_cliente', $body)) return null;
    $nombre = trim((string)$body['nombre_cliente']);
    if ($nombre === '') return null;
    if (strlen($nombre) > 120) {
        $nombre = substr($nombre, 0, 120);
    }
    return $nombre;
}

// ── Generadores ESC/POS (binario como string) ─────────────────
function _escposInit(): string {
    return "\x1B\x40";  // ESC @ — inicializar
}
function _escposCut(): string {
    return "\x1D\x56\x41\x00";  // GS V A — corte parcial
}
function _escposBold(bool $on): string {
    return $on ? "\x1B\x45\x01" : "\x1B\x45\x00";
}
function _escposCenter(): string { return "\x1B\x61\x01"; }
function _escposLeft():   string { return "\x1B\x61\x00"; }

function _nuevaLineaEscPos(int $mesa, array $linea, string $camarero): string {
    $t  = _escposInit();
    $t .= _escposCenter();
    $t .= _escposBold(true) . "*** PEDIDO MESA $mesa ***\n" . _escposBold(false);
    $t .= date('d/m/Y H:i:s') . "\n";
    $t .= "Camarero: $camarero\n";
    $t .= str_repeat('-', 32) . "\n";
    $t .= _escposLeft();
    $cant   = (int)($linea['cantidad'] ?? 1);
    $nombre = $linea['texto_imprimir_cocina'] ?? $linea['nombre_producto_pantalla'];
    $t .= _escposBold(true) . " $cant x $nombre\n" . _escposBold(false);
    if (!empty($linea['opciones_elegidas'])) {
        foreach ((array)$linea['opciones_elegidas'] as $grupo => $opcion) {
            if (is_array($opcion)) {
                $nombre = (string)($opcion['nombre'] ?? '');
            } else {
                $nombre = (string)$opcion;
            }
            if ($nombre !== '') {
                $t .= "   >> $nombre\n";
            }
        }
    }
    if (!empty(trim($linea['comentario'] ?? ''))) {
        $t .= "   Nota: " . trim($linea['comentario']) . "\n";
    }
    $t .= str_repeat('-', 32) . "\n";
    $t .= _escposCut();
    return $t;
}

function _cancelEscPos(int $mesa, string $producto, int $cant, string $camarero): string {
    $t  = _escposInit();
    $t .= _escposCenter();
    $t .= _escposBold(true) . "*** CANCELACION MESA $mesa ***\n" . _escposBold(false);
    $t .= date('d/m/Y H:i:s') . "\n";
    $t .= "Camarero: $camarero\n";
    $t .= str_repeat('-', 32) . "\n";
    $t .= _escposLeft();
    $t .= _escposBold(true) . " CANCELAR: $cant x $producto\n" . _escposBold(false);
    $t .= str_repeat('-', 32) . "\n";
    $t .= _escposCut();
    return $t;
}

function _mesaCambioEscPos(int $mesaO, int $mesaD, string $prod, int $cant, string $cam): string {
    $t  = _escposInit();
    $t .= _escposCenter();
    $t .= _escposBold(true) . "*** CAMBIO DE MESA ***\n" . _escposBold(false);
    $t .= date('d/m/Y H:i:s') . "\n";
    $t .= "Camarero: $cam\n";
    $t .= str_repeat('-', 32) . "\n";
    $t .= _escposLeft();
    $t .= " $cant x $prod\n";
    $t .= " Mesa $mesaO  -->  Mesa $mesaD\n";
    $t .= str_repeat('-', 32) . "\n";
    $t .= _escposCut();
    return $t;
}
