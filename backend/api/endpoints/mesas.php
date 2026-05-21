<?php
// backend/api/endpoints/mesas.php
declare(strict_types=1);

// ── Listar mesas abiertas ─────────────────────────────────────
function endpointMesasListar(array $payload): void {
    $db = getDB();
    $rows = $db->query(
        'SELECT pc.id_pedido, pc.id_mesa, pc.hora_creacion, pc.id_usuario_creacion,
                pc.hora_ultima_accion, pc.estado_mesa, pc.id_usuario_bloqueo, pc.hora_bloqueo,
                pc.terminal_serie_bloqueo, pc.nombre_cliente,
                ROUND(COALESCE(pc.base_imponible, 0) + COALESCE(pc.importe_IVA, 0), 2) AS total_importe,
                (SELECT COUNT(*) FROM pedido_detalles pd WHERE pd.id_pedido = pc.id_pedido) AS total_lineas
           FROM pedido_cabecera pc
          ORDER BY pc.id_mesa'
    )->fetchAll();
    jsonOk($rows);
}

// ── Abrir nueva mesa ──────────────────────────────────────────
function endpointMesaAbrir(array $payload): void {
    $body  = getBody();
    $mesa  = (int)($body['id_mesa'] ?? 0);
    if ($mesa <= 0) jsonError('Número de mesa inválido');
    $terminalSerie = terminalSerieDesdeBody($body);

    $db = getDB();

    // Verificar si ya existe mesa abierta con ese número
    $st = $db->prepare('SELECT id_pedido FROM pedido_cabecera WHERE id_mesa = ? LIMIT 1');
    $st->execute([$mesa]);
    if ($st->fetch()) jsonError("La mesa $mesa ya está abierta");

    $db->beginTransaction();
    try {
        verificarTerminalSinOtraMesaAbierta($db, $terminalSerie);
        $st = $db->prepare(
            'INSERT INTO pedido_cabecera
             (id_mesa, id_usuario_creacion, id_usuario_bloqueo, hora_bloqueo, hora_ultima_accion, terminal_serie_bloqueo)
             VALUES (?, ?, ?, NOW(), NOW(), ?)'
        );
        $st->execute([$mesa, $payload['sub'], $payload['sub'], $terminalSerie]);
        $id = $db->lastInsertId();
        $db->commit();
        jsonOk(['id_pedido' => $id]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error al abrir mesa: ' . $e->getMessage(), 500);
    }
}

// ── Bloquear mesa ─────────────────────────────────────────────
function endpointMesaBloquear(array $payload, int $idPedido): void {
    $body = getBody();
    $terminalSerie = terminalSerieDesdeBody($body);
    $db = getDB();
    $db->beginTransaction();
    try {
        // SELECT FOR UPDATE para atomicidad
        $st = $db->prepare(
            'SELECT id_usuario_bloqueo, hora_bloqueo, terminal_serie_bloqueo
               FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE'
        );
        $st->execute([$idPedido]);
        $row = $st->fetch();
        if (!$row) { $db->rollBack(); jsonError('Mesa no encontrada', 404); }

        $bloqueoPorOtro = !empty($row['terminal_serie_bloqueo']) &&
                          $row['terminal_serie_bloqueo'] !== $terminalSerie &&
                          $row['hora_bloqueo'] &&
                          (strtotime($row['hora_bloqueo']) + LOCK_TTL) > time();

        if ($bloqueoPorOtro) {
            $db->rollBack();
            $terminalBloqueador = $row['terminal_serie_bloqueo'] ?? 'Desconocido';
            jsonError("Mesa bloqueada por terminal $terminalBloqueador", 409);
        }

        verificarTerminalSinOtraMesaAbierta($db, $terminalSerie, $idPedido);

        $db->prepare(
            'UPDATE pedido_cabecera SET id_usuario_bloqueo=?, hora_bloqueo=NOW(), terminal_serie_bloqueo=?
              WHERE id_pedido=?'
        )->execute([$payload['sub'], $terminalSerie, $idPedido]);

        $db->commit();
        jsonOk(['bloqueado' => true]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error de bloqueo: ' . $e->getMessage(), 500);
    }
}

// ── Desbloquear al salir sin guardar ──────────────────────────
function endpointMesaDesbloquear(array $payload, int $idPedido): void {
    $body = getBody();
    $terminalSerie = terminalSerieDesdeBody($body);
    $db = getDB();
    liberarBloqueoMesaTerminal($db, $idPedido, $terminalSerie);
    jsonOk(['desbloqueado' => true]);
}

// ── Ping de bloqueo (cada minuto) ─────────────────────────────
function endpointMesaPing(array $payload, int $idPedido): void {
    $body = getBody();
    $terminalSerie = terminalSerieDesdeBody($body);
    $db = getDB();
    $st = $db->prepare(
        'UPDATE pedido_cabecera
            SET hora_bloqueo = NOW()
          WHERE id_pedido = ? AND terminal_serie_bloqueo = ?'
    );
    $st->execute([$idPedido, $terminalSerie]);
    if ($st->rowCount() === 0) jsonError('No tienes el bloqueo de esta mesa', 409);
    jsonOk(['ping' => 'ok']);
}

// ── Expulsar usuario (solo admin/supervisor) ──────────────────
function endpointMesaExpulsar(array $payload, int $idPedido): void {
    requireRole($payload, ['admin', 'supervisor']);
    $body = getBody();
    $terminalSerie = terminalSerieDesdeBody($body);
    $db = getDB();
    verificarTerminalSinOtraMesaAbierta($db, $terminalSerie, $idPedido);
    $db->prepare(
        'UPDATE pedido_cabecera SET id_usuario_bloqueo=?, hora_bloqueo=NOW(), terminal_serie_bloqueo=?
          WHERE id_pedido=?'
    )->execute([$payload['sub'], $terminalSerie, $idPedido]);
    jsonOk(['expulsado' => true]);
}

// ── Cerrar mesa (mover a histórico) ──────────────────────────
function endpointMesaCerrar(array $payload, int $idPedido): void {
    $body = getBody();
    $terminalSerie = terminalSerieDesdeBody($body);
    $db = getDB();
    $db->beginTransaction();
    try {
        // Verificar bloqueo
        $st = $db->prepare('SELECT * FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE');
        $st->execute([$idPedido]);
        $cab = $st->fetch();
        if (!$cab) { $db->rollBack(); jsonError('Mesa no encontrada', 404); }

        _verificarBloqueo($cab, $payload, $terminalSerie);

        // Copiar a histórico
        $db->prepare(
            'INSERT INTO pedido_cabecera_historico
             SELECT *, NOW() AS hora_cierre FROM pedido_cabecera WHERE id_pedido = ?'
        )->execute([$idPedido]);

        $db->prepare(
            'INSERT INTO pedido_detalles_historico
             SELECT *, ? AS id_pedido_historico FROM pedido_detalles WHERE id_pedido = ?'
        )->execute([$idPedido, $idPedido]);

        // Borrar activo
        $db->prepare('DELETE FROM pedido_detalles  WHERE id_pedido = ?')->execute([$idPedido]);
        $db->prepare('DELETE FROM pedido_cabecera  WHERE id_pedido = ?')->execute([$idPedido]);

        $db->commit();
        jsonOk(['cerrado' => true]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error al cerrar mesa: ' . $e->getMessage(), 500);
    }
}

// ── Helper privado: verifica que el payload tiene el bloqueo ─
function _verificarBloqueo(array $cab, array $payload, string $terminalSerie): void {
    if ($payload['rol'] === 'admin') return; // admin siempre puede
    if (
        ($cab['terminal_serie_bloqueo'] ?? '') !== $terminalSerie ||
        !$cab['hora_bloqueo'] ||
        (strtotime($cab['hora_bloqueo']) + LOCK_TTL) <= time()
    ) {
        jsonError('No tienes el bloqueo de esta mesa o ha expirado', 409);
    }
}

// ── Traspasar mesa completa a otra ────────────────────────────
function endpointMesaTraspasar(array $payload, int $idPedido): void {
    requireRole($payload, ['admin', 'supervisor']);
    $body = getBody();
    $idMesaDestino = (int)($body['id_mesa_destino'] ?? 0);
    if ($idMesaDestino <= 0) jsonError('Mesa destino inválida', 400);
    $terminalSerie = terminalSerieDesdeBody($body);

    $db = getDB();
    $db->beginTransaction();
    try {
        // Obtener cabecera de la mesa origen
        $stCab = $db->prepare('SELECT * FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE');
        $stCab->execute([$idPedido]);
        $cab = $stCab->fetch();
        if (!$cab) { $db->rollBack(); jsonError('Mesa no encontrada', 404); }

        $idMesaOrigen = (int)$cab['id_mesa'];
        if ($idMesaOrigen === $idMesaDestino) {
            $db->rollBack();
            jsonError('La mesa destino es la misma que la de origen', 400);
        }

        // Contar líneas de la mesa origen
        $stCount = $db->prepare('SELECT COUNT(*) AS c FROM pedido_detalles WHERE id_pedido = ?');
        $stCount->execute([$idPedido]);
        $numLineas = (int)($stCount->fetch()['c'] ?? 0);
        if ($numLineas === 0) {
            $db->rollBack();
            jsonError('La mesa de origen no tiene líneas para traspasar', 400);
        }

        // Obtener o crear el pedido de la mesa destino (bloquear fila si ya existe)
        $stDest = $db->prepare(
            'SELECT id_pedido FROM pedido_cabecera WHERE id_mesa = ? LIMIT 1 FOR UPDATE'
        );
        $stDest->execute([$idMesaDestino]);
        $destRow = $stDest->fetch();

        verificarMesaDestinoNoBloqueadaPorOtro($db, $idMesaDestino, $terminalSerie, true);

        if ($destRow) {
            $idPedidoDestino = (int)$destRow['id_pedido'];
        } else {
            $db->prepare(
                'INSERT INTO pedido_cabecera
                 (id_mesa, id_usuario_creacion, id_usuario_bloqueo, hora_bloqueo, hora_ultima_accion, nombre_cliente)
                 VALUES (?, ?, 0, NULL, NOW(), ?)'
            )->execute([$idMesaDestino, $payload['sub'], $cab['nombre_cliente']]);
            $idPedidoDestino = (int)$db->lastInsertId();
        }

        // Calcular el orden máximo actual en la mesa destino
        $stMax = $db->prepare('SELECT COALESCE(MAX(orden), 0) AS m FROM pedido_detalles WHERE id_pedido = ?');
        $stMax->execute([$idPedidoDestino]);
        $maxOrden = (int)($stMax->fetch()['m'] ?? 0);

        // Mover todas las líneas de origen a destino
        $stLineas = $db->prepare('SELECT id_linea FROM pedido_detalles WHERE id_pedido = ? ORDER BY orden');
        $stLineas->execute([$idPedido]);
        $stUpd = $db->prepare('UPDATE pedido_detalles SET id_pedido=?, orden=?, impreso=0 WHERE id_linea=?');
        foreach ($stLineas->fetchAll(PDO::FETCH_ASSOC) as $linea) {
            $maxOrden++;
            $stUpd->execute([$idPedidoDestino, $maxOrden, (int)$linea['id_linea']]);
        }

        // Recalcular totales de la mesa destino
        $stTot = $db->prepare(
            'SELECT precio_sin_IVA, porcentaje_IVA, cantidad FROM pedido_detalles WHERE id_pedido = ?'
        );
        $stTot->execute([$idPedidoDestino]);
        $baseImp = 0.0;
        $impIVA  = 0.0;
        foreach ($stTot->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $pu  = (float)$row['precio_sin_IVA'];
            $pct = (float)$row['porcentaje_IVA'];
            $q   = max(0, (int)$row['cantidad']);
            if ($q <= 0) continue;
            $factor  = 1.0 + $pct / 100.0;
            $pvpUnit = round($pu * $factor, 2);
            $lineTtc = round($pvpUnit * $q, 2);
            $baseLine = round($lineTtc / $factor, 2);
            $ivaLine  = round($lineTtc - $baseLine, 2);
            $baseImp += $baseLine;
            $impIVA  += $ivaLine;
        }
        $db->prepare(
            'UPDATE pedido_cabecera SET base_imponible=?, importe_IVA=?, hora_ultima_accion=NOW()
              WHERE id_pedido=?'
        )->execute([round($baseImp, 2), round($impIVA, 2), $idPedidoDestino]);

        // Registrar el traspaso en el log de cambios
        $db->prepare(
            'INSERT INTO registro_cambios (id_usuario, tipo_accion, json_cambio) VALUES (?,?,?)'
        )->execute([
            $payload['sub'],
            'traspaso_mesa',
            json_encode([
                'mesa_origen'   => $idMesaOrigen,
                'mesa_destino'  => $idMesaDestino,
                'num_lineas'    => $numLineas,
            ], JSON_UNESCAPED_UNICODE),
        ]);

        // Eliminar la cabecera de la mesa origen (ya sin líneas)
        $db->prepare('DELETE FROM pedido_cabecera WHERE id_pedido = ?')->execute([$idPedido]);

        $db->commit();
        jsonOk(['traspasado' => true, 'mesa_destino' => $idMesaDestino, 'num_lineas' => $numLineas]);
    } catch (Throwable $e) {
        $db->rollBack();
        logEvent('Error traspasar mesa ' . $idPedido . ': ' . $e->getMessage(), 'error');
        jsonError('Error interno: ' . $e->getMessage(), 500);
    }
}

// ── Movimientos de una mesa (solo admin) ──────────────────────
function endpointMesaMovimientos(array $payload, int $idPedido): void {
    requireRole($payload, ['admin']);

    $db = getDB();
    $st = $db->prepare('SELECT id_mesa FROM pedido_cabecera WHERE id_pedido = ? LIMIT 1');
    $st->execute([$idPedido]);
    $cab = $st->fetch(PDO::FETCH_ASSOC);
    if (!$cab) {
        jsonError('Mesa no encontrada', 404);
    }
    $idMesa = (int)$cab['id_mesa'];

    $st = $db->prepare(
        'SELECT r.id_linea, r.fecha_hora, r.id_usuario, r.tipo_accion, r.json_cambio,
                u.nombre_usuario
           FROM registro_cambios r
           LEFT JOIN usuarios u ON u.id_usuario = r.id_usuario
          WHERE (
                (r.tipo_accion IN (\'añadir\', \'borrar\', \'nota_libre\')
                 AND CAST(JSON_UNQUOTE(JSON_EXTRACT(r.json_cambio, \'$.id_pedido\')) AS UNSIGNED) = ?)
             OR (r.tipo_accion = \'cambio_mesa\'
                 AND (
                      CAST(JSON_UNQUOTE(JSON_EXTRACT(r.json_cambio, \'$.mesa_origen\')) AS UNSIGNED) = ?
                   OR CAST(JSON_UNQUOTE(JSON_EXTRACT(r.json_cambio, \'$.mesa_dest\')) AS UNSIGNED) = ?
                 ))
             OR (r.tipo_accion = \'traspaso_mesa\'
                 AND (
                      CAST(JSON_UNQUOTE(JSON_EXTRACT(r.json_cambio, \'$.mesa_origen\')) AS UNSIGNED) = ?
                   OR CAST(JSON_UNQUOTE(JSON_EXTRACT(r.json_cambio, \'$.mesa_destino\')) AS UNSIGNED) = ?
                 ))
          )
          ORDER BY r.fecha_hora DESC
          LIMIT 500'
    );
    $st->execute([$idPedido, $idMesa, $idMesa, $idMesa, $idMesa]);
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);

    $stDet = $db->prepare(
        'SELECT nombre_producto_pantalla, cantidad FROM pedido_detalles WHERE id_linea = ?'
    );

    $nuevos = [];
    $eliminados = [];
    $enviados = [];
    $recibidos = [];

    foreach ($rows as $r) {
        $data = json_decode((string)$r['json_cambio'], true);
        if (!is_array($data)) {
            $data = [];
        }
        $item = _movimientoItemDesdeRegistro($r, $data, $stDet);
        $tipo = (string)$r['tipo_accion'];

        if ($tipo === 'añadir' || $tipo === 'nota_libre') {
            $nuevos[] = $item;
            continue;
        }
        if ($tipo === 'borrar') {
            $eliminados[] = $item;
            continue;
        }
        if ($tipo === 'cambio_mesa') {
            $origen = (int)($data['mesa_origen'] ?? 0);
            $dest = (int)($data['mesa_dest'] ?? 0);
            if ($origen === $idMesa) {
                $enviados[] = $item;
            }
            if ($dest === $idMesa) {
                $recibidos[] = $item;
            }
            continue;
        }
        if ($tipo === 'traspaso_mesa') {
            $origen = (int)($data['mesa_origen'] ?? 0);
            $dest = (int)($data['mesa_destino'] ?? 0);
            $num = (int)($data['num_lineas'] ?? 0);
            $item['producto'] = $num > 0
                ? "Traspaso completo ($num líneas)"
                : 'Traspaso completo';
            $item['cantidad'] = $num > 0 ? $num : 1;
            if ($origen === $idMesa) {
                $item['mesa_destino'] = $dest;
                $enviados[] = $item;
            }
            if ($dest === $idMesa) {
                $item['mesa_origen'] = $origen;
                $recibidos[] = $item;
            }
        }
    }

    jsonOk([
        'id_mesa'    => $idMesa,
        'id_pedido'  => $idPedido,
        'nuevos'     => $nuevos,
        'eliminados' => $eliminados,
        'enviados'   => $enviados,
        'recibidos'  => $recibidos,
    ]);
}

/** @param array<string, mixed> $row @param array<string, mixed> $data */
function _movimientoItemDesdeRegistro(array $row, array $data, PDOStatement $stDet): array {
    $producto = trim((string)($data['producto'] ?? $data['texto'] ?? ''));
    $cantidad = (int)($data['cantidad'] ?? 1);
    if ($producto === '' && !empty($data['id_linea'])) {
        $stDet->execute([(int)$data['id_linea']]);
        $det = $stDet->fetch(PDO::FETCH_ASSOC);
        if ($det) {
            $producto = trim((string)($det['nombre_producto_pantalla'] ?? ''));
            if ($cantidad <= 0) {
                $cantidad = (int)($det['cantidad'] ?? 1);
            }
        }
    }
    if ($producto === '') {
        $producto = '—';
    }

    return [
        'fecha_hora'   => (string)$row['fecha_hora'],
        'usuario'      => trim((string)($row['nombre_usuario'] ?? '')),
        'producto'     => $producto,
        'cantidad'     => max(1, $cantidad),
        'mesa_origen'  => isset($data['mesa_origen']) ? (int)$data['mesa_origen'] : null,
        'mesa_destino' => isset($data['mesa_dest']) ? (int)$data['mesa_dest']
            : (isset($data['mesa_destino']) ? (int)$data['mesa_destino'] : null),
    ];
}
