<?php
// backend/api/endpoints/auth.php
declare(strict_types=1);

function endpointLogin(): void {
    $body = getBody();
    $idUsuario = (int)($body['id_usuario'] ?? 0);
    $passwordSha256 = trim((string)($body['password_sha256'] ?? ''));

    if (!$idUsuario || $passwordSha256 === '') {
        jsonError('Datos incompletos', 400);
    }
    if (!preg_match('/^[a-f0-9]{64}$/', $passwordSha256)) {
        jsonError('password_sha256 inválido', 400);
    }

    $db = getDB();
    ensureImpresoraColumnUsuarios($db);
    $st = $db->prepare('SELECT id_usuario, nombre_usuario, password_hash, permisos,
                                COALESCE(impresora, 0) AS impresora
                         FROM usuarios WHERE id_usuario = ? AND activo = 1');
    $st->execute([$idUsuario]);
    $user = $st->fetch();

    if (!$user) jsonError('Usuario no encontrado', 404);

    if (!hash_equals((string)$user['password_hash'], $passwordSha256)) {
        jsonError('Contraseña incorrecta', 401);
    }

    $idImpresora = (int)($user['impresora'] ?? 0);

    $token = JWT::encode([
        'sub'       => $user['id_usuario'],
        'name'      => $user['nombre_usuario'],
        'rol'       => $user['permisos'],
        'impresora' => $idImpresora,
        'iat'       => time(),
        'exp'       => time() + JWT_EXPIRY,
    ]);

    jsonOk([
        'token'    => $token,
        'usuario'  => [
            'id'        => $user['id_usuario'],
            'nombre'    => $user['nombre_usuario'],
            'permisos'  => $user['permisos'],
            'impresora' => $idImpresora,
        ],
    ]);
}
