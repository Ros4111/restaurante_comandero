<?php
// backend/api/endpoints/catalogo.php
declare(strict_types=1);

function endpointCatalogoReordenar(array $payload): void {
    requireRole($payload, ['admin', 'supervisor']);

    $body  = getBody();
    $items = $body['items'] ?? [];

    if (!is_array($items) || count($items) === 0) {
        jsonError('Se requiere una lista de items no vacía');
    }

    $db = getDB();
    $db->beginTransaction();
    try {
        $stCat  = $db->prepare('UPDATE categoria_producto SET orden = ? WHERE id_categoria = ?');
        $stProd = $db->prepare('UPDATE productos SET orden = ? WHERE id_producto = ?');

        foreach ($items as $item) {
            $tipo  = $item['tipo']  ?? '';
            $id    = isset($item['id'])    ? (int)$item['id']    : null;
            $orden = isset($item['orden']) ? (int)$item['orden'] : null;

            if (!in_array($tipo, ['categoria', 'producto'], true) || $id === null || $orden === null) {
                $db->rollBack();
                jsonError("Item inválido: " . json_encode($item));
            }

            if ($tipo === 'categoria') {
                $stCat->execute([$orden, $id]);
            } else {
                $stProd->execute([$orden, $id]);
            }
        }

        $db->commit();
        jsonOk(['actualizados' => count($items)]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('Error al reordenar: ' . $e->getMessage(), 500);
    }
}

function endpointCatalogo(array $payload): void {
    $db = getDB();
    ensureTablaCodigosColumn($db);
    ensureAgotadoColumnProductos($db);

    $cats = $db->query(
        'SELECT id_categoria, id_categoria_padre, nombre_categoria, nombre_imagen, disponible, orden FROM categoria_producto ORDER BY orden'
    )->fetchAll();

    $prods = $db->query(
        'SELECT id_producto, nombre_producto_pantalla, id_categoria,
                texto_imprimir_cocina, id_impresora, disponible,
                COALESCE(agotado, 0) AS agotado, orden,
                base_imponible, porcentaje_IVA, COALESCE(filtro, \'\') AS filtro
           FROM productos ORDER BY orden, id_producto'
    )->fetchAll();

    // Grupos
    $grupos = $db->query(
        'SELECT id_grupo_opciones, nombre_grupo, disponible, orden
           FROM grupos_opciones ORDER BY orden'
    )->fetchAll();

    // Opciones
    $opciones = $db->query(
        'SELECT id_opcion, id_producto, id_grupo_opciones,
                nombre_opcion, predeterminado, disponible, orden,
                suplemento_sin_iva
           FROM productos_opciones ORDER BY id_producto, id_grupo_opciones, orden'
    )->fetchAll();

    // Impresoras
    $impresoras = $db->query(
        'SELECT id_impresora, nombre, ip, puerto, tabla_codigos FROM impresoras'
    )->fetchAll();

    jsonOk([
        'categorias' => $cats,
        'productos'  => $prods,
        'grupos'     => $grupos,
        'opciones'   => $opciones,
        'impresoras' => $impresoras,
    ]);
}

/** Huella del estado 86/agotado para SSE del catálogo. */
function _catalogoAgotadoRevision(PDO $db): string {
    ensureAgotadoColumnProductos($db);
    $row = $db->query(
        'SELECT COUNT(*) AS num_productos,
                COALESCE(SUM(COALESCE(agotado, 0)), 0) AS sum_agotado,
                COALESCE(MAX(id_producto), 0) AS max_id
           FROM productos
          WHERE disponible = 1'
    )->fetch(PDO::FETCH_ASSOC) ?: [];

    return md5(json_encode($row, JSON_UNESCAPED_UNICODE));
}

/** Marca o desmarca un producto como agotado (86). Cocina/barra según impresora. */
function endpointCatalogoMarcarAgotado(array $payload): void {
    require_once __DIR__ . '/servicio.php';
    requireServicioAccess($payload);

    $body = getBody();
    $idProducto = isset($body['id_producto']) ? (int)$body['id_producto'] : 0;
    if ($idProducto <= 0) {
        jsonError('id_producto requerido');
    }
    $agotado = !empty($body['agotado']) ? 1 : 0;

    $db = getDB();
    ensureAgotadoColumnProductos($db);

    $st = $db->prepare(
        'SELECT id_producto, id_impresora, disponible, COALESCE(agotado, 0) AS agotado
           FROM productos WHERE id_producto = ?'
    );
    $st->execute([$idProducto]);
    $prod = $st->fetch(PDO::FETCH_ASSOC);
    if (!$prod) {
        jsonError('Producto no encontrado', 404);
    }
    if ((int)$prod['disponible'] !== 1) {
        jsonError('El producto no está disponible en catálogo');
    }

    $idsImp = _impresoraIdsFiltro($payload, $db);
    if ($idsImp !== null && !in_array((int)$prod['id_impresora'], $idsImp, true)) {
        jsonError('No puedes marcar 86 en productos de otra estación', 403);
    }

    $db->prepare('UPDATE productos SET agotado = ? WHERE id_producto = ?')
        ->execute([$agotado, $idProducto]);

    logEvent(
        ($agotado ? '86 agotado' : '86 disponible') . " producto #$idProducto",
        'info'
    );

    jsonOk([
        'id_producto' => $idProducto,
        'agotado'     => $agotado === 1,
    ]);
}

/** SSE: avisa cuando cambia el estado agotado del catálogo (~1 s). */
function endpointCatalogoStream(array $payload): void {
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
    $lastRevision = _catalogoAgotadoRevision($db);
    $started = time();
    $maxSeconds = 55;
    $tick = 0;

    echo ": connected\n\n";
    flush();

    while (!connection_aborted() && (time() - $started) < $maxSeconds) {
        $revision = _catalogoAgotadoRevision($db);
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
