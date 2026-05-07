<?php
// backend/api/endpoints/mesas.php
declare(strict_types=1);

// ── Listar mesas abiertas ─────────────────────────────────────
function endpointMesasListar(array $payload): void {
    $db = getDB();
    $rows = $db->query(
        'SELECT `id_pedido`, `id_mesa`, `hora_creacion`, `id_usuario_creacion`,
                `hora_ultima_accion`, `estado_mesa`, `id_usuario_bloqueo`, `hora_bloqueo`,
                `terminal_serie_bloqueo`, `nombre_cliente`
           FROM `pedido_cabecera`
          ORDER BY `id_mesa`'
    )->fetchAll();
    jsonOk($rows);
}

// ── Abrir nueva mesa ──────────────────────────────────────────
function endpointMesaAbrir(array $payload): void {
    $body  = getBody();
    $mesa  = (int)($body['id_mesa'] ?? 0);
    if ($mesa <= 0) jsonError('Número de mesa inválido');
    $terminalSerie = _terminalSerieDesdeBody($body);

    $db = getDB();

    // Verificar si ya existe mesa abierta con ese número
    $st = $db->prepare('SELECT id_pedido FROM pedido_cabecera WHERE id_mesa = ? LIMIT 1');
    $st->execute([$mesa]);
    if ($st->fetch()) jsonError("La mesa $mesa ya está abierta");

    $db->beginTransaction();
    try {
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
    $terminalSerie = _terminalSerieDesdeBody($body);
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

// ── Ping de bloqueo (cada minuto) ─────────────────────────────
function endpointMesaPing(array $payload, int $idPedido): void {
    $body = getBody();
    $terminalSerie = _terminalSerieDesdeBody($body);
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
    $terminalSerie = _terminalSerieDesdeBody($body);
    $db = getDB();
    $db->prepare(
        'UPDATE pedido_cabecera SET id_usuario_bloqueo=?, hora_bloqueo=NOW(), terminal_serie_bloqueo=?
          WHERE id_pedido=?'
    )->execute([$payload['sub'], $terminalSerie, $idPedido]);
    jsonOk(['expulsado' => true]);
}

// ── Cerrar mesa (mover a histórico) ──────────────────────────
function endpointMesaCerrar(array $payload, int $idPedido): void {
    $body = getBody();
    $terminalSerie = _terminalSerieDesdeBody($body);
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

function _terminalSerieDesdeBody(array $body): string {
    $terminal = trim((string)($body['terminal_serie'] ?? ''));
    if ($terminal === '') jsonError('Falta terminal_serie', 400);
    if (strlen($terminal) > 120) {
        $terminal = substr($terminal, 0, 120);
    }
    return $terminal;
}
