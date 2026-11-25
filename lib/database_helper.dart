import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'campo_tracker_v2.db');
    return await openDatabase(path, version: 2, onCreate: _onCreate, onUpgrade: _onUpgrade);
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''CREATE TABLE plots (
        id INTEGER PRIMARY KEY AUTOINCREMENT, project_name TEXT NOT NULL, experiment_type TEXT NOT NULL,
        plot_name TEXT NOT NULL, plot_number TEXT NOT NULL, accession_name TEXT NOT NULL,
        block_number INTEGER, pais TEXT, sample TEXT, UNIQUE(plot_name))''');
    await db.execute('''CREATE TABLE envios (
        id INTEGER PRIMARY KEY AUTOINCREMENT, project_name TEXT NOT NULL, experiment_type TEXT NOT NULL,
        plot_name TEXT NOT NULL, plot_number TEXT NOT NULL, accession_name TEXT NOT NULL,
        block_number INTEGER NOT NULL, fecha_envio TEXT NOT NULL, fecha_hora TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE bloques_estado (
        project_name TEXT NOT NULL, experiment_type TEXT NOT NULL, current_block INTEGER DEFAULT 1,
        PRIMARY KEY (project_name, experiment_type))''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE plots ADD COLUMN pais TEXT');
      await db.execute('ALTER TABLE plots ADD COLUMN sample TEXT');
    }
  }

  String _fechaHoy() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> limpiarEnviosPasados() async {
    final db = await database;
    await db.delete('envios', where: 'fecha_envio < ?', whereArgs: [_fechaHoy()]);
  }

  static Map<String, dynamic> parsePlotName(String plotName) {
    final parts = plotName.split('_');
    final plotNumber = parts.length > 1 ? parts.last : '';
    final baseName = parts.first;
    final baseParts = baseName.split('-');
    String projectName = '';
    String expType = 'UNKNOWN';
    for (int i = baseParts.length - 1; i >= 0; i--) {
      final part = baseParts[i].toUpperCase();
      if (part.startsWith('IPT') || part.startsWith('INT') || part.startsWith('SET') || part.startsWith('CPT')) {
        expType = part.substring(0, 3);
        projectName = baseParts.sublist(0, i).join('-');
        break;
      }
    }
    if (projectName.isEmpty && baseParts.length > 1) {
      projectName = baseParts.sublist(0, baseParts.length - 1).join('-');
    }
    return {'project_name': projectName, 'experiment_type': expType, 'plot_number': plotNumber};
  }

  Future<void> insertarPlots(List<Map<String, dynamic>> plots) async {
    final db = await database;
    final batch = db.batch();
    for (var plot in plots) {
      batch.insert('plots', plot, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<Map<String, dynamic>?> buscarPlot(String plotName) async {
    final db = await database;
    final results = await db.query('plots', where: 'plot_name = ?', whereArgs: [plotName], limit: 1);
    return results.isEmpty ? null : results.first;
  }

  Future<Map<String, dynamic>?> buscarPlotPorNumero(String project, String expType, String plotNumber) async {
    final db = await database;
    final numero = int.tryParse(plotNumber);
    List<Map<String, dynamic>> results;
    if (numero != null) {
      results = await db.query('plots',
          where: 'project_name = ? AND experiment_type = ? AND CAST(plot_number AS INTEGER) = ?',
          whereArgs: [project, expType, numero],
          limit: 1);
    } else {
      results = await db.query('plots',
          where: 'project_name = ? AND experiment_type = ? AND plot_number = ?',
          whereArgs: [project, expType, plotNumber],
          limit: 1);
    }
    return results.isEmpty ? null : results.first;
  }

  Future<List<Map<String, dynamic>>> buscarPorAccession(String project, String accession) async {
    final db = await database;
    return await db.query('plots',
        where: 'project_name = ? AND experiment_type = ? AND accession_name LIKE ?',
        whereArgs: [project, 'INT', '%$accession%']);
  }

  Future<List<Map<String, dynamic>>> obtenerPlotsBloque(String project, String expType, int block) async {
    final db = await database;
    final results = await db.query('plots',
        where: 'project_name = ? AND experiment_type = ? AND block_number = ?',
        whereArgs: [project, expType, block]);
    final mutableResults = List<Map<String, dynamic>>.from(results);
    mutableResults.sort((a, b) =>
        (int.tryParse(a['plot_number'] as String) ?? 0)
            .compareTo(int.tryParse(b['plot_number'] as String) ?? 0));
    return mutableResults;
  }

  Future<List<String>> obtenerProyectos() async {
    final db = await database;
    final results = await db.rawQuery('SELECT DISTINCT project_name FROM plots ORDER BY project_name');
    return results.map((r) => r['project_name'] as String).toList();
  }

  Future<int> contarPlotsProyecto(String project) async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM plots WHERE project_name = ?', [project]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<bool> proyectoTieneCPT(String project) async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM plots WHERE project_name = ? AND experiment_type = ?', [project, 'CPT']);
    return Sqflite.firstIntValue(result)! > 0;
  }

  Future<bool> proyectoTieneTipo(String project, String expType) async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) FROM plots WHERE project_name = ? AND experiment_type = ?', [project, expType]);
    return Sqflite.firstIntValue(result)! > 0;
  }

  Future<int> getBloqueActual(String project, String expType) async {
    final db = await database;
    
    // YA NO LEEMOS DE FIREBASE AQUÍ para ahorrar lecturas.
    // Solo leemos la base de datos local del celular.
    
    final result = await db.query('bloques_estado', 
        where: 'project_name = ? AND experiment_type = ?', 
        whereArgs: [project, expType]);
    if (result.isNotEmpty) return result.first['current_block'] as int;
    
    // Si no existe, lo creamos en 1
    await db.insert('bloques_estado', {
      'project_name': project,
      'experiment_type': expType,
      'current_block': 1,
    });
    return 1;
  }
  // Método para sincronizar desde la nube SOLO cuando se llama explícitamente
  Future<void> sincronizarBloquesDesdeNube(String project, String expType) async {
    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final docId = '${project}_$expType';
      final doc = await firestore.collection('bloques_estado').doc(docId).get(const GetOptions(source: Source.server));
      
      if (doc.exists && doc.data() != null) {
        final bloqueNube = doc.data()!['current_block'];
        if (bloqueNube != null) {
          final db = await database;
          await db.execute(
            'INSERT INTO bloques_estado (project_name, experiment_type, current_block) VALUES (?, ?, ?) '
            'ON CONFLICT(project_name, experiment_type) DO UPDATE SET current_block = excluded.current_block',
            [project, expType, bloqueNube],
          );
        }
      }
    } catch (e) {
      // Si no hay internet, simplemente no hace nada y usa el dato local
    }
  }
  
  Future<void> _cambiarBloque(String project, String expType, int delta) async {
    final db = await database;
    final actual = await getBloqueActual(project, expType);
    final nuevoBloque = actual + delta;
    if (nuevoBloque < 1) throw Exception('No se puede retroceder del bloque 1');
    await db.execute(
      'INSERT INTO bloques_estado (project_name, experiment_type, current_block) VALUES (?, ?, ?) '
      'ON CONFLICT(project_name, experiment_type) DO UPDATE SET current_block = excluded.current_block',
      [project, expType, nuevoBloque],
    );
    // Sincronizar a Firestore para que los demás usuarios lo reciban
    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      await firestore.collection('bloques_estado').doc('${project}_$expType').set({
        'current_block': nuevoBloque,
        'updated_at': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Sin internet, se queda solo local
    }
  }

  Future<void> avanzarBloque(String project, String expType) => _cambiarBloque(project, expType, 1);
  Future<void> retrocederBloque(String project, String expType) => _cambiarBloque(project, expType, -1);

  Future<Map<String, dynamic>> registrarEnvio(String plotName, String projectName, String expectedType) async {
    final plot = await buscarPlot(plotName);
    if (plot == null) return {'status': 'NO_ENCONTRADO'};
    if (plot['experiment_type'] != expectedType) {
      return {
        'status': 'TIPO_INCORRECTO',
        'mensaje': 'Este plot pertenece a ${plot['experiment_type']}, no a $expectedType.',
      };
    }
    final bloqueActual = await getBloqueActual(projectName, expectedType);
    final bloquePlot = plot['block_number'] as int;
    if (bloquePlot != bloqueActual) {
      return {
        'status': 'BLOQUE_FUTURO',
        'mensaje': 'Estás en el bloque $bloqueActual, pero este plot es del bloque $bloquePlot.\nAvanza el bloque para poder registrarlo.',
      };
    }
    final accession = plot['accession_name'] as String;
    final today = _fechaHoy();
    final duploHoy = await (await database).rawQuery(
      'SELECT COUNT(*) FROM envios WHERE plot_name = ? AND fecha_envio = ?',
      [plotName, today],
    );
    if (Sqflite.firstIntValue(duploHoy)! > 0) return {'status': 'PLOT_DUPLICADO_HOY'};
    final enviadoAntes = await (await database).rawQuery(
      'SELECT COUNT(*) FROM envios WHERE project_name = ? AND experiment_type = ? AND accession_name = ? AND block_number = ? AND fecha_envio < ?',
      [projectName, expectedType, accession, bloqueActual, today],
    );
    if (Sqflite.firstIntValue(enviadoAntes)! > 0) return {'status': 'BLOQUEADO_SEMANA_PASSADA'};
    await (await database).insert('envios', {
      'project_name': projectName,
      'experiment_type': expectedType,
      'plot_name': plotName,
      'plot_number': plot['plot_number'],
      'accession_name': accession,
      'block_number': bloquePlot,
      'fecha_envio': today,
      'fecha_hora': DateTime.now().toIso8601String(),
    });
    return {
      'status': 'OK',
      'accession_name': accession,
      'block_number': bloquePlot,
      'plot_number': plot['plot_number'],
    };
  }

  Future<Map<String, dynamic>> consultarCampo(String plotName, String projectName) async {
    final plot = await buscarPlot(plotName);
    if (plot == null) return {'status': 'NO_ENCONTRADO'};
    if (plot['experiment_type'] != 'INT') {
      return {'status': 'TIPO_INCORRECTO', 'mensaje': 'Este plot no es del libro de Campo (INT).'};
    }
    final accession = plot['accession_name'] as String;
    final bloqueIpt = await getBloqueActual(projectName, 'IPT');
    final bloqueSet = await getBloqueActual(projectName, 'SET');
    final bloqueCpt = await getBloqueActual(projectName, 'CPT');
    final tieneCpt = await proyectoTieneCPT(projectName);
    final db = await database;
    final hoy = _fechaHoy();

    final resIptCount = await db.rawQuery(
      'SELECT COUNT(*) FROM envios WHERE project_name = ? AND experiment_type = ? AND accession_name = ? AND block_number = ? AND fecha_envio = ?',
      [projectName, 'IPT', accession, bloqueIpt, hoy],
    );
    final resSetCount = await db.rawQuery(
      'SELECT COUNT(*) FROM envios WHERE project_name = ? AND experiment_type = ? AND accession_name = ? AND block_number = ? AND fecha_envio = ?',
      [projectName, 'SET', accession, bloqueSet, hoy],
    );

    bool enviadoIpt = Sqflite.firstIntValue(resIptCount)! > 0;
    bool enviadoSet = Sqflite.firstIntValue(resSetCount)! > 0;
    bool enviadoCpt = false;

    final resIptPlots = await db.rawQuery(
      'SELECT group_concat(plot_number) as plots FROM plots WHERE project_name = ? AND experiment_type = ? AND accession_name = ? AND block_number = ?',
      [projectName, 'IPT', accession, bloqueIpt],
    );
    final resSetPlots = await db.rawQuery(
      'SELECT group_concat(plot_number) as plots FROM plots WHERE project_name = ? AND experiment_type = ? AND accession_name = ? AND block_number = ?',
      [projectName, 'SET', accession, bloqueSet],
    );
    final resIntPlots = await db.rawQuery(
      'SELECT group_concat(plot_number) as plots FROM plots WHERE project_name = ? AND experiment_type = ? AND accession_name = ? ORDER BY CAST(plot_number AS INTEGER)',
      [projectName, 'INT', accession],
    );

    String listaIpt = (resIptPlots.isNotEmpty && resIptPlots.first['plots'] != null)
        ? resIptPlots.first['plots'] as String
        : '';
    String listaSet = (resSetPlots.isNotEmpty && resSetPlots.first['plots'] != null)
        ? resSetPlots.first['plots'] as String
        : '';
    String listaInt = (resIntPlots.isNotEmpty && resIntPlots.first['plots'] != null)
        ? resIntPlots.first['plots'] as String
        : '';
    String listaCpt = '';

    if (tieneCpt) {
      final resCptCount = await db.rawQuery(
        'SELECT COUNT(*) FROM envios WHERE project_name = ? AND experiment_type = ? AND accession_name = ? AND block_number = ? AND fecha_envio = ?',
        [projectName, 'CPT', accession, bloqueCpt, hoy],
      );
      enviadoCpt = Sqflite.firstIntValue(resCptCount)! > 0;
      final resCptPlots = await db.rawQuery(
        'SELECT group_concat(plot_number) as plots FROM plots WHERE project_name = ? AND experiment_type = ? AND accession_name = ? AND block_number = ?',
        [projectName, 'CPT', accession, bloqueCpt],
      );
      listaCpt = (resCptPlots.isNotEmpty && resCptPlots.first['plots'] != null)
          ? resCptPlots.first['plots'] as String
          : '';
    }

    return {
      'status': 'ENCONTRADO',
      'accession_name': accession,
      'plot_name': plotName,
      'plot_number': plot['plot_number'],
      'enviado_ipt': enviadoIpt,
      'enviado_set': enviadoSet,
      'enviado_cpt': enviadoCpt,
      'tiene_cpt': tieneCpt,
      'lista_ipt': listaIpt,
      'lista_set': listaSet,
      'lista_cpt': listaCpt,
      'lista_int': listaInt,
      'bloque_ipt': bloqueIpt,
      'bloque_set': bloqueSet,
      'bloque_cpt': bloqueCpt,
    };
  }

  Future<void> insertarEnviosHistoricos(String projectName, List<Map<String, dynamic>> envios) async {
    final db = await database;
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final fechaStr =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final allPlots = await db.query('plots', where: 'project_name = ?', whereArgs: [projectName]);
    final plotMap = {for (var p in allPlots) p['plot_name'] as String: p};
    int maxIpt = 0, maxSet = 0, maxCpt = 0;
    final batch = db.batch();
    for (var e in envios) {
      final plot = plotMap[e['plot_name']];
      if (plot != null) {
        final expType = plot['experiment_type'] as String;
        final block = e['block_number'] as int;
        if (expType == 'IPT' && block > maxIpt) maxIpt = block;
        if (expType == 'SET' && block > maxSet) maxSet = block;
        if (expType == 'CPT' && block > maxCpt) maxCpt = block;
        batch.insert('envios', {
          'project_name': projectName,
          'experiment_type': expType,
          'plot_name': e['plot_name'],
          'plot_number': e['plot_number'],
          'accession_name': e['accession_name'],
          'block_number': block,
          'fecha_envio': fechaStr,
          'fecha_hora': yesterday.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    await batch.commit(noResult: true);
    await _autoAvanzarSiMayor(projectName, 'IPT', maxIpt);
    await _autoAvanzarSiMayor(projectName, 'SET', maxSet);
    await _autoAvanzarSiMayor(projectName, 'CPT', maxCpt);
  }

  Future<void> _autoAvanzarSiMayor(String project, String expType, int maxBlock) async {
    if (maxBlock <= 0) return;
    final db = await database;
    final current = await getBloqueActual(project, expType);
    if (maxBlock > current) {
      await db.execute(
        'INSERT INTO bloques_estado (project_name, experiment_type, current_block) VALUES (?, ?, ?) '
        'ON CONFLICT(project_name, experiment_type) DO UPDATE SET current_block = excluded.current_block',
        [project, expType, maxBlock],
      );
      // Sincronizar a Firestore para que los demás usuarios reciban el bloque
      try {
        final FirebaseFirestore firestore = FirebaseFirestore.instance;
        await firestore.collection('bloques_estado').doc('${project}_$expType').set({
          'current_block': maxBlock,
          'updated_at': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Sin internet, queda solo local
      }
    }
  }

  Future<bool> fueEnviadoHoy(String plotName) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) FROM envios WHERE plot_name = ? AND fecha_envio = ?',
      [plotName, _fechaHoy()],
    );
    return Sqflite.firstIntValue(result)! > 0;
  }

  Future<void> eliminarEnvioHoy(String plotName) async {
    final db = await database;
    await db.delete('envios', where: 'plot_name = ? AND fecha_envio = ?', whereArgs: [plotName, _fechaHoy()]);
  }

  Future<String> generarCSVDia(String fecha) async {
    final db = await database;
    final envios = await db.query('envios',
        where: 'fecha_envio = ?', whereArgs: [fecha], orderBy: 'experiment_type ASC, plot_name ASC');
    final buffer = StringBuffer();
    buffer.writeln('plot_name,plot_number,accession_name,block_number,fecha,Enviado');
    for (var e in envios) {
      final partes = (e['fecha_envio'] as String).split('-');
      final fechaLatina = '${partes[2]}/${partes[1]}/${partes[0]}';
      buffer.writeln('${e['plot_name']},${e['plot_number']},${e['accession_name']},${e['block_number']},$fechaLatina,Ok');
    }
    return buffer.toString();
  }

  Future<int> contarEnviosHoy() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM envios WHERE fecha_envio = ?', [_fechaHoy()]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> limpiarTodo() async {
    final db = await database;
    await db.delete('envios');
    await db.delete('plots');
    await db.delete('bloques_estado');
  }

  List<Map<String, dynamic>> parsearCSV(String contenido) {
    final lineas = LineSplitter.split(contenido).toList();
    final plots = <Map<String, dynamic>>[];
    int lineaNum = 0;
    for (var linea in lineas) {
      lineaNum++;
      linea = linea.trim().replaceAll('\uFEFF', '');
      if (linea.isEmpty) continue;
      final separador = linea.contains(';') ? ';' : ',';
      final partes = linea.split(separador);
      if (partes[0].trim().toLowerCase().contains('plot')) continue;
      if (partes.length < 3) throw FormatException('Línea $lineaNum: Faltan columnas');
      final plotName = partes[0].trim();
      final parsed = parsePlotName(plotName);
      final String expType = parsed['experiment_type'];
      String accessionName, plotNumber;
      String? blockStr, pais, sample;
      if (expType == 'CPT' && partes.length >= 6) {
        plotNumber = partes[1].trim();
        accessionName = partes[2].trim();
        blockStr = partes[3].trim();
        pais = partes[4].trim();
        sample = partes[5].trim();
      } else {
        accessionName = partes[1].trim();
        plotNumber = partes[2].trim();
        blockStr = partes.length > 3 ? partes[3].trim() : null;
      }
      if (expType == 'UNKNOWN') {
        throw FormatException('Línea $lineaNum: No se pudo detectar el tipo en $plotName');
      }
      final plotMap = <String, dynamic>{
        'project_name': parsed['project_name'],
        'experiment_type': expType,
        'plot_name': plotName,
        'plot_number': plotNumber,
        'accession_name': accessionName,
        'block_number': blockStr != null ? int.tryParse(blockStr) : null,
      };
      if (pais != null) plotMap['pais'] = pais;
      if (sample != null) plotMap['sample'] = sample;
      plots.add(plotMap);
    }
    if (plots.isEmpty) throw FormatException('El archivo no tiene datos válidos');
    return plots;
  }
}

class LineSplitter {
  static List<String> split(String text) => text.split(RegExp(r'\r\n|\r|\n'));
}