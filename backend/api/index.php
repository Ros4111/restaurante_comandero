<?php
// backend/api/index.php
// Punto de entrada único — Apache rewrite dirige todo aquí
declare(strict_types=1);

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Authorization, Content-Type');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

require_once '/home/guardab/restaurante/config/database.php';
require_once '/home/guardab/restaurante/lib/jwt.php';
require_once '/home/guardab/restaurante/lib/helpers.php';

$uri    = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];

// Normaliza: elimina prefijo /api
$uri = preg_replace('#^/api#', '', $uri);
$uri = rtrim($uri, '/') ?: '/';

// ── Rutas públicas ──────────────────────────────────────────
if ($uri === '/usuarios/lista' && $method === 'GET') {
    require __DIR__ . '/endpoints/usuarios.php';
    endpointUsuariosLista();
}

if ($uri === '/auth/login' && $method === 'POST') {
    require __DIR__ . '/endpoints/auth.php';
    endpointLogin();
}

if ($uri === '/health' && $method === 'GET') {
    jsonOk(['status' => 'ok', 'ts' => date('c')]);
}

// ── Rutas protegidas ─────────────────────────────────────────
$payload = requireAuth();

// Catálogo
if ($uri === '/catalogo' && $method === 'GET') {
    require __DIR__ . '/endpoints/catalogo.php';
    endpointCatalogo($payload);
}

// Mesas
if ($uri === '/mesas' && $method === 'GET') {
    require __DIR__ . '/endpoints/mesas.php';
    endpointMesasListar($payload);
}
if ($uri === '/mesas/abrir' && $method === 'POST') {
    require __DIR__ . '/endpoints/mesas.php';
    endpointMesaAbrir($payload);
}
if (preg_match('#^/mesas/(\d+)/bloquear$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/mesas.php';
    endpointMesaBloquear($payload, (int)$m[1]);
}
if (preg_match('#^/mesas/(\d+)/ping$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/mesas.php';
    endpointMesaPing($payload, (int)$m[1]);
}
if (preg_match('#^/mesas/(\d+)/cerrar$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/mesas.php';
    endpointMesaCerrar($payload, (int)$m[1]);
}
if (preg_match('#^/mesas/(\d+)/expulsar$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/mesas.php';
    endpointMesaExpulsar($payload, (int)$m[1]);
}

// Pedidos
if (preg_match('#^/pedidos/(\d+)$#', $uri, $m) && $method === 'GET') {
    require __DIR__ . '/endpoints/pedidos.php';
    endpointPedidoGet($payload, (int)$m[1]);
}
if (preg_match('#^/pedidos/(\d+)/guardar$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/pedidos.php';
    endpointPedidoGuardar($payload, (int)$m[1]);
}

jsonError('Ruta no encontrada', 404);
