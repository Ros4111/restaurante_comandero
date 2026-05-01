<?php
// backend/api/endpoints/productos.php
declare(strict_types=1);

/**
 * Sustituye filas en productos_opciones para un producto.
 * $raw: lista de { id_grupo_opciones, nombre_opcion, predeterminado?, disponible?, orden? }
 */
function productoGuardarOpciones(PDO $db, int $idProducto, mixed $raw): void {
    if (!is_array($raw)) {
        return;
    }
    $db->prepare('DELETE FROM productos_opciones WHERE id_producto = ?')->execute([$idProducto]);
    if ($raw === []) {
        return;
    }
    $ins = $db->prepare(
        'INSERT INTO productos_opciones (id_producto, id_grupo_opciones, nombre_opcion, predeterminado, disponible, orden)
         VALUES (?,?,?,?,?,?)'
    );
    $ordenAuto = [];
    $yaPredeterminado = [];
    foreach ($raw as $o) {
        if (!is_array($o)) {
            continue;
        }
        $idGr = (int)($o['id_grupo_opciones'] ?? 0);
        $nom = trim((string)($o['nombre_opcion'] ?? ''));
        if ($idGr <= 0 || $nom === '') {
            continue;
        }
        $pred = !empty($o['predeterminado']) ? 1 : 0;
        if ($pred && !empty($yaPredeterminado[$idGr])) {
            $pred = 0;
        }
        if ($pred) {
            $yaPredeterminado[$idGr] = true;
        }
        $disp = array_key_exists('disponible', $o)
            ? (!empty($o['disponible']) ? 1 : 0)
            : 1;
        $ord = (int)($o['orden'] ?? 0);
        if ($ord <= 0) {
            $ordenAuto[$idGr] = ($ordenAuto[$idGr] ?? 0) + 1;
            $ord = $ordenAuto[$idGr];
        }
        $ins->execute([$idProducto, $idGr, $nom, $pred, $disp, $ord]);
    }
}

function endpointProductosListar(array $payload): void {
    requireRole($payload, ['admin', 'supervisor']);
    $db = getDB();
    $q = trim((string)($_GET['q'] ?? ''));

    if ($q === '') {
        $st = $db->query(
            'SELECT id_producto, nombre_producto, id_categoria, texto_imprimir,
                    id_impresora, disponible, orden
               FROM productos
           ORDER BY orden, id_producto
              LIMIT 150'
        );
        $rows = $st->fetchAll();
    } else {
        $like = '%' . $q . '%';
        $st = $db->prepare(
            'SELECT id_producto, nombre_producto, id_categoria, texto_imprimir,
                    id_impresora, disponible, orden
               FROM productos
              WHERE nombre_producto LIKE ? OR CAST(id_producto AS CHAR) LIKE ?
           ORDER BY nombre_producto
              LIMIT 100'
        );
        $st->execute([$like, $like . '%']);
        $rows = $st->fetchAll();
    }
    jsonOk($rows);
}

function endpointProductoGet(array $payload, int $id): void {
    requireRole($payload, ['admin', 'supervisor']);
    if ($id <= 0) jsonError('Id inválido', 400);
    $db = getDB();
    $st = $db->prepare(
        'SELECT id_producto, nombre_producto, id_categoria, texto_imprimir,
                id_impresora, disponible, orden
           FROM productos WHERE id_producto = ?'
    );
    $st->execute([$id]);
    $row = $st->fetch();
    if (!$row) jsonError('Producto no encontrado', 404);

    $stOp = $db->prepare(
        'SELECT id_opcion, id_grupo_opciones, nombre_opcion, predeterminado, disponible, orden
           FROM productos_opciones
          WHERE id_producto = ?
       ORDER BY id_grupo_opciones, orden, id_opcion'
    );
    $stOp->execute([$id]);
    $row['opciones'] = $stOp->fetchAll();

    jsonOk($row);
}

