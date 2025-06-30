import 'dart:async'; // Import pour StreamSubscription
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/data/services/weather_manager.dart';
import 'package:get_it/get_it.dart'; // Import GetIt
import 'package:solaredge_monitor/data/services/location_service.dart';
import 'package:solaredge_monitor/data/services/assistant_service.dart';
import 'package:solaredge_monitor/data/services/ai_service.dart'; // Ajouter cet import
import 'package:solaredge_monitor/data/services/solar_estimator.dart'; // Import SolarProductionEstimator
// --- Ajouts imports pour les getters ---
import 'package:solaredge_monitor/data/services/auth_service.dart';
import 'package:solaredge_monitor/data/services/notification_service.dart';
import 'package:solaredge_monitor/data/services/user_preferences_service.dart'; // Import du nouveau service
import 'package:solaredge_monitor/data/models/user_preferences.dart'; // Import UserPreferences
// --- Fin ajouts imports ---

/// Gestionnaire central des services de l'application
/// Permet de maintenir une référence unique et de notifier les mises à jour
class ServiceManager {
  // --- Singleton ---
  static final ServiceManager _instance = ServiceManager._internal();
  factory ServiceManager() => _instance;
  ServiceManager._internal();

  // --- Core Services Instances ---
  SharedPreferences? _prefs;
  SolarEdgeApiService? _apiService;
  LocationService? _locationService;
  WeatherManager? _weatherManager;
  AssistantService? _assistantService;
  AiService? _aiService; // Ajouter l'instance
  SolarProductionEstimator? _solarEstimator; // Add SolarProductionEstimator instance
  // --- Instances ajoutées ---
  AuthService? _authService;
  NotificationService? _notificationService;
  UserPreferencesService? _userPreferencesService; // Ajouter l'instance ici
  UserPreferences?
      _userPreferences; // Ajouter l'instance des préférences utilisateur
  // --- Fin instances ajoutées ---

  // --- Getters and Setters for Services ---
  SharedPreferences? get prefs => _prefs;
  SolarEdgeApiService? get apiService => _apiService;
  LocationService? get locationService => _locationService;
  WeatherManager? get weatherManager => _weatherManager;

  // Add setters for AssistantService and AiService
  AssistantService? get assistantService => _assistantService;
  set assistantService(AssistantService? service) {
    _assistantService = service;
  }

  AiService? get aiService => _aiService; // Ajouter le getter
  set aiService(AiService? service) { // Add setter for AiService
    _aiService = service;
  }

  SolarProductionEstimator? get solarEstimator => _solarEstimator; // Add SolarProductionEstimator getter
  // --- Getters ajoutés ---
  AuthService? get authService => _authService;
  NotificationService? get notificationService => _notificationService;
  UserPreferencesService? get userPreferencesService =>
      _userPreferencesService; // Ajouter le getter ici
  UserPreferences? get userPreferences =>
      _userPreferences; // Ajouter le getter pour les préférences utilisateur
  // --- Fin getters ajoutés ---

  // Add getter for geminiApiKey
  String? get geminiApiKey => _userPreferencesNotifier.value?.geminiApiKey;


  // --- API Configuration State ---
  // Modifier le StreamController pour émettre l'instance du service API (peut être null)
  final StreamController<SolarEdgeApiService?> _apiConfigChangedController =
      StreamController<SolarEdgeApiService?>.broadcast();
  Stream<SolarEdgeApiService?> get apiConfigChangedStream =>
      _apiConfigChangedController.stream;
  bool _isApiConfigured = false;
  bool get isApiConfigured => _isApiConfigured;

  // --- API Service ValueNotifier ---
  // Ajouter un ValueNotifier pour l'instance du service API
  final ValueNotifier<SolarEdgeApiService?> _apiServiceNotifier =
      ValueNotifier<SolarEdgeApiService?>(null);
  ValueNotifier<SolarEdgeApiService?> get apiServiceNotifier =>
      _apiServiceNotifier;

  // --- User Preferences State ---
  // Ajouter un ValueNotifier pour les préférences utilisateur
  final ValueNotifier<UserPreferences?> _userPreferencesNotifier =
      ValueNotifier<UserPreferences?>(null);
  ValueNotifier<UserPreferences?> get userPreferencesNotifier =>
      _userPreferencesNotifier;

