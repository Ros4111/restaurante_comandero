<?php
declare(strict_types=1);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

$configPath = __DIR__ . '/config.php';
if (!is_readable($configPath)) {
    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'ok'    => false,
        'error' => 'Falta config.php. Copie config.example.php a config.php.',
    ], JSON_UNESCAPED_UNICODE);
    exit;
}

require $configPath;
require __DIR__ . '/lib.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    pedidoJsonError('Método no permitido', 405);
}

$token = trim((string)($_GET['token'] ?? ''));
if ($token === '') {
  $path = parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH) ?: '';
  $parts = array_values(array_filter(explode('/', trim($path, '/'))));
  $last = $parts !== [] ? end($parts) : '';
  if (preg_match('/^[a-f0-9]{32}$/i', $last)) {
    $token = strtolower($last);
  }
}

if ($token === '') {
    pedidoJsonError('Falta código de pedido', 400);
}

try {
    pedidoJsonOk(pedidoObtenerPorToken(strtolower($token)));
} catch (Throwable $e) {
    pedidoJsonError('Error al cargar el pedido', 500);
}
