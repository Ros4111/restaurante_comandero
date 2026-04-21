<?php
// backend/config/database.php
declare(strict_types=1);

define('DB_HOST', 'guardabcomandero.mysql.db');
define('DB_PORT', 3306);
define('DB_NAME', 'guardabcomandero');
define('DB_USER', 'guardabcomandero');
define('DB_PASS', 'Nomemela2');
define('DB_CHARSET', 'utf8mb4');

define('JWT_SECRET', 'CHANGE_ME_MiguelRosRodriguezESBUENO');
define('JWT_EXPIRY',  86400);   // 24 h

define('LOCK_TTL',    180);     // 3 minutos en segundos

function getDB(): PDO {
    static $pdo = null;
    if ($pdo === null) {
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=%s',
            DB_HOST, DB_PORT, DB_NAME, DB_CHARSET
        );
        $pdo = new PDO($dsn, DB_USER, DB_PASS, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
        ]);
    }
    return $pdo;
}
