import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'database_helper.dart';

class EscaneoScreen extends StatefulWidget {
  final String proyecto;
  final String tipo;
  const EscaneoScreen({super.key, required this.proyecto, required this.tipo});

  @override
  State<EscaneoScreen> createState() => _EscaneoScreenState();
}

class _EscaneoScreenState extends State<EscaneoScreen> {
  final _db = DatabaseHelper();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    autoStart: false, // No enciende la cámara hasta que se le diga
    formats: [BarcodeFormat.qrCode],
    detectionTimeoutMs: 250,
  );

  bool _procesando = false;
  bool _permisoConcedido = false;
  bool _usandoCamara = false; // Controla si la cámara está encendida
  final List<Map<String, dynamic>> _enviosSesion = [];

  List<Map<String, dynamic>> _plotsSet = [];
  Set<String> _seleccionadosHoy = {};
  bool _cargandoPlots = true;
  String? _errorSet;

  List<Map<String, dynamic>> _plotsCpt = [];
  Set<String> _seleccionadosCptHoy = {};
  bool _cargandoPlotsCpt = true;
  String? _errorCpt;

  String? _ultimoPlot;
  String? _ultimoMsg;
  Color? _ultimoColor;
  bool _mostrarResultado = false;

  Map<String, dynamic>? _resultadoINT;
  List<Map<String, dynamic>> _enviosIptHoy = [];
  bool _cargandoIptHoy = false;

  // Controladores para el campo de texto del láser
  final _laserController = TextEditingController();
  final _laserFocusNode = FocusNode();

  String get _titulo => widget.tipo == 'IPT'
      ? 'Registrar Postcosecha'
      : widget.tipo == 'SET'
          ? 'Registrar Sensorial'
          : widget.tipo == 'CPT'
              ? 'Registrar Panel Consumidor (CPT)'
              : 'Consultar Campo (INT)';

  @override
  void initState() {
    super.initState();
    if (widget.tipo == 'SET') {
      _cargarPlotsSet();
    } else if (widget.tipo == 'CPT') {
      _cargarPlotsCpt();
    } else if (widget.tipo == 'IPT') {
      _cargarEnviosIptHoy();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _laserFocusNode.requestFocus();
      });
    } else {
      // INT: También inicia con teclado/láser listo
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _laserFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _laserController.dispose();
    _laserFocusNode.dispose();
    super.dispose();
  }

  // ==========================================
  // INTERFAZ LÁSER / TECLADO (Honeywell)
  // ==========================================
  Future<void> _procesarLaserInput(String input) async {
    if (_procesando || input.trim().isEmpty) return;
    setState(() => _procesando = true);
    
    // Selecciona todo el texto para que el próximo escaneo lo reemplace
    _laserController.selection = TextSelection(baseOffset: 0, extentOffset: _laserController.text.length);

    await _procesarEscaneo(input.trim());
    
    if (mounted) setState(() => _procesando = false);
  }

  Widget _buildLaserUI() {
    return Column(
      children: [
        if (_mostrarResultado && widget.tipo == 'INT' && _resultadoINT != null)
          _buildIntResultado()
        else if (_mostrarResultado)
          _buildResultado(),

        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.tipo == 'INT' ? 'Modo Lector / Consulta' : 'Modo Lector (Láser Honeywell)',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Apunte con el láser o escriba el código. Se procesa automáticamente al escanear.',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _laserController,
                focusNode: _laserFocusNode,
                autofocus: true,
                onSubmitted: _procesarLaserInput,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Esperando escaneo...',
                  prefixIcon: _procesando 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.qr_code_scanner),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _activarCamara,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Usar Cámara del Celular'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(width: 2),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Text('Registros esta sesión', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    Text('${_enviosSesion.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: _buildListaInferior(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _activarCamara() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      if (mounted) setState(() {
        _usandoCamara = true;
        _permisoConcedido = true;
      });
      _scannerController.start();
    } else {
      final res = await Permission.camera.request();
      if (res.isGranted) {
        if (mounted) setState(() {
          _usandoCamara = true;
          _permisoConcedido = true;
        });
        _scannerController.start();
      } else if (res.isPermanentlyDenied) {
        _mostrarDialogoPermiso();
      }
    }
  }

  // ==========================================
  // LÓGICA EXCLUSIVA PARA SET (SIN CAMBIOS)
  // ==========================================
  Future<void> _cargarPlotsSet() async {
    try {
      final bloque = await _db.getBloqueActual(widget.proyecto, 'SET');
      final plots = await _db.obtenerPlotsBloque(widget.proyecto, 'SET', bloque);
      final Set<String> enviados = {};
      for (var plot in plots) {
        if (await _db.fueEnviadoHoy(plot['plot_name'])) enviados.add(plot['plot_name'] as String);
      }
      if (mounted) setState(() { _plotsSet = plots; _seleccionadosHoy = enviados; _cargandoPlots = false; _errorSet = null; });
    } catch (e) {
      if (mounted) setState(() { _cargandoPlots = false; _errorSet = 'Error al cargar plots: $e'; });
    }
  }

  Future<void> _toggleSeleccion(Map<String, dynamic> plot) async {
    final plotName = plot['plot_name'] as String;
    final estaMarcado = _seleccionadosHoy.contains(plotName);
    String msg = '';
    Color color = Colors.red;
    if (estaMarcado) {
      await _db.eliminarEnvioHoy(plotName);
      if (mounted) setState(() { _seleccionadosHoy.remove(plotName); _enviosSesion.removeWhere((e) => e['plot'] == plotName); _mostrarResultado = false; });
    } else {
      final result = await _db.registrarEnvio(plotName, widget.proyecto, 'SET');
      if (result['status'] == 'OK') {
        msg = 'Accesión: ${result['accession_name']}\nBloque: ${result['block_number']}\nPlot N°: ${result['plot_number']}\n¡Registro exitoso!';
        color = Colors.green;
        if (mounted) setState(() { _seleccionadosHoy.add(plotName); _enviosSesion.add({'plot': plotName, 'msg': 'Acc: ${result['accession_name']} | Blq: ${result['block_number']}'}); });
        HapticFeedback.mediumImpact();
      } else if (result['status'] == 'BLOQUE_FUTURO') { msg = result['mensaje'] ?? 'Error al registrar.'; color = Colors.orange; HapticFeedback.heavyImpact(); }
      else { msg = 'Plot enviado'; color = Colors.red; HapticFeedback.heavyImpact(); }
    }
    if (mounted) setState(() { _ultimoPlot = plotName; _ultimoMsg = msg; _ultimoColor = color; _mostrarResultado = (msg.isNotEmpty); });
  }

  Future<void> _procesarManualSET(String input) async {
    final inputNum = int.tryParse(input);
    final plot = _plotsSet.firstWhere((p) => inputNum != null ? (int.tryParse(p['plot_number'] as String) == inputNum) : (p['plot_number'] == input), orElse: () => <String, dynamic>{});
    if (plot.isEmpty) { setState(() { _ultimoPlot = input; _ultimoMsg = 'Plot N° $input no encontrado en el bloque actual'; _ultimoColor = Colors.red; _mostrarResultado = true; }); HapticFeedback.heavyImpact(); return; }
    await _toggleSeleccion(plot);
  }

  void _mostrarIngresoManualSET() {
    final controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Registrar Sensorial (SET)'), content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Ej: 1', border: OutlineInputBorder(), isDense: true), onSubmitted: (v) { Navigator.pop(ctx); if (v.trim().isNotEmpty) _procesarManualSET(v.trim()); }), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), FilledButton(onPressed: () { Navigator.pop(ctx); if (controller.text.trim().isNotEmpty) _procesarManualSET(controller.text.trim()); }, child: const Text('Aceptar'))]));
  }

  Widget _buildSetUI() {
    if (_cargandoPlots) return const Center(child: CircularProgressIndicator());
    if (_errorSet != null) return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_errorSet!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))));
    if (_plotsSet.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No hay plots para el bloque actual en el libro SET.\nAsegúrate de haber cargado el CSV correctamente.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))));
    return Column(
      children: [
        if (_mostrarResultado) _buildResultado(),
        Expanded(child: ListView.builder(padding: const EdgeInsets.only(top: 8, bottom: 80), itemCount: _plotsSet.length, itemBuilder: (context, index) {
          final plot = _plotsSet[index]; final plotName = plot['plot_name'] as String; final estaMarcado = _seleccionadosHoy.contains(plotName);
          return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: estaMarcado ? Colors.teal.withOpacity(0.1) : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: estaMarcado ? Colors.teal : Colors.grey.shade300)), child: CheckboxListTile(controlAffinity: ListTileControlAffinity.leading, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), title: Text(plot['plot_number'], style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16)), subtitle: Text('${plot['plot_name']}\n${plot['accession_name']}', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey[700])), value: estaMarcado, activeColor: Colors.teal, onChanged: (bool? value) => _toggleSeleccion(plot)));
        })),
      ],
    );
  }

  // ==========================================
  // LÓGICA EXCLUSIVA PARA CPT (SIN CAMBIOS)
  // ==========================================
  Future<void> _cargarPlotsCpt() async {
    try {
      final bloque = await _db.getBloqueActual(widget.proyecto, 'CPT');
      final plots = await _db.obtenerPlotsBloque(widget.proyecto, 'CPT', bloque);
      final Set<String> enviados = {};
      for (var plot in plots) {
        if (await _db.fueEnviadoHoy(plot['plot_name'])) enviados.add(plot['plot_name'] as String);
      }
      if (mounted) setState(() { _plotsCpt = plots; _seleccionadosCptHoy = enviados; _cargandoPlotsCpt = false; _errorCpt = null; });
    } catch (e) {
      if (mounted) setState(() { _cargandoPlotsCpt = false; _errorCpt = 'Error al cargar plots CPT: $e'; });
    }
  }

  Future<void> _toggleSeleccionCpt(Map<String, dynamic> plot) async {
    final plotName = plot['plot_name'] as String;
    final estaMarcado = _seleccionadosCptHoy.contains(plotName);
    String msg = '';
    Color color = Colors.red;
    if (estaMarcado) {
      await _db.eliminarEnvioHoy(plotName);
      if (mounted) setState(() { _seleccionadosCptHoy.remove(plotName); _enviosSesion.removeWhere((e) => e['plot'] == plotName); _mostrarResultado = false; });
    } else {
      final result = await _db.registrarEnvio(plotName, widget.proyecto, 'CPT');
      if (result['status'] == 'OK') {
        msg = 'Sample: ${plot['sample'] ?? '-'}\nAccesión: ${result['accession_name']}\nBloque: ${result['block_number']}\nPlot N°: ${result['plot_number']}\n¡Registro exitoso!';
        color = Colors.green;
        if (mounted) setState(() { _seleccionadosCptHoy.add(plotName); _enviosSesion.add({'plot': plotName, 'msg': 'Samp: ${plot['sample'] ?? '-'} | Acc: ${result['accession_name']} | Blq: ${result['block_number']}'}); });
        HapticFeedback.mediumImpact();
      } else if (result['status'] == 'BLOQUE_FUTURO') { msg = result['mensaje'] ?? 'Error al registrar.'; color = Colors.orange; HapticFeedback.heavyImpact(); }
      else { msg = 'Plot enviado'; color = Colors.red; HapticFeedback.heavyImpact(); }
    }
    if (mounted) setState(() { _ultimoPlot = plotName; _ultimoMsg = msg; _ultimoColor = color; _mostrarResultado = (msg.isNotEmpty); });
  }

  Future<void> _procesarManualCPT(String input) async {
    final inputNum = int.tryParse(input);
    final plot = _plotsCpt.firstWhere((p) => inputNum != null ? (int.tryParse(p['plot_number'] as String) == inputNum) : (p['plot_number'] == input), orElse: () => <String, dynamic>{});
    if (plot.isEmpty) { setState(() { _ultimoPlot = input; _ultimoMsg = 'Plot N° $input no encontrado en el bloque actual de CPT'; _ultimoColor = Colors.red; _mostrarResultado = true; }); HapticFeedback.heavyImpact(); return; }
    await _toggleSeleccionCpt(plot);
  }

  void _mostrarIngresoManualCPT() {
    final controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Registrar Panel Consumidor (CPT)'), content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Plot Number (ej: 1)', border: OutlineInputBorder(), isDense: true), onSubmitted: (v) { Navigator.pop(ctx); if (v.trim().isNotEmpty) _procesarManualCPT(v.trim()); }), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), FilledButton(onPressed: () { Navigator.pop(ctx); if (controller.text.trim().isNotEmpty) _procesarManualCPT(controller.text.trim()); }, child: const Text('Aceptar'))]));
  }

  Widget _buildCptUI() {
    if (_cargandoPlotsCpt) return const Center(child: CircularProgressIndicator());
    if (_errorCpt != null) return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(_errorCpt!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))));
    if (_plotsCpt.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No hay plots para el bloque actual en CPT.\nAsegúrate de haber cargado el CSV correctamente.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))));
    return Column(
      children: [
        if (_mostrarResultado) _buildResultado(),
        Expanded(child: ListView.builder(padding: const EdgeInsets.only(top: 8, bottom: 80), itemCount: _plotsCpt.length, itemBuilder: (context, index) {
          final plot = _plotsCpt[index]; final plotName = plot['plot_name'] as String; final estaMarcado = _seleccionadosCptHoy.contains(plotName); final sample = plot['sample'] as String? ?? '-'; final pais = plot['pais'] as String? ?? '-';
          return Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: estaMarcado ? Colors.deepPurple.withOpacity(0.1) : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: estaMarcado ? Colors.deepPurple : Colors.grey.shade300)), child: CheckboxListTile(controlAffinity: ListTileControlAffinity.leading, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), title: Text(sample, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 16)), subtitle: Text('${plot['accession_name']}\nPaís: $pais | Blq: ${plot['block_number']}\n${plot['plot_name']}', style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey[700])), value: estaMarcado, activeColor: Colors.deepPurple, onChanged: (bool? value) => _toggleSeleccionCpt(plot)));
        })),
      ],
    );
  }

  // ==========================================
  // DESMARCAR IPT
  // ==========================================
  Future<void> _cargarEnviosIptHoy() async {
    setState(() => _cargandoIptHoy = true);
    try {
      final db = await _db.database;
      final now = DateTime.now();
      final hoy = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final results = await db.query('envios', where: 'project_name = ? AND experiment_type = ? AND fecha_envio = ?', whereArgs: [widget.proyecto, 'IPT', hoy], orderBy: 'fecha_hora DESC');
      if (mounted) setState(() { _enviosIptHoy = results; _cargandoIptHoy = false; });
    } catch (e) { if (mounted) setState(() => _cargandoIptHoy = false); }
  }

  Future<void> _desmarcarIpt(String plotName) async {
    await _db.eliminarEnvioHoy(plotName);
    if (mounted) setState(() { _enviosSesion.removeWhere((e) => e['plot'] == plotName); });
    await _cargarEnviosIptHoy();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Desmarcado: ${plotName.split('_').last}'), backgroundColor: Colors.orange, duration: const Duration(seconds: 2)));
  }

  // ==========================================
  // WIDGET RICO PARA INT
  // ==========================================
  Widget _buildIntResultado() {
    final r = _resultadoINT!;
    final String listaInt = (r['lista_int'] as String?) ?? '';
    final String listaIpt = (r['lista_ipt'] as String?) ?? '';
    final String listaSet = (r['lista_set'] as String?) ?? '';
    final String listaCpt = (r['lista_cpt'] as String?) ?? '';
    final bool enviadoIpt = r['enviado_ipt'] as bool;
    final bool enviadoSet = r['enviado_set'] as bool;
    final bool enviadoCpt = r['enviado_cpt'] as bool;
    final bool tieneCpt = r['tiene_cpt'] as bool;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('INT (Campo)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12)), const SizedBox(height: 4), Text('Plots: $listaInt', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 15)), Text('Accesión: ${r['accession_name']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.black54))])),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('IPT (Blq ${r['bloque_ipt']})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12)), const SizedBox(height: 4), if (listaIpt.isEmpty) const Text('Sin plot en este bloque', style: TextStyle(fontSize: 12, color: Colors.grey)) else Row(children: [Text('Plot: $listaIpt', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(width: 8), Icon(enviadoIpt ? Icons.check_circle : Icons.cancel, color: enviadoIpt ? Colors.green : Colors.red, size: 18), const SizedBox(width: 4), Text(enviadoIpt ? 'Enviado' : 'No enviado', style: TextStyle(color: enviadoIpt ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12))])])),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('SET (Blq ${r['bloque_set']})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 12)), const SizedBox(height: 4), if (listaSet.isEmpty) const Text('Sin plot en este bloque', style: TextStyle(fontSize: 12, color: Colors.grey)) else Row(children: [Text('Plot: $listaSet', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(width: 8), Icon(enviadoSet ? Icons.check_circle : Icons.cancel, color: enviadoSet ? Colors.green : Colors.red, size: 18), const SizedBox(width: 4), Text(enviadoSet ? 'Enviado' : 'No enviado', style: TextStyle(color: enviadoSet ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12))])])),
          if (tieneCpt) ...[const SizedBox(height: 8), Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.08), borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('CPT (Blq ${r['bloque_cpt']})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 12)), const SizedBox(height: 4), if (listaCpt.isEmpty) const Text('Sin plot en este bloque', style: TextStyle(fontSize: 12, color: Colors.grey)) else Row(children: [Text('Plot: $listaCpt', style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)), const SizedBox(width: 8), Icon(enviadoCpt ? Icons.check_circle : Icons.cancel, color: enviadoCpt ? Colors.green : Colors.red, size: 18), const SizedBox(width: 4), Text(enviadoCpt ? 'Enviado' : 'No enviado', style: TextStyle(color: enviadoCpt ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12))])]))],
        ],
      ),
    );
  }

  // ==========================================
  // CONSTRUIR LISTA INFERIOR
  // ==========================================
  List<Widget> _buildListaInferior() {
    final widgets = <Widget>[];
    for (var e in _enviosSesion) {
      widgets.add(ListTile(dense: true, title: Text(e['plot'], style: const TextStyle(fontFamily: 'monospace', fontSize: 12)), subtitle: Text(e['msg'], style: const TextStyle(fontSize: 11))));
    }
    if (widget.tipo == 'IPT') {
      if (_enviosSesion.isNotEmpty) widgets.add(const Divider(height: 1));
      widgets.add(Container(color: Colors.orange.shade50, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(children: [const Icon(Icons.undo, size: 16, color: Colors.orange), const SizedBox(width: 6), Expanded(child: Text('Enviados hoy (${_enviosIptHoy.length}) — toque × para desmarcar', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange))), if (_cargandoIptHoy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))])));
      if (_enviosIptHoy.isEmpty && _enviosSesion.isNotEmpty) {
        widgets.add(const Padding(padding: EdgeInsets.all(12), child: Text('Sin envíos pendientes', style: TextStyle(fontSize: 12, color: Colors.grey))));
      } else {
        for (var e in _enviosIptHoy) {
          widgets.add(ListTile(dense: true, leading: const Icon(Icons.check_circle, color: Colors.green, size: 18), title: Text(e['plot_number'] as String, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 13)), subtitle: Text('${e['accession_name']} | Blq: ${e['block_number']}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey)), trailing: IconButton(icon: const Icon(Icons.close, color: Colors.red, size: 18), onPressed: () => _desmarcarIpt(e['plot_name'] as String), tooltip: 'Desmarcar')));
        }
      }
    }
    return widgets;
  }

  // ==========================================
  // LÓGICA PARA CÁMARA
  // ==========================================
  void _mostrarDialogoPermiso() {
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Permiso Requerido'), content: const Text('Habilita la cámara.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), FilledButton(onPressed: () { Navigator.pop(ctx); openAppSettings(); }, child: const Text('Ir a Configuración'))]));
  }

  Widget _buildCamara() {
    if (!_permisoConcedido) {
      return Container(height: MediaQuery.of(context).size.height * 0.4, color: Colors.black87, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.camera_alt, size: 60, color: Colors.white54), const SizedBox(height: 16), ElevatedButton(onPressed: _activarCamara, child: const Text('Dar permiso'))])));
    }
    return SizedBox(height: MediaQuery.of(context).size.height * 0.4, child: Stack(children: [ClipRRect(borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(24), bottomRight: Radius.circular(24)), child: MobileScanner(controller: _scannerController, onDetect: _onDetect, errorBuilder: (c, e, ch) => Container(color: Colors.black))), Center(child: Container(width: 220, height: 220, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(16)), child: const Center(child: Icon(Icons.qr_code_2, size: 60, color: Colors.white54)))), if (_procesando) Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator(color: Colors.white)))]));
  }

  Widget _buildResultado() {
    if (_ultimoMsg == null || _ultimoColor == null) return const SizedBox.shrink();
    return Container(color: _ultimoColor!.withOpacity(0.1), padding: const EdgeInsets.all(12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(_ultimoColor == Colors.green ? Icons.check_circle : _ultimoColor == Colors.red ? Icons.block : Icons.info, color: _ultimoColor, size: 32), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_ultimoPlot ?? '', style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text(_ultimoMsg!, style: TextStyle(fontSize: 12, color: Colors.grey[700]))]))]));
  }

  @override
  Widget build(BuildContext context) {
    final bool esPantallaLista = widget.tipo == 'SET' || widget.tipo == 'CPT';

    return Scaffold(
      appBar: AppBar(
        title: Text(_titulo),
        actions: [
          if (!esPantallaLista && _usandoCamara)
            IconButton(
              icon: const Icon(Icons.keyboard),
              tooltip: 'Modo Láser / Teclado',
              onPressed: () {
                _scannerController.stop();
                setState(() => _usandoCamara = false);
                _laserFocusNode.requestFocus();
              },
            )
          else if (esPantallaLista)
            IconButton(icon: const Icon(Icons.numbers), tooltip: 'Ingreso por número', onPressed: widget.tipo == 'SET' ? _mostrarIngresoManualSET : _mostrarIngresoManualCPT)
          else
            IconButton(
              icon: widget.tipo == 'INT' ? const Icon(Icons.search) : const Icon(Icons.edit),
              tooltip: 'Búsqueda avanzada (INT)',
              onPressed: _mostrarIngresoManual,
            ),
        ],
      ),
      body: esPantallaLista
          ? (widget.tipo == 'SET' ? _buildSetUI() : _buildCptUI())
          : _usandoCamara
              ? Column(children: [
                  _buildCamara(),
                  const Divider(height: 1),
                  if (_mostrarResultado && widget.tipo == 'INT' && _resultadoINT != null) _buildIntResultado()
                  else if (_mostrarResultado) _buildResultado(),
                  Expanded(child: Column(children: [Padding(padding: const EdgeInsets.all(12), child: Row(children: [const Text('Registros esta sesión', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), Text('${_enviosSesion.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))])), const Divider(height: 1), Expanded(child: _enviosSesion.isEmpty ? const Center(child: Text('Apunta la cámara al QR\no usa el modo Láser', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))) : ListView(children: _buildListaInferior()))]))
                ])
              : _buildLaserUI(),
    );
  }

  // ==========================================
  // PROCESAMIENTO POR CÁMARA
  // ==========================================
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_procesando) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final valor = barcodes.first.rawValue;
    if (valor == null || valor.trim().isEmpty) return;
    await _procesarEscaneo(valor.trim());
  }

  Future<void> _procesarEscaneo(String plotName) async {
    if (_procesando) return;
    setState(() => _procesando = true);

    if (_usandoCamara) {
      await _scannerController.stop();
    }

    String msg = '';
    Color color = Colors.red;
    bool exito = false;

    if (widget.tipo == 'INT') {
      final res = await _db.consultarCampo(plotName, widget.proyecto);
      if (res['status'] == 'NO_ENCONTRADO' || res['status'] == 'TIPO_INCORRECTO') {
        msg = res['mensaje'] ?? 'Plot no encontrado.';
        _resultadoINT = null;
      } else {
        _resultadoINT = res;
        final acc = res['accession_name'];
        final ipt = res['enviado_ipt'] ? 'Sí (Blq ${res['bloque_ipt']})' : 'No';
        final set = res['enviado_set'] ? 'Sí (Blq ${res['bloque_set']})' : 'No';
        String mensajeCompleto = 'Accesión: $acc\nPostcosecha: $ipt\nSensorial: $set';
        if (res['tiene_cpt'] == true) { final cpt = res['enviado_cpt'] ? 'Sí (Blq ${res['bloque_cpt']})' : 'No'; mensajeCompleto += '\nPanel Consumidor: $cpt'; }
        msg = mensajeCompleto;
        final algoEnviado = res['enviado_ipt'] || res['enviado_set'];
        final cptEnviado = res['tiene_cpt'] == true && res['enviado_cpt'] == true;
        color = (algoEnviado || cptEnviado) ? Colors.orange : Colors.green;
      }
    } else {
      final result = await _db.registrarEnvio(plotName, widget.proyecto, widget.tipo);
      switch (result['status']) {
        case 'NO_ENCONTRADO': msg = 'Plot no existe.'; break;
        case 'TIPO_INCORRECTO': msg = result['mensaje']; break;
        case 'BLOQUE_FUTURO': msg = result['mensaje']; break;
        case 'PLOT_DUPLICADO_HOY': msg = 'ESTE PLOT específico ya fue escaneado hoy.'; break;
        case 'BLOQUEADO_SEMANA_PASSADA': msg = 'BLOQUEADO. Ya se registró este genotipo/bloque en un día anterior.'; break;
        case 'OK':
          msg = 'Accesión: ${result['accession_name']}\nBloque: ${result['block_number']}\nPlot N°: ${result['plot_number']}\n¡Registro exitoso!';
          color = Colors.green;
          exito = true;
          if (widget.tipo == 'IPT') _cargarEnviosIptHoy();
          break;
      }
    }

    if (mounted) {
      setState(() {
        _ultimoPlot = plotName;
        _ultimoMsg = msg;
        _ultimoColor = color;
        _mostrarResultado = true;
        _procesando = false;
        if (exito) _enviosSesion.add({'plot': plotName, 'msg': msg});
      });
      HapticFeedback.mediumImpact();

      if (_usandoCamara) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _scannerController.start();
        });
      }
    }
  }

  // ==========================================
  // INGRESO MANUAL (INT)
  // ==========================================
  void _mostrarIngresoManual() {
    final controller = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Consultar Planta'), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Números -> Plot Number\nLetras -> Accesion Name', style: TextStyle(fontSize: 13)), const SizedBox(height: 8), TextField(controller: controller, autofocus: true, decoration: const InputDecoration(hintText: 'Ej: 1 ó GEN-01', border: OutlineInputBorder(), isDense: true), onSubmitted: (v) { Navigator.pop(ctx); if (v.trim().isNotEmpty) _procesarManual(v.trim()); })]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), FilledButton(onPressed: () { Navigator.pop(ctx); if (controller.text.trim().isNotEmpty) _procesarManual(controller.text.trim()); }, child: const Text('Aceptar'))]));
  }

  Future<void> _procesarManual(String input) async {
    if (widget.tipo == 'INT') {
      final esNumero = int.tryParse(input) != null;
      Map<String, dynamic>? plot;
      if (esNumero) { plot = await _db.buscarPlotPorNumero(widget.proyecto, 'INT', input); } else { final resultados = await _db.buscarPorAccession(widget.proyecto, input); plot = resultados.isEmpty ? null : resultados.first; }
      if (plot == null) { setState(() { _ultimoPlot = input; _ultimoMsg = 'No encontrado en el libro de Campo (INT).'; _ultimoColor = Colors.red; _mostrarResultado = true; _resultadoINT = null; }); HapticFeedback.heavyImpact(); return; }
      await _procesarEscaneo(plot['plot_name']);
    } else {
      var plot = await _db.buscarPlot(input);
      if (plot == null) plot = await _db.buscarPlotPorNumero(widget.proyecto, widget.tipo, input);
      if (plot == null) { setState(() { _ultimoPlot = input; _ultimoMsg = 'Plot no encontrado.'; _ultimoColor = Colors.red; _mostrarResultado = true; }); HapticFeedback.heavyImpact(); return; }
      await _procesarEscaneo(plot['plot_name']);
    }
  }
}