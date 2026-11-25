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

  Future<void> bajarPlots() async {
    final snapshot = await _firestore.collection('plots').get();
    final listaPlots = <Map<String, dynamic>>[];
    for (var doc in snapshot.docs) {
      final data = doc.data();
      listaPlots.add({'project_name': data['project_name'], 'experiment_type': data['experiment_type'], 'plot_name': doc.id, 'plot_number': data['plot_number'], 'accession_name': data['accession_name'], 'block_number': data['block_number'], 'pais': data['pais'], 'sample': data['sample']});
    }
    if (listaPlots.isNotEmpty) await _db.insertarPlots(listaPlots);
  }

  Future<void> bajarEnvios() async {
    final snapshot = await _firestore.collection('envios').get();
    if (snapshot.docs.isEmpty) return;
    final db = await _db.database;
    final batchDelete = db.batch();
    for (var doc in snapshot.docs) { final data = doc.data(); batchDelete.delete('envios', where: 'plot_name = ? AND fecha_envio = ?', whereArgs: [data['plot_name'], data['fecha_envio']]); }
    await batchDelete.commit(noResult: true);
    final batchInsert = db.batch();
    for (var doc in snapshot.docs) {
      final data = doc.data();
      batchInsert.insert('envios', {'project_name': data['project_name'], 'experiment_type': data['experiment_type'], 'plot_name': data['plot_name'], 'plot_number': data['plot_number'], 'accession_name': data['accession_name'], 'block_number': data['block_number'], 'fecha_envio': data['fecha_envio'], 'fecha_hora': data['fecha_hora']});
    }
    await batchInsert.commit(noResult: true);
  }

  // NUEVO: Descargar bloques para sincronizar correctamente
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

  Future<void> sincronizarTodo({String? proyectoActual}) async {
    try {
      await _asegurarSesion();
      await subirPlots();
      await subirEnvios();
      await subirBloques();
      await bajarPlots();
      await bajarEnvios();
      await bajarBloques(); // NUEVO: Ahora sí descarga los bloques
    } catch (e) { throw Exception('Error al sincronizar: $e'); }
  }
}