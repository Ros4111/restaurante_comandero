<?php
// backend/api/endpoints/servicio.php
declare(strict_types=1);

const SERVIDO_PENDIENTE = '2000-01-01 00:00:00';

/** Roles con acceso a pendientes de servir. */
const SERVICIO_ROLES = ['servicio', 'cocina', 'barra', 'admin', 'supervisor'];

function requireServicioAccess(array $payload): void {
    if ((int)($payload['impresora'] ?? 0) > 0) {
        return;
    }
    requireRole($payload, SERVICIO_ROLES);
}

/**
 * null = sin filtro (todos); array = ids de impresora permitidos.
 */
function _impresoraIdsFiltro(array $payload, PDO $db): ?array {
    $idImpUsuario = (int)($payload['impresora'] ?? 0);
    if ($idImpUsuario > 0) {
        return [$idImpUsuario];
    }
    $rol = strtolower(trim((string)($payload['rol'] ?? '')));
    return _impresoraIdsParaPermiso($db, $rol);
}

/**
 * null = sin filtro (todos); array = ids de impresora permitidos.
 */
function _impresoraIdsParaPermiso(PDO $db, string $rol): ?array {
    $rol = strtolower(trim($rol));
    if (in_array($rol, ['admin', 'supervisor', 'servicio'], true)) {
        return null;
    }
    $needle = match ($rol) {
        'cocina' => 'cocina',
        'barra'  => 'barra',
        default  => null,
    };
    if ($needle === null) {
        return [];
    }
    $st = $db->prepare(
        'SELECT id_impresora FROM impresoras WHERE LOWER(nombre) LIKE ?'
    );
    $st->execute(['%' . $needle . '%']);
    $ids = array_map('intval', $st->fetchAll(PDO::FETCH_COLUMN));
    return $ids !== [] ? $ids : [-1];
}

/** JSON estable de opciones para comparar líneas equivalentes. */
function _opcionesCanonical(array $opciones): array {
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
            'nombre'          => trim((string)($op['nombre'] ?? '')),
            'predeterminado'  => (int)($op['predeterminado'] ?? 0),
        ];
    }
    return $out;
}

function _claveAgrupacionLinea(int $idProducto, string $comentario, array $opciones): string {
    return $idProducto . "\0" . trim($comentario) . "\0"
        . json_encode(_opcionesCanonical($opciones), JSON_UNESCAPED_UNICODE);
}

/**
 * Agrupa líneas del mismo lote con mismo producto, opciones y comentario.
 * @param list<array<string, mixed>> $lineas
 * @return list<array<string, mixed>>
 */
function _agruparLineasPendientes(array $lineas): array {
    $grupos = [];
    foreach ($lineas as $linea) {
        $opciones = $linea['opciones_elegidas'];
        if (!is_array($opciones)) {
            $opciones = [];
        }
        $key = _claveAgrupacionLinea(
            (int)$linea['id_producto'],
            (string)$linea['comentario'],
            $opciones
        );
        $idLinea = (int)$linea['id_linea'];
        $cant = (int)$linea['cantidad'];
        $esModificado = !empty($linea['modificado']);
        $esUrgente = !empty($linea['urgente']);
        if (!isset($grupos[$key])) {
            $grupos[$key] = [
                'id_linea'                 => $idLinea,
                'ids_linea'                => [$idLinea],
                'id_producto'              => (int)$linea['id_producto'],
                'cantidad'                 => $cant,
                'comentario'               => (string)$linea['comentario'],
                'nombre_producto_pantalla' => (string)$linea['nombre_producto_pantalla'],
                'opciones_elegidas'        => $opciones,
                'modificado'               => $esModificado,
                'urgente'                  => $esUrgente,
            ];
        } else {
            $grupos[$key]['ids_linea'][] = $idLinea;
            $grupos[$key]['cantidad'] += $cant;
            $grupos[$key]['modificado'] =
                ($grupos[$key]['modificado'] ?? false) || $esModificado;
            $grupos[$key]['urgente'] =
                ($grupos[$key]['urgente'] ?? false) || $esUrgente;
        }
    }
    return array_values($grupos);
}

