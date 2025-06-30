import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:solaredge_monitor/data/models/weather_data.dart';
import 'package:solaredge_monitor/data/services/open_meteo_weather_service.dart';
import 'package:solaredge_monitor/data/services/location_service.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Import pour ServiceManager
import 'package:geolocator/geolocator.dart'; // Import pour Geolocator, Position, LocationPermission, LocationAccuracy
// Importer ChangeNotifier
import 'package:flutter/material.dart';

/// Service centralisé pour gérer les données météo dans toute l'application
/// Utilise un pattern Singleton et notifie les changements via ChangeNotifier et Streams
class WeatherManager with ChangeNotifier {
  // --- Singleton ---
  static final WeatherManager _instance = WeatherManager._internal();
  factory WeatherManager() => _instance;
  WeatherManager._internal();

  // --- Dépendances Internes ---
  // Le manager crée et utilise ses propres instances de services dépendants
  final OpenMeteoWeatherService _weatherService = OpenMeteoWeatherService();
  final LocationService _locationService = LocationService();

  // Ajouter une dépendance vers ServiceManager pour accéder facilement aux UserPreferences
  // Cela suppose que WeatherManager est instancié là où il peut recevoir ServiceManager
  // ou y accéder via un singleton/Provider si ce n'est pas déjà le cas.
  // Pour cet exemple, nous allons supposer qu'il peut accéder à ServiceManager.userPreferencesNotifier.value

  final ServiceManager _serviceManager = ServiceManager(); // Accès direct au singleton, à adapter si vous utilisez GetIt différemment.


  // --- État Interne ---
  WeatherData? _currentWeather;
  WeatherForecast?
      _weatherForecastInternal; // Renommé pour éviter confusion avec getter public
  DateTime? _lastWeatherUpdate;
  DateTime? _lastForecastUpdate;
  DateTime? _lastForecastApiCall; // Timestamp of the last actual API call for forecast

  double? _latitude;
  double? _longitude;
  String? _locationSource;

  // Durée de validité du cache
  static const Duration _cacheValidityDuration = Duration(minutes: 15);

  // --- Contrôleurs de Stream (pour compatibilité si des parties de l'app les utilisent encore) ---
  // Note: Avec ChangeNotifier, les Streams deviennent moins essentiels pour l'UI directe via Provider
  late StreamController<WeatherData?> _weatherController;
  late StreamController<WeatherForecast?> _forecastController;
  late StreamController<(double, double)?> _locationController;

  bool _areControllersInitialized = false;
  bool _areControllersClosed = false;

  // --- Streams Publics ---
  Stream<WeatherData?> get weatherStream => _weatherController.stream;
  Stream<WeatherForecast?> get forecastStream => _forecastController.stream;
  Stream<(double, double)?> get locationStream => _locationController.stream;

  // --- Getters Publics (pour l'accès via Provider) ---
  WeatherData? get currentWeather => _currentWeather;
  WeatherForecast? get weatherForecast => _weatherForecastInternal;
  // Exposer la latitude et la longitude
  double? get latitude => _latitude;
  double? get longitude => _longitude;
  String? get locationSource => _locationSource; // Optionnel, mais peut être utile

  // --- Flags de Chargement ---
  bool _isLoadingWeather = false;
  bool _isLoadingForecast = false;
  bool _isLoadingLocation = false;
  // Getter pour l'état de chargement global (optionnel)
  bool get isLoading =>
      _isLoadingWeather || _isLoadingForecast || _isLoadingLocation;


  /// Initialise le service et charge les données nécessaires.
  /// Appelé une fois par ServiceManager.
  Future<void> initialize() async {
    // Évite les ré-initialisations multiples si déjà fait
    if (_areControllersInitialized) return;

    debugPrint('🌤️ Initialisation du WeatherManager...');
    _initStreamControllers();
    await loadLocation(isInitializing: true);
    // Charger les données sans forcer le refresh au démarrage
    // Les méthodes appelées vont notifier si des données sont chargées
    await getCurrentWeather(forceRefresh: false, isInitializing: true);
    await getWeatherForecast(forceRefresh: false, isInitializing: true);
    debugPrint('✅ WeatherManager initialisé.');
  }

