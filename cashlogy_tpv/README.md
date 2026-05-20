# cashlogy_tpv

Aplicación Flutter para **Windows** que permite realizar cobros en efectivo a través de un **Cashlogy Connector** (TCP).

## Características

- Teclado numérico táctil/ratón para introducir el importe (en céntimos acumulados → euros con 2 decimales)
- Comunicación TCP con el Cashlogy Connector v2.5 (comandos `#I#` inicialización + `#C#` cobro express)
- Pantalla de resultado detallada: efectivo automático, manual, cambio devuelto
- Configuración persistente de IP, puerto y código de caja
- Test de conexión desde la pantalla de configuración

## Primeros pasos

### 1. Crear el proyecto Flutter

Desde una terminal, en la carpeta `cashlogy_tpv/`:

```bash
flutter create . --platforms=windows
flutter pub get
```

El comando `flutter create .` genera los archivos de plataforma (carpeta `windows/`) sin sobreescribir los archivos Dart existentes.

### 2. Ejecutar en desarrollo

```bash
flutter run -d windows
```

### 3. Compilar para distribución

```bash
flutter build windows --release
```

El ejecutable queda en `build/windows/x64/runner/Release/`.

## Configuración

En la pantalla principal pulsa el icono ⚙ (arriba a la derecha):

| Campo | Por defecto | Descripción |
|---|---|---|
| IP | 192.168.100.19 | IP del PC donde corre el Cashlogy Connector |
| Puerto | 8092 | Puerto TCP del Connector |
| Código caja | TPV | Identificador de este terminal |

Pulsa **"Probar conexión"** para verificar que el Connector está activo antes de empezar a operar.

## Protocolo Cashlogy

El servicio implementa el **Cashlogy Connector v2.5**:

1. `#I#` — Inicializar sesión (respuesta: `#0#<version>#`)
2. `#C#<numOp>#<caja>#<centimos>#0#0#0#0#0#0#0#` — Cobro express (respuesta: `#<status>#<auto>#<devuelto>#<manual>#<cambio>#`)

### Estados de respuesta

| Status | Significado |
|---|---|
| `0` | Cobro completado correctamente |
| `WR:CANCEL` | Cliente canceló |
| `WR:LEVEL` | OK con aviso de nivel bajo |
| `ER:BUSY` | Cashlogy ocupado |
| `ER:GENERIC` | Error genérico |
| `ER:BAD_DATA` | Parámetros incorrectos |

## Uso

1. Introduce el importe pulsando los dígitos (los dos últimos siempre son céntimos: `1250` → `12,50 €`)
2. Pulsa **COBRAR**
3. El cliente introduce el efectivo en la máquina Cashlogy
4. La app muestra el resultado: efectivo recibido, cambio devuelto, etc.
5. Pulsa cualquier tecla para iniciar un nuevo cobro
