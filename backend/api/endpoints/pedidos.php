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
    $terminalSerie = terminalSerieDesdeBody($body);
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

        $trabajosImpresion = []; // [id_impresora => [bloques escpos]]
        $pendientesPorImpresora = []; // [id_impresora => líneas a agrupar en un ticket]

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
                if ((int)$cab['id_mesa'] === $mesaDest) {
                    jsonError('La mesa destino es la misma que la de origen', 400);
                }
                verificarMesaDestinoNoBloqueadaPorOtro($db, $mesaDest, $terminalSerie, true);
                $destPedidoId = _obtenerOCrearPedido($db, $mesaDest, $payload['sub']);
                $maxOrden = _maxOrden($db, $destPedidoId);
                $db->prepare(
                    'UPDATE pedido_detalles SET id_pedido=?, orden=?, impreso=0
                      WHERE id_linea=?'
                )->execute([$destPedidoId, $maxOrden + 1, $lid]);
                _registrarCambio($db, $payload['sub'], 'cambio_mesa', [
                    'id_linea'    => $lid,
                    'mesa_origen' => $cab['id_mesa'],
                    'mesa_dest'   => $mesaDest,
                    'producto'    => $bdRow['nombre_producto_pantalla'],
                    'cantidad'    => (int)$bdRow['cantidad'],
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

                if ((int)$bdRow['impreso'] === 1) {
                    $db->prepare(
                        'UPDATE pedido_detalles
                            SET cantidad=?, comentario=?, modificado_servicio=1, servido=?
                          WHERE id_linea=?'
                    )->execute([
                        (int)$envRow['cantidad'],
                        $comentNew,
                        '2000-01-01 00:00:00',
                        $lid,
                    ]);
                } else {
                    $db->prepare(
                        'UPDATE pedido_detalles SET cantidad=?, comentario=? WHERE id_linea=?'
                    )->execute([(int)$envRow['cantidad'], $comentNew, $lid]);
                }
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

            $idImp = _idImpresora($db, $idProdNuevo);
            if ($idImp > 0) {
                $pendientesPorImpresora[$idImp][] = [
                    'id_producto'             => $idProdNuevo,
                    'cantidad'                => max(1, (int)($n['cantidad'] ?? 1)),
                    'comentario'              => trim($n['comentario'] ?? ''),
                    'opciones_elegidas'       => is_array($opcionesDecoded) ? $opcionesDecoded : [],
                    'nombre_producto_pantalla'=> $txtProd['nombre_producto_pantalla'],
                    'texto_imprimir_cocina'   => $txtProd['texto_imprimir_cocina'],
                ];
                $db->prepare(
                    'UPDATE pedido_detalles SET impreso=1, servido=? WHERE id_linea=?'
                )->execute(['2000-01-01 00:00:00', $newId]);
            }
        }

        if ($pendientesPorImpresora !== []) {
            foreach ($pendientesPorImpresora as $idImp => $lineasPend) {
                $agrupadas = _agruparLineasImpresion($lineasPend);
                if ($agrupadas === []) {
                    continue;
                }
                $trabajosImpresion[$idImp][] = _ticketNuevasLineasEscPos(
                    $cab['id_mesa'],
                    $agrupadas,
                    $payload['name']
                );
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

function _obtenerOCrearPedido(PDO $db, int $idMesa, int $idUser): int {
    $st = $db->prepare('SELECT id_pedido FROM pedido_cabecera WHERE id_mesa = ? LIMIT 1');
    $st->execute([$idMesa]);
    $row = $st->fetch();
    if ($row) return (int)$row['id_pedido'];

    $db->prepare(
        'INSERT INTO pedido_cabecera
         (id_mesa, id_usuario_creacion, id_usuario_bloqueo, hora_bloqueo, hora_ultima_accion, terminal_serie_bloqueo)
         VALUES (?, ?, 0, NULL, NOW(), NULL)'
    )->execute([$idMesa, $idUser]);
    return (int)$db->lastInsertId();
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

function _opcionesCanonicalImp(array $opciones): array {
    if ($opciones === []) {
        return [];
    }
    ksort($opciones);
    $out = [];
    foreach ($opciones as $g => $op) {
        if (!is_array($op)) {
            continue;
        }
        $out[(string)(int)$g] = [
            'nombre'         => trim((string)($op['nombre'] ?? '')),
            'predeterminado' => (int)($op['predeterminado'] ?? 0),
        ];
    }
    return $out;
}

function _claveAgrupacionImpresion(array $linea): string {
    $opciones = $linea['opciones_elegidas'] ?? [];
    if (!is_array($opciones)) {
        $opciones = [];
    }
    return (int)($linea['id_producto'] ?? 0) . "\0" . trim((string)($linea['comentario'] ?? ''))
        . "\0" . json_encode(_opcionesCanonicalImp($opciones), JSON_UNESCAPED_UNICODE);
}

/** @param list<array<string, mixed>> $lineas */
function _agruparLineasImpresion(array $lineas): array {
    $grupos = [];
    $orden = [];
    foreach ($lineas as $linea) {
        $key = _claveAgrupacionImpresion($linea);
        $cant = (int)($linea['cantidad'] ?? 1);
        if (!isset($grupos[$key])) {
            $grupos[$key] = $linea;
            $grupos[$key]['cantidad'] = $cant;
            $orden[] = $key;
        } else {
            $grupos[$key]['cantidad'] += $cant;
        }
    }
  return array_map(static fn(string $k) => $grupos[$k], $orden);
}

function _lineaProductoEscPosBody(array $linea): string {
    $t = '';
    $cant   = (int)($linea['cantidad'] ?? 1);
    $nombre = $linea['texto_imprimir_cocina'] ?? $linea['nombre_producto_pantalla'] ?? '';
    $t .= _escposBold(true) . " $cant x $nombre\n" . _escposBold(false);
    if (!empty($linea['opciones_elegidas'])) {
        foreach ((array)$linea['opciones_elegidas'] as $opcion) {
            if (is_array($opcion)) {
                $nomOp = (string)($opcion['nombre'] ?? '');
            } else {
                $nomOp = (string)$opcion;
            }
            if ($nomOp !== '') {
                $t .= "   >> $nomOp\n";
            }
        }
    }
    if (!empty(trim($linea['comentario'] ?? ''))) {
        $t .= '   Nota: ' . trim($linea['comentario']) . "\n";
    }
    return $t;
}

/** @param list<array<string, mixed>> $lineasAgrupadas */
function _ticketNuevasLineasEscPos(int $mesa, array $lineasAgrupadas, string $camarero): string {
    if ($lineasAgrupadas === []) {
        return '';
    }
    $t  = _escposInit();
    $t .= _escposCenter();
    $t .= _escposBold(true) . "*** PEDIDO MESA $mesa ***\n" . _escposBold(false);
    $t .= date('d/m/Y H:i:s') . "\n";
    $t .= "Camarero: $camarero\n";
    $t .= str_repeat('-', 32) . "\n";
    $t .= _escposLeft();
    foreach ($lineasAgrupadas as $linea) {
        $t .= _lineaProductoEscPosBody($linea);
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

function _notaLibreEscPos(int $mesa, string $texto, float $pvp, string $camarero): string {
    $t  = _escposInit();
    $t .= _escposCenter();
    $t .= _escposBold(true) . "*** PEDIDO MESA $mesa ***\n" . _escposBold(false);
    $t .= date('d/m/Y H:i:s') . "\n";
    $t .= "Camarero: $camarero\n";
    $t .= str_repeat('-', 32) . "\n";
    $t .= _escposLeft();
    $t .= _escposBold(true) . " $texto\n" . _escposBold(false);
    if ($pvp > 0) {
        $t .= sprintf("   PVP: %.2f Eur\n", $pvp);
    }
    $t .= str_repeat('-', 32) . "\n";
    $t .= _escposCut();
    return $t;
}

// ── Crear nota / artículo libre ───────────────────────────────
// id_producto = 0: no existe en catálogo, nombre y precio libres.
// No hay FK de pedido_detalles.id_producto → productos, es seguro.
function endpointNotaLibre(array $payload, int $idPedido): void {
    $body          = getBody();
    $texto         = trim((string)($body['texto'] ?? ''));
    if ($texto === '') jsonError('El texto no puede estar vacío', 400);
    if (mb_strlen($texto) > 200) $texto = mb_substr($texto, 0, 200);

    $pvpConIva   = max(0.0, (float)($body['pvp_con_iva']  ?? 0));
    $idImpresora = (int)($body['id_impresora'] ?? 0);
    $terminalSerie = terminalSerieDesdeBody($body);

    // PVP indicado IVA 10 % incluido → desglosar
    $pct         = 10.0;
    $factor      = 1.0 + $pct / 100.0;
    $precioSinIva = $pvpConIva > 0 ? round($pvpConIva / $factor, 6) : 0.0;
    $importeIva   = round($precioSinIva * $pct / 100, 4);

    $db = getDB();
    $db->beginTransaction();
    try {
        $st = $db->prepare('SELECT * FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE');
        $st->execute([$idPedido]);
        $cab = $st->fetch();
        if (!$cab) { $db->rollBack(); jsonError('Mesa no encontrada', 404); }
        _verificarBloqueoGuardar($cab, $payload, $terminalSerie);

        $stMax = $db->prepare('SELECT COALESCE(MAX(orden), 0) AS m FROM pedido_detalles WHERE id_pedido = ?');
        $stMax->execute([$idPedido]);
        $orden = (int)($stMax->fetch()['m'] ?? 0) + 1;

        $db->prepare(
            'INSERT INTO pedido_detalles
             (id_pedido, id_producto, cantidad, comentario,
              nombre_producto_pantalla, opciones_elegidas, texto_imprimir_cocina, orden,
              precio_sin_IVA, porcentaje_IVA, importe_IVA, impreso, hora_pedido)
             VALUES (?, 0, 1, \'\', ?, NULL, ?, ?, ?, ?, ?, 0, NOW())'
        )->execute([
            $idPedido, $texto, $texto, $orden,
            $precioSinIva, $pct, $importeIva,
        ]);
        $newId = (int)$db->lastInsertId();

        _registrarCambio($db, $payload['sub'], 'nota_libre', [
            'id_pedido' => $idPedido,
            'id_linea'  => $newId,
            'texto'     => $texto,
            'pvp'       => $pvpConIva,
        ]);

        if ($idImpresora > 0) {
            $escpos = _notaLibreEscPos($cab['id_mesa'], $texto, $pvpConIva, $payload['name']);
            $db->prepare(
                'INSERT INTO cola_impresion (id_impresora, id_pedido, contenido_escpos) VALUES (?,?,?)'
            )->execute([$idImpresora, $idPedido, $escpos]);
            $db->prepare('UPDATE pedido_detalles SET impreso=1 WHERE id_linea=?')->execute([$newId]);
        }

        // Recalcular totales de la cabecera
        $tot = _totalesPedidoDesdeDetalles($db, $idPedido);
        $db->prepare(
            'UPDATE pedido_cabecera
                SET hora_ultima_accion=NOW(), base_imponible=?, importe_IVA=?
              WHERE id_pedido=?'
        )->execute([$tot['base_imponible'], $tot['importe_IVA'], $idPedido]);

        $db->commit();
        jsonOk(['id_linea' => $newId]);
    } catch (Throwable $e) {
        $db->rollBack();
        logEvent('Error nota_libre ' . $idPedido . ': ' . $e->getMessage(), 'error');
        jsonError('Error interno: ' . $e->getMessage(), 500);
    }
}

// ── Editar nota / artículo libre ─────────────────────────────
function endpointNotaLibreEditar(array $payload, int $idPedido, int $idLinea): void {
    $body  = getBody();
    $texto = trim((string)($body['texto'] ?? ''));
    if ($texto === '') jsonError('El texto no puede estar vacío', 400);
    if (mb_strlen($texto) > 200) $texto = mb_substr($texto, 0, 200);

    $pvpConIva     = max(0.0, (float)($body['pvp_con_iva'] ?? 0));
    $terminalSerie = terminalSerieDesdeBody($body);

    $pct          = 10.0;
    $factor       = 1.0 + $pct / 100.0;
    $precioSinIva = $pvpConIva > 0 ? round($pvpConIva / $factor, 6) : 0.0;
    $importeIva   = round($precioSinIva * $pct / 100, 4);

    $db = getDB();
    $db->beginTransaction();
    try {
        $st = $db->prepare('SELECT * FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE');
        $st->execute([$idPedido]);
        $cab = $st->fetch();
        if (!$cab) { $db->rollBack(); jsonError('Mesa no encontrada', 404); }
        _verificarBloqueoGuardar($cab, $payload, $terminalSerie);

        // Verificar que la línea pertenece al pedido y es nota libre
        $stLinea = $db->prepare(
            'SELECT id_linea FROM pedido_detalles WHERE id_linea=? AND id_pedido=? AND id_producto=0'
        );
        $stLinea->execute([$idLinea, $idPedido]);
        if (!$stLinea->fetch()) {
            $db->rollBack();
            jsonError('Línea no encontrada o no es nota libre', 404);
        }

        $db->prepare(
            'UPDATE pedido_detalles
                SET nombre_producto_pantalla=?, texto_imprimir_cocina=?,
                    precio_sin_IVA=?, porcentaje_IVA=?, importe_IVA=?
              WHERE id_linea=?'
        )->execute([$texto, $texto, $precioSinIva, $pct, $importeIva, $idLinea]);

        _registrarCambio($db, $payload['sub'], 'nota_libre_editar', [
            'id_linea' => $idLinea,
            'texto'    => $texto,
            'pvp'      => $pvpConIva,
        ]);

        $tot = _totalesPedidoDesdeDetalles($db, $idPedido);
        $db->prepare(
            'UPDATE pedido_cabecera
                SET hora_ultima_accion=NOW(), base_imponible=?, importe_IVA=?
              WHERE id_pedido=?'
        )->execute([$tot['base_imponible'], $tot['importe_IVA'], $idPedido]);

        $db->commit();
        jsonOk(['actualizado' => true]);
    } catch (Throwable $e) {
        $db->rollBack();
        logEvent('Error nota_libre_editar ' . $idLinea . ': ' . $e->getMessage(), 'error');
        jsonError('Error interno: ' . $e->getMessage(), 500);
    }
}
