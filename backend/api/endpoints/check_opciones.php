<?php
// backend/api/endpoints/check_opciones.php
// Ruta pública: GET /api/check-opciones
// Comprueba la integridad de la tabla productos_opciones.
declare(strict_types=1);

function endpointCheckOpciones(): void
{
    $pdo     = getDB();
    $errores = [];

    // ── 1. Cargar todas las opciones ─────────────────────────────────────────
    $opciones = $pdo
        ->query('SELECT id_opcion, id_producto, id_grupo_opciones,
                        nombre_opcion, predeterminado
                   FROM productos_opciones
                  ORDER BY id_grupo_opciones, id_opcion')
        ->fetchAll();

    $total = count($opciones);

    // ── 2. Cargar nombres de productos y grupos ───────────────────────────────
    // id_producto => nombre_producto_pantalla
    $nombresProductos = [];
    foreach ($pdo->query('SELECT id_producto, nombre_producto_pantalla FROM productos') as $row) {
        $nombresProductos[(int)$row['id_producto']] = $row['nombre_producto_pantalla'];
    }

    // id_grupo_opciones => nombre_grupo
    $nombresGrupos = [];
    foreach ($pdo->query('SELECT id_grupo_opciones, nombre_grupo FROM grupos_opciones') as $row) {
        $nombresGrupos[(int)$row['id_grupo_opciones']] = $row['nombre_grupo'];
    }

    // ── 3. FK producto y FK grupo fila a fila ─────────────────────────────────
    foreach ($opciones as $op) {
        $id = $op['id_opcion'];

        if (!array_key_exists($op['id_producto'], $nombresProductos)) {
            $errores[] = sprintf(
                'Opción #%d ("%s"): id_producto=%d no existe en la tabla productos.',
                $id, $op['nombre_opcion'], $op['id_producto']
            );
        }

        if (!array_key_exists($op['id_grupo_opciones'], $nombresGrupos)) {
            $errores[] = sprintf(
                'Opción #%d ("%s"): id_grupo_opciones=%d no existe en la tabla grupos_opciones.',
                $id, $op['nombre_opcion'], $op['id_grupo_opciones']
            );
        }
    }

    // ── 4. Agrupar por (id_producto, id_grupo_opciones) ───────────────────────
    $grupos = [];
    foreach ($opciones as $op) {
        $clave = $op['id_producto'] . '_' . $op['id_grupo_opciones'];
        if (!isset($grupos[$clave])) {
            $grupos[$clave] = [
                'id_producto'       => (int)$op['id_producto'],
                'id_grupo_opciones' => (int)$op['id_grupo_opciones'],
                'opciones'          => [],
                'predeterminados'   => 0,
            ];
        }
        $grupos[$clave]['opciones'][] = $op;
        if ((int)$op['predeterminado'] === 1) {
            $grupos[$clave]['predeterminados']++;
        }
    }

    // ── 5. Predeterminado único y mínimo 2 opciones ───────────────────────────
    foreach ($grupos as $g) {
        $idProd  = $g['id_producto'];
        $idGrupo = $g['id_grupo_opciones'];
        $nomProd  = $nombresProductos[$idProd]  ?? "id=$idProd";
        $nomGrupo = $nombresGrupos[$idGrupo] ?? "id=$idGrupo";
        $label = sprintf(
            'Producto #%d "%s" / Grupo #%d "%s"',
            $idProd, $nomProd, $idGrupo, $nomGrupo
        );
        $n = count($g['opciones']);

        if ($n < 2) {
            $errores[] = "$label: solo tiene $n opción/opciones (mínimo 2).";
        }
        if ($g['predeterminados'] === 0) {
            $errores[] = "$label: ninguna opción está marcada como predeterminada.";
        } elseif ($g['predeterminados'] > 1) {
            $errores[] = "$label: tiene {$g['predeterminados']} opciones predeterminadas (debe ser exactamente 1).";
        }
    }

    $ok = empty($errores);

    // ── Salida HTML ───────────────────────────────────────────────────────────
    header('Content-Type: text/html; charset=utf-8');
    ?>
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Check productos_opciones</title>
    <style>
        body { font-family: sans-serif; margin: 2rem; background: #1a1a2e; color: #e0e0e0; }
        h1   { color: #a0c4ff; margin-bottom: .25rem; }
        .meta { color: #888; font-size: .9rem; margin-bottom: 1.5rem; }
        .ok  { background: #1b4332; border-left: 4px solid #40916c;
               padding: .75rem 1rem; border-radius: 4px; font-size: 1.1rem; }
        .error-list { list-style: none; padding: 0; margin: 0; }
        .error-list li {
            background: #3b0f0f; border-left: 4px solid #e63946;
            padding: .6rem 1rem; border-radius: 4px; margin-bottom: .5rem;
            font-size: .95rem; line-height: 1.4;
        }
        .badge { display: inline-block; padding: .15rem .5rem; border-radius: 99px;
                 font-size: .8rem; font-weight: bold; margin-right: .4rem; }
        .badge-err { background: #e63946; color: #fff; }
        .badge-ok  { background: #40916c; color: #fff; }
    </style>
</head>
<body>
<h1>Integridad — <code>productos_opciones</code></h1>
<p class="meta">
    Filas analizadas: <strong><?= $total ?></strong> &nbsp;|&nbsp;
    Grupos (producto+grupo): <strong><?= count($grupos) ?></strong> &nbsp;|&nbsp;
    <?php if ($ok): ?>
        <span class="badge badge-ok">OK</span>
    <?php else: ?>
        <span class="badge badge-err"><?= count($errores) ?> error(es)</span>
    <?php endif; ?>
</p>

<?php if ($ok): ?>
    <div class="ok">✔ No se han encontrado errores de integridad.</div>
<?php else: ?>
    <ul class="error-list">
        <?php foreach ($errores as $e): ?>
            <li><?= htmlspecialchars($e) ?></li>
        <?php endforeach; ?>
    </ul>
<?php endif; ?>
</body>
</html>
    <?php
    exit;
}
