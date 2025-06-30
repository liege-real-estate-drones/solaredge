// lib/utils/file_logger.dart
// Version avec le getter isInitialized

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

/// Classe utilitaire pour écrire des logs dans un fichier.
/// Utilise un singleton pour partager la même instance de fichier.
class FileLogger {
  static final FileLogger _instance = FileLogger._internal();
  factory FileLogger() => _instance;
  FileLogger._internal();

  static const String _logFileName = 'background_log.txt';
  File? _logFile;
  bool _isInitializing = false;
  bool _isInitialized = false; // <- AJOUT: Flag pour suivre l'état

  // <- AJOUT: Getter public pour le flag
  bool get isInitialized => _isInitialized;

  /// Initialise le fichier de log. Doit être appelé avant d'écrire des logs.
  Future<void> initialize() async {
    // Évite les initialisations multiples concurrentes
    if (_isInitialized || _isInitializing) {
      // <- MODIFIÉ: Vérifie _isInitialized aussi
      return;
    }
    _isInitializing = true;
    _isInitialized = false; // <- Réinitialiser en début d'init

    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/$_logFileName';
      _logFile = File(path);

      // Crée le fichier s'il n'existe pas
      if (!await _logFile!.exists()) {
        await _logFile!.create(recursive: true);
      }
      // Écrire le message initial après avoir confirmé que le fichier existe/est créé
      // Utiliser directement writeAsString ici pour éviter boucle infinie potentielle avec log()
      final timestamp =
          DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
      await _logFile!.writeAsString(
          '$timestamp - INFO: --- Log Initialized ---\n',
          mode: FileMode.append,
          flush: true);

      _isInitialized = true; // <- Mettre à true APRES succès
      print('FileLogger Initialized: Log file at $path');
    } catch (e) {
      print('FileLogger Error Initializing: $e');
      _logFile = null;
      _isInitialized = false; // <- Assurer false en cas d'erreur
    } finally {
      _isInitializing = false;
    }
  }

  /// Écrit un message dans le fichier de log avec un timestamp.
  Future<void> log(String message, {required StackTrace stackTrace}) async {
    // Attend la fin de l'initialisation si elle est en cours
    while (_isInitializing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (!_isInitialized) {
      // <- Vérifie _isInitialized
      print(
          'FileLogger Error: Logger not initialized. Attempting to re-initialize...');
      // Tenter une réinitialisation AU CAS OÙ l'initialisation initiale aurait échoué silencieusement
      await initialize();
      // Si toujours pas initialisé après la tentative, log dans la console et abandonne
      if (!_isInitialized) {
        print(
            'FileLogger Error: Re-initialization failed. Cannot log message: $message');
        return;
      }
    }
    // À ce point, _logFile ne devrait pas être null si _isInitialized est true
    if (_logFile == null) {
      print(
          'FileLogger Error: _logFile is null despite logger being initialized. Cannot log message: $message');
      return;
    }

    try {
      final timestamp =
          DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(DateTime.now());
      // Simplification du formatage de la stack trace (prendre juste quelques lignes)
      final stackTraceLines = stackTrace.toString().split('\n');
      final shortStackTrace =
          stackTraceLines.take(5).join('\n'); // Prend les 5 premières lignes

      // Ajouter le message et la stack trace courte
      final logEntry =
          '$timestamp - $message\nStackTrace (short):\n$shortStackTrace\n---\n';

      await _logFile!
          .writeAsString(logEntry, mode: FileMode.append, flush: true);
    } catch (e) {
      // Log l'erreur d'écriture elle-même dans la console
      print('FileLogger Error Writing Log Entry: $e');
    }
  }

  /// Lit le contenu complet du fichier de log.
  Future<String?> readLog() async {
    while (_isInitializing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (!_isInitialized) {
      print('FileLogger Error: Logger not initialized for reading.');
      await initialize(); // Tentative d'initialisation
      if (!_isInitialized) return 'Logger could not be initialized.';
    }
    if (_logFile == null) {
      print(
          'FileLogger Error: _logFile is null despite logger being initialized. Cannot read log.');
      return 'Logger file is null.';
    }

    try {
      if (await _logFile!.exists()) {
        return await _logFile!.readAsString();
      } else {
        return 'Log file does not exist yet.';
      }
    } catch (e) {
      print('FileLogger Error Reading: $e');
      return 'Error reading log file: $e';
    }
  }

  /// Efface le contenu du fichier de log.
  Future<void> clearLog() async {
    while (_isInitializing) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (!_isInitialized) {
      print('FileLogger Error: Logger not initialized for clearing.');
      await initialize(); // Tentative d'initialisation
      if (!_isInitialized) return;
    }
    if (_logFile == null) {
      print(
          'FileLogger Error: _logFile is null despite logger being initialized. Cannot clear log.');
      return;
    }

    try {
      if (await _logFile!.exists()) {
        await _logFile!.writeAsString(''); // Écrase avec une chaîne vide
        print('FileLogger: Log cleared.');
        // Log l'action de nettoyage
        await log('INFO: --- Log Cleared ---', stackTrace: StackTrace.current);
      }
    } catch (e) {
      print('FileLogger Error Clearing: $e');
      // Essayer de logger l'erreur de nettoyage elle-même
      try {
        await log('ERROR: Failed to clear log file: $e',
            stackTrace: StackTrace.current);
      } catch (_) {} // Ignore si même le log de l'erreur échoue
    }
  }
}

// Fonction globale pour un accès facile (optionnel mais pratique)
final fileLogger = FileLogger();
