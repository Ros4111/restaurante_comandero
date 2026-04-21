<?php
// backend/api/endpoints/catalogo.php
declare(strict_types=1);

function endpointCatalogo(array $payload): void {
    $db = getDB();

    $cats = $db->query(
        'SELECT id_categoria, id_categoria_padre, nombre_categoria,
                nombre_imagen, disponible, orden
           FROM categoria_producto ORDER BY orden, id_categoria'
    )->fetchAll();

    $prods = $db->query(
        'SELECT id_producto, nombre_producto, id_categoria,
                texto_imprimir, id_impresora, disponible, personalizable, orden
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
        'SELECT id_impresora, nombre, ip, puerto FROM impresoras'
    )->fetchAll();

    jsonOk([
        'categorias' => $cats,
        'productos'  => $prods,
        'grupos'     => $grupos,
        'opciones'   => $opciones,
        'impresoras' => $impresoras,
    ]);
}
