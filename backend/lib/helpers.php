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
    return $st->rowCount() > 0;
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
