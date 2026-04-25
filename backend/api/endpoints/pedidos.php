<?php
// backend/api/endpoints/pedidos.php
declare(strict_types=1);

// ── Obtener pedido completo ────────────────────────────────────
function endpointPedidoGet(array $payload, int $idPedido): void {
    $db = getDB();

    $cab = $db->prepare('SELECT * FROM pedido_cabecera WHERE id_pedido = ?');
    $cab->execute([$idPedido]);
    $cabRow = $cab->fetch();
    if (!$cabRow) jsonError('Pedido no encontrado', 404);

    $det = $db->prepare(
        'SELECT * FROM pedido_detalles WHERE id_pedido = ? ORDER BY orden, id_linea'
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

    $db = getDB();
    $db->beginTransaction();
    try {
        // Leer cabecera con bloqueo
        $st = $db->prepare('SELECT * FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE');
        $st->execute([$idPedido]);
        $cab = $st->fetch();
        if (!$cab) { $db->rollBack(); jsonError('Mesa no encontrada', 404); }

        // Verificar que el usuario tiene el bloqueo vigente
        _verificarBloqueoGuardar($cab, $payload);

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
                    'producto'  => $bdRow['nombre_producto'],
                    'cantidad'  => $bdRow['cantidad'],
                ]);

                // Encolar cancelación en impresora si ya estaba impreso
                if ($bdRow['impreso']) {
                    $idImp = _idImpresora($db, (int)$bdRow['id_producto']);
                    if ($idImp > 0) {
                        $user = $payload['name'];
                        $trabajosImpresion[$idImp][] = _cancelEscPos(
                            $cab['id_mesa'], $bdRow['nombre_producto'],
                            $bdRow['cantidad'], $user
                        );
                    }
                }

                $db->prepare('DELETE FROM pedido_detalles WHERE id_linea = ?')
                   ->execute([$lid]);
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
                ]);
                // Imprimir nota de cambio de mesa en impresora del producto
                $idImp = _idImpresora($db, (int)$bdRow['id_producto']);
                if ($idImp > 0) {
                    $trabajosImpresion[$idImp][] = _mesaCambioEscPos(
                        $cab['id_mesa'], $mesaDest,
                        $bdRow['nombre_producto'], $bdRow['cantidad'],
                        $payload['name']
                    );
                }
                continue; // no actualizar otros campos
            }

            if ($changed) {
                $cambios['id_pedido'] = $idPedido;
                $cambios['id_linea']  = $lid;
                $cambios['producto']  = $bdRow['nombre_producto'];
                _registrarCambio($db, $payload['sub'], 'modificar', $cambios);

                $db->prepare(
                    'UPDATE pedido_detalles SET cantidad=?, comentario=? WHERE id_linea=?'
                )->execute([(int)$envRow['cantidad'], $comentNew, $lid]);
            }
        }

        // ── Insertar nuevas ──────────────────────────────────
        $maxOrden = _maxOrden($db, $idPedido);
        $stIns = $db->prepare(
            'INSERT INTO pedido_detalles
             (id_pedido, id_producto, cantidad, comentario,
              nombre_producto, opciones_elegidas, texto_imprimir, orden, impreso)
             VALUES (?,?,?,?,?,?,?,?,0)'
        );
        foreach ($nuevas as $n) {
            $maxOrden++;
            $opcionesJson = isset($n['opciones_elegidas'])
                ? json_encode($n['opciones_elegidas'], JSON_UNESCAPED_UNICODE)
                : null;
            $stIns->execute([
                $idPedido,
                (int)$n['id_producto'],
                max(1, (int)($n['cantidad'] ?? 1)),
                trim($n['comentario'] ?? ''),
                $n['nombre_producto'],
                $opcionesJson,
                $n['texto_imprimir'] ?? $n['nombre_producto'],
                $maxOrden,
            ]);
            $newId = (int)$db->lastInsertId();

            _registrarCambio($db, $payload['sub'], 'añadir', [
                'id_pedido'  => $idPedido,
                'id_linea'   => $newId,
                'producto'   => $n['nombre_producto'],
                'cantidad'   => $n['cantidad'],
            ]);

            // Encolar impresión nueva
            $idImp = _idImpresora($db, (int)$n['id_producto']);
            if ($idImp > 0) {
                $trabajosImpresion[$idImp][] = _nuevaLineaEscPos(
                    $cab['id_mesa'], $n, $payload['name']
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

        // Actualizar hora última acción
        $db->prepare('UPDATE pedido_cabecera SET hora_ultima_accion=NOW() WHERE id_pedido=?')
           ->execute([$idPedido]);

        $db->commit();
        jsonOk(['guardado' => true]);
    } catch (Throwable $e) {
        $db->rollBack();
        logEvent('Error guardar pedido ' . $idPedido . ': ' . $e->getMessage(), 'error');
        jsonError('Error interno: ' . $e->getMessage(), 500);
    }
}

// ── Helpers privados ──────────────────────────────────────────
function _verificarBloqueoGuardar(array $cab, array $payload): void {
    if ($payload['rol'] === 'admin') return;
    if (
        (int)$cab['id_usuario_bloqueo'] !== (int)$payload['sub'] ||
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
        'INSERT INTO pedido_cabecera (id_mesa, id_usuario_creacion, id_usuario_bloqueo, hora_bloqueo)
         VALUES (?,?,?,NOW())'
    )->execute([$idMesa, $idUser, $idUser]);
    return (int)$db->lastInsertId();
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
    $nombre = $linea['texto_imprimir'] ?? $linea['nombre_producto'];
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
