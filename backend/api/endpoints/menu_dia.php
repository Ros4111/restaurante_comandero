<?php
// backend/api/endpoints/menu_dia.php
declare(strict_types=1);

const MENU_DIA_GRUPOS = ['primero', 'segundo', 'bebida', 'postre'];

function _menuDiaFechaValida(?string $fecha): string {
    $f = trim((string)($fecha ?? ''));
    if ($f === '') {
        return date('Y-m-d');
    }
    $dt = DateTime::createFromFormat('Y-m-d', $f);
    if (!$dt || $dt->format('Y-m-d') !== $f) {
        jsonError('fecha inválida (YYYY-MM-DD)');
    }
    return $f;
}

function _menuDiaProductoRow(PDO $db, array $row): array {
    return [
        'id_producto'              => (int)$row['id_producto'],
        'nombre_producto_pantalla' => (string)$row['nombre_producto_pantalla'],
        'id_impresora'             => (int)$row['id_impresora'],
        'agotado'                  => (int)($row['agotado'] ?? 0) === 1,
        'orden'                    => (int)($row['orden'] ?? 0),
    ];
}

function endpointMenuDiaGet(array $payload): void {
    $db = getDB();
    ensureMenuDelDiaTables($db);
    ensureAgotadoColumnProductos($db);

    $fecha = _menuDiaFechaValida($_GET['fecha'] ?? null);
    $idMenu = idProductoMenuDelDia($db);

    $stCfg = $db->prepare('SELECT * FROM menu_dia WHERE fecha = ?');
    $stCfg->execute([$fecha]);
    $cfg = $stCfg->fetch(PDO::FETCH_ASSOC);

    $grupos = [];
    foreach (MENU_DIA_GRUPOS as $g) {
        $grupos[$g] = [];
    }

    if ($cfg) {
        $stProd = $db->prepare(
            'SELECT p.id_producto, p.nombre_producto_pantalla, p.id_impresora,
                    COALESCE(p.agotado, 0) AS agotado, m.orden, m.grupo
               FROM menu_dia_producto m
               INNER JOIN productos p ON p.id_producto = m.id_producto
              WHERE m.fecha = ?
                AND p.disponible = 1
              ORDER BY m.grupo, m.orden, p.nombre_producto_pantalla'
        );
        $stProd->execute([$fecha]);
        foreach ($stProd->fetchAll(PDO::FETCH_ASSOC) as $row) {
            $grupo = (string)$row['grupo'];
            if (!isset($grupos[$grupo])) {
                continue;
            }
            $grupos[$grupo][] = _menuDiaProductoRow($db, $row);
        }
    }

    $activo = $cfg && (int)($cfg['activo'] ?? 0) === 1;
    $tienePlatos = false;
    foreach (['primero', 'segundo', 'bebida'] as $g) {
        if ($grupos[$g] !== []) {
            $tienePlatos = true;
            break;
        }
    }

    jsonOk([
        'fecha'                          => $fecha,
        'id_producto_menu'               => $idMenu,
        'activo'                         => $activo && $tienePlatos && $idMenu !== null,
        'descuento_bebida_alternativa_pct'=> (float)($cfg['descuento_bebida_alternativa_pct'] ?? 0),
        'notas'                          => (string)($cfg['notas'] ?? ''),
        'grupos'                         => $grupos,
    ]);
}

function endpointMenuDiaGuardar(array $payload): void {
    requireRole($payload, ['admin', 'supervisor']);

    $body = getBody();
    $fecha = _menuDiaFechaValida($body['fecha'] ?? null);
    $activo = !empty($body['activo']) ? 1 : 0;
    $descuento = isset($body['descuento_bebida_alternativa_pct'])
        ? (float)$body['descuento_bebida_alternativa_pct']
        : 0.0;
    if ($descuento < 0 || $descuento > 100) {
        jsonError('descuento_bebida_alternativa_pct debe estar entre 0 y 100');
    }
    $notas = trim((string)($body['notas'] ?? ''));
    $productos = $body['productos'] ?? [];
    if (!is_array($productos)) {
        jsonError('productos debe ser un objeto con grupos');
    }

    $db = getDB();
    ensureMenuDelDiaTables($db);

    $db->beginTransaction();
    try {
        $db->prepare(
            'INSERT INTO menu_dia (fecha, activo, suplemento_bebida_libre_sin_iva, descuento_bebida_alternativa_pct, notas)
             VALUES (?, ?, 0, ?, ?)
             ON DUPLICATE KEY UPDATE
                activo = VALUES(activo),
                descuento_bebida_alternativa_pct = VALUES(descuento_bebida_alternativa_pct),
                notas = VALUES(notas)'
        )->execute([$fecha, $activo, round($descuento, 2), $notas !== '' ? $notas : null]);

        $db->prepare('DELETE FROM menu_dia_producto WHERE fecha = ?')->execute([$fecha]);

        $stIns = $db->prepare(
            'INSERT INTO menu_dia_producto (fecha, grupo, id_producto, orden)
             VALUES (?, ?, ?, ?)'
        );
        $stCheck = $db->prepare(
            'SELECT id_producto FROM productos WHERE id_producto = ? AND disponible = 1'
        );

        foreach (MENU_DIA_GRUPOS as $grupo) {
            $lista = $productos[$grupo] ?? [];
            if (!is_array($lista)) {
                $db->rollBack();
                jsonError("Grupo inválido: $grupo");
            }
            $orden = 0;
            foreach ($lista as $idRaw) {
                $idProd = (int)$idRaw;
                if ($idProd <= 0) {
                    continue;
                }
                $stCheck->execute([$idProd]);
                if (!$stCheck->fetch()) {
                    $db->rollBack();
                    jsonError("Producto no disponible: #$idProd");
                }
                $stIns->execute([$fecha, $grupo, $idProd, $orden]);
                $orden++;
            }
        }

        $db->commit();
        logEvent("Menú del día configurado para $fecha", 'info');
        $_GET['fecha'] = $fecha;
        endpointMenuDiaGet($payload);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error al guardar menú: ' . $e->getMessage(), 500);
    }
}
