#!/usr/bin/env python3
# worker/print_worker.py
# Servicio que procesa la cola de impresión y envía ESC/POS por TCP/IP
# Ejecutar como servicio systemd en Raspberry Pi

import time
import socket
import logging
import os
import sys
import mysql.connector
from mysql.connector import Error as MySQLError
from datetime import datetime

# ── Configuración ─────────────────────────────────────────────
DB_CONFIG = {
    'host':     '127.0.0.1',
    'port':     3306,
    'database': 'restaurante',
    'user':     'restaurante_user',
    'password': os.environ.get('DB_PASS', 'CHANGE_ME_PASSWORD'),
    'charset':  'utf8mb4',
    'autocommit': False,
    'connection_timeout': 5,
}

POLL_INTERVAL  = 2     # segundos entre ciclos
MAX_INTENTOS   = 5     # reintentos antes de marcar error
PRINT_TIMEOUT  = 5     # timeout socket en segundos

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('/var/log/print_worker.log'),
    ]
)
log = logging.getLogger('print_worker')

# ── BD helper ────────────────────────────────────────────────
def get_db():
    return mysql.connector.connect(**DB_CONFIG)

def log_event(cursor, desc: str, level: str = 'info'):
    try:
        cursor.execute(
            'INSERT INTO eventos_sistema (descripcion, nivel) VALUES (%s, %s)',
            (desc, level)
        )
    except Exception:
        pass

# ── Impresión TCP/IP ESC/POS ──────────────────────────────────
def print_escpos(ip: str, port: int, data: bytes) -> bool:
    try:
        with socket.create_connection((ip, port), timeout=PRINT_TIMEOUT) as s:
            s.sendall(data)
        return True
    except (socket.timeout, ConnectionRefusedError, OSError) as e:
        log.error(f"Error impresión {ip}:{port} — {e}")
        return False

# ── Ciclo principal ───────────────────────────────────────────
def process_queue(conn):
    cur = conn.cursor(dictionary=True)
    try:
        # Tomar trabajos pendientes con pocos intentos
        cur.execute(
            """SELECT cq.id_trabajo, cq.id_impresora, cq.contenido_escpos, cq.intentos,
                      i.ip, i.puerto
                 FROM cola_impresion cq
                 JOIN impresoras i USING (id_impresora)
                WHERE cq.estado = 'pendiente' AND cq.intentos < %s
             ORDER BY cq.id_trabajo
                LIMIT 20
               FOR UPDATE SKIP LOCKED""",
            (MAX_INTENTOS,)
        )
        jobs = cur.fetchall()

        for job in jobs:
            jid  = job['id_trabajo']
            ip   = job['ip']
            port = int(job['puerto'])
            data = bytes(job['contenido_escpos'])

            # Marcar como en proceso
            cur.execute(
                "UPDATE cola_impresion SET estado='imprimiendo', intentos=intentos+1 WHERE id_trabajo=%s",
                (jid,)
            )
            conn.commit()

            ok = print_escpos(ip, port, data)
            if ok:
                cur.execute(
                    "UPDATE cola_impresion SET estado='ok', fecha_actualizacion=NOW() WHERE id_trabajo=%s",
                    (jid,)
                )
                log.info(f"Trabajo {jid} impreso en {ip}:{port}")
            else:
                intentos = int(job['intentos']) + 1
                nuevo_estado = 'error' if intentos >= MAX_INTENTOS else 'pendiente'
                msg = f"Fallo impresión {ip}:{port} intento {intentos}"
                cur.execute(
                    """UPDATE cola_impresion
                          SET estado=%s, mensaje_error=%s, fecha_actualizacion=NOW()
                        WHERE id_trabajo=%s""",
                    (nuevo_estado, msg, jid)
                )
                log_event(cur, f"[PrintWorker] {msg}", 'error')
                log.warning(msg)

            conn.commit()

    except MySQLError as e:
        log.error(f"Error BD en ciclo: {e}")
        conn.rollback()
    finally:
        cur.close()

def main():
    log.info("PrintWorker iniciado")
    conn = None
    while True:
        try:
            if conn is None or not conn.is_connected():
                log.info("Conectando a BD...")
                conn = get_db()
                log.info("BD conectada")

            process_queue(conn)

        except MySQLError as e:
            log.error(f"Error de conexión BD: {e}")
            if conn:
                try: conn.close()
                except: pass
            conn = None
            time.sleep(5)
        except KeyboardInterrupt:
            log.info("PrintWorker detenido")
            break
        except Exception as e:
            log.error(f"Error inesperado: {e}")

        time.sleep(POLL_INTERVAL)

    if conn:
        conn.close()

if __name__ == '__main__':
    main()
