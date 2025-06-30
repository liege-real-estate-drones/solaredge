// solaredge_monitor/lib/main.dart
// Version corrigée : Workmanager est correctement initialisé avant toute planification
// et les tâches sont enregistrées juste après l'initialisation de l'API.

import 'dart:async';
import 'dart:developer';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:permission_handler/permission_handler.dart';

// --- Imports locaux ---------------------------------------------------------------------------
import 'data/models/notification_model.dart';
import 'data/models/user_preferences.dart';
import 'data/services/auth_service.dart';
import 'data/services/background_worker_service.dart';
import 'data/services/location_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/service_manager.dart';
import 'data/services/solaredge_api_service.dart';
import 'data/services/user_preferences_service.dart';
import 'data/services/weather_manager.dart';
import 'data/services/assistant_service.dart';
import 'data/services/ai_service.dart'; // Ajouter cet import

import 'presentation/pages/splash_screen.dart';
import 'presentation/pages/login_screen.dart';
import 'presentation/pages/home_screen.dart';
import 'presentation/pages/daily_screen.dart';
import 'presentation/pages/monthly_screen.dart';
import 'presentation/pages/yearly_screen.dart';
import 'presentation/pages/settings_screen.dart';
import 'presentation/pages/notifications_screen.dart';
import 'presentation/pages/location_configuration_screen.dart';
import 'presentation/pages/ai_assistant_screen.dart';
import 'presentation/pages/setup/setup_screen.dart';

import 'presentation/theme/app_theme.dart';
import 'utils/file_logger.dart';
import 'firebase_options.dart';
// ----------------------------------------------------------------------------------------------

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // --------------------------------------------------
  // 0. Logger
  // --------------------------------------------------
  final fileLogger = FileLogger();
  await fileLogger.initialize();
  fileLogger.log('INFO main: Application starting...',
      stackTrace: StackTrace.current);
  log('INFO main: Application starting...');

  // --------------------------------------------------
  // 1. Time-zone
  // --------------------------------------------------
  try {
    tzdata.initializeTimeZones();
    final String locationName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(locationName));
    fileLogger.log('INFO main: Timezone initialized to $locationName.',
        stackTrace: StackTrace.current);
  } catch (e, s) {
    const fallbackLocation = 'Europe/Brussels';
    tz.setLocalLocation(tz.getLocation(fallbackLocation));
    fileLogger.log('WARNING main: Timezone fallback to $fallbackLocation.',
        stackTrace: s);
  }

  await initializeDateFormatting('fr_FR', null);

  // --------------------------------------------------
  // 2. SharedPreferences & Hive
  // --------------------------------------------------
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // Demander les permissions de stockage avant d'initialiser Hive
  // Nécessaire pour Android 10+ et pour l'écriture de fichiers (logs, Hive)
  if (await Permission.storage.request().isGranted) {
    log('INFO main: Permission de stockage accordée.');
  } else {
    log('WARNING main: Permission de stockage refusée. Certaines fonctionnalités (logs, Hive) pourraient être limitées.');
    // Gérer le cas où la permission est refusée (ex: afficher un message à l'utilisateur)
  }
  // Pour Android 11+ et l'accès complet aux fichiers
  if (await Permission.manageExternalStorage.request().isGranted) {
    log('INFO main: Permission de gestion du stockage externe accordée.');
  } else {
    log('WARNING main: Permission de gestion du stockage externe refusée. L\'accès complet aux fichiers pourrait être limité.');
  }

  await Hive.initFlutter();
  Hive.registerAdapter(NotificationModelAdapter());
  Hive.registerAdapter(NotificationGroupAdapter());

  // --------------------------------------------------
  // 3. Firebase
  // --------------------------------------------------
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // --------------------------------------------------
  // 4. ServiceManager (tous les services *sauf* l'API SolarEdge)
  // --------------------------------------------------
  final serviceManager = ServiceManager();
  await serviceManager.initializeCoreServices();

  // --------------------------------------------------
  // 5. NotificationService (a besoin de Firebase + Hive)
  // --------------------------------------------------
  await serviceManager.notificationService?.initialize(null);

  // --------------------------------------------------
  // 6. BackgroundWorkerService (instance créée maintenant, mais initialisée plus tard)
  // --------------------------------------------------
  final backgroundWorkerService = BackgroundWorkerService(
    prefs: prefs,
    apiService: serviceManager
        .apiService, // pour l'instant null ⇒ réinjecté après init API
    fileLogger: fileLogger,
  );

  // --------------------------------------------------
  // 7. Lorsque l'utilisateur est authentifié, on initialise l'API *et* le worker
  // --------------------------------------------------
  StreamSubscription? authSub;
  authSub = serviceManager.authService!.authStateChanges.listen((fb_auth.User? user) async {
    fileLogger.log(
        'INFO main: authStateChanges emitted. user=${user is fb_auth.User ? user.uid : 'null'}',
        stackTrace: StackTrace.current);

    // On n'agit qu'une seule fois, dès qu'on a un utilisateur valide.
    if (user == null) return;

    // 7-a. Initialiser l'API SolarEdge à partir des préférences Firestore/sharedPrefs.
    await serviceManager.initializeApiServiceFromPreferences();

    // 7-b. Maintenant que serviceManager.apiService est prêt, on le donne au worker puis on l'initialise.
    backgroundWorkerService
      ..apiService ??= serviceManager.apiService // maj si besoin
      ..init().then((_) async {
        // 7-c. Planifier les deux tâches périodiques une seule fois.
        await backgroundWorkerService.schedulePowerCheckTask();
        fileLogger.log('INFO main: schedulePowerCheckTask() called.',
            stackTrace: StackTrace.current); // LOG AJOUTÉ
        await backgroundWorkerService.scheduleDailyProductionCheckTask();
        fileLogger.log('INFO main: scheduleDailyProductionCheckTask() called.',
            stackTrace: StackTrace.current); // LOG AJOUTÉ
      });

    await authSub?.cancel();
  });

  // --------------------------------------------------
  // 8. runApp avec tous les providers
  // --------------------------------------------------
  runApp(
    MultiProvider(
      providers: [
        Provider<ServiceManager>.value(value: serviceManager),
        Provider<SharedPreferences>.value(value: prefs),
        Provider<AuthService>.value(value: serviceManager.authService!),
        ChangeNotifierProvider<ValueNotifier<SolarEdgeApiService?>>.value(
          value: serviceManager.apiServiceNotifier,
        ),
        if (serviceManager.locationService != null)
          Provider<LocationService>.value(
              value: serviceManager.locationService!),
        if (serviceManager.weatherManager != null)
          ChangeNotifierProvider<WeatherManager>.value(
              value: serviceManager.weatherManager!),
        if (serviceManager.notificationService != null)
          Provider<NotificationService>.value(
              value: serviceManager.notificationService!),
        if (serviceManager.assistantService != null)
          ChangeNotifierProvider<AssistantService>.value(
              value: serviceManager.assistantService!),
        if (serviceManager.aiService != null)
          ChangeNotifierProvider<AiService>.value(
              value: serviceManager.aiService!),
        Provider<BackgroundWorkerService>.value(value: backgroundWorkerService),
        if (serviceManager.userPreferencesService != null)
          Provider<UserPreferencesService>.value(
              value: serviceManager.userPreferencesService!),
        ChangeNotifierProvider<ValueNotifier<UserPreferences?>>.value(
          value: serviceManager.userPreferencesNotifier,
        ),
      ],
      child: const MyApp(),
    ),
  );
}

