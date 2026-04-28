# 🍽️ Sistema TPV Restaurante — Guía de Instalación

## Arquitectura

```
[Sunmi V2 x5] ──HTTPS──▶ [Raspberry Pi 4]
                           ├── Apache + PHP (API REST)
                           ├── MySQL (BD)
                           └── PrintWorker (Python)
                                ├──TCP/IP──▶ Impresora Barra (192.168.1.101:9100)
                                └──TCP/IP──▶ Impresora Cocina (192.168.1.102:9100)
```

---

## 1. Raspberry Pi — Base de Datos

```bash
sudo mysql -u root -p < sql/schema.sql
# Crear usuario BD
sudo mysql -u root -p -e "
  CREATE USER 'restaurante_user'@'localhost' IDENTIFIED BY 'TU_PASSWORD';
  GRANT ALL PRIVILEGES ON restaurante.* TO 'restaurante_user'@'localhost';
  FLUSH PRIVILEGES;"
```

---

## 2. Raspberry Pi — Servidor Web (Apache + PHP)

```bash
sudo apt install apache2 php8.2 libapache2-mod-php8.2 php8.2-mysql -y
sudo a2enmod rewrite ssl

# Copiar backend
sudo cp -r backend/ /var/www/restaurante/
sudo chown -R www-data:www-data /var/www/restaurante/

# VirtualHost (editar IP/dominio)
sudo nano /etc/apache2/sites-available/restaurante.conf
```

### VirtualHost ejemplo:
```apache
<VirtualHost *:443>
    ServerName restaurante.local
    DocumentRoot /var/www/restaurante/api

    SSLEngine on
    SSLCertificateFile    /etc/ssl/restaurante/cert.pem
    SSLCertificateKeyFile /etc/ssl/restaurante/key.pem

    <Directory /var/www/restaurante/api>
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
```

```bash
sudo a2ensite restaurante.conf
sudo systemctl reload apache2
```

---

## 3. Editar configuración PHP

```bash
sudo nano /var/www/restaurante/config/database.php
# Cambiar: DB_PASS, JWT_SECRET
```

---

## 4. PrintWorker (Python)

```bash
sudo apt install python3-pip -y
pip3 install mysql-connector-python

# Archivo de variables de entorno
sudo mkdir /etc/restaurante
sudo bash -c 'echo "DB_PASS=TU_PASSWORD" > /etc/restaurante/env.conf'
sudo chmod 600 /etc/restaurante/env.conf

# Copiar worker
sudo cp backend/worker/print_worker.py /var/www/restaurante/worker/

# Instalar servicio systemd
sudo cp systemd/print_worker.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable print_worker
sudo systemctl start print_worker

# Ver logs
sudo journalctl -u print_worker -f
```

---

## 5. App Flutter (Sunmi V2)

### Requisitos:
- Flutter SDK ≥ 3.10
- Android SDK (target API 25 para Android 7.1.2)

```bash
cd flutter_app
flutter pub get
flutter build apk --release
# Instalar en Sunmi:
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Primera ejecución en el Sunmi:
1. Abre la app → pantalla de configuración
2. Introduce la URL: `https://192.168.1.X` (IP de la Raspberry)
3. Pulsa **Guardar y Conectar**
4. Selecciona tu usuario e introduce la contraseña
5. ¡Listo!

---

## 6. Contraseña admin por defecto

- Usuario: **admin**  
- Contraseña: **admin1234**  
⚠️ Cámbiala inmediatamente en producción.

---

## 7. IPs de impresoras

Editar en la BD:
```sql
UPDATE restaurante.impresoras SET ip='192.168.100.10' WHERE nombre='Barra';
UPDATE restaurante.impresoras SET ip='192.168.100.11' WHERE nombre='Cocina';
```

---

## 8. Estructura de archivos

```
restaurante/
├── sql/
│   └── schema.sql               ← Ejecutar primero en MySQL
├── backend/
│   ├── config/database.php      ← ⚙️ Editar credenciales
│   ├── lib/
│   │   ├── jwt.php
│   │   └── helpers.php
│   ├── api/
│   │   ├── index.php            ← Punto de entrada API
│   │   ├── .htaccess
│   │   └── endpoints/
│   │       ├── auth.php
│   │       ├── usuarios.php
│   │       ├── catalogo.php
│   │       ├── mesas.php
│   │       └── pedidos.php
│   └── worker/
│       └── print_worker.py      ← Worker ESC/POS
├── systemd/
│   └── print_worker.service     ← Servicio systemd
└── flutter_app/                 ← Proyecto Flutter completo
    ├── pubspec.yaml
    ├── lib/
    │   ├── main.dart
    │   ├── models/models.dart
    │   ├── services/
    │   │   ├── api_service.dart
    │   │   ├── catalogo_provider.dart
    │   │   └── sunmi_service.dart
    │   ├── screens/
    │   │   ├── config_screen.dart
    │   │   ├── login_screen.dart
    │   │   ├── mesas_screen.dart
    │   │   └── hacer_pedido_screen.dart
    │   ├── widgets/
    │   │   ├── catalogo_panel.dart
    │   │   ├── lineas_panel.dart
    │   │   ├── producto_opciones_dialog.dart
    │   │   └── editar_linea_dialog.dart
    │   └── utils/theme.dart
    └── android/app/src/main/AndroidManifest.xml
```

---

## 9. Seguridad en producción

- [ ] Cambiar `JWT_SECRET` en `database.php` (mín. 32 chars aleatorios)
- [ ] Cambiar password del admin
- [ ] Usar certificado SSL válido (Let's Encrypt o auto-firmado con CA propia)
- [ ] Firewall: solo puertos 443 y 9100 (impresoras) accesibles internamente
- [ ] `DB_PASS` solo en `/etc/restaurante/env.conf` con permisos 600
