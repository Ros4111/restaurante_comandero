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

function endpointCatalogo(array $payload): void {
    $db = getDB();
    ensureTablaCodigosColumn($db);

    $cats = $db->query(
        'SELECT id_categoria, id_categoria_padre, nombre_categoria, nombre_imagen, disponible, orden FROM categoria_producto ORDER BY orden'
    )->fetchAll();

    $prods = $db->query(
        'SELECT id_producto, nombre_producto, id_categoria,
                texto_imprimir, id_impresora, disponible, orden
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
                nombre_opcion, predeterminado, disponible, orden
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
