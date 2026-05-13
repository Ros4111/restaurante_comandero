<?php
// backend/api/endpoints/catalogo.php
declare(strict_types=1);

function ensureTablaCodigosColumn(PDO $db): void {
    try {
        $check = $db->query("SHOW COLUMNS FROM impresoras LIKE 'tabla_codigos'");
        $exists = $check && $check->fetch();
        if (!$exists) {
            $db->exec("ALTER TABLE impresoras ADD COLUMN tabla_codigos VARCHAR(32) NOT NULL DEFAULT 'CP1252' AFTER puerto");
        }
    } catch (Throwable $e) {
        // Si falla el ALTER o la comprobación, el SELECT posterior devolverá error controlado.
    }
}

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

    $cats = $db->query(
        'SELECT id_categoria, id_categoria_padre, nombre_categoria, nombre_imagen, disponible, orden FROM categoria_producto ORDER BY orden'
    )->fetchAll();

    $prods = $db->query(
        'SELECT id_producto, nombre_producto_pantalla, id_categoria,
                texto_imprimir_cocina, id_impresora, disponible, orden,
                base_imponible, porcentaje_IVA
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
                suplemento_sin_iva, porcentaje_IVA
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
