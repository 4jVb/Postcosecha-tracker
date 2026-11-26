import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // NUEVO
import 'package:file_selector/file_selector.dart';
import 'database_helper.dart';

class CargarHistoricosScreen extends StatefulWidget {
  final String proyecto;
  const CargarHistoricosScreen({super.key, required this.proyecto});

  @override
  State<CargarHistoricosScreen> createState() => _CargarHistoricosScreenState();
}

class _CargarHistoricosScreenState extends State<CargarHistoricosScreen> {
  final _db = DatabaseHelper();
  String? _rutaArchivo;
  int _cantidadParseada = 0;
  String? _error;
  bool _cargando = false;
  bool _guardado = false;

  Future<void> _seleccionarYProcesar() async {
    setState(() { _error = null; _guardado = false; _cantidadParseada = 0; });
    try {
      const XTypeGroup typeGroup = XTypeGroup(label: 'CSV', extensions: ['csv', 'txt']);
      final XFile? archivo = await openFile(acceptedTypeGroups: [typeGroup]);
      if (archivo == null) return;
      final contenido = await archivo.readAsString();
      // FIX RENDIMIENTO: Procesar en segundo plano
      // NUEVO: usa el parser flexible de DatabaseHelper (detecta columnas por encabezado)
      final historicos = await compute(DatabaseHelper.parsearHistoricos, contenido);
      if (historicos.isEmpty) throw FormatException('No hay datos válidos');
      if (mounted) setState(() { _rutaArchivo = archivo.path; _cantidadParseada = historicos.length; });
      setState(() => _cargando = true);
      await _db.insertarEnviosHistoricos(widget.proyecto, historicos);
      if (mounted) setState(() { _cargando = false; _guardado = true; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  // El parseo ahora vive en DatabaseHelper.parsearHistoricos (columnas flexibles)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cargar Históricos')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(color: Colors.blue.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.table_chart, color: Colors.blue.shade700), const SizedBox(width: 8), Text('Columnas esperadas (en cualquier orden)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700))]),
          const SizedBox(height: 8),
          const Text(
            'El CSV debe tener estas 4 columnas. Si el archivo tiene encabezado (fila de títulos), el orden no importa:\n\n'
            '• plot_name — nombre del plot (ej: PROY-IPT_12)\n'
            '• accession_name — accesión / genotipo (ej: GEN-01)\n'
            '• plot_number — número de plot (ej: 12)\n'
            '• block_number — número de bloque (ej: 1)\n\n'
            'Si NO tiene encabezado, el orden debe ser exactamente:\nplot_name, accession_name, plot_number, block_number',
            style: TextStyle(fontSize: 13),
          )
        ]))),
        const SizedBox(height: 16),
        Card(color: Colors.amber.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.info, color: Colors.amber.shade800), const SizedBox(width: 8), Text('Auto-avance de bloques', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800))]),
          const SizedBox(height: 8),
          const Text('Al cargar este CSV, la app buscará el bloque más alto y actualizará automáticamente el contador. También se sincronizará con Firebase.', style: TextStyle(fontSize: 13))
        ]))),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _cargando ? null : _seleccionarYProcesar, icon: _cargando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload), label: const Text('Seleccionar y Procesar CSV'), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16))),
        const SizedBox(height: 16),
        if (_rutaArchivo != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('Archivo: $_rutaArchivo', style: const TextStyle(fontSize: 12)))),
        if (_error != null) Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))),
        if (_cantidadParseada > 0) Card(color: _guardado ? Colors.green.shade50 : Colors.blue.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Text(_guardado ? '✓ $_cantidadParseada registros cargados y bloques actualizados (local + Firebase)' : 'Procesando $_cantidadParseada registros...', style: TextStyle(fontWeight: FontWeight.bold, color: _guardado ? Colors.green : Colors.blue))))
      ])),
    );
  }
}