<?php
// backend/api/endpoints/mesas.php
declare(strict_types=1);

// ── Listar mesas abiertas ─────────────────────────────────────
function endpointMesasListar(array $payload): void {
    $db = getDB();
    $terminalSerie = trim((string)($_GET['terminal_serie'] ?? ''));
    $rows = $db->query(
        'SELECT pc.id_pedido, pc.id_mesa, pc.hora_creacion, pc.id_usuario_creacion,
                pc.hora_ultima_accion, pc.estado_mesa, pc.id_usuario_bloqueo, pc.hora_bloqueo,
                pc.terminal_serie_bloqueo, pc.nombre_cliente,
                ROUND(COALESCE(pc.base_imponible, 0) + COALESCE(pc.importe_IVA, 0), 2) AS total_importe,
                (SELECT COUNT(*) FROM pedido_detalles pd WHERE pd.id_pedido = pc.id_pedido) AS total_lineas
           FROM pedido_cabecera pc
          ORDER BY pc.id_mesa'
    )->fetchAll();
    foreach ($rows as &$row) {
        $vigente = pedidoBloqueoVigente($row);
        $serie = trim((string)($row['terminal_serie_bloqueo'] ?? ''));
        $porMi = $vigente
            && $serie !== ''
            && $terminalSerie !== ''
            && strcasecmp($serie, $terminalSerie) === 0;
        $row['bloqueo_vigente'] = $vigente && $serie !== '';
        $row['bloqueada_por_mi'] = $porMi;
        if (!$porMi) {
            $row['terminal_serie_bloqueo'] = '';
        }
    }
    unset($row);
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
        ensureTokenPublicoPedidoCabecera($db);
        $tokenPublico = generarTokenPublicoPedido();
        liberarOtrasMesasBloqueadasDelTerminal($db, $terminalSerie, (int)$payload['sub']);
        $st = $db->prepare(
            'INSERT INTO pedido_cabecera
             (id_mesa, id_usuario_creacion, id_usuario_bloqueo, hora_bloqueo,
              hora_ultima_accion, nombre_cliente, terminal_serie_bloqueo, token_publico)
             VALUES (?, ?, ?, NOW(), NOW(), \'\', ?, ?)'
        );
        $st->execute([$mesa, $payload['sub'], $payload['sub'], $terminalSerie, $tokenPublico]);
        $id = (int)$db->lastInsertId();
        verificarBloqueoPersistido($db, $id, $terminalSerie);
        $db->commit();
        jsonOk([
            'id_pedido'      => $id,
            'bloqueado'      => true,
            'terminal_serie' => $terminalSerie,
            'token_publico'  => $tokenPublico,
            'url_publica'    => urlPublicaPedido($tokenPublico),
        ]);
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
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            $db->rollBack();
            incidenciaMesaNoEncontrada($db, 'bloquear_mesa', $idPedido, $terminalSerie, (int)$payload['sub']);
            jsonError('Mesa no encontrada', 404);
        }

        if (otroTerminalTieneBloqueoPedido($row, $terminalSerie)) {
            $db->rollBack();
            jsonError(mensajeMesaBloqueadaSoloLectura(), 409);
        }

        liberarOtrasMesasBloqueadasDelTerminal($db, $terminalSerie, (int)$payload['sub'], $idPedido);

        if (!adquirirBloqueoMesa($db, $idPedido, (int)$payload['sub'], $terminalSerie)) {
            $db->rollBack();
            jsonError(
                'Otro dispositivo acaba de tomar esta mesa. Actualiza la lista e inténtalo de nuevo.',
                409
            );
        }

        verificarBloqueoPersistido($db, $idPedido, $terminalSerie);
        $db->commit();
        jsonOk([
            'bloqueado'      => true,
            'terminal_serie' => $terminalSerie,
        ]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error de bloqueo: ' . $e->getMessage(), 500);
    }
}

