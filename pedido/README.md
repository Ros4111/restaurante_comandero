# Carpeta `pedido` — subir a www.guardamar.es

Contenido para desplegar en **`https://www.guardamar.es/pedido/`** (vista pública del pedido para clientes, sin login).

## Instalación

1. Suba **todo el contenido** de esta carpeta al directorio `/pedido/` del hosting.
2. Copie `config.example.php` a **`config.php`** y edite host, base de datos, usuario y contraseña (misma BD que el TPV).
3. Compruebe que PHP tiene PDO MySQL habilitado.
4. La app TPV (Sunmi) imprime el QR en el **primer guardado** de la mesa con URL:
   `https://www.guardamar.es/pedido/{token}`

## Archivos

| Archivo | Función |
|---------|---------|
| `config.php` | Credenciales MySQL (no versionar; crear desde `config.example.php`) |
| `lib.php` | Conexión y consultas del pedido |
| `api.php` | API JSON: `GET api.php?token=...` |
| `index.html` | Página que ve el cliente al escanear el QR |
| `.htaccess` | Enlaces `.../pedido/TOKEN` → `index.html` |

## Prueba

Tras guardar un pedido en el TPV, abra en el navegador:

`https://www.guardamar.es/pedido/` + el código de 32 caracteres del ticket.

O directamente: `https://www.guardamar.es/pedido/api.php?token=CODIGO`

## Nota

El endpoint `https://restaurante.guardamar.es/api/public/pedido/{token}` sigue disponible para la app; esta carpeta es **autónoma** y no depende del API del restaurante.