  /// Initialise tous les services principaux au démarrage de l'application.
  /// Doit être appelé une fois dans main.dart avant runApp.
  Future<void> initializeCoreServices() async {
    debugPrint("🔧 Initialisation des services principaux...");
    try {
      // Enregistrer les services avec GetIt
      final getIt = GetIt.I;

      // 1. SharedPreferences (souvent nécessaire en premier)
      _prefs = await SharedPreferences.getInstance();
      if (!getIt.isRegistered<SharedPreferences>()) {
        getIt.registerSingleton<SharedPreferences>(_prefs!);
      }
      debugPrint("✅ SharedPreferences initialisé et enregistré.");

      // 2. Location Service
      _locationService = LocationService();
      if (!getIt.isRegistered<LocationService>()) {
        getIt.registerSingleton<LocationService>(_locationService!);
      }
      debugPrint("✅ LocationService initialisé et enregistré.");

      // 3. User Preferences Service (nécessite Firestore) - Déplacé avant AuthService
      _userPreferencesService = UserPreferencesService();
      if (!getIt.isRegistered<UserPreferencesService>()) {
        getIt.registerSingleton<UserPreferencesService>(
            _userPreferencesService!);
      }
      debugPrint("✅ UserPreferencesService initialisé et enregistré.");

      // 4. Authentication Service (peut être nécessaire avant l'API si l'API dépend de l'auth)
      // Injecter UserPreferencesService dans AuthService
      _authService =
          AuthService(userPreferencesService: _userPreferencesService!);
      if (!getIt.isRegistered<AuthService>()) {
        getIt.registerSingleton<AuthService>(_authService!);
      }
      debugPrint("✅ AuthService initialisé et enregistré.");

      // 5. SolarEdge API Service (basé sur les préférences utilisateur)
      _apiService =
          await initializeApiServiceFromPreferences(); // Utiliser la nouvelle méthode
      // L'enregistrement de ApiService se fait dans initializeApiServiceFromPreferences car l'instance peut changer
      debugPrint(
          "✅ SolarEdgeApiService initialisé (état: ${isApiConfigured ? 'Configuré' : 'Non configuré'}).");

      // 6. Weather Manager
      _weatherManager = WeatherManager();
      await _weatherManager!.initialize();
      if (!getIt.isRegistered<WeatherManager>()) {
        getIt.registerSingleton<WeatherManager>(_weatherManager!);
      }
      debugPrint("✅ WeatherManager initialisé et enregistré.");

      // 7. Solar Production Estimator (nécessite WeatherManager et ApiService)
      if (_weatherManager != null && _apiService != null) {
        _solarEstimator = SolarProductionEstimator(
          weather: _weatherManager!,
          solarEdgeApi: _apiService!,
        );
        // Note: We don't register SolarProductionEstimator with GetIt
        // as it's accessed directly via ServiceManager getter.
        debugPrint("✅ SolarProductionEstimator initialisé.");
      } else {
        debugPrint("⚠️ SolarProductionEstimator non initialisé. Dépendances manquantes : Weather=${_weatherManager != null}, API=${_apiService != null}");
        _solarEstimator = null;
      }


      // 8. Notification Service (nécessite potentiellement Prefs, Firebase init)
      _notificationService = NotificationService();
      if (!getIt.isRegistered<NotificationService>()) {
        getIt.registerSingleton<NotificationService>(_notificationService!);
      }
      // L'initialisation de NotificationService (avec context si besoin)
      // sera appelée depuis main.dart *après* l'initialisation de Firebase.
      // PAS d'appel à _notificationService.initialize() ici.
      debugPrint(
          "✅ NotificationService instancié et enregistré (initialisation différée).");

      // 8. AI Service (a besoin de l'API Key, WeatherManager, Notifiers API et UserPrefs)
      // Récupérer la clé API Gemini depuis les préférences utilisateur
      final String? geminiApiKey = _userPreferencesNotifier.value?.geminiApiKey;

      if (geminiApiKey == null || geminiApiKey.isEmpty) {
         debugPrint("⚠️ ATTENTION: Clé API Gemini non trouvée dans les préférences utilisateur. L'AiService ne fonctionnera pas.");
         _aiService = null; // S'assurer que l'instance est nulle si la clé manque
         if (getIt.isRegistered<AiService>()) {
           getIt.unregister<AiService>(); // Désenregistrer si elle existait
           debugPrint("ℹ️ AiService désenregistré car clé API manquante.");
         }
      } else if (_weatherManager != null) { // Vérifier que les autres dépendances sont prêtes
        // Initialiser ou ré-initialiser AiService si la clé est présente et les dépendances sont prêtes
        if (_aiService == null || !getIt.isRegistered<AiService>()) {
           _aiService = AiService(
             apiKey: geminiApiKey, // Fournir la clé API des préférences
             apiServiceNotifier: _apiServiceNotifier, // Passer le notifier API
             weatherManager: _weatherManager!,        // Passer WeatherManager
             userPrefsNotifier: _userPreferencesNotifier, // Passer le notifier UserPrefs
           );
           getIt.registerSingleton<AiService>(_aiService!);
           debugPrint("✅ AiService initialisé et enregistré avec clé API.");
        } else {
           // Si AiService existe déjà, on pourrait vouloir le ré-initialiser avec la nouvelle clé
           // Pour l'instant, on suppose que le ValueNotifier userPrefsNotifier
           // permettra à AiService de réagir aux changements de clé.
           // Si AiService a besoin de la clé dans son constructeur, il faudrait le ré-instancier ici.
           // Pour une approche plus simple, on s'assure juste qu'il est enregistré.
           debugPrint("ℹ️ AiService déjà initialisé. Utilise la clé des préférences.");
        }
      } else {
        debugPrint("⚠️ AiService non initialisé. Dépendances manquantes : Weather=${_weatherManager != null}");
        _aiService = null; // S'assurer que l'instance est nulle si les dépendances manquent
        if (getIt.isRegistered<AiService>()) {
           getIt.unregister<AiService>();
           debugPrint("ℹ️ AiService désenregistré car dépendances manquantes.");
         }
      }

      // Ajouter un listener pour réagir aux changements de préférences utilisateur (y compris la clé Gemini)
      _userPreferencesNotifier.addListener(_onUserPreferencesChanged);
      debugPrint("✅ Listener ajouté à _userPreferencesNotifier.");


      // 9. Assistant Service (maintenant injecté avec les notifiers)
      if (_weatherManager != null) {
        _assistantService = AssistantService(
          weatherManager: _weatherManager!,
          userPreferencesNotifier: _userPreferencesNotifier,
          apiServiceNotifier: _apiServiceNotifier,
        );
        if (!getIt.isRegistered<AssistantService>()) {
          getIt.registerSingleton<AssistantService>(_assistantService!);
        }
        debugPrint("✅ AssistantService initialisé et enregistré.");
      } else {
        debugPrint("⚠️ AssistantService non initialisé car WeatherManager est manquant.");
        _assistantService = null;
      }

      debugPrint("👍 Initialisation des services principaux terminée.");
    } catch (e, stacktrace) {
      debugPrint("❌ Erreur majeure lors de l'initialisation des services: $e");
      debugPrint("StackTrace: $stacktrace");
      // Gérer l'erreur
      _prefs = null;
      _apiService = null;
      _locationService = null;
      _weatherManager = null;
      _assistantService = null;
      _authService = null;
      _notificationService = null;
      _aiService = null; // Ajouter à la gestion d'erreur
      _isApiConfigured = false;

      // Nettoyer GetIt en cas d'erreur majeure ? Dépend de la stratégie de gestion d'erreur.
      // Pour l'instant, on laisse les instances nulles.
    }
  }

