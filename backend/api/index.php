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

if ($uri === '/impresoras/config' && $method === 'GET') {
    require __DIR__ . '/endpoints/impresoras.php';
    endpointImpresorasConfigGet();
}
if ($uri === '/impresoras/config' && $method === 'POST') {
    require __DIR__ . '/endpoints/impresoras.php';
    endpointImpresorasConfigSave();
}
if ($uri === '/impresoras/config/crear' && $method === 'POST') {
    require __DIR__ . '/endpoints/impresoras.php';
    endpointImpresoraCrear();
}
if (preg_match('#^/impresoras/config/(\d+)/eliminar$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/impresoras.php';
    endpointImpresoraEliminar((int)$m[1]);
}

if ($uri === '/check-opciones' && $method === 'GET') {
    require __DIR__ . '/endpoints/check_opciones.php';
    endpointCheckOpciones();
}

// ── Rutas protegidas ─────────────────────────────────────────
$payload = requireAuth();

// Catálogo
if ($uri === '/catalogo' && $method === 'GET') {
    require __DIR__ . '/endpoints/catalogo.php';
    endpointCatalogo($payload);
}
if ($uri === '/catalogo/reordenar' && $method === 'POST') {
    require __DIR__ . '/endpoints/catalogo.php';
    endpointCatalogoReordenar($payload);
}

// Usuarios admin
if ($uri === '/usuarios/admin/lista' && $method === 'GET') {
    require __DIR__ . '/endpoints/usuarios.php';
    endpointUsuariosAdminLista($payload);
}
if ($uri === '/usuarios/admin/crear' && $method === 'POST') {
    require __DIR__ . '/endpoints/usuarios.php';
    endpointUsuariosAdminCrear($payload);
}
if (preg_match('#^/usuarios/admin/(\d+)/actualizar$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/usuarios.php';
    endpointUsuariosAdminActualizar($payload, (int)$m[1]);
}
if (preg_match('#^/usuarios/admin/(\d+)/eliminar$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/usuarios.php';
    endpointUsuariosAdminEliminar($payload, (int)$m[1]);
}

// Productos (admin / supervisor)
if ($uri === '/productos' && $method === 'GET') {
    require __DIR__ . '/endpoints/productos.php';
    endpointProductosListar($payload);
}
if (preg_match('#^/productos/(\d+)$#', $uri, $m) && $method === 'GET') {
    require __DIR__ . '/endpoints/productos.php';
    endpointProductoGet($payload, (int)$m[1]);
}
if ($uri === '/productos/crear' && $method === 'POST') {
    require __DIR__ . '/endpoints/productos.php';
    endpointProductoCrear($payload);
}
if (preg_match('#^/productos/(\d+)/actualizar$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/productos.php';
    endpointProductoActualizar($payload, (int)$m[1]);
}
if (preg_match('#^/productos/(\d+)/eliminar$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/productos.php';
    endpointProductoEliminar($payload, (int)$m[1]);
}
if ($uri === '/productos/copiar' && $method === 'POST') {
    require __DIR__ . '/endpoints/productos.php';
    endpointProductoCopiar($payload);
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
if (preg_match('#^/mesas/(\d+)/traspasar$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/mesas.php';
    endpointMesaTraspasar($payload, (int)$m[1]);
}

// Dispositivos
if ($uri === '/dispositivos/ping' && $method === 'POST') {
    require __DIR__ . '/endpoints/dispositivos.php';
    endpointDispositivoPing($payload);
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
if (preg_match('#^/pedidos/(\d+)/nota-libre$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/pedidos.php';
    endpointNotaLibre($payload, (int)$m[1]);
}
if (preg_match('#^/pedidos/(\d+)/nota-libre/(\d+)/editar$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/pedidos.php';
    endpointNotaLibreEditar($payload, (int)$m[1], (int)$m[2]);
}

// Historial de mesas (solo admin)
if ($uri === '/historico/mesas' && $method === 'GET') {
    require __DIR__ . '/endpoints/historico.php';
    endpointHistoricoMesasListar($payload);
}
if (preg_match('#^/historico/mesas/(\d+)$#', $uri, $m) && $method === 'GET') {
    require __DIR__ . '/endpoints/historico.php';
    endpointHistoricoMesaDetalle($payload, (int)$m[1]);
}
if (preg_match('#^/historico/mesas/(\d+)/reabrir$#', $uri, $m) && $method === 'POST') {
    require __DIR__ . '/endpoints/historico.php';
    endpointHistoricoMesaReabrir($payload, (int)$m[1]);
}

// Servicio en mesa (líneas pendientes de servir)
if ($uri === '/servicio/pendientes' && $method === 'GET') {
    require __DIR__ . '/endpoints/servicio.php';
    endpointServicioPendientes($payload);
}
if ($uri === '/servicio/marcar-servido' && $method === 'POST') {
    require __DIR__ . '/endpoints/servicio.php';
    endpointServicioMarcarServido($payload);
}

jsonError('Ruta no encontrada', 404);
