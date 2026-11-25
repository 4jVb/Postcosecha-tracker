import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'database_helper.dart';

class EnviosScreen extends StatefulWidget {
  const EnviosScreen({super.key});

  @override
  State<EnviosScreen> createState() => _EnviosScreenState();
}

class _EnviosScreenState extends State<EnviosScreen> {
  final _db = DatabaseHelper();
  String _csv = '';
  bool _cargando = true;

  // Canal para comunicarse con el código nativo de Android (MainActivity.kt)
  static const MethodChannel _channel = MethodChannel('com.example.campo_tracker/archivo');

  @override
  void initState() {
    super.initState();
    _generarCSV();
    // Escuchar las respuestas que envía Android
    _channel.setMethodCallHandler(_manejarRespuestaAndroid);
  }

  Future<void> _generarCSV() async {
    final now = DateTime.now();
    final fecha = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final data = await _db.generarCSVDia(fecha);
    if (mounted) setState(() { _csv = data; _cargando = false; });
  }

  // Recibe la URI de Android y le pide que escriba el contenido ahí
  Future<dynamic> _manejarRespuestaAndroid(MethodCall call) async {
    if (call.method == "rutaSeleccionada") {
      final String uriStr = call.arguments as String;
      if (uriStr.isNotEmpty) {
        try {
          // Enviar la URI y el texto a Android para que lo escriba correctamente
          final String resultado = await _channel.invokeMethod('escribirEnUri', {
            'uri': uriStr,
            'contenido': _csv,
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('¡Archivo guardado con éxito!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } on PlatformException catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error al guardar: ${e.message}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  // BOTÓN 1: Guardar Local (Abre el explorador de Android para elegir carpeta)
  Future<void> _guardarLocal() async {
    try {
      final now = DateTime.now();
      final fechaStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      
      // Llama a Android para abrir la ventana de "Guardar como"
      await _channel.invokeMethod('abrirGuardador', {
        'nombreSugerido': 'Envios_$fechaStr.csv'
      });
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al abrir explorador: ${e.message}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // BOTÓN 2: Compartir (WhatsApp, Gmail, Bluetooth, etc.)
  Future<void> _compartir() async {
    final directory = await getTemporaryDirectory();
    final now = DateTime.now();
    final fechaStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final archivo = File('${directory.path}/Envios_$fechaStr.csv');
    await archivo.writeAsString(_csv);
    if (!mounted) return;
    await Share.shareXFiles([XFile(archivo.path)], text: 'Envíos del $fechaStr');
  }

  @override
  Widget build(BuildContext context) {
    bool hayDatos = _csv.split('\n').length > 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Envíos de Hoy')),
      body: _cargando 
        ? const Center(child: CircularProgressIndicator()) 
        : Column(children: [
            if (hayDatos) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Colors.blue.shade50,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Opciones de Exportación', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Botón Guardar Local
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _guardarLocal,
                            icon: const Icon(Icons.save_alt, size: 18),
                            label: const Text('Guardar Local', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Botón Compartir
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _compartir,
                            icon: const Icon(Icons.share, size: 18),
                            label: const Text('Compartir', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
            // Vista previa del CSV
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text(_csv, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))
              )
            )
          ])
    );
  }
}