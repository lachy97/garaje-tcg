package cu.garajetcg.garaje_tcg

import android.net.Uri
import androidx.core.content.FileProvider

/**
 * FileProvider que anuncia todos sus archivos como "application/octet-stream".
 *
 * WhatsApp decide si algo es foto o documento preguntando el tipo del archivo.
 * Con el FileProvider normal un .png responde "image/png" y WhatsApp lo comprime
 * como foto. Respondiendo un tipo genérico lo envía como DOCUMENTO, intacto; el
 * nombre sigue terminando en .png, así que al abrirlo se ve como imagen.
 */
class DocumentShareProvider : FileProvider() {
    override fun getType(uri: Uri): String = "application/octet-stream"
}
