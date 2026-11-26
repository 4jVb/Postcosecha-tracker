import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

class FirebaseSync {
  final _db = DatabaseHelper();
  final _firestore = FirebaseFirestore.instance;

  Future<void> _asegurarSesion() async {
    if (FirebaseAuth.instance.currentUser != null) return;
    await FirebaseAuth.instance.signInAnonymously();
  }

  Future<void> subirPlots() async {
    final db = await _db.database;
    final plotsLocales = await db.query('plots');
    if (plotsLocales.isEmpty) return;
    final int batchSize = 400;
    for (int i = 0; i < plotsLocales.length; i += batchSize) {
      final end = (i + batchSize < plotsLocales.length) ? i + batchSize : plotsLocales.length;
      final chunk = plotsLocales.sublist(i, end);
      final batch = _firestore.batch();
      for (var plot in chunk) {
        final docRef = _firestore.collection('plots').doc(plot['plot_name'] as String);
        batch.set(docRef, {'project_name': plot['project_name'], 'experiment_type': plot['experiment_type'], 'plot_number': plot['plot_number'], 'accession_name': plot['accession_name'], 'block_number': plot['block_number'], 'pais': plot['pais'], 'sample': plot['sample']}, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> subirEnvios() async {
    final db = await _db.database;
    final enviosLocales = await db.query('envios');
    if (enviosLocales.isEmpty) return;
    final int batchSize = 400;
    for (int i = 0; i < enviosLocales.length; i += batchSize) {
      final end = (i + batchSize < enviosLocales.length) ? i + batchSize : enviosLocales.length;
      final chunk = enviosLocales.sublist(i, end);
      final batch = _firestore.batch();
      for (var envio in chunk) {
        final fecha = envio['fecha_envio'] as String;
        final idUnico = '${envio['plot_name']}_$fecha';
        final docRef = _firestore.collection('envios').doc(idUnico);
        batch.set(docRef, {'project_name': envio['project_name'], 'experiment_type': envio['experiment_type'], 'plot_name': envio['plot_name'], 'plot_number': envio['plot_number'], 'accession_name': envio['accession_name'], 'block_number': envio['block_number'], 'fecha_envio': envio['fecha_envio'], 'fecha_hora': envio['fecha_hora']}, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> subirBloques() async {
    final db = await _db.database;
    final bloques = await db.query('bloques_estado');
    if (bloques.isEmpty) return;
    final batch = _firestore.batch();
    for (var bloque in bloques) {
      final docId = '${bloque['project_name']}_${bloque['experiment_type']}';
      batch.set(_firestore.collection('bloques_estado').doc(docId), {'current_block': bloque['current_block']}, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> bajarBloques() async {
    final snapshot = await _firestore.collection('bloques_estado').get();
    if (snapshot.docs.isEmpty) return;
    final db = await _db.database;
    for (var doc in snapshot.docs) {
      final partes = doc.id.split('_');
      if (partes.length == 2) {
        await db.execute(
          'INSERT INTO bloques_estado (project_name, experiment_type, current_block) VALUES (?, ?, ?) '
          'ON CONFLICT(project_name, experiment_type) DO UPDATE SET current_block = excluded.current_block',
          [partes[0], partes[1], doc.data()!['current_block']],
        );
      }
    }
  }

  // ============================================================
  // NUEVO: DESCARGA de plots desde Firestore.
  // Permite recuperar los libros de campo al instalar la app en un
  // dispositivo nuevo o después de "Formatear Todo".
  // Inserta por chunks para no saturar la RAM ni la base local.
  // ============================================================
  Future<int> bajarPlots() async {
    final snapshot = await _firestore.collection('plots').get();
    if (snapshot.docs.isEmpty) return 0;
    final db = await _db.database;
    final int chunkSize = 500;
    for (int i = 0; i < snapshot.docs.length; i += chunkSize) {
      final end = (i + chunkSize < snapshot.docs.length) ? i + chunkSize : snapshot.docs.length;
      final batch = db.batch();
      for (var doc in snapshot.docs.sublist(i, end)) {
        final d = doc.data();
        final bloque = d['block_number'];
        batch.insert('plots', {
          'project_name': (d['project_name'] ?? '').toString(),
          'experiment_type': (d['experiment_type'] ?? '').toString(),
          'plot_name': doc.id,
          'plot_number': (d['plot_number'] ?? '').toString(),
          'accession_name': (d['accession_name'] ?? '').toString(),
          'block_number': bloque is int ? bloque : int.tryParse('${bloque ?? ''}'),
          'pais': d['pais']?.toString(),
          'sample': d['sample']?.toString(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore); // plots tiene UNIQUE(plot_name)
      }
      await batch.commit(noResult: true);
    }
    return snapshot.docs.length;
  }

  // ============================================================
  // NUEVO: DESCARGA de envíos históricos desde Firestore.
  // La tabla envios NO tiene restricción UNIQUE, así que se
  // des-duplica manualmente con la clave plot_name + fecha_envio.
  // ============================================================
  Future<int> bajarEnvios() async {
    final snapshot = await _firestore.collection('envios').get();
    if (snapshot.docs.isEmpty) return 0;
    final db = await _db.database;
    // Claves ya existentes en local para no duplicar
    final existentes = await db.rawQuery('SELECT plot_name || \'_\' || fecha_envio AS clave FROM envios');
    final clavesExistentes = existentes.map((r) => r['clave'] as String).toSet();
    final int chunkSize = 500;
    int insertados = 0;
    for (int i = 0; i < snapshot.docs.length; i += chunkSize) {
      final end = (i + chunkSize < snapshot.docs.length) ? i + chunkSize : snapshot.docs.length;
      final batch = db.batch();
      for (var doc in snapshot.docs.sublist(i, end)) {
        final d = doc.data();
        final plotName = (d['plot_name'] ?? doc.id.split('_').first).toString();
        final fecha = (d['fecha_envio'] ?? '').toString();
        if (fecha.isEmpty) continue;
        final clave = '${plotName}_$fecha';
        if (clavesExistentes.contains(clave)) continue; // ya existe localmente
        clavesExistentes.add(clave);
        final bloque = d['block_number'];
        batch.insert('envios', {
          'project_name': (d['project_name'] ?? '').toString(),
          'experiment_type': (d['experiment_type'] ?? '').toString(),
          'plot_name': plotName,
          'plot_number': (d['plot_number'] ?? '').toString(),
          'accession_name': (d['accession_name'] ?? '').toString(),
          'block_number': bloque is int ? bloque : int.tryParse('${bloque ?? ''}') ?? 0,
          'fecha_envio': fecha,
          'fecha_hora': (d['fecha_hora'] ?? '').toString(),
        });
        insertados++;
      }
      await batch.commit(noResult: true);
    }
    return insertados;
  }

  // ============================================================
  // sincronizarTodo:
  //  1. Sube todo lo local (plots, envíos, bloques)
  //  2. Baja bloques (siempre: es liviano)
  //  3. Si [descargarDatos] = true, también BAJA plots y envíos
  //     de la nube (necesario en dispositivo nuevo o tras formatear).
  // ============================================================
  Future<void> sincronizarTodo({String? proyectoActual, bool descargarDatos = false}) async {
    try {
      await _asegurarSesion();
      await subirPlots();
      await subirEnvios();
      await subirBloques();
      await bajarBloques();
      if (descargarDatos) {
        await bajarPlots();
        await bajarEnvios();
      }
    } catch (e) {
      throw Exception('Error al sincronizar: $e');
    }
  }
}
