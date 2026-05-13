<?php
// backend/api/endpoints/dispositivos.php
declare(strict_types=1);

/**
 * POST /dispositivos/ping
 * Body: { id_dispositivo, nombre_dispositivo, bateria }
 * Inserta o actualiza el registro del dispositivo.
 * id_usuario se toma del token JWT.
 */
function endpointDispositivoPing(array $payload): void {
    $body = getBody();

    $idDispositivo     = trim((string)($body['id_dispositivo']     ?? ''));
    $nombreDispositivo = trim((string)($body['nombre_dispositivo'] ?? ''));
    $bateria           = isset($body['bateria']) ? (int)$body['bateria'] : null;
    $idUsuario         = (int)$payload['sub'];

    if ($idDispositivo === '') {
        jsonError('id_dispositivo es obligatorio', 400);
    }
    if (strlen($idDispositivo) > 120) {
        $idDispositivo = substr($idDispositivo, 0, 120);
    }
    if (strlen($nombreDispositivo) > 120) {
        $nombreDispositivo = substr($nombreDispositivo, 0, 120);
    }
    if ($bateria !== null) {
        $bateria = max(0, min(100, $bateria));
    }

    try {
        $db = getDB();

        // Comprobamos si ya existe una fila con este id_dispositivo
        $stCheck = $db->prepare(
            'SELECT COUNT(*) FROM dispositivos WHERE id_dispositivo = ?'
        );
        $stCheck->execute([$idDispositivo]);
        $existe = (int)$stCheck->fetchColumn() > 0;

        if ($existe) {
            $db->prepare(
                'UPDATE dispositivos
                    SET nombre_dispositivo = ?,
                        bateria            = ?,
                        ultimo_uso         = NOW(),
                        id_usuario         = ?
                  WHERE id_dispositivo = ?'
            )->execute([$nombreDispositivo, $bateria, $idUsuario, $idDispositivo]);
        } else {
            $db->prepare(
                'INSERT INTO dispositivos
                     (id_dispositivo, nombre_dispositivo, bateria, ultimo_uso, id_usuario)
                 VALUES (?, ?, ?, NOW(), ?)'
            )->execute([$idDispositivo, $nombreDispositivo, $bateria, $idUsuario]);
        }

        jsonOk(['ok' => true, 'accion' => $existe ? 'actualizado' : 'insertado']);
    } catch (Throwable $e) {
        logEvent('Error dispositivos/ping: ' . $e->getMessage(), 'error');
        jsonError('Error al guardar dispositivo: ' . $e->getMessage(), 500);
    }
}
