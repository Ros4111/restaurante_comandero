<?php
// backend/api/endpoints/usuarios.php
declare(strict_types=1);

function endpointUsuariosLista(): void {
    $db = getDB();
    $st = $db->query('SELECT id_usuario, nombre_usuario, permisos, orden
                       FROM usuarios WHERE activo = 1 ORDER BY orden, nombre_usuario');
    jsonOk($st->fetchAll());
}

function endpointUsuariosAdminLista(array $payload): void {
    requireRole($payload, ['admin']);
    $db = getDB();
    $st = $db->query('SELECT id_usuario, nombre_usuario, permisos, orden, activo
                       FROM usuarios ORDER BY activo DESC, orden, nombre_usuario');
    jsonOk($st->fetchAll());
}

function endpointUsuariosAdminCrear(array $payload): void {
    requireRole($payload, ['admin']);
    $body = getBody();
    $nombre = trim((string)($body['nombre_usuario'] ?? ''));
    $password = trim((string)($body['password'] ?? ''));
    $permisos = trim((string)($body['permisos'] ?? 'camarero'));
    $orden = (int)($body['orden'] ?? 0);
    $activo = !array_key_exists('activo', $body) || !empty($body['activo']) ? 1 : 0;

    if ($nombre === '' || $password === '') {
        jsonError('Nombre y contraseña son obligatorios', 400);
    }
    if (!in_array($permisos, ['camarero', 'supervisor', 'admin'], true)) {
        jsonError('Permisos inválidos', 400);
    }

    $db = getDB();
    $salt = bin2hex(random_bytes(16));
    $hash = hash('sha256', $salt . $password);
    $st = $db->prepare(
        'INSERT INTO usuarios (nombre_usuario, password_hash, salt, permisos, orden, activo)
         VALUES (?, ?, ?, ?, ?, ?)'
    );
    $st->execute([$nombre, $hash, $salt, $permisos, $orden, $activo]);
    jsonOk(['id_usuario' => (int)$db->lastInsertId()]);
}

function endpointUsuariosAdminActualizar(array $payload, int $idUsuario): void {
    requireRole($payload, ['admin']);
    if ($idUsuario <= 0) jsonError('Id inválido', 400);

    $body = getBody();
    $nombre = trim((string)($body['nombre_usuario'] ?? ''));
    $password = trim((string)($body['password'] ?? ''));
    $permisos = trim((string)($body['permisos'] ?? 'camarero'));
    $orden = (int)($body['orden'] ?? 0);
    $activo = !array_key_exists('activo', $body) || !empty($body['activo']) ? 1 : 0;

    if ($nombre === '') {
        jsonError('Nombre obligatorio', 400);
    }
    if (!in_array($permisos, ['camarero', 'supervisor', 'admin'], true)) {
        jsonError('Permisos inválidos', 400);
    }

    $db = getDB();
    if ($password !== '') {
        $salt = bin2hex(random_bytes(16));
        $hash = hash('sha256', $salt . $password);
        $st = $db->prepare(
            'UPDATE usuarios
                SET nombre_usuario = ?, permisos = ?, orden = ?, activo = ?, password_hash = ?, salt = ?
              WHERE id_usuario = ?'
        );
        $st->execute([$nombre, $permisos, $orden, $activo, $hash, $salt, $idUsuario]);
    } else {
        $st = $db->prepare(
            'UPDATE usuarios
                SET nombre_usuario = ?, permisos = ?, orden = ?, activo = ?
              WHERE id_usuario = ?'
        );
        $st->execute([$nombre, $permisos, $orden, $activo, $idUsuario]);
    }
    if ($st->rowCount() === 0) {
        $chk = $db->prepare('SELECT 1 FROM usuarios WHERE id_usuario = ?');
        $chk->execute([$idUsuario]);
        if (!$chk->fetch()) jsonError('Usuario no encontrado', 404);
    }
    jsonOk(['ok' => true]);
}

function endpointUsuariosAdminEliminar(array $payload, int $idUsuario): void {
    requireRole($payload, ['admin']);
    if ($idUsuario <= 0) jsonError('Id inválido', 400);
    $db = getDB();
    $st = $db->prepare('UPDATE usuarios SET activo = 0 WHERE id_usuario = ?');
    $st->execute([$idUsuario]);
    if ($st->rowCount() === 0) jsonError('Usuario no encontrado', 404);
    jsonOk(['ok' => true]);
}