  /// Initialise les contrôleurs de flux de manière sûre.
  void _initStreamControllers() {
    // Si déjà initialisés et non fermés, ne rien faire
    if (_areControllersInitialized && !_areControllersClosed) return;

    // (Ré)Initialiser les contrôleurs
    _weatherController = StreamController<WeatherData?>.broadcast();
    _forecastController = StreamController<WeatherForecast?>.broadcast();
    _locationController = StreamController<(double, double)?>.broadcast();

    _areControllersInitialized = true;
    _areControllersClosed = false; // Marquer comme ouverts
    debugPrint('📊 WeatherManager: StreamControllers initialisés.');
  }

  /// Charge les coordonnées de localisation (depuis cache ou appareil) en fonction de la préférence utilisateur.
  Future<void> loadLocation({bool isInitializing = false}) async {
    if (_isLoadingLocation && !isInitializing) return;
    _isLoadingLocation = true;
    if (!isInitializing) {
      notifyListeners(); // Notifier que le chargement commence
    }

    // Récupérer les préférences utilisateur
    // Note: Assurez-vous que _serviceManager est initialisé et accessible.
    final userPrefs = _serviceManager.userPreferencesNotifier.value;
    final weatherSourcePref = userPrefs?.weatherLocationSource ?? 'site_primary';

    debugPrint('🌦️ WeatherManager: loadLocation - Préférence source météo: $weatherSourcePref');

    try {
      if (weatherSourcePref == 'device_gps') {
        debugPrint('🌍 WeatherManager: Tentative de récupération de la position GPS de l\'appareil pour la météo...');
        // Vérifier la permission
        // Note: Geolocator est nécessaire ici. Assurez-vous qu'il est importé et configuré.
        // import 'package:geolocator/geolocator.dart';
        // import 'package:geolocator_platform_interface/geolocator_platform_interface.dart'; // Peut être nécessaire pour LocationPermission
        // Si vous n'avez pas Geolocator, vous devrez l'ajouter à pubspec.yaml
        // Pour l'exemple, je vais ajouter l'import ici, mais vous devrez l'installer si ce n'est pas fait.
        // import 'package:geolocator/geolocator.dart'; // Assurez-vous que cet import est présent

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
            debugPrint('❌ WeatherManager: Permission GPS refusée.');
            // Fallback sur les coordonnées du site si GPS refusé
            await _loadSitePrimaryCoordinates();
            return; // Sortir après le fallback
          }
        }

        if (permission == LocationPermission.deniedForever) {
             debugPrint('❌ WeatherManager: Permission GPS refusée définitivement.');
            await _loadSitePrimaryCoordinates();
            return;
        }

        final Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationSource = LocationService.sourceDeviceLocation;
        debugPrint('✅ WeatherManager: Coordonnées GPS obtenues pour la météo: $_latitude, $_longitude');
        _safeAdd(_locationController, (_latitude!, _longitude!));
      } else { // 'site_primary' ou autre (par défaut)
        await _loadSitePrimaryCoordinates();
      }
    } catch (e) {
      debugPrint('❌ WeatherManager: Erreur chargement coordonnées pour la météo: $e. Fallback sur les coordonnées du site.');
      // En cas d'erreur (ex: GPS désactivé), fallback sur les coordonnées du site
      await _loadSitePrimaryCoordinates();
    } finally {
      _isLoadingLocation = false;
      // Notifier la fin du chargement, même si pas de changement,
      // pour que l'UI puisse réagir à la fin de l'indicateur de chargement.
      // Ne notifier que si ce n'est PAS l'initialisation
      if (!isInitializing) {
        notifyListeners();
      }
    }
  }

  // Nouvelle méthode helper pour charger les coordonnées primaires du site
  Future<void> _loadSitePrimaryCoordinates() async {
    debugPrint('🌍 WeatherManager: Chargement des coordonnées principales du site pour la météo...');
    final (latitude, longitude, source) = await _locationService.getSavedCoordinates();

    if (latitude != null && longitude != null) {
      if (_latitude != latitude || _longitude != longitude || _locationSource != source) {
        _latitude = latitude;
        _longitude = longitude;
        _locationSource = source;
        debugPrint(
            '✅ WeatherManager: Coordonnées principales du site chargées pour la météo: $_latitude, $_longitude (source: $_locationSource)');
        _safeAdd(_locationController, (_latitude!, _longitude!));
      }
    } else {
      _latitude = _latitude ?? 48.8566;
      _longitude = _longitude ?? 2.3522;
      _locationSource = _locationSource ?? LocationService.sourceDefault;
      debugPrint(
          '⚠️ WeatherManager: Aucune coordonnée principale trouvée, utilisation des valeurs de fallback pour la météo.');
      _safeAdd(_locationController, (_latitude!, _longitude!));
    }
  }


  /// Vérifie si les données en cache sont encore valides.
  bool _isCacheValid(DateTime? lastUpdate) {
    if (lastUpdate == null) return false;
    return DateTime.now().difference(lastUpdate) < _cacheValidityDuration;
  }

  /// Récupère les données météo actuelles.
  Future<WeatherData?> getCurrentWeather({bool forceRefresh = true, bool isInitializing = false}) async {
    // Utiliser le cache si valide et non forcé
    if (!forceRefresh &&
        _isCacheValid(_lastWeatherUpdate) &&
        _currentWeather != null) {
      debugPrint('🌤️ WeatherManager: Utilisation météo cache.');
      return _currentWeather;
    }

    // Éviter les appels multiples
    if (_isLoadingWeather) {
      debugPrint('⏳ WeatherManager: Chargement météo déjà en cours...');
      return _currentWeather;
    }
    _isLoadingWeather = true;
    if (!isInitializing) {
      notifyListeners(); // Notifier début chargement
    }

    WeatherData? resultData =
        _currentWeather; // Garder les anciennes données en cas d'erreur

    try {
      // S'assurer d'avoir des coordonnées
      if (_latitude == null || _longitude == null) await loadLocation(isInitializing: isInitializing);
      if (_latitude == null || _longitude == null) {
        throw Exception("Coordonnées non disponibles pour getCurrentWeather");
      }

      debugPrint(
          '🔄 WeatherManager: Rafraîchissement météo pour: $_latitude, $_longitude');
      final weatherData =
          await _weatherService.getCurrentWeather(_latitude!, _longitude!);

      // Mettre à jour l'état interne
      _currentWeather = weatherData;
      _lastWeatherUpdate = DateTime.now();
      resultData = weatherData; // Mettre à jour le résultat

      _safeAdd(_weatherController, _currentWeather); // Notifier les streams
      debugPrint(
          '✅ WeatherManager: Météo MàJ: ${weatherData.temperature}°C, ${weatherData.condition}');
    } catch (e) {
      debugPrint('❌ WeatherManager: Erreur récupération météo: $e');
      // En cas d'erreur, on garde resultData qui contient les anciennes données (ou null)
    } finally {
      _isLoadingWeather = false;
      // Notifier la fin du chargement (potentiellement avec de nouvelles données ou les anciennes)
      if (!isInitializing) {
        notifyListeners();
      }
    }
    return resultData;
  }

  /// Récupère les prévisions météo.
  Future<WeatherForecast?> getWeatherForecast(
      {bool forceRefresh = true, bool isInitializing = false}) async {
    final now = DateTime.now();
    // 1. Utiliser le cache interne si valide et non forcé
    if (!forceRefresh &&
        _isCacheValid(_lastForecastUpdate) &&
        _weatherForecastInternal != null) {
      debugPrint('🌤️ WeatherManager: Utilisation prévisions cache (validité interne).');
      _safeAdd(_forecastController, _weatherForecastInternal); // <--- AJOUTEZ CETTE LIGNE
      return _weatherForecastInternal;
    }

    // 2. Éviter les appels API trop rapprochés (même si forceRefresh=true)
    //    pour éviter le spamming du bouton par exemple.
    const Duration minIntervalBetweenApiCall = Duration(minutes: 2);
    if (_lastForecastApiCall != null && now.difference(_lastForecastApiCall!) < minIntervalBetweenApiCall) {
   debugPrint('🌤️ WeatherManager: Appel API prévisions récent (< ${minIntervalBetweenApiCall.inMinutes} min), utilisation données actuelles/cache.');
   if (_weatherForecastInternal != null) { // Vérifier si des données existent avant de les pousser
     _safeAdd(_forecastController, _weatherForecastInternal); // <--- AJOUTEZ CETTE LIGNE (avec vérification)
   }
   return _weatherForecastInternal;
}


    // 3. Éviter les appels multiples si déjà en cours
    if (_isLoadingForecast) {
      debugPrint('⏳ WeatherManager: Chargement prévisions déjà en cours...');
      return _weatherForecastInternal;
    }
    _isLoadingForecast = true;
    if (!isInitializing) {
      notifyListeners(); // Notifier début chargement
    }

    WeatherForecast? resultForecast = _weatherForecastInternal;

    try {
      // S'assurer d'avoir des coordonnées
      if (_latitude == null || _longitude == null) await loadLocation(isInitializing: isInitializing);
      if (_latitude == null || _longitude == null) {
        throw Exception("Coordonnées non disponibles pour getWeatherForecast");
      }

      debugPrint(
          '🔄 WeatherManager: Rafraîchissement prévisions API pour: $_latitude, $_longitude');
      final forecast =
          await _weatherService.getWeatherForecast(_latitude!, _longitude!);

      // Mettre à jour l'état interne
      _weatherForecastInternal = forecast;
      _lastForecastUpdate = now; // Utiliser 'now' défini au début
      _lastForecastApiCall = now; // Mettre à jour le timestamp du dernier appel API EFFECTIF
      resultForecast = forecast;

      _safeAdd(_forecastController,
          _weatherForecastInternal); // Notifier les streams
      debugPrint(
          '✅ WeatherManager: Prévisions MàJ via API: ${forecast.hourlyForecast.length}h, ${forecast.dailyForecast.length}j');
    } catch (e) {
      debugPrint('❌ WeatherManager: Erreur récupération prévisions: $e');
    } finally {
      _isLoadingForecast = false;
      // Notifier la fin du chargement
      if (!isInitializing) {
        // Différer la notification à la fin du frame courant
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      }
    }
    return resultForecast;
  }

  /// Obtient les prévisions historiques pour une date spécifique (ne notifie pas les listeners).
  Future<WeatherData?> getHistoricalWeather(DateTime date) async {
    // Pas de gestion de cache ou d'état de chargement ici car c'est un appel ponctuel
    try {
      if (_latitude == null || _longitude == null) await loadLocation();
      if (_latitude == null || _longitude == null) {
        throw Exception(
            "Coordonnées non disponibles pour getHistoricalWeather");
      }
      return await _weatherService.getHistoricalWeather(
          _latitude!, _longitude!, date);
    } catch (e) {
      debugPrint('❌ WeatherManager: Erreur récupération historique: $e');
      return null;
    }
  }

  /// Met à jour les coordonnées et rafraîchit les données météo si la localisation change.
  Future<void> updateLocationAndWeather() async { // Renommer ou créer une nouvelle méthode si besoin
    // Cette méthode est appelée quand la préférence de source météo change dans SettingsScreen
    // ou quand la localisation principale change dans LocationConfigurationScreen.
    // Elle doit recharger la localisation en fonction de la préférence, PUIS la météo.
    debugPrint('🔄 WeatherManager: updateLocationAndWeather called.');
    await loadLocation(); // loadLocation lit maintenant la préférence et charge les bonnes coordonnées

    // Si la localisation a effectivement changé ou si forcé, rafraîchir la météo
    if (_latitude != null && _longitude != null) { // Assurez-vous que les coordonnées sont valides
      await getCurrentWeather(forceRefresh: true);
      await getWeatherForecast(forceRefresh: true);
      debugPrint('🔄 WeatherManager: Location and weather data refreshed.');
    } else {
      debugPrint('⚠️ WeatherManager: updateLocationAndWeather - Coordonnées non valides, météo non rafraîchie.');
    }
  }


  /// Méthode sécurisée pour ajouter aux StreamControllers.
  void _safeAdd<T>(StreamController<T> controller, T data) {
    if (_areControllersClosed) {
      debugPrint(
          "⚠️ WeatherManager: Tentative d'ajout à un StreamController après dispose().");
      return;
    }
    // Assurer l'initialisation si elle n'a pas eu lieu (sécurité)
    if (!_areControllersInitialized) _initStreamControllers();

    if (!controller.isClosed) {
      controller.add(data);
    } else {
      debugPrint(
          "⚠️ WeatherManager: Tentative d'ajout à un StreamController déjà fermé.");
    }
  }

  /// Nettoie les ressources (StreamControllers).
  @override
  void dispose() {
    debugPrint("🧹 Disposing WeatherManager...");
    if (!_areControllersClosed && _areControllersInitialized) {
      try {
        _weatherController.close();
        _forecastController.close();
        _locationController.close();
        _areControllersClosed = true; // Marquer comme fermé
        debugPrint('📊 WeatherManager: StreamControllers fermés.');
      } catch (e) {
        debugPrint('❌ WeatherManager: Erreur fermeture StreamControllers: $e');
      }
    }
    super.dispose(); // Important pour ChangeNotifier
    debugPrint("✅ WeatherManager disposed.");
  }
}
