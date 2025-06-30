// lib/data/services/background_worker_service.dart
// Version RÉVISÉE et CORRIGÉE
// - Ajout d'un getter & setter public pour apiService
// - Suppression du mot‑clé `final` devant _apiService pour qu'il soit mutable
// - Quelques petits commentaires de log pour tracer la mise à jour du service
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:developer'; // log()
import 'dart:math' hide log; // évite le conflit « log » de dart:math
import 'dart:ui'; // DartPluginRegistrant

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solaredge_monitor/data/models/api_exceptions.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';
import 'package:get_it/get_it.dart';

import '../../firebase_options.dart';
import '../../utils/file_logger.dart';
import '../models/notification_model.dart';
import '../models/user_preferences.dart';
import 'notification_service.dart';
import 'service_manager.dart';
import 'solaredge_api_service.dart';
import 'auth_service.dart';
import 'user_preferences_service.dart';

// -----------------------------------------------------------------------------
//  CONSTANTES & CHANNELS
// -----------------------------------------------------------------------------
const String tag = 'BackgroundWorker';
const String lastNotifTimestampPrefix = 'last_notif_ts_';
const String dailyNotifCountPrefix = 'daily_notif_count_';
const String dailyRecapSentDateKey = 'daily_recap_sent_date';

const AndroidNotificationChannel userAlertChannel = AndroidNotificationChannel(
  'solaredge_channel_id',
  'Alertes SolarEdge',
  description: 'Notifications importantes concernant votre production solaire.',
  importance: Importance.max,
);

const AndroidNotificationChannel backgroundServiceChannel =
    AndroidNotificationChannel(
  'solaredge_background_service_channel',
  'Service Arrière‑Plan',
  description:
      'Notification indiquant que l\'application surveille en arrière‑plan.',
  importance: Importance.low,
  showBadge: false,
);

final FileLogger _backgroundLogger = FileLogger();

// -----------------------------------------------------------------------------
//  CALLBACK DISPATCHER  (tâches WorkManager)
// -----------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> callbackDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // Locale / intl dans l\'isolate BG
  Intl.defaultLocale = 'fr_FR';
  await initializeDateFormatting('fr_FR', null);

  // Initialiser le logger en premier
  final _backgroundLogger = FileLogger();
  await _backgroundLogger.initialize();
  _backgroundLogger.log('INFO $tag: callbackDispatcher started.',
      stackTrace: StackTrace.current);

  // 1. Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  _backgroundLogger.log('INFO $tag: Firebase initialized.',
      stackTrace: StackTrace.current);

  // 2. Hive – init AVANT registerAdapter/openBox
  await Hive.initFlutter();
  _backgroundLogger.log('INFO $tag: Hive initialized.',
      stackTrace: StackTrace.current);
  if (!Hive.isAdapterRegistered(NotificationModelAdapter().typeId)) {
    Hive.registerAdapter(NotificationModelAdapter());
    _backgroundLogger.log('INFO $tag: NotificationModelAdapter registered.',
        stackTrace: StackTrace.current);
  }
  if (!Hive.isAdapterRegistered(NotificationGroupAdapter().typeId)) {
    Hive.registerAdapter(NotificationGroupAdapter());
    _backgroundLogger.log('INFO $tag: NotificationGroupAdapter registered.',
        stackTrace: StackTrace.current);
  }
  await Hive.openBox<NotificationModel>('notifications');
  _backgroundLogger.log('INFO $tag: Hive box "notifications" opened.',
      stackTrace: StackTrace.current);

  // 3. Local notifications
  final fln = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await fln.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  _backgroundLogger.log('INFO $tag: Plugin local_notifications initialized.',
      stackTrace: StackTrace.current);

  final android = fln.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  // Supprimer/recréer pour être sûr
  await android?.deleteNotificationChannel('solaredge_channel_id');
  _backgroundLogger.log(
      'INFO $tag: Deleted old solaredge_channel_id if existed.',
      stackTrace: StackTrace.current);
  await android?.createNotificationChannel(userAlertChannel);
  _backgroundLogger.log('INFO $tag: Created userAlertChannel.',
      stackTrace: StackTrace.current);
  await android?.createNotificationChannel(backgroundServiceChannel);
  _backgroundLogger.log('INFO $tag: Created backgroundServiceChannel.',
      stackTrace: StackTrace.current);

  // 4. lancer Workmanager
  Workmanager().executeTask((taskName, inputData) async {
    _backgroundLogger.log('INFO $tag: Executing BG task $taskName',
        stackTrace: StackTrace.current);
    try {
      // Les initialisations Firebase et local_notifications sont faites AVANT executeTask
      // dans le callbackDispatcher.

      // Time‑zone
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Europe/Brussels'));
      _backgroundLogger.log('INFO $tag: Timezone initialized.',
          stackTrace: StackTrace.current);

      // Pré‑requis pour nos services
      final prefs = await SharedPreferences.getInstance();
      _backgroundLogger.log('INFO $tag: SharedPreferences instance obtained.',
          stackTrace: StackTrace.current);

      // Hive pour historiser les notifs - Déjà initialisé et box ouverte AVANT executeTask
      // Assurez-vous que la box est accessible si nécessaire, bien qu'elle soit ouverte globalement maintenant.
      // final notificationBox = Hive.box<NotificationModel>('notifications');
      // _backgroundLogger.log('INFO $tag: Accessed notifications Hive box.',
      //     stackTrace: StackTrace.current);

      // Récupération des pref utilisateur / clés API
      final userPrefService = UserPreferencesService();
      final authService = AuthService(userPreferencesService: userPrefService);
      String? apiKey;
      String? siteId;
      UserPreferences? userPrefs;

      final user = authService.currentUser;
      if (user != null) {
        userPrefs = await userPrefService.loadUserPreferences(user);
        apiKey = userPrefs?.solarEdgeApiKey;
        siteId = userPrefs?.siteId;
        _backgroundLogger.log(
            'INFO $tag: User preferences loaded for logged-in user.',
            stackTrace: StackTrace.current);
      } else {
        _backgroundLogger.log(
            'INFO $tag: No logged-in user, attempting to get API keys from SharedPreferences.',
            stackTrace: StackTrace.current);
      }
      apiKey ??= prefs.getString('solaredge_api_key');
      siteId ??= prefs.getString('solaredge_site_id');
      if (apiKey == null || siteId == null) {
        _backgroundLogger.log('ERROR $tag: Missing API keys – abort.',
            stackTrace: StackTrace.current);
        return Future.value(false);
      }
      userPrefs ??= UserPreferences(solarEdgeApiKey: apiKey, siteId: siteId);
      _backgroundLogger.log('INFO $tag: API Key and Site ID obtained.',
          stackTrace: StackTrace.current);

      final apiSrv = SolarEdgeApiService(apiKey: apiKey, siteId: siteId);
      // NotificationService n'a plus besoin d'être initialisé ici car Hive et le plugin sont déjà prêts
      final notifSrv = NotificationService();
      await notifSrv.initialize(null); // <- indispensable dans l'isolate

      final worker = BackgroundWorkerService(
        prefs: prefs,
        apiService: apiSrv,
        notificationService: notifSrv,
        fileLogger: _backgroundLogger,
        userPreferences: userPrefs,
      );
      _backgroundLogger.log(
          'INFO $tag: BackgroundWorkerService instance created.',
          stackTrace: StackTrace.current);

      bool success = false;
      switch (taskName) {
        case BackgroundWorkerService.powerCheckTask:
          _backgroundLogger.log('INFO $tag: Handling power check task.',
              stackTrace: StackTrace.current);
          success = await worker._handlePowerCheck();
          break;
        case BackgroundWorkerService.dailyProductionCheckTask:
          _backgroundLogger.log(
              'INFO $tag: Handling daily production check task.',
              stackTrace: StackTrace.current);
          success = await worker._handleDailyProductionCheck();
          break;
        default:
          _backgroundLogger.log('WARN $tag: Unknown task: $taskName',
              stackTrace: StackTrace.current);
          success = true; // tâche inconnue => OK pour Workmanager
      }
      _backgroundLogger.log(
          'INFO $tag: Task $taskName finished with success: $success',
          stackTrace: StackTrace.current);
      return Future.value(success);
    } catch (e, s) {
      _backgroundLogger.log(
          'ERROR $tag: Unhandled exception in executeTask for $taskName – $e',
          stackTrace: s);
      _backgroundLogger.log('ERROR $tag: Stack trace: $s',
          stackTrace: StackTrace.current); // Log stack trace
      return Future.value(false);
    } finally {
      // Hive.close() n'est plus nécessaire ici car la box est gérée globalement
      // await Hive.close();
      _backgroundLogger.log('INFO $tag: executeTask finished.',
          stackTrace: StackTrace.current);
    }
  });
}

