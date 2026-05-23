package com.restaurante.restaurante_tpv

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceSerial" -> result.success(readDeviceSerial())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isDeviceAdminActive" -> {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    val admin = ComponentName(this, TpvDeviceAdminReceiver::class.java)
                    result.success(dpm.isAdminActive(admin))
                }

                "requestDeviceAdmin" -> {
                    try {
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                            putExtra(
                                DevicePolicyManager.EXTRA_DEVICE_ADMIN,
                                ComponentName(
                                    this@MainActivity,
                                    TpvDeviceAdminReceiver::class.java,
                                ),
                            )
                            putExtra(
                                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                getString(R.string.device_admin_explanation),
                            )
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DEVICE_ADMIN", e.message, null)
                    }
                }

                "removeDeviceAdmin" -> {
                    try {
                        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        val admin = ComponentName(this, TpvDeviceAdminReceiver::class.java)
                        if (dpm.isAdminActive(admin)) {
                            dpm.removeActiveAdmin(admin)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("DEVICE_ADMIN", e.message, null)
                    }
                }

                "isLockTaskPermitted" -> {
                    val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    result.success(dpm.isLockTaskPermitted(packageName))
                }

                "startLockTask" -> {
                    try {
                        startLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "stopLockTask" -> {
                    try {
                        stopLockTask()
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "isInLockTaskMode" -> {
                    result.success(isInLockTaskModeCompat())
                }

                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun readDeviceSerial(): String? {
        return try {
            val serial =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Build.getSerial()
                } else {
                    Build.SERIAL
                }
            val trimmed = serial.trim()
            if (trimmed.isEmpty() || trimmed.equals("unknown", ignoreCase = true)) {
                null
            } else {
                trimmed
            }
        } catch (_: SecurityException) {
            null
        } catch (_: Exception) {
            null
        }
    }

    @Suppress("DEPRECATION")
    private fun isInLockTaskModeCompat(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        } else {
            am.isInLockTaskMode
        }
    }

    companion object {
        private const val CHANNEL = "com.restaurante.restaurante_tpv/kiosk"
        private const val DEVICE_CHANNEL = "com.restaurante.restaurante_tpv/device"
    }
}
