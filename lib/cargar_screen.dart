import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // NUEVO
import 'package:file_selector/file_selector.dart';
import 'database_helper.dart';

class CargarScreen extends StatefulWidget {
  const CargarScreen({super.key});

  @override
  State<CargarScreen> createState() => _CargarScreenState();
}

class _CargarScreenState extends State<CargarScreen> {
  final _db = DatabaseHelper();
  String? _rutaArchivo;
  List<Map<String, dynamic>> _plotsParseados = [];
  String? _error;
  bool _cargando = false;
  bool _guardado = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Cargar Libro de Campo')), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(color: Colors.blue.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(Icons.info_outline, color: Colors.blue.shade700), const SizedBox(width: 8), Text('Formato CSV Automático', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700))]),
        const SizedBox(height: 8),
        const Text('La app detectará el Proyecto y el Tipo automáticamente del nombre del plot.\n\nColumnas esperadas:\n- Campo/INT: plot_name, accession_name, plot_number\n- Postcosecha/Sensorial: plot_name, accession_name, plot_number, block_number', style: TextStyle(fontSize: 13))
      ]))),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _cargando ? null : _seleccionarArchivo, icon: const Icon(Icons.folder_open), label: const Text('Seleccionar archivo CSV'), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16))),
      const SizedBox(height: 16),
      if (_rutaArchivo != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Icon(Icons.insert_drive_file, color: Colors.green), const SizedBox(width: 12), Expanded(child: Text(_rutaArchivo!, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis))])))
      else const SizedBox(height: 8),
      if (_error != null) Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.error, color: Colors.red.shade700, size: 20), const SizedBox(width: 8), Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700)))]))),
      if (_plotsParseados.isNotEmpty) ...[
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Vista previa: ${_plotsParseados.length} plots', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Proyecto: ${_plotsParseados.first['project_name']} | Tipo: ${_plotsParseados.first['experiment_type']}', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 8),
          SizedBox(height: 150, child: ListView.builder(itemCount: _plotsParseados.length > 30 ? 30 : _plotsParseados.length, itemBuilder: (context, index) {
            final p = _plotsParseados[index];
            return Text('${index + 1}. ${p['plot_name']} (${p['accession_name']})', style: const TextStyle(fontSize: 11, fontFamily: 'monospace'));
          }))
        ]))),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _cargando ? null : _guardarPlots, icon: _cargando ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save), label: Text(_guardado ? '✓ Guardado' : 'Guardar en Base de Datos'), style: FilledButton.styleFrom(backgroundColor: _guardado ? Colors.green : null, padding: const EdgeInsets.symmetric(vertical: 16)))
      ]
    ])));
  }

  Future<void> _seleccionarArchivo() async {
    setState(() { _error = null; _guardado = false; _plotsParseados = []; });
    try {
      const XTypeGroup typeGroup = XTypeGroup(label: 'CSV', extensions: ['csv', 'txt']);
      final XFile? archivo = await openFile(acceptedTypeGroups: [typeGroup]);
      if (archivo == null) return;
      final contenido = await archivo.readAsString();
      // FIX RENDIMIENTO: Procesar en segundo plano
      final plots = await compute(_parsearCSVenSegundoPlano, contenido);
      setState(() { _rutaArchivo = archivo.path; _plotsParseados = plots; });
    } catch (e) { setState(() => _error = e.toString()); }
  }

  // Función estática para segundo plano
  static List<Map<String, dynamic>> _parsearCSVenSegundoPlano(String contenido) {
    return DatabaseHelper().parsearCSV(contenido);
  }

  Future<void> _guardarPlots() async {
    setState(() => _cargando = true);
    try {
      await _db.insertarPlots(_plotsParseados);
      if (mounted) { setState(() { _cargando = false; _guardado = true; }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_plotsParseados.length} plots cargados'), backgroundColor: Colors.green)); }
    } catch (e) { if (mounted) setState(() { _cargando = false; _error = 'Error al guardar: $e'; }); }
  }
}