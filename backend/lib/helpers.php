<?php
// backend/lib/helpers.php
declare(strict_types=1);

function jsonOk(mixed $data, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => true, 'data' => $data], JSON_UNESCAPED_UNICODE);
    exit;
}

function jsonError(string $msg, int $code = 400): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['ok' => false, 'error' => $msg], JSON_UNESCAPED_UNICODE);
    exit;
}

function requireAuth(): array {
    // En hosting compartido Apache no pasa Authorization directamente
    $h = $_SERVER['HTTP_AUTHORIZATION']
      ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION']
      ?? getallheaders()['Authorization']
      ?? '';

    if (!preg_match('/^Bearer (.+)$/i', $h, $m)) jsonError('No autorizado', 401);
    $payload = JWT::decode($m[1]);
    if (!$payload) jsonError('Token inválido o expirado', 401);
    return $payload;
}

function requireRole(array $payload, array $roles): void {
    if (!in_array($payload['rol'], $roles, true)) jsonError('Sin permisos', 403);
}

function getBody(): array {
    $raw = file_get_contents('php://input');
    $data = json_decode($raw ?: '{}', true);
    return is_array($data) ? $data : [];
}

function logEvent(string $desc, string $level = 'info'): void {
    try {
        $db = getDB();
        $st = $db->prepare('INSERT INTO eventos_sistema (descripcion, nivel) VALUES (?,?)');
        $st->execute([$desc, $level]);
    } catch (Throwable $e) {}
}
