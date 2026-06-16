<?php
// backend/api/endpoints/historico.php
declare(strict_types=1);

// ── Listar mesas cerradas (historial) ────────────────────────
// Solo admin. Devuelve hasta 100 entradas ordenadas por actividad.
// Nota: hora_cierre en el histórico es poco fiable por alineación de columnas
// en el INSERT SELECT original; se usa hora_ultima_accion como referencia de cierre.
// El total se calcula desde pedido_detalles_historico (precio almacenado por línea).
function endpointHistoricoMesasListar(array $payload): void {
    requireRole($payload, ['admin']);

    $db   = getDB();
    $dias = (int)($_GET['dias'] ?? 0); // 0 = sin límite, 1 = hoy, 7 = semana…

    $condicion = '';
    $params    = [];
    if ($dias > 0) {
        $condicion = 'WHERE h.hora_ultima_accion >= DATE_SUB(NOW(), INTERVAL ? DAY)';
        $params[]  = $dias;
    }

    $sql = "SELECT h.id_pedido,
                   h.id_mesa,
                   h.nombre_cliente,
                   h.hora_creacion,
                   h.hora_ultima_accion,
                   h.id_usuario_creacion,
                   ROUND(
                       COALESCE(
                           (SELECT SUM(
                               ROUND(ROUND(d.precio_sin_IVA * (1 + d.porcentaje_IVA / 100), 2) * d.cantidad, 2)
                            FROM pedido_detalles_historico d
                            WHERE d.id_pedido = h.id_pedido
                           ), 0
                       ), 2
                   ) AS total_importe,
                   (SELECT COUNT(*) FROM pedido_detalles_historico d2
                    WHERE d2.id_pedido = h.id_pedido) AS total_lineas
              FROM pedido_cabecera_historico h
              $condicion
             ORDER BY h.hora_ultima_accion DESC
             LIMIT 150";

    $st = $db->prepare($sql);
    $st->execute($params);
    jsonOk($st->fetchAll());
}

// ── Detalle de una mesa cerrada (líneas) ─────────────────────
function endpointHistoricoMesaDetalle(array $payload, int $idPedido): void {
    requireRole($payload, ['admin']);
    $db = getDB();

    $stCab = $db->prepare('SELECT * FROM pedido_cabecera_historico WHERE id_pedido = ?');
    $stCab->execute([$idPedido]);
    $cab = $stCab->fetch(PDO::FETCH_ASSOC);
    if (!$cab) jsonError('Mesa no encontrada en histórico', 404);

    $stDet = $db->prepare(
        'SELECT id_linea, id_producto, cantidad, comentario,
                nombre_producto_pantalla, opciones_elegidas,
                texto_imprimir_cocina, orden,
                precio_sin_IVA, porcentaje_IVA
           FROM pedido_detalles_historico
          WHERE id_pedido = ?
          ORDER BY orden'
    );
    $stDet->execute([$idPedido]);
    $detalles = $stDet->fetchAll(PDO::FETCH_ASSOC);

    foreach ($detalles as &$d) {
        $d['opciones_elegidas'] = $d['opciones_elegidas']
            ? json_decode($d['opciones_elegidas'], true)
            : [];
        // PVP unitario calculado para mostrar al admin
        $pu  = (float)$d['precio_sin_IVA'];
        $pct = (float)$d['porcentaje_IVA'];
        $d['pvp_unitario'] = $pu > 0 ? round($pu * (1 + $pct / 100), 2) : 0.0;
    }
    unset($d);

    jsonOk(['cabecera' => $cab, 'detalles' => $detalles]);
}

// ── Reabrir mesa cerrada ──────────────────────────────────────
// Solo admin. Crea un nuevo pedido activo con los mismos productos.
// Mantiene el registro histórico intacto (trazabilidad).
function endpointHistoricoMesaReabrir(array $payload, int $idPedido): void {
    requireRole($payload, ['admin']);
    $body          = getBody();
    $terminalSerie = trim((string)($body['terminal_serie'] ?? 'reopen-admin'));
    if ($terminalSerie === '') $terminalSerie = 'reopen-admin';
    if (strlen($terminalSerie) > 120) $terminalSerie = substr($terminalSerie, 0, 120);

    $db = getDB();
    $db->beginTransaction();
    try {
        // Obtener registro histórico
        $stCab = $db->prepare(
            'SELECT * FROM pedido_cabecera_historico WHERE id_pedido = ? FOR UPDATE'
        );
        $stCab->execute([$idPedido]);
        $cab = $stCab->fetch(PDO::FETCH_ASSOC);
        if (!$cab) { $db->rollBack(); jsonError('Mesa no encontrada en histórico', 404); }

        $idMesa = (int)$cab['id_mesa'];

        // Verificar que la mesa no está ya activa
        $stAct = $db->prepare(
            'SELECT id_pedido FROM pedido_cabecera WHERE id_mesa = ? LIMIT 1'
        );
        $stAct->execute([$idMesa]);
        if ($stAct->fetch()) {
            $db->rollBack();
            jsonError("La mesa $idMesa ya está abierta; ciérrala primero", 409);
        }

        // Obtener líneas del histórico
        $stLineas = $db->prepare(
            'SELECT * FROM pedido_detalles_historico WHERE id_pedido = ? ORDER BY orden'
        );
        $stLineas->execute([$idPedido]);
        $lineas = $stLineas->fetchAll(PDO::FETCH_ASSOC);

        if (empty($lineas)) {
            $db->rollBack();
            jsonError('La mesa cerrada no tiene líneas registradas', 400);
        }

        // Recalcular totales desde las líneas históricas
        $baseImp = 0.0;
        $impIVA  = 0.0;
        foreach ($lineas as $l) {
            $pu     = (float)$l['precio_sin_IVA'];
            $pct    = (float)$l['porcentaje_IVA'];
            $q      = max(0, (int)$l['cantidad']);
            if ($q <= 0 || $pu <= 0) continue;
            $factor  = 1.0 + $pct / 100.0;
            $pvpUnit = round($pu * $factor, 2);
            $lineTtc = round($pvpUnit * $q, 2);
            $baseLine = round($lineTtc / $factor, 2);
            $ivaLine  = round($lineTtc - $baseLine, 2);
            $baseImp += $baseLine;
            $impIVA  += $ivaLine;
        }

        // Crear nuevo pedido activo (nuevo id_pedido auto-increment)
        $newId = insertarPedidoCabecera($db, [
            'id_mesa'               => $idMesa,
            'id_usuario_creacion'   => (int)$payload['sub'],
            'id_usuario_bloqueo'    => (int)$payload['sub'],
            'hora_bloqueo'          => 'now',
            'nombre_cliente'        => (string)($cab['nombre_cliente'] ?? ''),
            'base_imponible'        => round($baseImp, 2),
            'importe_IVA'           => round($impIVA, 2),
            'estado_mesa'           => 'abierta',
            'terminal_serie_bloqueo'=> $terminalSerie,
        ]);

        foreach ($lineas as $l) {
            insertarPedidoDetalle($db, [
                'id_pedido'               => $newId,
                'id_producto'             => (int)$l['id_producto'],
                'cantidad'                => max(1, (int)$l['cantidad']),
                'comentario'              => $l['comentario'] ?? '',
                'nombre_producto_pantalla'=> $l['nombre_producto_pantalla'],
                'opciones_elegidas'       => $l['opciones_elegidas'] ?? null,
                'texto_imprimir_cocina'   => $l['texto_imprimir_cocina'],
                'texto_imprimir_cliente'  => $l['texto_imprimir_cliente'] ?? '',
                'orden'                   => (int)$l['orden'],
                'precio_sin_IVA'          => $l['precio_sin_IVA'],
                'porcentaje_IVA'          => $l['porcentaje_IVA'],
                'importe_IVA'             => $l['importe_IVA'],
                'servido'                 => $l['servido'] ?? '2000-01-01 00:00:00',
                'hora_pedido'             => $l['hora_pedido'] ?? 'now',
                'modificado_servicio'     => (int)($l['modificado_servicio'] ?? 0),
                'urgente'                 => (int)($l['urgente'] ?? 0),
            ]);
        }

        // Registrar en log de cambios
        $db->prepare(
            'INSERT INTO registro_cambios (id_usuario, tipo_accion, json_cambio) VALUES (?,?,?)'
        )->execute([
            $payload['sub'],
            'reabrir_mesa',
            json_encode([
                'id_pedido_historico' => $idPedido,
                'id_pedido_nuevo'     => $newId,
                'id_mesa'             => $idMesa,
                'num_lineas'          => count($lineas),
            ], JSON_UNESCAPED_UNICODE),
        ]);

        $db->commit();
        jsonOk([
            'id_pedido' => $newId,
            'id_mesa'   => $idMesa,
        ]);
    } catch (Throwable $e) {
        $db->rollBack();
        logEvent('Error reabrir_mesa ' . $idPedido . ': ' . $e->getMessage(), 'error');
        jsonError('Error interno: ' . $e->getMessage(), 500);
    }
}
