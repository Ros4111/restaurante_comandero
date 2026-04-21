<?php
declare(strict_types=1);

require_once __DIR__ . '/database.php';

try {
    // Intentar conexión
    $pdo = getDB();
    echo "<h2 style='color:green;'>✔ Conexión a la base de datos exitosa</h2>";

    // Consultar tabla usuarios
    $stmt = $pdo->query("SELECT * FROM usuarios");
    $usuarios = $stmt->fetchAll();

    if (count($usuarios) === 0) {
        echo "<p>No hay usuarios en la base de datos.</p>";
        exit;
    }

    echo "<h3>Lista de usuarios:</h3>";
    echo "<table border='1' cellpadding='8' cellspacing='0'>";
    echo "<tr>";

    // Encabezados dinámicos
    foreach (array_keys($usuarios[0]) as $columna) {
        echo "<th>" . htmlspecialchars($columna) . "</th>";
    }
    echo "</tr>";

    // Datos
    foreach ($usuarios as $usuario) {
        echo "<tr>";
        foreach ($usuario as $valor) {
            echo "<td>" . htmlspecialchars((string)$valor) . "</td>";
        }
        echo "</tr>";
    }

    echo "</table>";

} catch (PDOException $e) {
    echo "<h2 style='color:red;'>❌ Error de conexión</h2>";
    echo "<p><strong>Mensaje:</strong> " . htmlspecialchars($e->getMessage()) . "</p>";
}