function endpointServicioPendientes(array $payload): void {
    requireServicioAccess($payload);

    $db = getDB();
    ensureUrgenteColumnPedidoDetalles($db);
    $idsImp = _impresoraIdsFiltro($payload, $db);

    $sql = 'SELECT d.id_linea, d.id_pedido, d.id_producto, d.cantidad, d.comentario,
                   d.nombre_producto_pantalla, d.opciones_elegidas, d.orden, d.hora_pedido,
                   COALESCE(d.modificado_servicio, 0) AS modificado_servicio,
                   COALESCE(d.urgente, 0) AS urgente,
                   c.id_mesa, COALESCE(c.nombre_cliente, \'\') AS nombre_cliente,
                   p.id_impresora
              FROM pedido_detalles d
              INNER JOIN pedido_cabecera c ON c.id_pedido = d.id_pedido
              INNER JOIN productos p ON p.id_producto = d.id_producto
             WHERE d.servido = ?
               AND d.cantidad > 0';
    $params = [SERVIDO_PENDIENTE];

    if ($idsImp !== null) {
        $placeholders = implode(',', array_fill(0, count($idsImp), '?'));
        $sql .= " AND p.id_impresora IN ($placeholders)";
        $params = array_merge($params, $idsImp);
    }

    $sql .= ' ORDER BY COALESCE(d.urgente, 0) DESC, d.hora_pedido ASC, d.orden ASC, d.id_linea ASC';

    $st = $db->prepare($sql);
    $st->execute($params);
    $rows = $st->fetchAll(PDO::FETCH_ASSOC);

    $pedidos = [];
    foreach ($rows as $r) {
        $idPedido = (int)$r['id_pedido'];
        $horaPedido = (string)$r['hora_pedido'];
        // Un envío a cocina = misma hora_pedido; lotes distintos → tarjetas separadas.
        $idGrupo = $idPedido . '|' . $horaPedido;
        if (!isset($pedidos[$idGrupo])) {
            $pedidos[$idGrupo] = [
                'id_grupo'       => $idGrupo,
                'id_pedido'      => $idPedido,
                'hora_pedido'    => $horaPedido,
                'id_mesa'        => (int)$r['id_mesa'],
                'nombre_cliente' => (string)$r['nombre_cliente'],
                'lineas'         => [],
            ];
        }
        $opciones = $r['opciones_elegidas']
            ? json_decode((string)$r['opciones_elegidas'], true)
            : [];
        if (!is_array($opciones)) {
            $opciones = [];
        }
        $idProducto = (int)$r['id_producto'];
        $pedidos[$idGrupo]['lineas'][] = [
            'id_linea'                 => (int)$r['id_linea'],
            'id_producto'              => $idProducto,
            'cantidad'                 => (int)$r['cantidad'],
            'comentario'               => (string)$r['comentario'],
            'nombre_producto_pantalla' => (string)$r['nombre_producto_pantalla'],
            'opciones_elegidas'        => $opciones,
            'modificado'               => (int)$r['modificado_servicio'] === 1,
            'urgente'                  => (int)($r['urgente'] ?? 0) === 1,
        ];
    }

    foreach ($pedidos as &$pedido) {
        $pedido['lineas'] = _agruparLineasPendientes($pedido['lineas']);
        usort(
            $pedido['lineas'],
            static fn(array $a, array $b): int =>
                ((int)($b['urgente'] ?? 0) <=> (int)($a['urgente'] ?? 0))
        );
    }
    unset($pedido);

    $lista = array_values($pedidos);
    usort(
        $lista,
        static function (array $a, array $b): int {
            $ua = array_reduce(
                $a['lineas'],
                static fn(bool $c, array $l): bool => $c || !empty($l['urgente']),
                false
            );
            $ub = array_reduce(
                $b['lineas'],
                static fn(bool $c, array $l): bool => $c || !empty($l['urgente']),
                false
            );
            if ($ua !== $ub) {
                return $ub <=> $ua;
            }
            return strcmp((string)$a['hora_pedido'], (string)$b['hora_pedido']);
        }
    );

    jsonOk($lista);
}

function endpointServicioMarcarServido(array $payload): void {
    requireServicioAccess($payload);

    $body = getBody();
    $ids = $body['ids_linea'] ?? [];
    if (!is_array($ids) || $ids === []) {
        jsonError('ids_linea obligatorio', 400);
    }

    $idsLinea = [];
    foreach ($ids as $id) {
        $n = (int)$id;
        if ($n > 0) {
            $idsLinea[] = $n;
        }
    }
    if ($idsLinea === []) {
        jsonError('Ningún id_linea válido', 400);
    }

    $db = getDB();
    $idsImp = _impresoraIdsFiltro($payload, $db);

    $placeholders = implode(',', array_fill(0, count($idsLinea), '?'));
    $sql = "UPDATE pedido_detalles d
               INNER JOIN productos p ON p.id_producto = d.id_producto
               SET d.servido = NOW(), d.modificado_servicio = 0
             WHERE d.servido = ?
               AND d.id_linea IN ($placeholders)";
    $params = array_merge([SERVIDO_PENDIENTE], $idsLinea);

    if ($idsImp !== null) {
        $phImp = implode(',', array_fill(0, count($idsImp), '?'));
        $sql .= " AND p.id_impresora IN ($phImp)";
        $params = array_merge($params, $idsImp);
    }

    $st = $db->prepare($sql);
    $st->execute($params);

    jsonOk([
        'actualizadas' => $st->rowCount(),
    ]);
}

/**
 * Huella estable del estado de pendientes (misma lógica de filtro que la lista).
 * Cambia al guardar pedidos, marcar servido o modificar líneas en cocina.
 */
function _servicioPendientesRevision(PDO $db, ?array $idsImp): string {
    $sql = 'SELECT COUNT(*) AS num_lineas,
                   COALESCE(MAX(d.id_linea), 0) AS max_id_linea,
                   COALESCE(MAX(d.hora_pedido), \'\') AS max_hora,
                   COALESCE(SUM(d.cantidad), 0) AS sum_cantidad,
                   COALESCE(SUM(COALESCE(d.modificado_servicio, 0)), 0) AS sum_modificadas,
                   COALESCE(SUM(COALESCE(d.urgente, 0)), 0) AS sum_urgentes
              FROM pedido_detalles d
              INNER JOIN productos p ON p.id_producto = d.id_producto
             WHERE d.servido = ?
               AND d.cantidad > 0';
    $params = [SERVIDO_PENDIENTE];

    if ($idsImp !== null) {
        $placeholders = implode(',', array_fill(0, count($idsImp), '?'));
        $sql .= " AND p.id_impresora IN ($placeholders)";
        $params = array_merge($params, $idsImp);
    }

    $st = $db->prepare($sql);
    $st->execute($params);
    $row = $st->fetch(PDO::FETCH_ASSOC) ?: [];

    return md5(json_encode($row, JSON_UNESCAPED_UNICODE));
}

/** SSE: avisa cuando cambia la cola de pendientes (~1 s). Reconexión automática en el cliente. */
function endpointServicioStream(array $payload): void {
    requireServicioAccess($payload);

    @ini_set('zlib.output_compression', '0');
    @ini_set('output_buffering', 'off');
    @set_time_limit(0);
    while (ob_get_level() > 0) {
        ob_end_flush();
    }

    header('Content-Type: text/event-stream; charset=utf-8');
    header('Cache-Control: no-cache, no-transform');
    header('Connection: keep-alive');
    header('X-Accel-Buffering: no');

    $db = getDB();
    ensureUrgenteColumnPedidoDetalles($db);
    $idsImp = _impresoraIdsFiltro($payload, $db);
    $lastRevision = _servicioPendientesRevision($db, $idsImp);
    $started = time();
    $maxSeconds = 55;
    $tick = 0;

    echo ": connected\n\n";
    flush();

    while (!connection_aborted() && (time() - $started) < $maxSeconds) {
        $revision = _servicioPendientesRevision($db, $idsImp);
        if ($revision !== $lastRevision) {
            $lastRevision = $revision;
            echo 'event: update' . "\n";
            echo 'data: ' . json_encode(['revision' => $revision], JSON_UNESCAPED_UNICODE) . "\n\n";
            flush();
        } elseif ($tick % 15 === 0) {
            echo ': ping ' . time() . "\n\n";
            flush();
        }
        $tick++;
        sleep(1);
    }
    exit;
}
