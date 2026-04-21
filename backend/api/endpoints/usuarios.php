<?php
// backend/api/endpoints/usuarios.php
declare(strict_types=1);

function endpointUsuariosLista(): void {
    $db = getDB();
    $st = $db->query('SELECT id_usuario, nombre_usuario, permisos, orden
                       FROM usuarios WHERE activo = 1 ORDER BY orden, nombre_usuario');
    jsonOk($st->fetchAll());
}
