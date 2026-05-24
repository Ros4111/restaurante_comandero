# restaurante_comandero — Guía para asistentes IA

TPV de restaurante: Flutter en **Sunmi V2** (Android) + API **PHP** en Raspberry Pi + **MySQL** + cola de impresión ESC/POS.

## Stack

| Capa | Tecnología |
|------|------------|
| Cliente | Flutter 3.x, Provider, `http`, Sunmi printer |
| API | PHP 8.x, Apache, JWT 24h |
| BD | MySQL (`pedido_cabecera`, `pedido_detalles`, catálogo, `incidencias`, histórico) |
| Impresión cocina/barra | Print worker (Python) en Pi, TCP 9100 |
| Dispositivo objetivo | Sunmi V2, Android 7.1+, modo kiosco |

Paquete Flutter: `restaurante_tpv` (v ver `pubspec.yaml`).

## Estructura del repo

```
lib/
  main.dart                 # Providers: ApiService, SesionProvider, CatalogoProvider, MesaProvider
  screens/                  # UI principal
  services/                 # api_service, catalogo_provider, sunmi_service, cashlogy_service
  widgets/                  # catalogo_panel, lineas_panel, producto_opciones_dialog
  models/models.dart
  utils/                    # theme, mesa_bloqueo, precio_redondeo, busqueda_texto
backend/
  api/index.php             # Router REST (require paths en servidor: /home/guardab/restaurante/...)
  api/endpoints/            # mesas, pedidos, catalogo, auth, historico, servicio, ...
  lib/helpers.php           # Bloqueos, incidencias, JSON helpers
  guardabcomandero.sql      # Dump/esquema referencia
android/                    # MainActivity.kt: kiosco + canal device serial
Instrucciones.txt           # Especificación funcional original (español)
```

## Pantallas principales

| Pantalla | Rol |
|----------|-----|
| `config_screen` | URL servidor |
| `login_screen` | JWT, NFC opcional |
| `mesas_screen` | Grid mesas, abrir/bloquear, menú largo |
| `hacer_pedido_screen` | Catálogo + líneas, guardar, cerrar mesa |
| `pendientes_servir_screen` | Cocina/servicio |
| `reparto_comensales_screen` | Cierre con reparto |
| `historico_mesas_screen` | Admin: mesas cerradas / reabrir |
| `settings_menu_screen` | Admin: usuarios, Cashlogy, etc. |

## API — convenciones

- Base: `https://host/api`
- Respuesta: `{ "ok": true, "data": ... }` o `{ "ok": false, "error": "..." }`
- Auth: header `Authorization: Bearer <jwt>`
- **Siempre** enviar `terminal_serie` en body/query de mesas y pedidos (identifica el TPV).

### Rutas críticas

- `GET /mesas?terminal_serie=` — listado; no expone serie de otro terminal (`bloqueo_vigente`, `bloqueada_por_mi`)
- `POST /mesas/{id}/bloquear|desbloquear|ping`
- `GET /pedidos/{id}?terminal_serie=`
- `POST /pedidos/{id}/guardar`
- `POST /pedidos/{id}/nota-libre`
- `GET /catalogo`
- `POST /auth/login`

## Bloqueo de mesas (reglas actuales)

Lógica central en `backend/lib/helpers.php`:

1. **Un terminal, una mesa activa** (bloqueo vigente &lt; 3 min): al abrir otra, se libera la anterior y se registra **incidencia**.
2. **Otro terminal con bloqueo vigente** → 409, mensaje: `Mesa Bloqueada. Solo Ver.` (sin revelar serie del bloqueador).
3. El terminal con bloqueo puede **editar y guardar**; el ping renueva `hora_bloqueo` cada ~60 s.
4. **Desbloqueo** solo al pulsar Salir (`desbloquear`), no en `dispose` del widget.
5. Tras **guardar**, se mantiene el bloqueo del terminal (no vaciar `terminal_serie_bloqueo`).

Flutter:

- `mesas_screen`: `bloquearMesa` → si 409, entra en solo lectura (`bloqueadoPorMi: false`).
- `hacer_pedido_screen`: confía en bloqueo concedido al entrar; no marcar “bloqueo perdido” en el primer ping.
- Mensaje UI: `lib/utils/mesa_bloqueo.dart` → `kMesaBloqueadaSoloVer`.

## Identificación del terminal

- **Android**: `Build.getSerial()` vía `MethodChannel` `com.restaurante.restaurante_tpv/device` (`MainActivity.kt`). No usar `device_info_plus` para serie (v13 eliminó `serialNumber`).
- **Escritorio/web**: ID único en `SharedPreferences` (`desk-...`).
- Implementación: `ApiService.terminalSerie()`.

## Impresión

- **Sunmi**: ticket cliente en dispositivo (`sunmi_service.dart`).
- **Cocina/barra**: servidor encola; worker Python imprime por TCP.
- Producto con `id_impresora`; notas libres con impresora elegida.

## Cashlogy

- Integración opcional: `CashlogyService` + flag `cashlogy_enabled`; pantalla `cashlogy_config_screen.dart`.
- Si desactivado, cerrar mesa no cobra por datáfono.

## Búsqueda en pedido

- Campo superior en `hacer_pedido_screen`: texto normal o prefijo `mm` + código → filtra por `Producto.filtro`.
- Helper: `interpretarCampoBusquedaCatalogoMm()`.

## UI pedido (estado reciente)

- AppBar: solo número de mesa; flecha atrás compacta.
- Sin cabeceras “Menú” / “Pedido”; nota libre desde casilla **Manualmente** al final del catálogo (raíz).
- Catálogo: `catalogo_panel.dart`; líneas: `lineas_panel.dart`.

## Despliegue

Subir **juntos** tras cambios de bloqueo:

- `backend/lib/helpers.php`
- `backend/api/endpoints/mesas.php`
- `backend/api/endpoints/pedidos.php`

Recompilar e instalar APK en **todos** los TPV.

En el servidor, `index.php` referencia rutas absolutas del hosting (`/home/guardab/restaurante/...`); adaptar si el entorno difiere.

## Reglas de código (proyecto)

- `.cursor/rules/karpathy-guidelines.mdc`: cambios mínimos, sin sobre-ingeniería.
- No commitear sin pedirlo; `NoSubirGithub/` ignorar capturas locales.
- Estilo existente: español en UI/mensajes, Provider para estado de mesa/catálogo.

## Archivos que suelen tocarse juntos

| Tarea | Archivos |
|-------|----------|
| Bloqueo mesa | `helpers.php`, `mesas.php`, `pedidos.php`, `mesas_screen.dart`, `hacer_pedido_screen.dart` |
| Serie terminal | `api_service.dart`, `MainActivity.kt` |
| Catálogo/pedido UI | `hacer_pedido_screen.dart`, `catalogo_panel.dart`, `lineas_panel.dart` |
| Modelos API | `models.dart`, `api_service.dart` |

## Documentación humana

- `README.md` — instalación Pi, Apache, SSL, worker.
- `Instrucciones.txt` — requisitos funcionales completos.