// ------------------------------------------------------------------------------------------------
// 9. Application racine
// ------------------------------------------------------------------------------------------------
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialise les notifications (permis) dans l'UI principale
    Future.microtask(() => NotificationService().initialize(context));

    return MaterialApp(
      title: 'SolarEdge Monitor',
      theme: AppTheme.getTheme(),
      darkTheme: AppTheme.getTheme(),
      themeMode: ThemeMode.dark,
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr', 'FR'), Locale('en', 'US')],
      locale: const Locale('fr', 'FR'),
      initialRoute: '/splash',
      routes: {
        '/splash': (_) => const SplashScreen(),
        '/setup': (_) => const SetupScreen(),
        '/login': (_) => const LoginScreen(),
        '/home': (_) => const HomeScreen(),
        '/daily': (_) => const DailyScreen(),
        '/monthly': (_) => const MonthlyScreen(),
        '/yearly': (_) => const YearlyScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/notifications': (_) => const NotificationsScreen(),
        '/location_config': (_) => const LocationConfigurationScreen(),
        '/ai_assistant': (context) => Provider.of<ServiceManager>(context, listen: false).aiService != null ? const AiAssistantScreen() : const Text('AI Assistant non disponible'),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/monthly') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
              builder: (_) => MonthlyScreen(
                  initialDate: args?['selectedDate'] as DateTime?));
        }
        if (settings.name == '/daily') {
          return MaterialPageRoute(builder: (_) => const DailyScreen());
        }
        return null;
      },
      onUnknownRoute: (_) =>
          MaterialPageRoute(builder: (_) => const SplashScreen()),
    );
  }
}
