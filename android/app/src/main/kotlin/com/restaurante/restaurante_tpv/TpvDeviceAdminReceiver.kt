package com.restaurante.restaurante_tpv

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Administrador de dispositivo mínimo para poder usar políticas de bloqueo (kiosco)
 * cuando el terminal esté provisionado como propietario del dispositivo, o como
 * paso previo a habilitar el modo de tarea bloqueada según el fabricante.
 */
class TpvDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        Log.i(TAG, "Device admin activado")
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        Log.i(TAG, "Device admin desactivado")
    }

    companion object {
        private const val TAG = "TpvDeviceAdmin"
    }
}
