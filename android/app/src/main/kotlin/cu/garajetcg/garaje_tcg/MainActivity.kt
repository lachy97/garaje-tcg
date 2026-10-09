package cu.garajetcg.garaje_tcg

import android.content.ClipData
import android.content.Intent
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
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