  /// Initialise ou réinitialise SPÉCIFIQUEMENT le service API et charge les préférences utilisateur.
  /// Tente de charger les préférences depuis Firestore via UserPreferencesService
  /// si un utilisateur est connecté, sinon utilise SharedPreferences comme fallback.
  /// Appelé depuis initializeCoreServices et potentiellement depuis SettingsScreen.
  Future<SolarEdgeApiService?> initializeApiServiceFromPreferences() async {
    debugPrint(
        'DEBUG ServiceManager: initializeApiServiceFromPreferences called.'); // Added log
    SolarEdgeApiService? initializedService;
    bool previousConfigState = _isApiConfigured; // Mémoriser l'état précédent
    bool success = false;
    final getIt = GetIt.I; // Obtenir l'instance GetIt

    try {
      final AuthService authService = getIt<AuthService>();
      final UserPreferencesService userPreferencesService =
          getIt<UserPreferencesService>();
      final SharedPreferences prefs =
          getIt<SharedPreferences>(); // Pour le fallback/migration

      String? apiKey;
      String? siteId;
      UserPreferences?
          loadedPreferences; // Variable pour stocker les préférences chargées

      final user = authService.currentUser;
      debugPrint(
          'DEBUG ServiceManager: Inside initializeApiServiceFromPreferences, authService.currentUser is ${user == null ? 'null' : user.uid}.'); // Added log

      if (user != null) {
        // Tenter de charger depuis Firestore
        debugPrint(
            'DEBUG ServiceManager: User is not null, attempting to load preferences from Firestore.'); // Added log
        loadedPreferences =
            await userPreferencesService.loadUserPreferences(user);

        // DETAILED LOGGING FOR LOADED PREFERENCES FROM FIRESTORE
        if (loadedPreferences != null) {
          debugPrint("ServiceManager - Loaded from Firestore: "
                     "apiKey=${loadedPreferences.solarEdgeApiKey != null && loadedPreferences.solarEdgeApiKey!.isNotEmpty}, "
                     "siteId=${loadedPreferences.siteId != null && loadedPreferences.siteId!.isNotEmpty}, "
                     "geminiApiKey=${loadedPreferences.geminiApiKey != null && loadedPreferences.geminiApiKey!.isNotEmpty}, "
                     "darkMode=${loadedPreferences.darkMode}, "
                     "displayUnit=${loadedPreferences.displayUnit?.toString() ?? 'null'}, "
                     "currency=${loadedPreferences.currency?.toString() ?? 'null'}, "
                     "energyRate=${loadedPreferences.energyRate}, "
                     "peakPowerKw=${loadedPreferences.peakPowerKw}, "
                     "panelTilt=${loadedPreferences.panelTilt}, "
                     "panelOrientation=${loadedPreferences.panelOrientation}, "
                     "washingMachineKw=${loadedPreferences.washingMachineKw}, "
                     "defaultWashingMachineDurationMin=${loadedPreferences.defaultWashingMachineDurationMin}, "
                     "latitude=${loadedPreferences.latitude}, "
                     "longitude=${loadedPreferences.longitude}, "
                     "weatherLocationSource=${loadedPreferences.weatherLocationSource?.toString() ?? 'null'}");
        } else {
          // This log is requested by the user. It might be similar to an existing one that follows if user is not null.
          if (user != null) { // Check user is not null before logging with user.uid
            debugPrint("ServiceManager - No preferences loaded from Firestore for user ${user.uid}.");
          } else {
            debugPrint("ServiceManager - No preferences loaded from Firestore (user was null).");
          }
        }
        // END DETAILED LOGGING
        if (loadedPreferences != null) {
          apiKey = loadedPreferences.solarEdgeApiKey;
          siteId = loadedPreferences.siteId;
          debugPrint(
              '🔄 ServiceManager: Loaded API keys and preferences from Firestore for user ${user.uid}.');
        } else {
          debugPrint(
              '⚠️ ServiceManager: No user preferences found in Firestore for user ${user.uid}.');
        }
      } else {
        debugPrint(
            '⚠️ ServiceManager: No authenticated user found. Will attempt to load API keys from SharedPreferences.');
      }

      // Si les clés ne sont pas trouvées dans Firestore (ou pas d'utilisateur),
      // tenter de charger depuis SharedPreferences (pour la migration ou si pas d'auth)
      if (apiKey == null ||
          apiKey.isEmpty ||
          siteId == null ||
          siteId.isEmpty) {
        debugPrint(
            '🔄 ServiceManager: API keys not found in Firestore or no user. Attempting to load from SharedPreferences.');
        apiKey = prefs.getString('solaredge_api_key');
        siteId = prefs.getString('solaredge_site_id');
        // Si chargées depuis SharedPreferences, créer un objet UserPreferences minimal pour le ValueNotifier
        if (apiKey != null &&
            apiKey.isNotEmpty &&
            siteId != null &&
            siteId.isNotEmpty) {
          debugPrint(
              '✅ ServiceManager: Loaded API keys from SharedPreferences.');
          // Créer un objet UserPreferences minimal pour le ValueNotifier
          loadedPreferences =
              UserPreferences(solarEdgeApiKey: apiKey, siteId: siteId);
        } else {
          debugPrint(
              '⚠️ ServiceManager: API keys not found in SharedPreferences either.');
          loadedPreferences =
              null; // Assurer que les préférences sont null si les clés manquent
        }
      }

      // Mettre à jour l'instance locale des préférences et notifier le ValueNotifier
      _userPreferences = loadedPreferences;
      _userPreferencesNotifier.value =
          _userPreferences; // Notifier les écouteurs
      debugPrint(
          "DEBUG ServiceManager: _userPreferences updated to ${_userPreferences == null ? 'null' : 'instance'}. Notifier updated.");

      if (apiKey != null &&
          apiKey.isNotEmpty &&
          siteId != null &&
          siteId.isNotEmpty) {
        debugPrint(
            '🔄 ServiceManager: Initializing/Updating SolarEdgeApiService.');
        initializedService = SolarEdgeApiService(
          apiKey: apiKey,
          siteId: siteId,
        );
        success = true; // Supposer succès pour l'instant
      } else {
        debugPrint(
            '⚠️ ServiceManager: Missing API Key or Site ID. SolarEdgeApiService will be null.');
        initializedService = null;
        success = false;
        _userPreferences = null; // Réinitialiser les préférences en cas d'erreur
        _userPreferencesNotifier.value =
            null; // Notifier que les préférences sont nulles
      }
    } catch (e, s) {
      debugPrint(
          '❌ ServiceManager: Error during initializeApiServiceFromPreferences: $e');
      debugPrint('StackTrace: $s');
      initializedService = null;
      success = false;
      _userPreferences = null; // Réinitialiser les préférences en cas d'erreur
      _userPreferencesNotifier.value =
          null; // Notifier que les préférences sont nulles
    }

    // Mettre à jour l'état et notifier seulement si l'état a changé
    if (success != previousConfigState || _apiService != initializedService) {
      _apiService = initializedService;
      _isApiConfigured = success;
      debugPrint(
          "🔄 ServiceManager: _apiService updated to ${initializedService != null ? 'a new instance' : 'null'}. API configured: $_isApiConfigured"); // Added log

      // Mettre à jour le ValueNotifier de l'API
      _apiServiceNotifier.value = _apiService;
      debugPrint(
          "DEBUG ServiceManager: _apiServiceNotifier updated to ${_apiService == null ? 'null' : 'instance'}.");

      // Enregistrer ou remplacer l'instance de SolarEdgeApiService dans GetIt
      if (getIt.isRegistered<SolarEdgeApiService>()) {
        getIt.unregister<SolarEdgeApiService>();
        debugPrint(
            "ℹ️ ServiceManager: Unregistered old SolarEdgeApiService from GetIt.");
      }
      if (_apiService != null) {
        getIt.registerSingleton<SolarEdgeApiService>(_apiService!);
        debugPrint(
            "✅ ServiceManager: Registered new SolarEdgeApiService in GetIt.");
      } else {
        debugPrint(
            "ℹ️ ServiceManager: SolarEdgeApiService is null, not registering in GetIt.");
      }
      debugPrint(
          "✅ ServiceManager: SolarEdgeApiService registered/updated in GetIt.");

      notifyApiConfigChanged(); // Notifier seulement si l'état change
      debugPrint("DEBUG ServiceManager: notifyApiConfigChanged called.");

      // Ajouter un listener pour réagir aux changements de préférences utilisateur (y compris la clé Gemini)
      _userPreferencesNotifier.addListener(_onUserPreferencesChanged);
      debugPrint("✅ Listener ajouté à _userPreferencesNotifier.");

      // Réinitialiser ou mettre à jour AssistantService si la config API change
      // L'AssistantService dépend maintenant du ValueNotifier de l'API, pas de l'instance directe
      // Il n'est donc pas nécessaire de le ré-instancier ici.
      // if (_isApiConfigured &&
      //     _apiService != null &&
      //     _weatherManager != null &&
      //     _prefs != null) { // _prefs est toujours là pour d'autres usages
      //   // Si l'API devient valide
      //   // Ré-enregistrer AssistantService car il dépend de ApiService
      //    if (getIt.isRegistered<AssistantService>()) {
      //      getIt.unregister<AssistantService>();
      //    }
      //   _assistantService = AssistantService(
      //     solarEdgeApiService: _apiService!,
      //     weatherManager: _weatherManager!,
      //     prefs: _prefs!, // Toujours passer prefs si AssistantService en a besoin
      //   );
      //    getIt.registerSingleton<AssistantService>(_assistantService!);
      //   debugPrint(
      //       "🔄 ServiceManager: AssistantService ré-initialisé et ré-enregistré suite à MàJ API (valide).");
      // } else if (!_isApiConfigured && _assistantService != null) {
      //   // Si l'API devient invalide
      //   _assistantService?.clearInsights();
      //   // Optionnel: Désenregistrer AssistantService si l'API est invalide
      //    if (getIt.isRegistered<AssistantService>()) {
      //      getIt.unregister<AssistantService>();
      //    }
      //    _assistantService = null; // Mettre l'instance locale à null
      //   debugPrint("ℹ️ ServiceManager: AssistantService vidé et désenregistré suite à invalidation API.");
      // }
    }

    return _apiService; // Retourner la nouvelle instance (ou null)
  }