// -----------------------------------------------------------------------------
//  CLASSE PRINCIPALE
// -----------------------------------------------------------------------------
class BackgroundWorkerService {
  // -------------------------------------------------------------------------
  //  SINGLETON
  // -------------------------------------------------------------------------
  static BackgroundWorkerService? _instance;
  factory BackgroundWorkerService({
    SharedPreferences? prefs,
    SolarEdgeApiService? apiService,
    NotificationService? notificationService,
    FileLogger? fileLogger,
    UserPreferences? userPreferences,
  }) {
    _instance ??= BackgroundWorkerService._internal(
      prefs: prefs,
      apiService: apiService,
      notificationService: notificationService,
      fileLogger: fileLogger,
      userPreferences: userPreferences,
    );
    return _instance!;
  }

  // -------------------------------------------------------------------------
  //  CHAMPS PRIVÉS   (note: _apiService N\'est plus final pour être mutable)
  // -------------------------------------------------------------------------
  final SharedPreferences? _prefs;
  SolarEdgeApiService? _apiService; // <‑‑ plus "final" !
  final NotificationService? _notificationService;
  final FileLogger _fileLogger;
  UserPreferences? _userPreferences; // <--- Retrait de 'final'

  // -------------------------------------------------------------------------
  //  CONSTRUCTEUR PRIVÉ
  // -------------------------------------------------------------------------
  BackgroundWorkerService._internal({
    SharedPreferences? prefs,
    SolarEdgeApiService? apiService,
    NotificationService? notificationService,
    FileLogger? fileLogger,
    UserPreferences? userPreferences,
  })  : _prefs = prefs,
        _apiService = apiService,
        _notificationService = notificationService,
        _fileLogger = fileLogger ?? FileLogger(),
        _userPreferences = userPreferences;

  // -------------------------------------------------------------------------
  //  GETTER / SETTER PUBLICS POUR _apiService
  // -------------------------------------------------------------------------
  SolarEdgeApiService? get apiService => _apiService;
  set apiService(SolarEdgeApiService? service) {
    _fileLogger.log(
      'DEBUG $tag: apiService updated via public setter.',
      stackTrace: StackTrace.current,
    );
    _apiService = service;
  }

  // -------------------------------------------------------------------------
  //  SETTER PUBLIC POUR _userPreferences
  // -------------------------------------------------------------------------
  set userPreferences(UserPreferences prefs) {
    _fileLogger.log(
      'DEBUG $tag: userPreferences updated via public setter.',
      stackTrace: StackTrace.current,
    );
    _userPreferences = prefs;
  }

