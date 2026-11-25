import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'cargar_screen.dart';
import 'cargar_historicos_screen.dart';
import 'escaneo_screen.dart';
import 'envios_screen.dart';
import 'firebase_sync.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseHelper();
  final _sync = FirebaseSync();
  List<String> _proyectos = [];
  String? _proyectoSeleccionado;
  int _plotsCargados = 0, _enviosHoy = 0, _bloqueIpt = 1, _bloqueSet = 1, _bloqueCpt = 1;
  bool _tieneCPT = false, _cargando = true, _sincronizando = false;

  @override
  void initState() { super.initState(); _cargarDatos(); }

  Future<void> _cargarDatos() async {
    final proyectos = await _db.obtenerProyectos();
    if (proyectos.isNotEmpty && _proyectoSeleccionado == null) _proyectoSeleccionado = proyectos.first;
    // Trae los bloques de la nube SOLO una vez al abrir la app, para todos los proyectos
    for (var proyecto in proyectos) {
      await _db.sincronizarBloquesDesdeNube(proyecto, 'IPT');
      await _db.sincronizarBloquesDesdeNube(proyecto, 'SET');
      await _db.sincronizarBloquesDesdeNube(proyecto, 'CPT');
    }

    await _cargarEstadisticas();
    if (mounted) setState(() { _proyectos = proyectos; _cargando = false; });
  }

  Future<void> _cargarEstadisticas() async {
    if (_proyectoSeleccionado == null) return;
    final plots = await _db.contarPlotsProyecto(_proyectoSeleccionado!);
    final envios = await _db.contarEnviosHoy();
    final bIpt = await _db.getBloqueActual(_proyectoSeleccionado!, 'IPT');
    final bSet = await _db.getBloqueActual(_proyectoSeleccionado!, 'SET');
    final bCpt = await _db.getBloqueActual(_proyectoSeleccionado!, 'CPT');
    final tieneCpt = await _db.proyectoTieneCPT(_proyectoSeleccionado!);
    if (mounted) setState(() { _plotsCargados = plots; _enviosHoy = envios; _bloqueIpt = bIpt; _bloqueSet = bSet; _bloqueCpt = bCpt; _tieneCPT = tieneCpt; });
  }

  Future<void> _sincronizar() async {
    if (_sincronizando) return;
    setState(() => _sincronizando = true);
    try {
      await _sync.sincronizarTodo(proyectoActual: _proyectoSeleccionado);
      await _cargarDatos();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✓ Sincronizado con la nube'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sin conexión a la nube. La app seguirá funcionando local.\nDetalle: ${e.toString().replaceFirst('Exception: ', '')}'), backgroundColor: Colors.orange, duration: const Duration(seconds: 4)));
    } finally { if (mounted) setState(() => _sincronizando = false); }
  }

  Future<void> _cambiarBloque(String tipo, int delta) async {
    final nombres = {'IPT': 'Postcosecha', 'SET': 'Sensorial', 'CPT': 'Panel Consumidor'};
    final nombreTipo = nombres[tipo] ?? tipo;
    final accion = delta > 0 ? 'Avanzar' : 'Retroceder';
    int bloqueNuevo;
    if (tipo == 'IPT') bloqueNuevo = _bloqueIpt + delta; else if (tipo == 'SET') bloqueNuevo = _bloqueSet + delta; else bloqueNuevo = _bloqueCpt + delta;
    final confirmar = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text('$accion Bloque $nombreTipo'),
      content: Text(delta > 0 ? '¿Pasar al bloque $bloqueNuevo?\nSe reiniciará la lista de enviados.' : '¿Retroceder al bloque $bloqueNuevo?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar'))],
    ));
    if (confirmar == true) {
      try {
        if (delta > 0) await _db.avanzarBloque(_proyectoSeleccionado!, tipo); else await _db.retrocederBloque(_proyectoSeleccionado!, tipo);
        _cargarEstadisticas();
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red)); }
    }
  }

  void _formatTotal() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('⚠️ FORMATEAR TODO', style: TextStyle(color: Colors.red)),
      content: const Text('Se eliminarán TODOS los proyectos, libros de campo, envíos y bloques.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () async { await _db.limpiarTodo(); if (mounted) { Navigator.pop(ctx); setState(() { _proyectos = []; _proyectoSeleccionado = null; _plotsCargados = 0; _enviosHoy = 0; _tieneCPT = false; }); } }, child: const Text('Borrar Todo'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Postcosecha Tracker'), centerTitle: true, elevation: 0),
      body: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: DropdownButtonFormField<String>(value: _proyectoSeleccionado, decoration: const InputDecoration(border: InputBorder.none, icon: Icon(Icons.folder_open)), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.black87), items: _proyectos.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(), onChanged: (val) { setState(() => _proyectoSeleccionado = val); _cargarEstadisticas(); })),
        const SizedBox(height: 24),
        Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Estado Actual', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16),
          Row(children: [Expanded(child: _statCard(Icons.inventory_2, 'Plots', '$_plotsCargados', Colors.indigo)), const SizedBox(width: 12), Expanded(child: _statCard(Icons.check_circle_outline, 'Envíos Hoy', '$_enviosHoy', Colors.green))]),
          const Divider(height: 32),
          _filaStatModerna(Icons.agriculture, 'Postcosecha (IPT)', 'Bloque $_bloqueIpt', Colors.purple), const SizedBox(height: 12),
          _filaStatModerna(Icons.rate_review, 'Sensorial (SET)', 'Bloque $_bloqueSet', Colors.teal),
          if (_tieneCPT) ...[const SizedBox(height: 12), _filaStatModerna(Icons.groups, 'Panel Consumidor (CPT)', 'Bloque $_bloqueCpt', Colors.deepPurple)],
        ]))),
        const SizedBox(height: 32),
        _accionPrincipal(Icons.qr_code_scanner, 'Registrar Postcosecha (IPT)', 'Escaneo por QR', Colors.purple, _irAIPT, hab: _proyectoSeleccionado != null), const SizedBox(height: 12),
        _accionPrincipal(Icons.checklist, 'Registrar Sensorial (SET)', 'Selección por bloque', Colors.teal, _irASET, hab: _proyectoSeleccionado != null),
        if (_tieneCPT) ...[const SizedBox(height: 12), _accionPrincipal(Icons.groups, 'Registrar Panel Consumidor (CPT)', 'Selección por bloque', Colors.deepPurple, _irACPT, hab: _proyectoSeleccionado != null)],
        const SizedBox(height: 12),
        _accionPrincipal(Icons.search, 'Consultar Campo (INT)', 'Consulta rápida de accesiones', Colors.brown, _irAINT, hab: _proyectoSeleccionado != null),
        const SizedBox(height: 32),
        Text('Herramientas y Datos', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600])), const SizedBox(height: 12),
        _accionSecundaria(Icons.upload_file, 'Cargar Libros de Campo', 'CSV de Campo, Postcosecha, Sensorial o CPT', _irACargar),
        _accionSecundaria(Icons.history, 'Cargar Históricos', 'CSV de plots ya enviados', _irAHistoricos, hab: _proyectoSeleccionado != null),
        Container(margin: const EdgeInsets.only(bottom: 12, top: 4), decoration: BoxDecoration(color: _sincronizando ? Colors.blue.withOpacity(0.1) : Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade200)), child: ListTile(leading: _sincronizando ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)) : const Icon(Icons.cloud_upload_outlined, color: Colors.blue), title: Text('Sincronizar Nube', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade700)), subtitle: Text(_sincronizando ? 'Sincronizando...' : 'Actualizar datos con otros usuarios', style: TextStyle(fontSize: 12, color: Colors.blue.shade400)), trailing: const Icon(Icons.chevron_right, color: Colors.blue), onTap: !_sincronizando ? _sincronizar : null)),
        const SizedBox(height: 24),
        Text('Gestión de Bloques', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600])), const SizedBox(height: 12),
        _botonesBloque('IPT', Colors.purple), const SizedBox(height: 8), _botonesBloque('SET', Colors.teal),
        if (_tieneCPT) ...[const SizedBox(height: 8), _botonesBloque('CPT', Colors.deepPurple)],
        const SizedBox(height: 32),
        FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EnviosScreen())), icon: const Icon(Icons.download), label: const Text('Ver Envíos de Hoy y Exportar CSV'), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 16),
        OutlinedButton.icon(icon: const Icon(Icons.delete_forever, color: Colors.red), label: const Text('Formatear Todo', style: TextStyle(color: Colors.red)), style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _formatTotal),
        const SizedBox(height: 40),
      ])),
    );
  }

  Widget _statCard(IconData icon, String title, String value, Color color) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Column(children: [Icon(icon, color: color, size: 28), const SizedBox(height: 8), Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)), Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600]))]));
  }

  Widget _filaStatModerna(IconData icon, String title, String value, Color color) {
    return Row(children: [Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)), const SizedBox(width: 16), Expanded(child: Text(title, style: const TextStyle(fontSize: 15))), Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)), child: Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)))]);
  }

  Widget _accionPrincipal(IconData icon, String titulo, String sub, Color color, VoidCallback onTap, {bool hab = true}) {
    return Card(elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: hab ? color.withOpacity(0.2) : Colors.grey.shade200)), child: InkWell(borderRadius: BorderRadius.circular(16), onTap: hab ? onTap : null, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [Container(width: 52, height: 52, decoration: BoxDecoration(color: hab ? color : Colors.grey, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Colors.white, size: 28)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(titulo, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: hab ? Colors.black87 : Colors.grey)), const SizedBox(height: 4), Text(sub, style: TextStyle(fontSize: 13, color: hab ? Colors.grey[600] : Colors.grey))])), if (hab) Icon(Icons.arrow_forward_ios, size: 16, color: color.withOpacity(0.5))]))));
  }

  Widget _accionSecundaria(IconData icon, String titulo, String sub, VoidCallback onTap, {bool hab = true}) {
    return Container(margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)), child: ListTile(leading: Icon(icon, color: hab ? Colors.grey[700] : Colors.grey), title: Text(titulo, style: TextStyle(fontWeight: FontWeight.w500, color: hab ? Colors.black87 : Colors.grey)), subtitle: Text(sub, style: TextStyle(fontSize: 12, color: hab ? Colors.grey[600] : Colors.grey)), trailing: const Icon(Icons.chevron_right, color: Colors.grey), onTap: hab ? onTap : null));
  }

  Widget _botonesBloque(String tipo, Color color) {
    return Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _proyectoSeleccionado != null ? () => _cambiarBloque(tipo, -1) : null, icon: Icon(Icons.fast_rewind, color: _proyectoSeleccionado != null ? color : Colors.grey, size: 18), label: Text('Retroceder $tipo', style: TextStyle(color: _proyectoSeleccionado != null ? color : Colors.grey, fontSize: 13)), style: OutlinedButton.styleFrom(side: BorderSide(color: _proyectoSeleccionado != null ? color : Colors.grey), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)))), const SizedBox(width: 12), Expanded(child: FilledButton.icon(onPressed: _proyectoSeleccionado != null ? () => _cambiarBloque(tipo, 1) : null, icon: const Icon(Icons.fast_forward, size: 18), label: Text('Avanzar $tipo', style: const TextStyle(fontSize: 13)), style: FilledButton.styleFrom(backgroundColor: _proyectoSeleccionado != null ? color : Colors.grey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12))))]);
  }

  void _irACargar() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => const CargarScreen())); _cargarDatos(); }
  void _irAHistoricos() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => CargarHistoricosScreen(proyecto: _proyectoSeleccionado!))); _cargarEstadisticas(); }
  void _irAIPT() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => EscaneoScreen(proyecto: _proyectoSeleccionado!, tipo: 'IPT'))); _cargarEstadisticas(); }
  void _irASET() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => EscaneoScreen(proyecto: _proyectoSeleccionado!, tipo: 'SET'))); _cargarEstadisticas(); }
  void _irACPT() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => EscaneoScreen(proyecto: _proyectoSeleccionado!, tipo: 'CPT'))); _cargarEstadisticas(); }
  void _irAINT() async { await Navigator.push(context, MaterialPageRoute(builder: (_) => EscaneoScreen(proyecto: _proyectoSeleccionado!, tipo: 'INT'))); _cargarEstadisticas(); }
}