  /// Notifie les écouteurs qu'une mise à jour de la configuration API a eu lieu
  void notifyApiConfigChanged() {
    debugPrint(
        '📣 Notification de changement de configuration API -> État configuré: $_isApiConfigured (via ServiceManager)');
    if (!_apiConfigChangedController.isClosed) {
      // Ajouter l'instance actuelle de _apiService au stream
      _apiConfigChangedController.add(_apiService);
    }
  }

  /// Gère les changements dans les préférences utilisateur (appelé par le listener).
  /// Ré-initialise AiService si la clé Gemini change.
  void _onUserPreferencesChanged() {
    debugPrint("DEBUG ServiceManager: _onUserPreferencesChanged called.");
    final getIt = GetIt.I;

    // Récupérer la nouvelle clé Gemini des préférences
    final String? newGeminiApiKey = _userPreferencesNotifier.value?.geminiApiKey;
    final String? currentGeminiApiKey = _aiService?.apiKey; // Supposant que AiService a un getter apiKey

    // Vérifier si la clé a changé
    if (newGeminiApiKey != currentGeminiApiKey) {
      debugPrint("INFO ServiceManager: Gemini API key changed. Re-initializing AiService.");

      // Disposer l'ancienne instance si elle existe
      _aiService?.dispose();
      if (getIt.isRegistered<AiService>()) {
        getIt.unregister<AiService>();
        debugPrint("ℹ️ Ancienne AiService désenregistrée.");
      }
      _aiService = null; // Mettre l'instance locale à null

      // Initialiser une nouvelle instance si la nouvelle clé est valide et les dépendances sont prêtes
      if (newGeminiApiKey != null && newGeminiApiKey.isNotEmpty && _weatherManager != null) {
         _aiService = AiService(
           apiKey: newGeminiApiKey, // Utiliser la nouvelle clé
           apiServiceNotifier: _apiServiceNotifier,
           weatherManager: _weatherManager!,
           userPrefsNotifier: _userPreferencesNotifier,
         );
         getIt.registerSingleton<AiService>(_aiService!);
         debugPrint("✅ Nouvelle AiService initialisée et enregistrée.");
      } else {
         debugPrint("⚠️ AiService non ré-initialisé. Clé manquante ou dépendances non prêtes.");
      }
    } else {
       debugPrint("DEBUG ServiceManager: Gemini API key did not change.");
    }
  }


  /// Nettoie les ressources lors de la fin de l'application
  void dispose() {
    debugPrint("🧹 Disposing ServiceManager...");
    // Retirer le listener avant de disposer le notifier
    _userPreferencesNotifier.removeListener(_onUserPreferencesChanged);
    debugPrint("✅ Listener retiré de _userPreferencesNotifier.");

    if (!_apiConfigChangedController.isClosed) {
      _apiConfigChangedController.close();
      debugPrint("✅ StreamController API fermé.");
    }
    _weatherManager?.dispose();
    _notificationService
        ?.dispose(); // Appeler dispose si notificationService a cette méthode
    _aiService?.dispose(); // Appeler dispose s'il existe
    _userPreferencesNotifier
        .dispose(); // Disposer le ValueNotifier des préférences
    _apiServiceNotifier.dispose(); // Disposer le ValueNotifier de l'API

    // Optionnel: Nettoyer GetIt si nécessaire à la fin de l'application
    // GetIt.I.reset(); // Peut être trop agressif, à utiliser avec prudence
    debugPrint("✅ ServiceManager disposed.");
  }
}
