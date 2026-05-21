<?php
// backend/api/endpoints/impresoras.php
declare(strict_types=1);

function endpointImpresorasConfigGet(): void {
    $db = getDB();
    ensureTablaCodigosColumn($db);
    $rows = $db->query(
        "SELECT id_impresora, nombre, ip, puerto, tabla_codigos
           FROM impresoras
       ORDER BY id_impresora"
    )->fetchAll();
    jsonOk($rows);
}

function endpointImpresorasConfigSave(): void {
    $body = getBody();
    $items = $body['impresoras'] ?? null;
    if (!is_array($items)) {
        jsonError('Se esperaba lista de impresoras', 400);
    }

    $db = getDB();
    ensureTablaCodigosColumn($db);
    $st = $db->prepare(
        "UPDATE impresoras
            SET nombre = ?, ip = ?, puerto = ?, tabla_codigos = ?
          WHERE id_impresora = ?"
    );

    $db->beginTransaction();
    try {
        foreach ($items as $raw) {
            if (!is_array($raw)) {
                continue;
            }
            $id = (int)($raw['id_impresora'] ?? 0);
            if ($id <= 0) {
                continue;
            }
            $nombre = trim((string)($raw['nombre'] ?? ''));
            if ($nombre === '') {
                $nombre = 'Impresora ' . $id;
            }
            $ip = trim((string)($raw['ip'] ?? ''));
            $puerto = (int)($raw['puerto'] ?? 0);
            $tabla = strtoupper(trim((string)($raw['tabla_codigos'] ?? 'CP1252')));
            if ($tabla === '') {
                $tabla = 'CP1252';
            }
            $st->execute([$nombre, $ip, $puerto, $tabla, $id]);
        }
        $db->commit();
        jsonOk(['ok' => true]);
    } catch (Throwable $e) {
        $db->rollBack();
        jsonError('No se pudo guardar la configuración de impresoras', 500);
    }
}

function endpointImpresoraCrear(): void {
    $db = getDB();
    ensureTablaCodigosColumn($db);

    $body = getBody();
    $nombre = trim((string)($body['nombre'] ?? ''));
    $ip = trim((string)($body['ip'] ?? ''));
    $puerto = (int)($body['puerto'] ?? 9100);
    $tabla = strtoupper(trim((string)($body['tabla_codigos'] ?? 'CP1252')));
    if ($tabla === '') {
        $tabla = 'CP1252';
    }

    if ($nombre === '') {
        $maxId = (int)$db->query("SELECT COALESCE(MAX(id_impresora), 0) + 1 FROM impresoras")->fetchColumn();
        $nombre = 'Impresora ' . $maxId;
    }

    $st = $db->prepare(
        "INSERT INTO impresoras (nombre, ip, puerto, tabla_codigos)
         VALUES (?, ?, ?, ?)"
    );
    $st->execute([$nombre, $ip, $puerto, $tabla]);
    $id = (int)$db->lastInsertId();

    jsonOk([
        'id_impresora' => $id,
        'nombre' => $nombre,
        'ip' => $ip,
        'puerto' => $puerto,
        'tabla_codigos' => $tabla,
    ]);
}

function endpointImpresoraEliminar(int $idImpresora): void {
    if ($idImpresora <= 0) {
        jsonError('Id de impresora inválido', 400);
    }

    $db = getDB();
    $stUse = $db->prepare(
        "SELECT COUNT(*) FROM productos WHERE id_impresora = ?"
    );
    $stUse->execute([$idImpresora]);
    $enUso = (int)$stUse->fetchColumn();
    if ($enUso > 0) {
        jsonError('No se puede eliminar: hay productos asignados a esta impresora', 409);
    }

    $st = $db->prepare("DELETE FROM impresoras WHERE id_impresora = ?");
    $st->execute([$idImpresora]);
    if ($st->rowCount() === 0) {
        jsonError('Impresora no encontrada', 404);
    }

    jsonOk(['ok' => true]);
}
