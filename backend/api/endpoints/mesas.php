<?php
// backend/api/endpoints/mesas.php
declare(strict_types=1);

// ── Listar mesas abiertas ─────────────────────────────────────
function endpointMesasListar(array $payload): void {
    $db = getDB();
    $rows = $db->query(
        'SELECT pc.id_pedido, pc.id_mesa, pc.hora_creacion, pc.hora_ultima_accion,
                pc.estado_mesa, pc.id_usuario_bloqueo, pc.hora_bloqueo,
                u.nombre_usuario AS nombre_usuario_bloqueo,
                COUNT(pd.id_linea) AS total_lineas
           FROM pedido_cabecera pc
      LEFT JOIN usuarios u ON u.id_usuario = pc.id_usuario_bloqueo
      LEFT JOIN pedido_detalles pd ON pd.id_pedido = pc.id_pedido
          GROUP BY pc.id_pedido
          ORDER BY pc.id_mesa'
    )->fetchAll();
    jsonOk($rows);
}

// ── Abrir nueva mesa ──────────────────────────────────────────
function endpointMesaAbrir(array $payload): void {
    $body  = getBody();
    $mesa  = (int)($body['id_mesa'] ?? 0);
    if ($mesa <= 0) jsonError('Número de mesa inválido');

    $db = getDB();

    // Verificar si ya existe mesa abierta con ese número
    $st = $db->prepare('SELECT id_pedido FROM pedido_cabecera WHERE id_mesa = ? LIMIT 1');
    $st->execute([$mesa]);
    if ($st->fetch()) jsonError("La mesa $mesa ya está abierta");

    $db->beginTransaction();
    try {
        $st = $db->prepare(
            'INSERT INTO pedido_cabecera (id_mesa, id_usuario_creacion, id_usuario_bloqueo, hora_bloqueo)
             VALUES (?, ?, ?, NOW())'
        );
        $st->execute([$mesa, $payload['sub'], $payload['sub']]);
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
    $db = getDB();
    $db->beginTransaction();
    try {
        // SELECT FOR UPDATE para atomicidad
        $st = $db->prepare(
            'SELECT id_usuario_bloqueo, hora_bloqueo
               FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE'
        );
        $st->execute([$idPedido]);
        $row = $st->fetch();
        if (!$row) { $db->rollBack(); jsonError('Mesa no encontrada', 404); }

        $bloqueoPorOtro = $row['id_usuario_bloqueo'] &&
                          $row['id_usuario_bloqueo'] != $payload['sub'] &&
                          $row['hora_bloqueo'] &&
                          (strtotime($row['hora_bloqueo']) + LOCK_TTL) > time();

        if ($bloqueoPorOtro) {
            $db->rollBack();
            // Devuelve info del bloqueador para mostrar mensaje al camarero
            $u = $db->prepare('SELECT nombre_usuario FROM usuarios WHERE id_usuario = ?');
            $u->execute([$row['id_usuario_bloqueo']]);
            $nombre = $u->fetch()['nombre_usuario'] ?? 'Desconocido';
            jsonError("Mesa bloqueada por $nombre", 409);
        }

        $db->prepare(
            'UPDATE pedido_cabecera SET id_usuario_bloqueo=?, hora_bloqueo=NOW()
              WHERE id_pedido=?'
        )->execute([$payload['sub'], $idPedido]);

        $db->commit();
        jsonOk(['bloqueado' => true]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error de bloqueo: ' . $e->getMessage(), 500);
    }
}

// ── Ping de bloqueo (cada minuto) ─────────────────────────────
function endpointMesaPing(array $payload, int $idPedido): void {
    $db = getDB();
    $st = $db->prepare(
        'UPDATE pedido_cabecera
            SET hora_bloqueo = NOW()
          WHERE id_pedido = ? AND id_usuario_bloqueo = ?'
    );
    $st->execute([$idPedido, $payload['sub']]);
    if ($st->rowCount() === 0) jsonError('No tienes el bloqueo de esta mesa', 409);
    jsonOk(['ping' => 'ok']);
}

// ── Expulsar usuario (solo admin/supervisor) ──────────────────
function endpointMesaExpulsar(array $payload, int $idPedido): void {
    requireRole($payload, ['admin', 'supervisor']);
    $db = getDB();
    $db->prepare(
        'UPDATE pedido_cabecera SET id_usuario_bloqueo=?, hora_bloqueo=NOW()
          WHERE id_pedido=?'
    )->execute([$payload['sub'], $idPedido]);
    jsonOk(['expulsado' => true]);
}

// ── Cerrar mesa (mover a histórico) ──────────────────────────
function endpointMesaCerrar(array $payload, int $idPedido): void {
    $db = getDB();
    $db->beginTransaction();
    try {
        // Verificar bloqueo
        $st = $db->prepare('SELECT * FROM pedido_cabecera WHERE id_pedido = ? FOR UPDATE');
        $st->execute([$idPedido]);
        $cab = $st->fetch();
        if (!$cab) { $db->rollBack(); jsonError('Mesa no encontrada', 404); }

        _verificarBloqueo($cab, $payload);

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
function _verificarBloqueo(array $cab, array $payload): void {
    if ($payload['rol'] === 'admin') return; // admin siempre puede
    if (
        $cab['id_usuario_bloqueo'] != $payload['sub'] ||
        !$cab['hora_bloqueo'] ||
        (strtotime($cab['hora_bloqueo']) + LOCK_TTL) <= time()
    ) {
        jsonError('No tienes el bloqueo de esta mesa o ha expirado', 409);
    }
}
