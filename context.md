# Contexto acumulado del proyecto

Documento de continuidad entre sesiones (mayo 2026). Complementa `claude.md` e `Instrucciones.txt`.

---

## Estado funcional acordado: bloqueos de mesa

### Comportamiento deseado

1. Cualquier terminal puede **intentar abrir** una mesa.
2. Si el terminal ya tiene **otra mesa bloqueada** (&lt; 3 min), al abrir una nueva se **desbloquea la anterior** (con registro en tabla `incidencias`).
3. Si la mesa está bloqueada por **otro** terminal → el segundo entra en **solo lectura** (ver pedido, no guardar ni cobrar).
4. El bloqueo del terminal que **sí tiene** la mesa se mantiene hasta **Salir** o **3 minutos** sin ping (ya no se desbloquea en `dispose` de la pantalla).
5. Al **guardar**, el bloqueo **no se borra** en BD (evitar que otro terminal entre tras guardar).

### Problemas que se corrigieron

| Problema | Causa | Solución |
|----------|--------|----------|
| Dos usuarios guardando a la vez | `terminal-no-android` compartido en PC, admin saltaba bloqueo, `desbloquear` en dispose, guardar vaciaba bloqueo | Serie única por dispositivo; sin bypass admin; desbloquear solo en Salir; renovar bloqueo al guardar |
| Terminal “dueño” veía solo lectura | Doble `bloquear`, GET con `tengo_bloqueo` falso, ping 409 al entrar | Un solo bloqueo en `mesas_screen`; confiar en `bloqueadoPorMi` al cargar; ping inicial sin pasar a solo lectura |
| Serie incorrecta en Android | `device_info_plus` 13 quitó `serialNumber`; se usaba `info.id` | Canal nativo `getDeviceSerial` en `MainActivity.kt`; prioridad serie hardware |
| Mensajes duplicados / con ID terminal | SnackBar + banner + chip; PHP devolvía serie en 409 | Un mensaje: **Mesa Bloqueada. Solo Ver.**; PHP no expone serie a otros terminales |
| Texto “Solo lectura · Mesa…” | Chip concatenaba prefijo + `nombreBloqueador` | Constante única `kMesaBloqueadaSoloVer` en `lib/utils/mesa_bloqueo.dart` |

### Mensaje estándar solo lectura

```
Mesa Bloqueada. Solo Ver.
```

- PHP: `mensajeMesaBloqueadaSoloLectura()` en `helpers.php`
- Flutter: `kMesaBloqueadaSoloVer`
- Sin SnackBar al entrar; chip naranja en AppBar si aplica

---

## Cambios UI — `hacer_pedido_screen`

- **AppBar**: solo número de mesa (sin “Mesa”); flecha ← con padding mínimo.
- **Búsqueda**: iconos lupa/limpiar sin padding lateral; altura alineada al campo.
- **Columna izquierda**: sin cabecera “Menú”; casilla **Manualmente** al final de la raíz (sustituye botón + de nota libre).
- **Columna derecha**: sin cabecera “Pedido” ni botón +.
- **Solo lectura**: catálogo muestra `kMesaBloqueadaSoloVer` en lugar del grid.

---

## Backend — piezas clave

### `helpers.php`

- `pedidoBloqueoVigente()` — TTL 3 min sobre `hora_bloqueo`
- `adquirirBloqueoMesa()`, `otroTerminalTieneBloqueoPedido()`
- `liberarOtrasMesasBloqueadasDelTerminal()` + `registrarIncidencia()`
- `verificarBloqueoPersistido()` tras abrir/bloquear

### `mesas.php`

- `endpointMesaBloquear` — transacción `FOR UPDATE`
- `endpointMesaPing` — renueva o recupera bloqueo propio
- Listado con `bloqueo_vigente` / `bloqueada_por_mi`; oculta `terminal_serie_bloqueo` a terceros

### `pedidos.php`

- `getPedido` — `bloqueo.vigente`, `bloqueo.tengo_bloqueo` (sin campo `terminal` al cliente ajeno)
- `guardar` — `_verificarBloqueoGuardar()` con mensaje genérico

### Migraciones mencionadas (aplicar en servidor si faltan)

- Tabla `incidencias`
- Alineación histórico (`align_historico_pedido_tables.sql` — si existía en repo local)
- `add_servido_pedido_detalles.sql` — servicio cocina
- Endpoint `servicio.php` para pendientes de servir

*(Verificar en servidor qué SQL ya está aplicado.)*

---

## Cashlogy

- Flag `cashlogy_enabled` en `CashlogyService`
- Config en `cashlogy_config_screen.dart`
- Si desactivado: cerrar mesa **no** cobra por datáfono (código conservado)

---

## Despliegue habitual

Tras cambios de bloqueo o pedidos:

1. Subir `helpers.php`, `mesas.php`, `pedidos.php`
2. Recompilar APK
3. Instalar en **todos** los Sunmi
4. Cerrar y abrir app (caché de `terminalSerie` en memoria)

---

## Git / trabajo pendiente habitual

- No se han pedido commits automáticos en las sesiones de bloqueo.
- Carpeta `NoSubirGithub/` — capturas locales, no subir.
- Rama con cambios locales en: `hacer_pedido_screen`, `mesas_screen`, `api_service`, `helpers.php`, `catalogo_panel`, `lineas_panel`, etc.

---

## Pantallas y flujos relacionados

- **Movimientos de mesa**: un evento `cambio_mesa` por línea al traspasar (no un solo evento agregado).
- **Histórico / reabrir**: solo admin; `historico_mesas_screen.dart`.
- **Pendientes servir**: `pendientes_servir_screen.dart` + API servicio.
- **Reparto comensales**: long-press cerrar mesa (supervisor).

---

## Notas para la próxima sesión

- Si vuelve a fallar la serie: comprobar permisos `READ_PHONE_STATE` / dispositivo Sunmi y que todos los TPV tengan la **misma versión** de APK.
- Si bloqueos “fantasma”: revisar en BD `terminal_serie_bloqueo` y `hora_bloqueo` en `pedido_cabecera`.
- Al tocar bloqueos, **no** reintroducir `desbloquear` en `dispose` ni segundo `bloquearMesa` en `initState` de `hacer_pedido_screen`.
- Preferir mensaje único `kMesaBloqueadaSoloVer` sin exponer serie del otro terminal.

---

*Última actualización de contexto: trabajo de bloqueos, serie terminal, mensajes solo lectura y UI de pedido (mayo 2026).*
