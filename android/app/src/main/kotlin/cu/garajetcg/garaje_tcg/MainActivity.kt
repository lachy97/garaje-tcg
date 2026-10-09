package cu.garajetcg.garaje_tcg

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    // Bloqueo de capturas y grabación de pantalla (FLAG_SECURE). Activo por
    // defecto; solo se quita si el administrador lo desactivó en la app
    // (preferencia "screen_protection_off" de shared_preferences).
    override fun onCreate(savedInstanceState: Bundle?) {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val off = try {
            prefs.getBoolean("flutter.screen_protection_off", false)
        } catch (e: Exception) {
            false
        }
        setSecure(!off)
        super.onCreate(savedInstanceState)
    }

    private fun setSecure(secure: Boolean) {
        if (secure) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Identificador del teléfono para las licencias (ANDROID_ID). Es estable:
        // solo cambia si se restablece el teléfono de fábrica.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "garage_tcg/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "androidId" -> result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    )
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: true
                        runOnUiThread { setSecure(secure) }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Compartir un archivo como DOCUMENTO (sin que WhatsApp lo comprima).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "garage_tcg/share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareAsDocument" -> {
                        try {
                            val file = File(call.argument<String>("path")!!)
                            val text = call.argument<String>("text")
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.document_provider", file
                            )
                            val send = Intent(Intent.ACTION_SEND).apply {
                                type = "application/octet-stream"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                if (text != null) putExtra(Intent.EXTRA_TEXT, text)
                                clipData = ClipData.newRawUri(file.name, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            val chooser = Intent.createChooser(send, "Enviar imagen como archivo")
                            chooser.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            startActivity(chooser)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("share_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
