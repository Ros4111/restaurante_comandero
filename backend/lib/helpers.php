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

function mensajeMesaBloqueadaSoloLectura(): string {
    return 'Bloqueada';
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

/** Solo el usuario con id_usuario = 1 (administrador principal). */
function requireUsuarioPrincipal(array $payload): void {
    if ((int)($payload['sub'] ?? 0) !== 1) {
        jsonError('Solo el administrador principal puede realizar esta acción', 403);
    }
}

function ensureImpresoraColumnUsuarios(PDO $db): void {
    try {
        $check = $db->query("SHOW COLUMNS FROM usuarios LIKE 'impresora'");
        if (!$check || !$check->fetch()) {
            $db->exec(
                'ALTER TABLE usuarios ADD COLUMN impresora INT UNSIGNED NOT NULL DEFAULT 0 AFTER activo'
            );
        }
    } catch (Throwable $e) {
        // El SELECT posterior fallará con mensaje claro si falta la columna.
    }
}

function ensureUrgenteColumnPedidoDetalles(PDO $db): void {
    try {
        $check = $db->query("SHOW COLUMNS FROM pedido_detalles LIKE 'urgente'");
        if (!$check || !$check->fetch()) {
            $db->exec(
                'ALTER TABLE pedido_detalles ADD COLUMN urgente TINYINT(1) NOT NULL DEFAULT 0 AFTER modificado_servicio'
            );
        }
    } catch (Throwable $e) {
        // El SELECT posterior fallará con mensaje claro si falta la columna.
    }
}

function ensureAgotadoColumnProductos(PDO $db): void {
    try {
        $check = $db->query("SHOW COLUMNS FROM productos LIKE 'agotado'");
        if (!$check || !$check->fetch()) {
            $db->exec(
                'ALTER TABLE productos ADD COLUMN agotado TINYINT(1) NOT NULL DEFAULT 0 AFTER disponible'
            );
        }
    } catch (Throwable $e) {
        // El SELECT posterior fallará con mensaje claro si falta la columna.
    }
}

function ensureMenuDelDiaTables(PDO $db): void {
    try {
        $db->exec(
            'CREATE TABLE IF NOT EXISTS menu_dia (
                fecha DATE NOT NULL PRIMARY KEY,
                activo TINYINT(1) NOT NULL DEFAULT 1,
                suplemento_bebida_libre_sin_iva DECIMAL(8,4) NOT NULL DEFAULT 0,
                notas VARCHAR(255) DEFAULT NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
        $db->exec(
            'CREATE TABLE IF NOT EXISTS menu_dia_producto (
                fecha DATE NOT NULL,
                grupo VARCHAR(20) NOT NULL,
                id_producto INT UNSIGNED NOT NULL,
                orden INT NOT NULL DEFAULT 0,
                PRIMARY KEY (fecha, grupo, id_producto),
                KEY idx_menu_dia_fecha_grupo (fecha, grupo)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
        );
    } catch (Throwable $e) {
        // El endpoint devolverá error claro si faltan tablas.
    }
    try {
        $check = $db->query(
            "SHOW COLUMNS FROM menu_dia LIKE 'descuento_bebida_alternativa_pct'"
        );
        if (!$check || !$check->fetch()) {
            $db->exec(
                'ALTER TABLE menu_dia ADD COLUMN descuento_bebida_alternativa_pct DECIMAL(5,2) NOT NULL DEFAULT 0 AFTER suplemento_bebida_libre_sin_iva'
            );
        }
    } catch (Throwable $e) {
    }
}

/** URL base para el QR del pedido (sin barra final). */
function urlBasePublicaPedido(): string {
    return 'https://www.guardamar.es/pedido';
}

function ensureTokenPublicoPedidoCabecera(PDO $db): void {
    try {
        $check = $db->query("SHOW COLUMNS FROM pedido_cabecera LIKE 'token_publico'");
        if (!$check || !$check->fetch()) {
            $db->exec(
                'ALTER TABLE pedido_cabecera
                 ADD COLUMN token_publico CHAR(32) NULL DEFAULT NULL,
                 ADD UNIQUE KEY uk_pedido_token_publico (token_publico)'
            );
        }
    } catch (Throwable $e) {
    }
    try {
        $check = $db->query("SHOW COLUMNS FROM pedido_cabecera_historico LIKE 'token_publico'");
        if (!$check || !$check->fetch()) {
            $db->exec(
                'ALTER TABLE pedido_cabecera_historico
                 ADD COLUMN token_publico CHAR(32) NULL DEFAULT NULL,
                 ADD UNIQUE KEY uk_pedido_hist_token_publico (token_publico)'
            );
        }
    } catch (Throwable $e) {
    }
}

function generarTokenPublicoPedido(): string {
    return bin2hex(random_bytes(16));
}

function asegurarTokenPublicoPedido(PDO $db, int $idPedido): string {
    ensureTokenPublicoPedidoCabecera($db);
    $st = $db->prepare('SELECT token_publico FROM pedido_cabecera WHERE id_pedido = ?');
    $st->execute([$idPedido]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        jsonError('Pedido no encontrado', 404);
    }
    $token = trim((string)($row['token_publico'] ?? ''));
    if ($token !== '' && preg_match('/^[a-f0-9]{32}$/', $token)) {
        return $token;
    }
    do {
        $token = generarTokenPublicoPedido();
        $dup = $db->prepare(
            'SELECT 1 FROM pedido_cabecera WHERE token_publico = ?
             UNION SELECT 1 FROM pedido_cabecera_historico WHERE token_publico = ? LIMIT 1'
        );
        $dup->execute([$token, $token]);
    } while ($dup->fetch());
    $db->prepare('UPDATE pedido_cabecera SET token_publico = ? WHERE id_pedido = ?')
        ->execute([$token, $idPedido]);
    return $token;
}

function urlPublicaPedido(string $token): string {
    return urlBasePublicaPedido() . '/' . $token;
}

/** id_producto del producto cabecera Menú del Día (filtro menu_dia). */
function idProductoMenuDelDia(PDO $db): ?int {
    ensureAgotadoColumnProductos($db);
    $st = $db->query(
        "SELECT id_producto FROM productos WHERE filtro = 'menu_dia' AND disponible = 1 LIMIT 1"
    );
    $id = $st ? $st->fetchColumn() : false;
    return $id !== false ? (int)$id : null;
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

function terminalSerieDesdeBody(array $body): string {
    $terminal = trim((string)($body['terminal_serie'] ?? ''));
    if ($terminal === '') {
        jsonError('Falta terminal_serie', 400);
    }
    if (strlen($terminal) > 120) {
        $terminal = substr($terminal, 0, 120);
    }
    return $terminal;
}

function ensureTablaCodigosColumn(PDO $db): void {
    try {
        $check = $db->query("SHOW COLUMNS FROM impresoras LIKE 'tabla_codigos'");
        if (!$check || !$check->fetch()) {
            $db->exec(
                "ALTER TABLE impresoras ADD COLUMN tabla_codigos VARCHAR(32) NOT NULL DEFAULT 'CP1252' AFTER puerto"
            );
        }
    } catch (Throwable $e) {
        // El SELECT posterior fallará con mensaje claro si falta la columna.
    }
}

/** Registra una incidencia operativa (fallo silencioso si la tabla no existe). */
function registrarIncidencia(
    PDO $db,
    string $descripcion,
    string $terminal,
    int $idUsuario
): void {
    $descripcion = trim($descripcion);
    if ($descripcion === '') {
        return;
    }
    if (strlen($descripcion) > 500) {
        $descripcion = substr($descripcion, 0, 497) . '...';
    }
    if (strlen($terminal) > 120) {
        $terminal = substr($terminal, 0, 120);
    }
    try {
        $st = $db->prepare(
            'INSERT INTO incidencias (descripcion, cuando, terminal, id_usuario)
             VALUES (?, NOW(), ?, ?)'
        );
        $st->execute([$descripcion, $terminal, max(0, $idUsuario)]);
    } catch (Throwable $e) {
        logEvent('incidencia no guardada: ' . $e->getMessage(), 'warning');
    }
}

/**
 * Si el terminal tenía otra mesa bloqueada, la desbloquea y lo anota (no debería ocurrir).
 */
function liberarOtrasMesasBloqueadasDelTerminal(
    PDO $db,
    string $terminalSerie,
    int $idUsuario,
    int $exceptoIdPedido = 0
): void {
    $sql = 'SELECT id_pedido, id_mesa FROM pedido_cabecera
              WHERE terminal_serie_bloqueo = ?
                AND hora_bloqueo IS NOT NULL
                AND DATE_ADD(hora_bloqueo, INTERVAL ? SECOND) > NOW()';
    $params = [$terminalSerie, LOCK_TTL];
    if ($exceptoIdPedido > 0) {
        $sql .= ' AND id_pedido != ?';
        $params[] = $exceptoIdPedido;
    }
    $st = $db->prepare($sql);
    $st->execute($params);
    while ($row = $st->fetch(PDO::FETCH_ASSOC)) {
        $idPedido = (int)$row['id_pedido'];
        $idMesa   = (int)$row['id_mesa'];
        liberarBloqueoMesaTerminal($db, $idPedido, $terminalSerie);
        registrarIncidencia(
            $db,
            "El terminal tenía bloqueada la mesa $idMesa (pedido $idPedido) al intentar usar otra mesa; "
            . 'se desbloqueó automáticamente (no debería ocurrir).',
            $terminalSerie,
            $idUsuario
        );
    }
}

/** @deprecated Use liberarOtrasMesasBloqueadasDelTerminal */
function verificarTerminalSinOtraMesaAbierta(
    PDO $db,
    string $terminalSerie,
    int $exceptoIdPedido = 0
): void {
    liberarOtrasMesasBloqueadasDelTerminal($db, $terminalSerie, 0, $exceptoIdPedido);
}

function incidenciaMesaNoEncontrada(
    PDO $db,
    string $contexto,
    int $idPedido,
    string $terminalSerie,
    int $idUsuario
): void {
    registrarIncidencia(
        $db,
        "$contexto: id_pedido=$idPedido no existe en pedido_cabecera (mesa cerrada o inconsistente).",
        $terminalSerie,
        $idUsuario
    );
}

/** Normaliza nombre_cliente del body; si no viene, conserva el valor actual. */
function nombreClienteDesdeBody(array $body, string $actual = ''): string {
    if (!array_key_exists('nombre_cliente', $body)) {
        return $actual;
    }
    $nombre = trim((string)$body['nombre_cliente']);
    if (strlen($nombre) > 120) {
        $nombre = substr($nombre, 0, 120);
    }
    return $nombre;
}

/**
 * INSERT en pedido_cabecera con todas las columnas NOT NULL explícitas.
 * @param array<string, mixed> $d
 */
function insertarPedidoCabecera(PDO $db, array $d): int {
    ensureTokenPublicoPedidoCabecera($db);

    $nombreCliente = trim((string)($d['nombre_cliente'] ?? ''));
    if (strlen($nombreCliente) > 120) {
        $nombreCliente = substr($nombreCliente, 0, 120);
    }
    $terminalSerie = trim((string)($d['terminal_serie_bloqueo'] ?? ''));
    if (strlen($terminalSerie) > 120) {
        $terminalSerie = substr($terminalSerie, 0, 120);
    }

    $horaBloqueo = null;
    if (array_key_exists('hora_bloqueo', $d)) {
        $hb = $d['hora_bloqueo'];
        if ($hb === 'now') {
            $horaBloqueo = date('Y-m-d H:i:s');
        } elseif ($hb !== null && $hb !== false) {
            $horaBloqueo = (string)$hb;
        }
    }

    $db->prepare(
        'INSERT INTO pedido_cabecera
         (id_mesa, hora_creacion, nombre_cliente, id_usuario_creacion,
          terminal_serie_bloqueo, hora_ultima_accion, estado_mesa,
          id_usuario_bloqueo, hora_bloqueo, base_imponible, importe_IVA, token_publico)
         VALUES (?, NOW(), ?, ?, ?, NOW(), ?, ?, ?, ?, ?, ?)'
    )->execute([
        (int)($d['id_mesa'] ?? 0),
        $nombreCliente,
        (int)($d['id_usuario_creacion'] ?? 0),
        $terminalSerie,
        (string)($d['estado_mesa'] ?? 'abierta'),
        (int)($d['id_usuario_bloqueo'] ?? 0),
        $horaBloqueo,
        round((float)($d['base_imponible'] ?? 0), 2),
        round((float)($d['importe_IVA'] ?? 0), 2),
        $d['token_publico'] ?? null,
    ]);

    return (int)$db->lastInsertId();
}

/**
 * INSERT en pedido_detalles con todas las columnas NOT NULL explícitas.
 * @param array<string, mixed> $d
 */
function insertarPedidoDetalle(PDO $db, array $d): int {
    ensureUrgenteColumnPedidoDetalles($db);

    $opciones = $d['opciones_elegidas'] ?? null;
    if (is_array($opciones)) {
        $opciones = json_encode($opciones, JSON_UNESCAPED_UNICODE);
    }

    $horaPedido = $d['hora_pedido'] ?? date('Y-m-d H:i:s');
    if ($horaPedido === 'now') {
        $horaPedido = date('Y-m-d H:i:s');
    }

    $db->prepare(
        'INSERT INTO pedido_detalles
         (id_pedido, id_producto, cantidad, comentario,
          nombre_producto_pantalla, opciones_elegidas, texto_imprimir_cocina,
          texto_imprimir_cliente, orden, precio_sin_IVA, porcentaje_IVA, importe_IVA,
          impreso, servido, hora_pedido, modificado_servicio, urgente)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)'
    )->execute([
        (int)($d['id_pedido'] ?? 0),
        (int)($d['id_producto'] ?? 0),
        max(1, (int)($d['cantidad'] ?? 1)),
        trim((string)($d['comentario'] ?? '')),
        (string)($d['nombre_producto_pantalla'] ?? ''),
        $opciones,
        (string)($d['texto_imprimir_cocina'] ?? ''),
        (string)($d['texto_imprimir_cliente'] ?? ''),
        (int)($d['orden'] ?? 0),
        (float)($d['precio_sin_IVA'] ?? 0),
        (float)($d['porcentaje_IVA'] ?? 0),
        (float)($d['importe_IVA'] ?? 0),
        (int)($d['impreso'] ?? 0),
        (string)($d['servido'] ?? '2000-01-01 00:00:00'),
        (string)$horaPedido,
        (int)($d['modificado_servicio'] ?? 0),
        !empty($d['urgente']) ? 1 : 0,
    ]);

    return (int)$db->lastInsertId();
}

function liberarBloqueoMesaTerminal(PDO $db, int $idPedido, string $terminalSerie): void {
    $db->prepare(
        'UPDATE pedido_cabecera
            SET id_usuario_bloqueo = 0,
                terminal_serie_bloqueo = \'\',
                hora_bloqueo = NULL
          WHERE id_pedido = ?
            AND terminal_serie_bloqueo = ?'
    )->execute([$idPedido, $terminalSerie]);
}

/**
 * Si el pedido no tiene líneas en pedido_detalles, elimina pedido_cabecera.
 * @return bool true si se eliminó la cabecera
 */
function eliminarPedidoSiSinDetalles(PDO $db, int $idPedido): bool {
    $st = $db->prepare(
        'SELECT COUNT(*) FROM pedido_detalles WHERE id_pedido = ?'
    );
    $st->execute([$idPedido]);
    if (((int)$st->fetchColumn()) > 0) {
        return false;
    }
    $stDel = $db->prepare('DELETE FROM pedido_cabecera WHERE id_pedido = ?');
    $stDel->execute([$idPedido]);

    return $stDel->rowCount() > 0;
}

/**
 * Impide mover líneas o traspasar a una mesa con pedido activo bloqueado por otro terminal.
 */
function pedidoBloqueoVigente(array $cab): bool {
    $terminal = trim((string)($cab['terminal_serie_bloqueo'] ?? ''));
    return $terminal !== ''
        && !empty($cab['hora_bloqueo'])
        && (strtotime((string)$cab['hora_bloqueo']) + LOCK_TTL) > time();
}

function terminalTieneBloqueoPedido(array $cab, string $terminalSerie): bool {
    return pedidoBloqueoVigente($cab)
        && trim((string)($cab['terminal_serie_bloqueo'] ?? '')) === trim($terminalSerie);
}

function otroTerminalTieneBloqueoPedido(array $cab, string $terminalSerie): bool {
    return pedidoBloqueoVigente($cab)
        && !terminalTieneBloqueoPedido($cab, $terminalSerie);
}

/**
 * Toma el bloqueo solo si la mesa está libre, expirada o ya es de este terminal.
 * @return bool false si otro terminal tiene el bloqueo vigente
 */
function adquirirBloqueoMesa(
    PDO $db,
    int $idPedido,
    int $idUsuario,
    string $terminalSerie
): bool {
    $terminalSerie = trim($terminalSerie);
    $st = $db->prepare(
        'UPDATE pedido_cabecera
            SET id_usuario_bloqueo = ?,
                hora_bloqueo = NOW(),
                terminal_serie_bloqueo = ?
          WHERE id_pedido = ?
            AND (
                  hora_bloqueo IS NULL
               OR terminal_serie_bloqueo = \'\'
               OR terminal_serie_bloqueo = ?
               OR DATE_ADD(hora_bloqueo, INTERVAL ? SECOND) <= NOW()
            )'
    );
    $st->execute([$idUsuario, $terminalSerie, $idPedido, $terminalSerie, LOCK_TTL]);
    if ($st->rowCount() > 0) {
        return true;
    }
    // Tras abrir_mesa el bloqueo ya es de este terminal; un UPDATE inmediato puede
    // no modificar filas (mismos valores) y rowCount() = 0 sin ser un conflicto.
    $chk = $db->prepare(
        'SELECT id_usuario_bloqueo, hora_bloqueo, terminal_serie_bloqueo
           FROM pedido_cabecera WHERE id_pedido = ?'
    );
    $chk->execute([$idPedido]);
    $row = $chk->fetch(PDO::FETCH_ASSOC);
    if ($row === false || !terminalTieneBloqueoPedido($row, $terminalSerie)) {
        return false;
    }
    $db->prepare(
        'UPDATE pedido_cabecera SET hora_bloqueo = NOW()
          WHERE id_pedido = ? AND terminal_serie_bloqueo = ?'
    )->execute([$idPedido, $terminalSerie]);
    return true;
}

/** Comprueba que el bloqueo quedó persistido en BD. */
function verificarBloqueoPersistido(PDO $db, int $idPedido, string $terminalSerie): void {
    $st = $db->prepare(
        'SELECT id_usuario_bloqueo, hora_bloqueo, terminal_serie_bloqueo
           FROM pedido_cabecera WHERE id_pedido = ?'
    );
    $st->execute([$idPedido]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row || !terminalTieneBloqueoPedido($row, $terminalSerie)) {
        jsonError('Error interno: el bloqueo de la mesa no se guardó en el servidor', 500);
    }
}

function verificarMesaDestinoNoBloqueadaPorOtro(
    PDO $db,
    int $idMesa,
    string $terminalSerie,
    bool $forUpdate = false
): void {
    $sql = 'SELECT terminal_serie_bloqueo, hora_bloqueo
              FROM pedido_cabecera WHERE id_mesa = ? LIMIT 1';
    if ($forUpdate) {
        $sql = 'SELECT terminal_serie_bloqueo, hora_bloqueo
                  FROM pedido_cabecera WHERE id_mesa = ? FOR UPDATE';
    }
    $st = $db->prepare($sql);
    $st->execute([$idMesa]);
    $row = $st->fetch(PDO::FETCH_ASSOC);
    if (!$row) {
        return;
    }
    if (otroTerminalTieneBloqueoPedido($row, $terminalSerie)) {
        jsonError(
            "La mesa destino ($idMesa) está bloqueada. Solo lectura",
            409
        );
    }
}
