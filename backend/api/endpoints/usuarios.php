<?php
// backend/api/endpoints/usuarios.php
declare(strict_types=1);

function endpointUsuariosLista(): void {
    $db = getDB();
    $st = $db->query('SELECT id_usuario, nombre_usuario, orden
                       FROM usuarios WHERE activo = 1 ORDER BY orden, nombre_usuario');
    jsonOk($st->fetchAll());
}

function endpointUsuariosAdminLista(array $payload): void {
    requireRole($payload, ['admin']);
    $db = getDB();
    $st = $db->query('SELECT id_usuario, nombre_usuario, permisos, orden, activo
                       FROM usuarios ORDER BY orden, nombre_usuario where activo = 1');
    jsonOk($st->fetchAll());
}

function endpointUsuariosAdminCrear(array $payload): void {
    requireRole($payload, ['admin']);
    $body = getBody();
    $nombre = trim((string)($body['nombre_usuario'] ?? ''));
    $passwordSha256 = trim((string)($body['password_sha256'] ?? ''));
    $permisos = trim((string)($body['permisos'] ?? 'camarero'));
    $orden = (int)($body['orden'] ?? 0);
    $activo = !array_key_exists('activo', $body) || !empty($body['activo']) ? 1 : 0;

    if ($nombre === '' || $passwordSha256 === '') {
        jsonError('Nombre y contraseña son obligatorios', 400);
    }
    if (!in_array($permisos, ['camarero', 'supervisor', 'admin'], true)) {
        jsonError('Permisos inválidos', 400);
    }
    if (!preg_match('/^[a-f0-9]{64}$/', $passwordSha256)) {
        jsonError('password_sha256 inválido', 400);
    }
    $db = getDB();
    $st = $db->prepare(
        'INSERT INTO usuarios (nombre_usuario, password_hash, permisos, orden, activo)
         VALUES (?, ?, ?, ?, ?)'
    );
    $st->execute([$nombre, $passwordSha256, $permisos, $orden, $activo]);
    jsonOk(['id_usuario' => (int)$db->lastInsertId()]);
}

function endpointUsuariosAdminActualizar(array $payload, int $idUsuario): void {
    requireRole($payload, ['admin']);
    if ($idUsuario <= 0) jsonError('Id inválido', 400);

    $body = getBody();
    $nombre = trim((string)($body['nombre_usuario'] ?? ''));
    $passwordSha256 = trim((string)($body['password_sha256'] ?? ''));
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
    if ($passwordSha256 !== '') {
        if (!preg_match('/^[a-f0-9]{64}$/', $passwordSha256)) {
            jsonError('password_sha256 inválido', 400);
        }
        $st = $db->prepare(
            'UPDATE usuarios
                SET nombre_usuario = ?, permisos = ?, orden = ?, activo = ?, password_hash = ?
              WHERE id_usuario = ?'
        );
        $st->execute([$nombre, $permisos, $orden, $activo, $passwordSha256, $idUsuario]);
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