  // -------------------------------------------------------------------------
  //  IDENTIFIANTS DE TÂCHES
  // -------------------------------------------------------------------------
  static const String powerCheckTask = 'com.solaredge.monitor.POWER_CHECK';
  static const String dailyProductionCheckTask =
      'com.solaredge.monitor.DAILY_PRODUCTION';

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // -------------------------------------------------------------------------
  //  HELPER pour générer un ID de notification valide (int32)
  // -------------------------------------------------------------------------
  int _generateNotifId() {
    // on garde la micro-unicité mais on reste dans 0 … 2^31-1
    return DateTime.now().millisecondsSinceEpoch & 0x7FFFFFFF;
  }

  // -------------------------------------------------------------------------
  //  INIT depuis le thread UI (planification)
  // -------------------------------------------------------------------------
  Future<void> init() async {
    if (!_fileLogger.isInitialized) await _fileLogger.initialize();

    await Workmanager()
        .initialize(callbackDispatcher, isInDebugMode: kDebugMode);
    await _createNotificationChannels();

    await schedulePowerCheckTask();
    await scheduleDailyProductionCheckTask();
  }

  Future<void> _createNotificationChannels() async {
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(userAlertChannel);
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(backgroundServiceChannel);
  }

  // -------------------------------------------------------------------------
  //  PLANIFICATION DES TÂCHES PERIODIQUES
  // -------------------------------------------------------------------------
  Future<void> schedulePowerCheckTask() async {
    final SharedPreferences prefsInstance =
        _prefs ?? await SharedPreferences.getInstance();
    final int frequencyMinutes =
        prefsInstance.getInt('power_check_frequency') ?? 30;
    final Duration freq = Duration(minutes: max(15, frequencyMinutes));

    await Workmanager().registerPeriodicTask(
      powerCheckTask,
      powerCheckTask,
      frequency: freq,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 10),
    );
  }

  Future<void> scheduleDailyProductionCheckTask() async {
    // ► 1. prefs à jour
    final prefsInstance = await SharedPreferences.getInstance();

    // ► 2. on annule l’ancien job périodique
    await Workmanager().cancelByUniqueName('daily_recap_job');

    // ► 3. on lit l’heure souhaitée
    final String timeStr = prefsInstance.getString('daily_summary_time') ??
        _userPreferences?.notificationSettings.dailySummaryTime ??
        '18:00';

    final parts = timeStr.split(':');
    final hour = int.tryParse(parts[0]) ?? 18;
    final minute = int.tryParse(parts[1]) ?? 0;

    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Brussels'));

    final now = tz.TZDateTime.now(tz.local);
    var first =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);

    // ► 4. si l’heure est déjà passée → one-off immédiat
    if (first.isBefore(now)) {
      await Workmanager().registerOneOffTask(
        'daily_recap_oneoff', // uniqueName
        dailyProductionCheckTask, // taskName
        initialDelay: const Duration(seconds: 5),
        constraints: Constraints(networkType: NetworkType.connected),
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 10),
      );
      first = first.add(const Duration(days: 1)); // périodique → demain
    }

    final initialDelay = first.difference(now);

    // ► 5. on (re)programme le périodique
    await Workmanager().registerPeriodicTask(
      'daily_recap_job', // uniqueName
      dailyProductionCheckTask, // taskName
      frequency: const Duration(days: 1),
      initialDelay: initialDelay, // ≤24 h → lance déjà ce soir si possible
      constraints: Constraints(networkType: NetworkType.connected),
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(hours: 1),
    );
  }

  Future<void> cancelAllTasks() async {
    await Workmanager().cancelAll();
    _fileLogger.log(
        'INFO $tag: UI All background tasks cancelled via Workmanager.',
        stackTrace: StackTrace.current);
    log('$tag: UI Annulation de toutes les tâches.');
  }

  // --- Logique d'exécution des tâches ---

  // ================================================================
  // _handlePowerCheck CORRIGÉ (appels aux helpers locaux + _notificationService.show...)
  // ================================================================
  Future<bool> _handlePowerCheck() async {
    debugPrint(
        '$tag/_handlePowerCheck: Starting power check function...'); // Added log
    if (_prefs == null || _apiService == null || _notificationService == null) {
      _fileLogger.log(
          'ERROR $tag/_handlePowerCheck: Missing dependencies (prefs, apiService, or notificationService). Cannot execute task.',
          stackTrace: StackTrace.current);
      debugPrint('$tag/_handlePowerCheck: Missing dependencies.'); // Added log
      return false;
    }
    _fileLogger.log(
        'DEBUG $tag/_handlePowerCheck: Starting power check function...',
        stackTrace: StackTrace.current);

    try {
      final bool notificationsEnabledGlobally =
          _prefs!.getBool('notifications_enabled') ?? true;
      _fileLogger.log(
          'DEBUG $tag/_handlePowerCheck: Notifications globally enabled value from prefs: $notificationsEnabledGlobally',
          stackTrace: StackTrace.current);
      if (!notificationsEnabledGlobally) {
        _fileLogger.log(
            'INFO $tag/_handlePowerCheck: Notifications globally disabled via SharedPreferences. Task successful (no action needed).',
            stackTrace: StackTrace.current);
        return true;
      }

      // Utiliser les préférences utilisateur passées au constructeur
      final UserPreferences? userPreferences = _userPreferences;
      _fileLogger.log(
          'DEBUG $tag/_handlePowerCheck: UserPreferences object from constructor: ${userPreferences != null}',
          stackTrace: StackTrace.current);

      if (userPreferences == null) {
        _fileLogger.log(
            'ERROR $tag/_handlePowerCheck: UserPreferences not available in worker instance. Cannot proceed.',
            stackTrace: StackTrace.current);
        return false; // Signaler l'échec à Workmanager
      }
      if (!userPreferences.notificationSettings.enablePowerNotifications) {
        _fileLogger.log(
            'INFO $tag/_handlePowerCheck: Power notifications disabled in UserPreferences settings. Task successful (no action needed).',
            stackTrace: StackTrace.current);
        return true;
      }

      _fileLogger.log(
          'DEBUG $tag/_handlePowerCheck: Calling _apiService.getCurrentPowerData()...',
          stackTrace: StackTrace.current);
      SolarData solarData;
      // *** CORRECTION: try/catch spécifique pour l'appel API ***
      try {
        solarData = await _apiService!.getCurrentPowerData();
        _fileLogger.log(
            'DEBUG $tag/_handlePowerCheck: API call finished. Power data received. Current Power: ${solarData.power} W',
            stackTrace: StackTrace.current);
      } on SolarEdgeApiException catch (apiError, apiStack) {
        _fileLogger.log(
            'ERROR $tag/_handlePowerCheck: API Error fetching power data: ${apiError.message} (Type: ${apiError.errorType}, Status: ${apiError.statusCode})',
            stackTrace: apiStack);
        // Indiquer à WorkManager de réessayer en cas d'erreur API
        return false;
      }
      // *** FIN CORRECTION try/catch API ***

      // Le reste de la logique s'exécute uniquement si l'appel API a réussi
      final currentPower = solarData.power;
      _fileLogger.log(
          'INFO $tag/_handlePowerCheck: Current Power = ${currentPower.toStringAsFixed(2)} W',
          stackTrace: StackTrace.current);
      _fileLogger.log(
          'DETAIL $tag/_handlePowerCheck: Valeur exacte de currentPower = ${currentPower.toStringAsFixed(2)} W',
          stackTrace: StackTrace.current); // LOG AJOUTÉ

      final criteriaList = userPreferences.notificationSettings.powerCriteria;
      _fileLogger.log(
          'DEBUG $tag/_handlePowerCheck: Evaluating ${criteriaList.length} power criteria...',
          stackTrace: StackTrace.current);
      bool notificationSentInThisRun = false;

      for (final criteria in criteriaList) {
        _fileLogger.log(
            'DEBUG $tag/_handlePowerCheck: === Evaluating criteria ID: ${criteria.id} (Enabled: ${criteria.isEnabled}) ===',
            stackTrace: StackTrace.current);
        if (!criteria.isEnabled) {
          _fileLogger.log(
              'DEBUG $tag/_handlePowerCheck: Criteria ${criteria.id} is disabled. Skipping.',
              stackTrace: StackTrace.current);
          continue;
        }
        _fileLogger.log(
            'DEBUG $tag/_handlePowerCheck: Criteria details: Type=${criteria.type}, Threshold=${criteria.threshold}${criteria.unit}, Max=${criteria.maxNotificationsPerDay}/day, Time=${criteria.startTime}-${criteria.endTime}, Days=${criteria.activeDays}',
            stackTrace: StackTrace.current);

        bool conditionMet = false;
        double currentPowerInCriteriaUnit = currentPower;
        if (criteria.unit == 'kW') {
          currentPowerInCriteriaUnit = currentPower / 1000.0;
          _fileLogger.log(
              'DEBUG $tag/_handlePowerCheck: Converted current power to kW: $currentPowerInCriteriaUnit',
              stackTrace: StackTrace.current);
        } else if (criteria.unit != 'W') {
          _fileLogger.log(
              'WARN $tag/_handlePowerCheck: Unsupported unit "${criteria.unit}" for criteria ${criteria.id}. Skipping.',
              stackTrace: StackTrace.current);
          continue;
        }

        conditionMet = (criteria.type == 'above' &&
                currentPowerInCriteriaUnit > criteria.threshold) ||
            (criteria.type == 'below' &&
                currentPowerInCriteriaUnit < criteria.threshold);

        _fileLogger.log(
            'DEBUG $tag/_handlePowerCheck: Criteria ${criteria.id} - Condition Met: $conditionMet (Current: ${currentPowerInCriteriaUnit.toStringAsFixed(2)} ${criteria.unit}, Threshold: ${criteria.threshold.toStringAsFixed(0)} ${criteria.unit})',
            stackTrace: StackTrace.current);
        _fileLogger.log(
            'DETAIL $tag/_handlePowerCheck: [Critère ${criteria.id}] Résultat du test conditionMet = $conditionMet',
            stackTrace: StackTrace.current); // LOG AJOUTÉ

        if (conditionMet) {
          _fileLogger.log(
              'DEBUG $tag/_handlePowerCheck: Condition met for criteria ${criteria.id}. Checking rules using local helper _canSendNotification...',
              stackTrace: StackTrace.current);
          // ***** APPEL CORRIGÉ: Utilise le helper local *****
          final bool canSend = await _canSendNotification(criteria);
          _fileLogger.log(
              'INFO $tag/_handlePowerCheck: Criteria ${criteria.id} - Can Send Notification check result: $canSend',
              stackTrace: StackTrace.current);
          _fileLogger.log(
              'DETAIL $tag/_handlePowerCheck: [Critère ${criteria.id}] Résultat du test _canSendNotification = $canSend',
              stackTrace: StackTrace.current); // LOG AJOUTÉ

          if (canSend) {
            _fileLogger.log(
                'INFO $tag/_handlePowerCheck: Conditions met for criteria ${criteria.id}. Attempting to send notification via NotificationService.',
                stackTrace: StackTrace.current);
            final title = criteria.message?.isNotEmpty == true
                ? criteria.message!
                : (criteria.type == 'above'
                    ? 'Alerte Puissance Haute ⚡'
                    : 'Alerte Puissance Basse 📉');
            final body = criteria.message?.isNotEmpty == true
                ? '${criteria.message!} (Actuel: ${currentPowerInCriteriaUnit.toStringAsFixed(1)} ${criteria.unit})'
                : 'La puissance actuelle (${currentPowerInCriteriaUnit.toStringAsFixed(1)} ${criteria.unit}) a ${criteria.type == 'above' ? 'dépassé' : 'est inférieure au'} seuil de ${criteria.threshold.toStringAsFixed(0)} ${criteria.unit}.';

            // ***** APPEL CORRIGÉ: Utilise NotificationService pour afficher *****
            _fileLogger.log(
                'ACTION $tag/_handlePowerCheck: [Critère ${criteria.id}] Tentative d\'appel à _notificationService!.showBackgroundNotification...',
                stackTrace: StackTrace.current); // LOG AJOUTÉ
            try {
              await _notificationService!.showBackgroundNotification(
                  id: _notificationService!
                      .generateNotifId(), // Utilise l'ID généré int32 depuis NotificationService
                  title: title,
                  body: body,
                  payload: 'criteria_${criteria.id}',
                  channel: userAlertChannel);
              _fileLogger.log(
                  'INFO $tag/_handlePowerCheck: Call to showBackgroundNotification done for criteria ${criteria.id}. Updating state locally...',
                  stackTrace: StackTrace.current);
              notificationSentInThisRun = true;
            } catch (notifError, notifStack) {
              _fileLogger.log(
                  'ERROR $tag/_handlePowerCheck: Exception caught calling showBackgroundNotification for criteria ${criteria.id}: $notifError',
                  stackTrace: notifStack);
              // Ne pas retourner false ici, car l'échec de la notification ne doit pas faire échouer la tâche WorkManager entière.
              // L'état local ne sera pas mis à jour, ce qui est le comportement souhaité si la notif échoue.
            }

            // ***** APPEL CORRIGÉ: Utilise le helper local pour mettre à jour l'état *****
            _fileLogger.log(
                'ACTION $tag/_handlePowerCheck: [Critère ${criteria.id}] Tentative d\'appel à _updateNotificationState...',
                stackTrace: StackTrace.current); // LOG AJOUTÉ
            await _updateNotificationState(criteria);
            _fileLogger.log(
                'DEBUG $tag/_handlePowerCheck: Local notification state updated for criteria ${criteria.id}.',
                stackTrace: StackTrace.current);

            // break;
          } else {
            _fileLogger.log(
                'INFO $tag/_handlePowerCheck: Cannot send notification for ${criteria.id} due to time window, cooldown, or daily limit.',
                stackTrace: StackTrace.current);
          }
        }
        _fileLogger.log(
            'DEBUG $tag/_handlePowerCheck: === Finished evaluating criteria ID: ${criteria.id} ===',
            stackTrace: StackTrace.current);
      }

      _fileLogger.log(
          'INFO $tag/_handlePowerCheck: Finished power check evaluation. Notification sent in this run: $notificationSentInThisRun',
          stackTrace: StackTrace.current);
      return true;
    } catch (e, s) {
      _fileLogger.log(
          'ERROR $tag/_handlePowerCheck: Unhandled exception during power check: $e',
          stackTrace: s);
      if (e.toString().contains("HiveError") ||
          e.toString().contains("FileSystemException")) {
        // ***** CORRECTION: Ajout stackTrace *****
        _fileLogger.log(
            'ERROR $tag/_handlePowerCheck: Potential Hive Box or FileSystem issue detected.',
            stackTrace: s);
      }
      return false;
    }
    // Retrait du bloc finally pour _handlePowerCheck
  }

  // ================================================================
  // _handleDailyProductionCheck CORRIGÉ (appel showBackgroundNotification + stackTrace)
  // ================================================================
  Future<bool> _handleDailyProductionCheck() async {
    debugPrint(
        '$tag/_handleDailyProductionCheck: Starting daily production check function...'); // Added log
    if (_prefs == null || _apiService == null || _notificationService == null) {
      _fileLogger.log(
          'ERROR $tag/_handleDailyProductionCheck: Missing dependencies. Cannot execute.',
          stackTrace: StackTrace.current);
      debugPrint(
          '$tag/_handleDailyProductionCheck: Missing dependencies.'); // Added log
      return false;
    }
    _fileLogger.log(
        'DEBUG $tag/_handleDailyProductionCheck: Starting daily production check function...',
        stackTrace: StackTrace.current);
    Box<UserPreferences>? prefsBox;
    final String todayStr = _todayDateString();
    _fileLogger.log(
        'DEBUG $tag/_handleDailyProductionCheck: Today is $todayStr.',
        stackTrace: StackTrace.current);
    debugPrint(
        '$tag/_handleDailyProductionCheck: Today is $todayStr.'); // Added log

    try {
      final lastSentDate = _prefs!.getString(dailyRecapSentDateKey);
      _fileLogger.log(
          'DEBUG $tag/_handleDailyProductionCheck: Last sent date from prefs: $lastSentDate',
          stackTrace: StackTrace.current);
      if (lastSentDate == todayStr) {
        _fileLogger.log(
            'INFO $tag/_handleDailyProductionCheck: Daily recap already sent today ($todayStr). Skipping task. Success.',
            stackTrace: StackTrace.current);
        return true;
      }
      //_fileLogger.log('DEBUG $tag/_handleDailyProductionCheck: Daily recap not sent today. Proceeding...');

      final bool notificationsEnabledGlobally =
          _prefs!.getBool('notifications_enabled') ?? true;
      _fileLogger.log(
          'DEBUG $tag/_handleDailyProductionCheck: Notifications globally enabled: $notificationsEnabledGlobally',
          stackTrace: StackTrace.current);
      if (!notificationsEnabledGlobally) {
        _fileLogger.log(
            'INFO $tag/_handleDailyProductionCheck: Notifications globally disabled. Skipping task. Success.',
            stackTrace: StackTrace.current);
        return true;
      }

      // Utiliser les préférences utilisateur passées au constructeur
      final UserPreferences? userPreferences = _userPreferences;
      _fileLogger.log(
          'DEBUG $tag/_handleDailyProductionCheck: UserPreferences object from constructor: ${userPreferences != null}',
          stackTrace: StackTrace.current);

      if (userPreferences == null) {
        _fileLogger.log(
            'ERROR $tag/_handleDailyProductionCheck: UserPreferences not available in worker instance. Cannot proceed.',
            stackTrace: StackTrace.current);
        return false; // Signaler l'échec à Workmanager
      }
      if (!userPreferences.notificationSettings.enableDailySummary) {
        _fileLogger.log(
            'INFO $tag/_handleDailyProductionCheck: Daily summary disabled in UserPreferences settings. Skipping task. Success.',
            stackTrace: StackTrace.current);
        return true;
      }
      //_fileLogger.log('DEBUG $tag/_handleDailyProductionCheck: Daily summary is enabled in UserPreferences.');

      final today = tz.TZDateTime.now(tz.local);
      final formattedToday = DateFormat('yyyy-MM-dd').format(today);
      _fileLogger.log(
          'DEBUG $tag/_handleDailyProductionCheck: Fetching energy data for today ($formattedToday)...',
          stackTrace: StackTrace.current);

      DailySolarData? dailyData;
      try {
        dailyData = await _apiService!
            .getDailyEnergy(today); // Utilise la date d'aujourd'hui
        _fileLogger.log(
            'DEBUG $tag/_handleDailyProductionCheck: API call finished. Energy data received: ${dailyData != null}. Total energy: ${dailyData?.totalEnergy}',
            stackTrace: StackTrace.current);
      } on SolarEdgeApiException catch (apiError, apiStack) {
        _fileLogger.log(
            'ERROR $tag/_handleDailyProductionCheck: API Error fetching today\'s energy data: ${apiError.message}. Status: ${apiError.statusCode}',
            stackTrace: apiStack);
        return false; // Retourner false en cas d'erreur API
      } catch (e, s) {
        _fileLogger.log(
            'ERROR $tag/_handleDailyProductionCheck: Unexpected error fetching today\'s energy data: $e',
            stackTrace: s);
        return false;
      }

      _fileLogger.log(
          'DEBUG $tag/_handleDailyProductionCheck: Checking if dailyData is valid...',
          stackTrace: StackTrace.current);
      if (dailyData == null || dailyData.totalEnergy <= 0) {
        _fileLogger.log(
            'WARN $tag/_handleDailyProductionCheck: No valid energy data available (result was ${dailyData?.totalEnergy}) for today ($formattedToday). Skipping recap. Task successful.',
            stackTrace: StackTrace.current);
        return true;
      }
      _fileLogger.log(
          'DEBUG $tag/_handleDailyProductionCheck: Daily data is valid. Total energy: ${dailyData.totalEnergy}',
          stackTrace: StackTrace.current);

      _fileLogger.log(
          'DEBUG $tag/_handleDailyProductionCheck: Formatting total energy and date...',
          stackTrace: StackTrace.current);
      final totalKWh = (dailyData.totalEnergy / 1000.0).toStringAsFixed(2);
      final formattedDate = DateFormat('EEEE d MMMM', 'fr_FR')
          .format(today); // Utilise la date d'aujourd'hui
      final title = 'Récap Production Solaire ☀️';
      final body =
          'Aujourd\'hui ($formattedDate), vous avez produit $totalKWh kWh.'; // Met à jour le message
      _fileLogger.log(
          'DEBUG $tag/_handleDailyProductionCheck: Notification title: "$title", body: "$body"',
          stackTrace: StackTrace.current);

      _fileLogger.log(
          'INFO $tag/_handleDailyProductionCheck: Preparing to send daily summary notification: "$body"',
          stackTrace: StackTrace.current);

      // ***** APPEL CORRIGÉ: Utilise NotificationService pour afficher *****
      _fileLogger.log(
          'DEBUG $tag/_handleDailyProductionCheck: Calling _notificationService.showBackgroundNotification...',
          stackTrace: StackTrace.current);
      bool sent = false; // Variable pour suivre le succès de l'envoi
      try {
        await _notificationService!.showBackgroundNotification(
            id: _notificationService!
                .generateNotifId(), // Utilise l'ID généré int32 depuis NotificationService
            title: title,
            body: body,
            payload: 'daily_summary_$todayStr',
            channel: userAlertChannel);
        _fileLogger.log(
            'INFO $tag/_handleDailyProductionCheck: Call to showBackgroundNotification done for daily summary.',
            stackTrace: StackTrace.current);
        sent = true; // Marquer comme envoyé si l'appel réussit
      } catch (notifError, notifStack) {
        _fileLogger.log(
            'ERROR $tag/_handleDailyProductionCheck: Exception caught calling showBackgroundNotification for daily summary: $notifError',
            stackTrace: notifStack);
        // Ne pas retourner false ici
      }

      // 👉 on ne marque “déjà envoyé” que si l’envoi a vraiment réussi
      if (sent) {
        _fileLogger.log(
            'DEBUG $tag/_handleDailyProductionCheck: Updating last sent date in SharedPreferences to $todayStr...',
            stackTrace: StackTrace.current);
        await _prefs!.setString(dailyRecapSentDateKey, todayStr);
        _fileLogger.log(
            'INFO $tag/_handleDailyProductionCheck: Daily recap sent and marked for $todayStr. Task successful.',
            stackTrace: StackTrace.current);
      } else {
        _fileLogger.log(
            'INFO $tag/_handleDailyProductionCheck: Daily recap notification failed to send. Not marking as sent.',
            stackTrace: StackTrace.current);
      }

      return true;
    } catch (e, s) {
      // Loguer le type d'exception et le message
      _fileLogger.log(
          'ERROR $tag/_handleDailyProductionCheck: Unhandled exception during daily check. Type: ${e.runtimeType}, Message: $e',
          stackTrace: s);
      if (e.toString().contains("HiveError") ||
          e.toString().contains("FileSystemException")) {
        _fileLogger.log(
            'ERROR $tag/_handleDailyProductionCheck: Potential Hive Box or FileSystem issue detected.',
            stackTrace: s);
      }
      return false;
    }
    // Retrait du bloc finally pour _handleDailyProductionCheck
  }

  // --- Fonctions Helper (appelées par les handlers locaux) ---

  String _todayDateString() {
    final now = tz.TZDateTime.now(tz.local);
    return DateFormat('yyyy-MM-dd').format(now);
  }

  // Vérifie cooldown, limite journalière, fenêtre horaire, jour actif
  Future<bool> _canSendNotification(NotificationCriteria criteria) async {
    _fileLogger.log(
        'DEBUG $tag/_canSendNotification: [Critère ${criteria.id}] Checking rules...', // Log initial plus concis
        stackTrace: StackTrace.current);

    if (!_isWithinTimeWindow(criteria.startTime, criteria.endTime)) {
      _fileLogger.log(
          'DEBUG $tag/_canSendNotification: [${criteria.id}] FAILED: Outside time window (${criteria.startTime}-${criteria.endTime}).',
          stackTrace: StackTrace.current);
      return false;
    }
    _fileLogger.log(
        'DEBUG $tag/_canSendNotification: [Critère ${criteria.id}] PASSED: Within time window.',
        stackTrace: StackTrace.current);

    if (!_isDayActive(criteria.activeDays)) {
      _fileLogger.log(
          'DEBUG $tag/_isDayActive: [${criteria.id}] FAILED: Day not active (Today: ${tz.TZDateTime.now(tz.local).weekday}, Active: ${criteria.activeDays}).',
          stackTrace: StackTrace.current);
      return false;
    }
    _fileLogger.log(
        'DEBUG $tag/_canSendNotification: [Critère ${criteria.id}] PASSED: Day is active.', // Correction _isDayActive -> _canSendNotification
        stackTrace: StackTrace.current);

    // --- Cooldown Check (SUPPRIMÉ) ---
    // final lastSentTimestampKey = '$lastNotifTimestampPrefix${criteria.id}';
    // _fileLogger.log(
    //     'DETAIL $tag/_canSendNotification: [Critère ${criteria.id}] Reading cooldown timestamp with key: $lastSentTimestampKey',
    //     stackTrace: StackTrace.current); // LOG AJOUTÉ
    // final lastSentMillis = _prefs!.getInt(lastSentTimestampKey);
    // _fileLogger.log(
    //     'DETAIL $tag/_canSendNotification: [Critère ${criteria.id}] Value read for lastSentMillis: $lastSentMillis',
    //     stackTrace: StackTrace.current); // LOG AJOUTÉ
    //
    // if (lastSentMillis != null) {
    //   final nowMillis = DateTime.now().millisecondsSinceEpoch;
    //   // final cooldownMillis = criteria.frequency * 60 * 1000; // ERREUR ICI car frequency n'existe plus
    //   final elapsedMillis = nowMillis - lastSentMillis;
    //   // final bool cooldownActive = elapsedMillis < cooldownMillis;
    //   // _fileLogger.log(
    //   //     'DETAIL $tag/_canSendNotification: [Critère ${criteria.id}] Cooldown check: Now=${nowMillis}, LastSent=${lastSentMillis}, Elapsed=${elapsedMillis}ms, Required=${cooldownMillis}ms, CooldownActive=$cooldownActive',
    //   //     stackTrace: StackTrace.current); // LOG AJOUTÉ
    //   // if (cooldownActive) {
    //   //   _fileLogger.log(
    //   //       'DEBUG $tag/_canSendNotification: [Critère ${criteria.id}] FAILED: Cooldown active. Returning false.',
    //   //       stackTrace: StackTrace.current); // LOG AJOUTÉ
    //   //   return false;
    //   // }
    // }
    // _fileLogger.log(
    //     'DEBUG $tag/_canSendNotification: [Critère ${criteria.id}] PASSED: Cooldown inactive or first time.',
    //     stackTrace: StackTrace.current);

    // --- Daily Limit Check ---
    final todayStr = _todayDateString();
    final dailyLimitKey = '$dailyNotifCountPrefix${criteria.id}_$todayStr';
    _fileLogger.log(
        'DETAIL $tag/_canSendNotification: [Critère ${criteria.id}] Reading daily count with key: $dailyLimitKey',
        stackTrace: StackTrace.current); // LOG AJOUTÉ
    final sentTodayCount = _prefs!.getInt(dailyLimitKey) ?? 0;
    final maxPerDay = criteria.maxNotificationsPerDay;
    _fileLogger.log(
        'DETAIL $tag/_canSendNotification: [Critère ${criteria.id}] Daily limit check: SentTodayCount=$sentTodayCount, MaxPerDay=$maxPerDay',
        stackTrace: StackTrace.current); // LOG AJOUTÉ
    final bool limitReached = sentTodayCount >= maxPerDay;
    if (limitReached) {
      _fileLogger.log(
          'DEBUG $tag/_canSendNotification: [Critère ${criteria.id}] FAILED: Daily limit reached ($sentTodayCount >= $maxPerDay). Returning false.',
          stackTrace: StackTrace.current); // LOG AJOUTÉ
      return false;
    }
    _fileLogger.log(
        'DEBUG $tag/_canSendNotification: [Critère ${criteria.id}] PASSED: Daily limit not reached.',
        stackTrace: StackTrace.current);

    _fileLogger.log(
        'INFO $tag/_canSendNotification: [Critère ${criteria.id}] All rules PASSED. Returning true.',
        stackTrace: StackTrace.current); // LOG AJOUTÉ
    return true; // Retour final
  }

  // Met à jour le timestamp et le compteur journalier
  Future<void> _updateNotificationState(NotificationCriteria criteria) async {
    _fileLogger.log(
        'DEBUG $tag/_updateNotificationState: Updating state for criteria ${criteria.id}...',
        stackTrace: StackTrace.current);
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    final todayStr = _todayDateString();
    // final lastSentTimestampKey = '$lastNotifTimestampPrefix${criteria.id}'; // SUPPRIMÉ
    final dailyLimitKey = '$dailyNotifCountPrefix${criteria.id}_$todayStr';

    final currentCount = _prefs!.getInt(dailyLimitKey) ?? 0;
    final newCount = currentCount + 1;

    // _fileLogger.log(
    //     'DEBUG $tag/_updateNotificationState: [${criteria.id}] Setting last sent timestamp ($lastSentTimestampKey) to $nowMillis',
    //     stackTrace: StackTrace.current);
    // await _prefs!.setInt(lastSentTimestampKey, nowMillis); // SUPPRIMÉ
    _fileLogger.log(
        'DEBUG $tag/_updateNotificationState: [${criteria.id}] Setting daily count ($dailyLimitKey) to $newCount',
        stackTrace: StackTrace.current);
    await _prefs!.setInt(dailyLimitKey, newCount);

    // ***** CORRECTION: Ajout stackTrace *****
    _fileLogger.log(
        'INFO $tag/_updateNotificationState: Updated state for criteria ${criteria.id}. Count today: $newCount',
        stackTrace: StackTrace.current);
  }

  // Vérifie si l'heure actuelle est dans la fenêtre définie
  bool _isWithinTimeWindow(String startTimeStr, String endTimeStr) {
    _fileLogger.log(
        'DEBUG $tag/_isWithinTimeWindow: Checking time window $startTimeStr - $endTimeStr',
        stackTrace: StackTrace.current);
    try {
      final now = tz.TZDateTime.now(tz.local);
      final startTimeParts = startTimeStr.split(':');
      final endTimeParts = endTimeStr.split(':');
      if (startTimeParts.length != 2 || endTimeParts.length != 2) {
        _fileLogger.log(
            'WARN $tag/_isWithinTimeWindow: Invalid time format ($startTimeStr or $endTimeStr). Assuming true.',
            stackTrace: StackTrace.current);
        return true;
      }
      final startHour = int.parse(startTimeParts[0]);
      final startMinute = int.parse(startTimeParts[1]);
      final endHour = int.parse(endTimeParts[0]);
      final endMinute = int.parse(endTimeParts[1]);

      final startTime = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, startHour, startMinute);
      var endTime = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, endHour, endMinute);

      bool isWithin;
      if (endTime.isBefore(startTime)) {
        endTime = endTime.add(const Duration(days: 1));
        isWithin = now.isAfter(startTime) || now.isBefore(endTime);
        _fileLogger.log(
            'DEBUG $tag/_isWithinTimeWindow: Overnight window. Now: $now, Start: $startTime, End (next day): $endTime. Is within: $isWithin',
            stackTrace: StackTrace.current);
      } else {
        isWithin = now.isAfter(startTime) && now.isBefore(endTime);
        _fileLogger.log(
            'DEBUG $tag/_isWithinTimeWindow: Same day window. Now: $now, Start: $startTime, End: $endTime. Is within: $isWithin',
            stackTrace: StackTrace.current);
      }
      return isWithin;
    } catch (e, s) {
      // ***** CORRECTION: Ajout stackTrace *****
      _fileLogger.log(
          'ERROR $tag/_isWithinTimeWindow: Error parsing time window ($startTimeStr - $endTimeStr): $e',
          stackTrace: s);
      return true;
    }
  }

  // Vérifie si le jour actuel est actif
  bool _isDayActive(List<int> activeDays) {
    if (activeDays.isEmpty) {
      _fileLogger.log(
          'DEBUG $tag/_isDayActive: No specific active days set. Assuming active.',
          stackTrace: StackTrace.current);
      return true;
    }
    final now = tz.TZDateTime.now(tz.local);
    final currentWeekday = now.weekday;
    final isActive = activeDays.contains(currentWeekday);
    _fileLogger.log(
        'DEBUG $tag/_isDayActive: Today is weekday $currentWeekday. Active days: $activeDays. Is active: $isActive',
        stackTrace: StackTrace.current);
    return isActive;
  }
} // Fin classe BackgroundWorkerService
