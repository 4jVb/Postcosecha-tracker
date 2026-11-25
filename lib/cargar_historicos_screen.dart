import 'dart:io';
import 'package:flutter/material.dart';
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
      final lineas = contenido.split(RegExp(r'\r\n|\r|\n'));
      final historicos = <Map<String, dynamic>>[];
      for (var linea in lineas) {
        linea = linea.trim().replaceAll('\uFEFF', ''); if (linea.isEmpty) continue;
        final separador = linea.contains(';') ? ';' : ',';
        final partes = linea.split(separador);
        if (partes[0].trim().toLowerCase().contains('plot')) continue;
        if (partes.length < 4) throw FormatException('Faltan columnas (se necesitan 4)');
        historicos.add({'plot_name': partes[0].trim(), 'accession_name': partes[1].trim(), 'plot_number': partes[2].trim(), 'block_number': int.parse(partes[3].trim())});
      }
      if (historicos.isEmpty) throw FormatException('No hay datos válidos');
      if (mounted) setState(() { _rutaArchivo = archivo.path; _cantidadParseada = historicos.length; });
      setState(() => _cargando = true);
      // SE PASA EL PROYECTO AQUÍ
      await _db.insertarEnviosHistoricos(widget.proyecto, historicos);
      if (mounted) setState(() { _cargando = false; _guardado = true; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cargar Históricos')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Card(color: Colors.amber.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(Icons.info, color: Colors.amber.shade800), const SizedBox(width: 8), Text('Auto-avance de bloques', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber.shade800))]),
          const SizedBox(height: 8),
          const Text('Al cargar este CSV, la app buscará el bloque más alto (ej. Bloque 2) y actualizará automáticamente el contador de la pantalla principal a ese bloque.', style: TextStyle(fontSize: 13))
        ]))),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _cargando ? null : _seleccionarYProcesar, icon: _cargando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload), label: const Text('Seleccionar y Procesar CSV'), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16))),
        const SizedBox(height: 16),
        if (_rutaArchivo != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('Archivo: $_rutaArchivo', style: const TextStyle(fontSize: 12)))),
        if (_error != null) Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))),
        if (_cantidadParseada > 0) Card(color: _guardado ? Colors.green.shade50 : Colors.blue.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Text(_guardado ? '✓ $_cantidadParseada registros cargados y bloques actualizados' : 'Procesando $_cantidadParseada registros...', style: TextStyle(fontWeight: FontWeight.bold, color: _guardado ? Colors.green : Colors.blue))))
      ])),
    );
  }
}