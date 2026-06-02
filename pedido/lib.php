<?php
declare(strict_types=1);

function pedidoGetDB(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=%s',
            DB_HOST,
            DB_PORT,
            DB_NAME,
            DB_CHARSET
        );
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    }
    return $pdo;
}

function pedidoJsonOk(mixed $data, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => true, 'data' => $data], JSON_UNESCAPED_UNICODE);
    exit;
}

function pedidoJsonError(string $msg, int $code = 400): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => false, 'error' => $msg], JSON_UNESCAPED_UNICODE);
    exit;
}

function pedidoEnsureTokenColumn(PDO $db): void {
    try {
        $check = $db->query("SHOW COLUMNS FROM pedido_cabecera LIKE 'token_publico'");
        if (!$check || !$check->fetch()) {
            $db->exec(
                'ALTER TABLE pedido_cabecera
                 ADD COLUMN token_publico CHAR(32) NULL DEFAULT NULL,
                 ADD UNIQUE KEY uk_pedido_token_publico (token_publico)'
            );
        }
    } catch (Throwable $e) {
    }
}

function pedidoTextoCambio(array $row): string {
    $tipo = (string)($row['tipo_accion'] ?? '');
    $json = json_decode((string)($row['json_cambio'] ?? '{}'), true);
    if (!is_array($json)) {
        $json = [];
    }
    $producto = trim((string)($json['producto'] ?? $json['nombre_producto_pantalla'] ?? ''));

    switch ($tipo) {
        case 'añadir':
            $qty = (int)($json['cantidad'] ?? 1);
            return $producto !== ''
                ? "Añadido: $producto" . ($qty > 1 ? " ×$qty" : '')
                : 'Producto añadido';
        case 'borrar':
            $qty = (int)($json['cantidad'] ?? 1);
            return $producto !== ''
                ? "Eliminado: $producto" . ($qty > 1 ? " ×$qty" : '')
                : 'Producto eliminado';
        case 'modificar':
            $partes = [];
            if ($producto !== '') {
                $partes[] = $producto;
            }
            if (isset($json['cantidad_old'], $json['cantidad_new'])
                && (int)$json['cantidad_old'] !== (int)$json['cantidad_new']) {
                $partes[] = 'cantidad ' . (int)$json['cantidad_old'] . ' → ' . (int)$json['cantidad_new'];
            }
            $co = trim((string)($json['comentario_old'] ?? ''));
            $cn = trim((string)($json['comentario_new'] ?? ''));
            if ($co !== $cn) {
                $partes[] = 'nota actualizada';
            }
            return $partes !== [] ? 'Modificado: ' . implode(' · ', $partes) : 'Pedido modificado';
        case 'cambio_mesa':
            $origen = (int)($json['mesa_origen'] ?? 0);
            $dest = (int)($json['mesa_dest'] ?? 0);
            if ($producto !== '' && $origen > 0 && $dest > 0) {
                return "Movido mesa $origen → $dest: $producto";
            }
            return 'Línea movida de mesa';
        case 'traspaso_mesa':
            $origen = (int)($json['mesa_origen'] ?? 0);
            $dest = (int)($json['mesa_destino'] ?? 0);
            if ($origen > 0 && $dest > 0) {
                return "Traspaso de mesa $origen a mesa $dest";
            }
            return 'Traspaso de mesa';
        case 'nota_libre':
            $t = trim((string)($json['texto'] ?? ''));
            return $t !== '' ? "Nota: $t" : 'Nota libre añadida';
        case 'nota_libre_editar':
            return 'Nota libre modificada';
        default:
            return '';
    }
}

