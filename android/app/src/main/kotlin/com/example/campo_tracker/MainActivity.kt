package com.example.campo_tracker

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.campo_tracker/archivo"
    private val CREAR_ARCHIVO = 1001

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "abrirGuardador" -> {
                    val nombre = call.argument<String>("nombreSugerido") ?: "archivo.csv"
                    abrirExploradorArchivos(nombre)
                    result.success(null)
                }
                "escribirEnUri" -> {
                    val uri = call.argument<String>("uri")
                    val contenido = call.argument<String>("contenido")
                    escribirEnUri(uri, contenido, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun abrirExploradorArchivos(nombreArchivo: String) {
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "text/csv"
            putExtra(Intent.EXTRA_TITLE, nombreArchivo)
        }
        startActivityForResult(intent, CREAR_ARCHIVO)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CREAR_ARCHIVO && resultCode == Activity.RESULT_OK) {
            data?.data?.let { uri ->
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                    
                    val path = uri.toString()
                    MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                        .invokeMethod("rutaSeleccionada", path)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }

    private fun escribirEnUri(uriStr: String?, contenido: String?, result: MethodChannel.Result) {
        try {
            if (uriStr == null || contenido == null) {
                result.error("ERROR", "Datos vacíos", null)
                return
            }
            val uri = Uri.parse(uriStr)
            contentResolver.openOutputStream(uri)?.use { outputStream ->
                outputStream.write(contenido.toByteArray(Charsets.UTF_8))
                outputStream.flush()
                result.success("OK")
            } ?: run {
                result.error("ERROR", "No se pudo abrir el archivo", null)
            }
        } catch (e: Exception) {
            result.error("ERROR_ESCRITURA", e.message, null)
        }
    }
}