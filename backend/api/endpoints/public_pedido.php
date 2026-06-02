<?php
// backend/api/endpoints/public_pedido.php
declare(strict_types=1);

/**
 * Vista pública del pedido por token (sin login).
 */
function endpointPublicPedidoGet(string $token): void {
    if (!preg_match('/^[a-f0-9]{32}$/', $token)) {
        jsonError('Código no válido', 404);
    }

    $db = getDB();
    ensureTokenPublicoPedidoCabecera($db);

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
        jsonError('Pedido no encontrado', 404);
    }

    $idPedido = (int)$cab['id_pedido'];
    $idMesa = (int)$cab['id_mesa'];

    if ($historico) {
        $stDet = $db->prepare(
            'SELECT id_linea, id_producto, cantidad, comentario, nombre_producto_pantalla,
                    opciones_elegidas, orden, hora_pedido, urgente
               FROM pedido_detalles_historico
              WHERE id_pedido = ?
              ORDER BY orden, id_linea'
        );
    } else {
        $stDet = $db->prepare(
            'SELECT id_linea, id_producto, cantidad, comentario, nombre_producto_pantalla,
                    opciones_elegidas, orden, hora_pedido, urgente
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
        'SELECT r.fecha_hora, r.tipo_accion, r.json_cambio, u.nombre_usuario
           FROM registro_cambios r
           LEFT JOIN usuarios u ON u.id_usuario = r.id_usuario
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
        $texto = _textoCambioPublicoPedido($row);
        if ($texto === '') {
            continue;
        }
        $cambios[] = [
            'hora'  => (string)$row['fecha_hora'],
            'tipo'  => (string)$row['tipo_accion'],
            'texto' => $texto,
        ];
    }

    jsonOk([
        'mesa'              => $idMesa,
        'hora_creacion'     => (string)($cab['hora_creacion'] ?? ''),
        'hora_ultima_accion'=> (string)($cab['hora_ultima_accion'] ?? ''),
        'hora_cierre'       => $historico ? (string)($cab['hora_cierre'] ?? '') : null,
        'cerrado'           => $historico,
        'nombre_cliente'    => trim((string)($cab['nombre_cliente'] ?? '')),
        'lineas'            => $lineas,
        'modificaciones'    => $cambios,
    ]);
}

function _textoCambioPublicoPedido(array $row): string {
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