function pedidoObtenerPorToken(string $token): array {
    if (!preg_match('/^[a-f0-9]{32}$/', $token)) {
        pedidoJsonError('Código no válido', 404);
    }

    $db = pedidoGetDB();
    pedidoEnsureTokenColumn($db);

    $cab = null;
    $historico = false;

    $st = $db->prepare('SELECT * FROM pedido_cabecera WHERE token_publico = ? LIMIT 1');
    $st->execute([$token]);
    $cab = $st->fetch(PDO::FETCH_ASSOC);

    if (!$cab) {
        $stH = $db->prepare(
            'SELECT * FROM pedido_cabecera_historico WHERE token_publico = ? LIMIT 1'
        );
        $stH->execute([$token]);
        $cab = $stH->fetch(PDO::FETCH_ASSOC);
        $historico = (bool)$cab;
    }

    if (!$cab) {
        pedidoJsonError('Pedido no encontrado', 404);
    }

    $idPedido = (int)$cab['id_pedido'];
    $idMesa = (int)$cab['id_mesa'];

    if ($historico) {
        $stDet = $db->prepare(
            'SELECT cantidad, comentario, nombre_producto_pantalla, opciones_elegidas,
                    hora_pedido, urgente
               FROM pedido_detalles_historico
              WHERE id_pedido = ?
              ORDER BY orden, id_linea'
        );
    } else {
        $stDet = $db->prepare(
            'SELECT cantidad, comentario, nombre_producto_pantalla, opciones_elegidas,
                    hora_pedido, urgente
               FROM pedido_detalles
              WHERE id_pedido = ?
              ORDER BY orden, id_linea'
        );
    }
    $stDet->execute([$idPedido]);
    $detallesRaw = $stDet->fetchAll(PDO::FETCH_ASSOC);

    $lineas = [];
    foreach ($detallesRaw as $d) {
        $opciones = [];
        if (!empty($d['opciones_elegidas'])) {
            $decoded = json_decode((string)$d['opciones_elegidas'], true);
            if (is_array($decoded)) {
                foreach ($decoded as $op) {
                    if (is_array($op) && isset($op['nombre'])) {
                        $opciones[] = (string)$op['nombre'];
                    } elseif (is_string($op)) {
                        $opciones[] = $op;
                    }
                }
            }
        }
        $comentario = trim((string)($d['comentario'] ?? ''));
        if ($comentario === 'Menú del día') {
            $comentario = '';
        }
        $lineas[] = [
            'nombre'     => (string)($d['nombre_producto_pantalla'] ?? ''),
            'cantidad'   => (int)($d['cantidad'] ?? 1),
            'opciones'   => $opciones,
            'comentario' => $comentario,
            'hora'       => $d['hora_pedido'] ?? null,
            'urgente'    => (int)($d['urgente'] ?? 0) === 1,
        ];
    }

    $stCam = $db->prepare(
        'SELECT r.fecha_hora, r.tipo_accion, r.json_cambio
           FROM registro_cambios r
          WHERE (
                CAST(JSON_UNQUOTE(JSON_EXTRACT(r.json_cambio, \'$.id_pedido\')) AS UNSIGNED) = ?
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
          ORDER BY r.fecha_hora ASC
          LIMIT 300'
    );
    $stCam->execute([$idPedido, $idMesa, $idMesa, $idMesa, $idMesa]);
    $cambios = [];
    foreach ($stCam->fetchAll(PDO::FETCH_ASSOC) as $row) {
        $texto = pedidoTextoCambio($row);
        if ($texto === '') {
            continue;
        }
        $cambios[] = [
            'hora'  => (string)$row['fecha_hora'],
            'tipo'  => (string)$row['tipo_accion'],
            'texto' => $texto,
        ];
    }

    return [
        'mesa'               => $idMesa,
        'hora_creacion'      => (string)($cab['hora_creacion'] ?? ''),
        'hora_ultima_accion' => (string)($cab['hora_ultima_accion'] ?? ''),
        'hora_cierre'        => $historico ? (string)($cab['hora_cierre'] ?? '') : null,
        'cerrado'            => $historico,
        'nombre_cliente'     => trim((string)($cab['nombre_cliente'] ?? '')),
        'lineas'             => $lineas,
        'modificaciones'     => $cambios,
    ];
}