function endpointProductoCrear(array $payload): void {
    requireRole($payload, ['admin', 'supervisor']);
    $body = getBody();
    $nombre = trim((string)($body['nombre_producto'] ?? ''));
    $idCat = (int)($body['id_categoria'] ?? 0);
    if ($nombre === '' || $idCat <= 0) jsonError('Nombre e id_categoria son obligatorios', 400);

    $texto = trim((string)($body['texto_imprimir'] ?? $nombre));
    $idImp = (int)($body['id_impresora'] ?? 0);
    $disp = (int)!empty($body['disponible']);
    $orden = (int)($body['orden'] ?? 0);

    $db = getDB();
    if ($orden <= 0) {
        $mx = $db->prepare('SELECT COALESCE(MAX(orden), 0) + 1 FROM productos WHERE id_categoria = ?');
        $mx->execute([$idCat]);
        $orden = (int)$mx->fetchColumn();
    }

    $st = $db->prepare(
        'INSERT INTO productos (nombre_producto, id_categoria, texto_imprimir, id_impresora, disponible, orden)
         VALUES (?,?,?,?,?,?)'
    );
    $db->beginTransaction();
    try {
        $st->execute([$nombre, $idCat, $texto, $idImp, $disp, $orden]);
        $id = (int)$db->lastInsertId();
        if (array_key_exists('opciones', $body)) {
            productoGuardarOpciones($db, $id, $body['opciones']);
        }
        $db->commit();
        jsonOk(['id_producto' => $id]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error al crear producto', 500);
    }
}

function endpointProductoActualizar(array $payload, int $id): void {
    requireRole($payload, ['admin', 'supervisor']);
    if ($id <= 0) jsonError('Id inválido', 400);
    $body = getBody();
    $nombre = trim((string)($body['nombre_producto'] ?? ''));
    $idCat = (int)($body['id_categoria'] ?? 0);
    if ($nombre === '' || $idCat <= 0) jsonError('Nombre e id_categoria son obligatorios', 400);

    $texto = trim((string)($body['texto_imprimir'] ?? $nombre));
    $idImp = (int)($body['id_impresora'] ?? 0);
    $disp = (int)!empty($body['disponible']);
    $orden = (int)($body['orden'] ?? 0);

    $db = getDB();
    if ($orden <= 0) {
        $st0 = $db->prepare('SELECT orden FROM productos WHERE id_producto = ?');
        $st0->execute([$id]);
        $orden = (int)($st0->fetchColumn() ?: 0);
    }

    $st = $db->prepare(
        'UPDATE productos SET nombre_producto = ?, id_categoria = ?, texto_imprimir = ?,
                id_impresora = ?, disponible = ?, orden = ?
          WHERE id_producto = ?'
    );
    $db->beginTransaction();
    try {
        $st->execute([$nombre, $idCat, $texto, $idImp, $disp, $orden, $id]);
        if ($st->rowCount() === 0) {
            $chk = $db->prepare('SELECT 1 FROM productos WHERE id_producto = ?');
            $chk->execute([$id]);
            if (!$chk->fetch()) {
                $db->rollBack();
                jsonError('Producto no encontrado', 404);
            }
        }
        if (array_key_exists('opciones', $body)) {
            productoGuardarOpciones($db, $id, $body['opciones']);
        }
        $db->commit();
        jsonOk(['ok' => true]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error al actualizar producto', 500);
    }
}

function endpointProductoEliminar(array $payload, int $id): void {
    requireRole($payload, ['admin', 'supervisor']);
    if ($id <= 0) jsonError('Id inválido', 400);
    $db = getDB();
    $db->beginTransaction();
    try {
        $st1 = $db->prepare('DELETE FROM productos_opciones WHERE id_producto = ?');
        $st1->execute([$id]);
        $st2 = $db->prepare('DELETE FROM productos WHERE id_producto = ?');
        $st2->execute([$id]);
        if ($st2->rowCount() === 0) {
            $db->rollBack();
            jsonError('Producto no encontrado', 404);
        }
        $db->commit();
        jsonOk(['ok' => true]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('No se pudo eliminar (puede estar en uso en pedidos)', 409);
    }
}

function endpointProductoCopiar(array $payload): void {
    requireRole($payload, ['admin', 'supervisor']);
    $body = getBody();
    $idO = (int)($body['id_producto_origen'] ?? 0);
    if ($idO <= 0) jsonError('id_producto_origen requerido', 400);

    $db = getDB();
    $st = $db->prepare(
        'SELECT nombre_producto, id_categoria, texto_imprimir, id_impresora, disponible, orden
           FROM productos WHERE id_producto = ?'
    );
    $st->execute([$idO]);
    $orig = $st->fetch();
    if (!$orig) jsonError('Producto origen no encontrado', 404);

    $nombreNuevo = trim((string)($body['nombre_producto'] ?? ''));
    if ($nombreNuevo === '') {
        $nombreNuevo = $orig['nombre_producto'] . ' (copia)';
    }

    $mx = $db->prepare('SELECT COALESCE(MAX(orden), 0) + 1 FROM productos WHERE id_categoria = ?');
    $mx->execute([(int)$orig['id_categoria']]);
    $orden = (int)$mx->fetchColumn();

    $db->beginTransaction();
    try {
        $ins = $db->prepare(
            'INSERT INTO productos (nombre_producto, id_categoria, texto_imprimir, id_impresora, disponible, orden)
             VALUES (?,?,?,?,?,?,?)'
        );
        $ins->execute([
            $nombreNuevo,
            (int)$orig['id_categoria'],
            $orig['texto_imprimir'],
            (int)$orig['id_impresora'],
            (int)$orig['disponible'],
            $orden,
        ]);
        $idNuevo = (int)$db->lastInsertId();

        $op = $db->prepare(
            'SELECT id_grupo_opciones, nombre_opcion, predeterminado, disponible, orden
               FROM productos_opciones WHERE id_producto = ?'
        );
        $op->execute([$idO]);
        $opts = $op->fetchAll();

        if ($opts) {
            $insOp = $db->prepare(
                'INSERT INTO productos_opciones (id_producto, id_grupo_opciones, nombre_opcion, predeterminado, disponible, orden)
                 VALUES (?,?,?,?,?,?)'
            );
            foreach ($opts as $r) {
                $insOp->execute([
                    $idNuevo,
                    (int)$r['id_grupo_opciones'],
                    $r['nombre_opcion'],
                    (int)$r['predeterminado'],
                    (int)$r['disponible'],
                    (int)$r['orden'],
                ]);
            }
        }

        $db->commit();
        jsonOk(['id_producto' => $idNuevo]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error al copiar producto', 500);
    }
}
