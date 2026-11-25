import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'database_helper.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  final db = DatabaseHelper();
  await db.database;
  
  // Borrar envíos de días anteriores al abrir la app para que el conteo sea solo del día actual
  await db.limpiarEnviosPasados();
  
  runApp(const CampoTrackerApp());
}

class CampoTrackerApp extends StatelessWidget {
  const CampoTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Postcosecha Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}