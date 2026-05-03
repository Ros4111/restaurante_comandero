<?php
// backend/api/endpoints/auth.php
declare(strict_types=1);

function endpointLoginSalt(): void {
    $idUsuario = (int)($_GET['id_usuario'] ?? 0);
    if ($idUsuario <= 0) jsonError('id_usuario inválido', 400);
    $db = getDB();
    $st = $db->prepare('SELECT salt FROM usuarios WHERE id_usuario = ? AND activo = 1');
    $st->execute([$idUsuario]);
    $salt = $st->fetchColumn();
    if (!$salt) jsonError('Usuario no encontrado', 404);
    jsonOk(['salt' => $salt]);
}

function endpointLogin(): void {
    $body = getBody();
    $idUsuario = (int)($body['id_usuario'] ?? 0);
    $password  = trim($body['password'] ?? '');
    $passwordHashClient = trim((string)($body['password_hash'] ?? ''));

    if (!$idUsuario || ($password === '' && $passwordHashClient === '')) {
        jsonError('Datos incompletos', 400);
    }

    $db = getDB();
    $st = $db->prepare('SELECT id_usuario, nombre_usuario, password_hash, salt, permisos
                         FROM usuarios WHERE id_usuario = ? AND activo = 1');
    $st->execute([$idUsuario]);
    $user = $st->fetch();

    if (!$user) jsonError('Usuario no encontrado', 404);

    $hash = $passwordHashClient !== ''
        ? $passwordHashClient
        : hash('sha256', $user['salt'] . $password);
    if (!hash_equals($user['password_hash'], $hash)) {
        jsonError('Contraseña incorrecta', 401);
    }

    $token = JWT::encode([
        'sub'  => $user['id_usuario'],
        'name' => $user['nombre_usuario'],
        'rol'  => $user['permisos'],
        'iat'  => time(),
        'exp'  => time() + JWT_EXPIRY,
    ]);

    jsonOk([
        'token'    => $token,
        'usuario'  => [
            'id'       => $user['id_usuario'],
            'nombre'   => $user['nombre_usuario'],
            'permisos' => $user['permisos'],
        ],
    ]);
}