// ── Desbloquear al salir (si no hay líneas en BD, elimina el pedido) ──
function endpointMesaDesbloquear(array $payload, int $idPedido): void {
    $body = getBody();
    $terminalSerie = terminalSerieDesdeBody($body);
    $db = getDB();
    $db->beginTransaction();
    try {
        $st = $db->prepare(
            'SELECT id_pedido FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE'
        );
        $st->execute([$idPedido]);
        if (!$st->fetch()) {
            $db->rollBack();
            jsonOk(['desbloqueado' => true, 'pedido_eliminado' => false]);
            return;
        }

        if (eliminarPedidoSiSinDetalles($db, $idPedido)) {
            $db->commit();
            jsonOk(['desbloqueado' => true, 'pedido_eliminado' => true]);
            return;
        }

        liberarBloqueoMesaTerminal($db, $idPedido, $terminalSerie);
        $db->commit();
        jsonOk(['desbloqueado' => true, 'pedido_eliminado' => false]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error al desbloquear: ' . $e->getMessage(), 500);
    }
}

// ── Ping de bloqueo (cada minuto) ─────────────────────────────
function endpointMesaPing(array $payload, int $idPedido): void {
    $body = getBody();
    $terminalSerie = terminalSerieDesdeBody($body);
    $db = getDB();
    $db->beginTransaction();
    try {
        $st = $db->prepare(
            'SELECT terminal_serie_bloqueo, hora_bloqueo
               FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE'
        );
        $st->execute([$idPedido]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            $db->rollBack();
            jsonError('Mesa no encontrada', 404);
        }
        if (otroTerminalTieneBloqueoPedido($row, $terminalSerie)) {
            $db->rollBack();
            jsonError(mensajeMesaBloqueadaSoloLectura(), 409);
        }
        if (!adquirirBloqueoMesa($db, $idPedido, (int)$payload['sub'], $terminalSerie)) {
            $db->rollBack();
            jsonError('No tienes el bloqueo de esta mesa', 409);
        }
        $db->commit();
        jsonOk(['ping' => 'ok']);
    } catch (Throwable $e) {
        $db->rollBack();
        throw $e;
    }
}

// ── Expulsar usuario (solo admin/supervisor) ──────────────────
function endpointMesaExpulsar(array $payload, int $idPedido): void {
    requireRole($payload, ['admin', 'supervisor']);
    $body = getBody();
    $terminalSerie = terminalSerieDesdeBody($body);
    $db = getDB();
    $db->beginTransaction();
    try {
        $st = $db->prepare(
            'SELECT terminal_serie_bloqueo, hora_bloqueo FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE'
        );
        $st->execute([$idPedido]);
        $row = $st->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            $db->rollBack();
            jsonError('Mesa no encontrada', 404);
        }
        liberarOtrasMesasBloqueadasDelTerminal($db, $terminalSerie, (int)$payload['sub'], $idPedido);
        if (!adquirirBloqueoMesa($db, $idPedido, (int)$payload['sub'], $terminalSerie)) {
            $db->rollBack();
            jsonError('No se pudo tomar el bloqueo de la mesa', 409);
        }
        $db->commit();
        jsonOk(['expulsado' => true]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error al expulsar: ' . $e->getMessage(), 500);
    }
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
        if (!$cab) {
            $db->rollBack();
            incidenciaMesaNoEncontrada($db, 'cerrar_mesa', $idPedido, $terminalSerie, (int)$payload['sub']);
            jsonError('Mesa no encontrada', 404);
        }

        _verificarBloqueo($cab, $payload, $terminalSerie);

        // Copiar a histórico (columnas explícitas: orden distinto en tablas históricas)
        ensureTokenPublicoPedidoCabecera($db);
        asegurarTokenPublicoPedido($db, $idPedido);

        $db->prepare(
            'INSERT INTO pedido_cabecera_historico
             (id_pedido, id_mesa, hora_creacion, nombre_cliente, id_usuario_creacion,
              terminal_serie_bloqueo, hora_ultima_accion, estado_mesa, id_usuario_bloqueo,
              hora_bloqueo, base_imponible, importe_IVA, hora_cierre, token_publico)
             SELECT id_pedido, id_mesa, hora_creacion, nombre_cliente, id_usuario_creacion,
              terminal_serie_bloqueo, hora_ultima_accion, estado_mesa, id_usuario_bloqueo,
              hora_bloqueo, base_imponible, importe_IVA, NOW(), token_publico
               FROM pedido_cabecera WHERE id_pedido = ?'
        )->execute([$idPedido]);

        $db->prepare(
            'INSERT INTO pedido_detalles_historico
             (id_linea, id_pedido, id_producto, cantidad, comentario, nombre_producto_pantalla,
              opciones_elegidas, texto_imprimir_cocina, texto_imprimir_cliente, orden,
              precio_sin_IVA, porcentaje_IVA, importe_IVA, impreso, servido, hora_pedido,
              modificado_servicio, id_pedido_historico)
             SELECT id_linea, id_pedido, id_producto, cantidad, comentario, nombre_producto_pantalla,
              opciones_elegidas, texto_imprimir_cocina, texto_imprimir_cliente, orden,
              precio_sin_IVA, porcentaje_IVA, importe_IVA, impreso, servido, hora_pedido,
              modificado_servicio, ?
               FROM pedido_detalles WHERE id_pedido = ?'
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
    if (!terminalTieneBloqueoPedido($cab, $terminalSerie)) {
        if (otroTerminalTieneBloqueoPedido($cab, $terminalSerie)) {
            jsonError(mensajeMesaBloqueadaSoloLectura(), 409);
        }
        jsonError(
            'No tienes el bloqueo activo de esta mesa (expiró tras 3 min sin actividad).',
            409
        );
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
                 (id_mesa, id_usuario_creacion, id_usuario_bloqueo, hora_bloqueo,
                  hora_ultima_accion, nombre_cliente, terminal_serie_bloqueo)
                 VALUES (?, ?, 0, NULL, NOW(), ?, \'\')'
            )->execute([$idMesaDestino, $payload['sub'], $cab['nombre_cliente'] ?? '']);
            $idPedidoDestino = (int)$db->lastInsertId();
        }

        // Calcular el orden máximo actual en la mesa destino
        $stMax = $db->prepare('SELECT COALESCE(MAX(orden), 0) AS m FROM pedido_detalles WHERE id_pedido = ?');
        $stMax->execute([$idPedidoDestino]);
        $maxOrden = (int)($stMax->fetch()['m'] ?? 0);

        // Mover todas las líneas de origen a destino (un registro por línea)
        $stLineas = $db->prepare(
            'SELECT id_linea, nombre_producto_pantalla, cantidad
               FROM pedido_detalles WHERE id_pedido = ? ORDER BY orden'
        );
        $stLineas->execute([$idPedido]);
        $lineasTraspaso = $stLineas->fetchAll(PDO::FETCH_ASSOC);
        $stUpd = $db->prepare('UPDATE pedido_detalles SET id_pedido=?, orden=?, impreso=0 WHERE id_linea=?');
        $stLog = $db->prepare(
            'INSERT INTO registro_cambios (id_usuario, tipo_accion, json_cambio) VALUES (?,?,?)'
        );
        foreach ($lineasTraspaso as $linea) {
            $maxOrden++;
            $idLinea = (int)$linea['id_linea'];
            $stUpd->execute([$idPedidoDestino, $maxOrden, $idLinea]);
            $stLog->execute([
                $payload['sub'],
                'cambio_mesa',
                json_encode([
                    'id_linea'    => $idLinea,
                    'mesa_origen' => $idMesaOrigen,
                    'mesa_dest'   => $idMesaDestino,
                    'producto'    => trim((string)$linea['nombre_producto_pantalla']),
                    'cantidad'    => max(1, (int)$linea['cantidad']),
                ], JSON_UNESCAPED_UNICODE),
            ]);
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
            // Registros antiguos (un solo evento agregado)
            $origen = (int)($data['mesa_origen'] ?? 0);
            $dest = (int)($data['mesa_destino'] ?? 0);
            $lineasJson = $data['lineas'] ?? null;
            if (is_array($lineasJson) && $lineasJson !== []) {
                foreach ($lineasJson as $ln) {
                    if (!is_array($ln)) {
                        continue;
                    }
                    $det = $item;
                    $det['producto'] = trim((string)($ln['producto'] ?? ''));
                    if ($det['producto'] === '') {
                        $det['producto'] = '—';
                    }
                    $det['cantidad'] = max(1, (int)($ln['cantidad'] ?? 1));
                    if ($origen === $idMesa) {
                        $det['mesa_destino'] = $dest;
                        $enviados[] = $det;
                    }
                    if ($dest === $idMesa) {
                        $det['mesa_origen'] = $origen;
                        $recibidos[] = $det;
                    }
                }
            } else {
                $num = (int)($data['num_lineas'] ?? 0);
                $item['producto'] = $num > 0
                    ? "Traspaso completo ($num líneas, sin detalle)"
                    : 'Traspaso completo (sin detalle)';
                $item['cantidad'] = 1;
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
