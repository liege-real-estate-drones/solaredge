import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/data/models/user_preferences.dart';
// --- IMPORTATION REQUISE (Vérifiée comme présente) ---
import 'package:solaredge_monitor/data/models/weather_data.dart';
// -----------------------------------------
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/data/services/weather_manager.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:solaredge_monitor/presentation/pages/api_configuration_screen.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:solaredge_monitor/presentation/widgets/power_gauge_widget.dart';
import 'package:solaredge_monitor/presentation/widgets/weather_info_widget.dart';
import 'package:solaredge_monitor/utils/power_utils.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Import ServiceManager

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  SolarData? _currentPowerData;
  WeatherData? _currentWeather; // Données météo actuelles
  WeatherForecast? _weatherForecast; // Prévisions météo
  DailySolarData? _todayData;
  List<SolarData>?
      _yesterdayPowerDetails; // Nouvelle variable pour les détails de puissance d'hier
  Timer? _refreshTimer;
  Timer? _clockTimer; // Timer pour l'horloge
  DateTime _currentTime = DateTime.now(); // Heure actuelle
  bool _isLoading = true; // Commence en chargement
  bool _hasError = false;
  String _errorMessage = '';
  late AnimationController _animationController;
  bool get _hasInitialData =>
      _currentPowerData != null &&
      _currentWeather != null &&
      _todayData != null &&
      _yesterdayPowerDetails != null &&
      _weatherForecast != null;
  // Supprimer _solarEdgeServiceInstance; // Ne plus stocker l'instance localement

  // Gestionnaire de météo centralisé
  late WeatherManager _weatherManager;
  StreamSubscription? _weatherSubscription;
  // Supprimer _apiServiceSubscription

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    // Initialiser l'horloge qui se met à jour chaque minute
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });

    // Configurer une mise à jour périodique des données
    _refreshTimer = Timer.periodic(const Duration(minutes: 15), (timer) {
      // Obtenir l'instance du service API via le Provider pour le rafraîchissement
      final solarEdgeService =
          Provider.of<SolarEdgeApiService?>(context, listen: false);
      if (solarEdgeService != null) {
        _loadData(solarEdgeService);
      } else {
        debugPrint(
            'Timer: Service API non disponible pour le rafraîchissement périodique.');
      }
    });

    // Déclencher le chargement initial si le service API est déjà disponible
    final initialApiService =
        Provider.of<ValueNotifier<SolarEdgeApiService?>>(context, listen: false)
            .value;
    if (initialApiService != null) {
      debugPrint(
          "INFO HomeScreen: API Service available in initState. Will wait for didChangeDependencies to load data.");
      // Retiré l'appel à unawaited(_loadData(initialApiService));
    } else {
      debugPrint(
          "INFO HomeScreen: API Service not available in initState. Will wait for didChangeDependencies.");
      // Si le service n'est pas disponible en initState, on s'assure que _isLoading est false
      // pour que la vue de configuration s'affiche si nécessaire, ou que didChangeDependencies
      // puisse déclencher le chargement plus tard.
      // Cependant, l'état initial est déjà _isLoading = true, ce qui est correct pour afficher le chargement.
      // On ne change pas _isLoading ici pour éviter un flash de l'écran de config si le service arrive vite.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint("DEBUG HomeScreen: didChangeDependencies called.");

    // Initialiser le WeatherManager et s'abonner ici
    // car context est disponible de manière fiable
    if (_weatherSubscription == null) {
      _weatherManager = Provider.of<WeatherManager>(context, listen: false);
      _weatherSubscription =
          _weatherManager.weatherStream.listen((weatherData) {
        if (weatherData != null && mounted) {
          setState(() {
            _currentWeather = weatherData;
          });
        }
      });
      // Charger la météo initiale après le frame actuel
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _weatherManager.getCurrentWeather(forceRefresh: true);
      });
      debugPrint(
          "DEBUG HomeScreen: WeatherManager initialized and subscribed.");
    }

    // Réagir aux changements du service API via le ValueNotifier
    final solarEdgeService =
        Provider.of<ValueNotifier<SolarEdgeApiService?>>(context)
            .value; // Lire la valeur du notifier

    // Obtenir l'ancienne instance du service API si elle existait avant ce didChangeDependencies
    // On utilise listen: false pour ne pas déclencher didChangeDependencies à nouveau juste pour ça
    final oldApiService =
        Provider.of<ValueNotifier<SolarEdgeApiService?>>(context, listen: false)
            .value;

    // Logique pour gérer les changements du service API
    if (solarEdgeService != oldApiService) {
      debugPrint(
          "INFO HomeScreen: API Service instance changed in didChangeDependencies.");
      if (solarEdgeService != null) {
        // Si le nouveau service est disponible, déclencher un nouveau chargement de données
        debugPrint(
            "INFO HomeScreen: New API Service available. Triggering data load.");
        // Réinitialiser l'état pour montrer le chargement et déclencher le chargement
        if (mounted) {
          setState(() {
            _currentPowerData = null;
            _currentWeather = null;
            _todayData = null;
            _isLoading = true; // Important: Repasser en chargement
            _hasError = false;
            _errorMessage = '';
          });
          // Déclencher le chargement des données immédiatement après la mise à jour de l'état
          unawaited(_loadData(solarEdgeService));
        }
      } else {
        // Si le service devient null, réinitialiser l'état et afficher la vue de configuration nécessaire
        debugPrint(
            "INFO HomeScreen: API Service became null. Resetting data and showing config view.");
        if (mounted) {
          setState(() {
            _currentPowerData = null;
            _currentWeather = null; // Clear weather data too
            _todayData = null;
            _isLoading = false; // Stop loading
            _hasError = true; // Indicate error/config needed
            _errorMessage =
                'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
          });
        }
      }
    } else {
      // Si le service API n'a pas changé, vérifier si les données doivent être chargées (ex: premier démarrage)
      // S'assurer que le WeatherManager est aussi initialisé avant de charger les données complètes
      if (solarEdgeService != null &&
          _weatherManager != null &&
          _currentPowerData == null &&
          !_hasError) {
        // Removed !_isLoading condition here
        debugPrint(
            "INFO HomeScreen: API Service and WeatherManager available but data missing (initial load?). Triggering data load.");
        // Réinitialiser l'état pour montrer le chargement
        if (mounted) {
          setState(() {
            _isLoading = true; // Important: Repasser en chargement
            _hasError = false;
            _errorMessage = '';
          });
          // Déclencher le chargement des données immédiatement après la mise à jour de l'état
          unawaited(_loadData(solarEdgeService));
        }
      } else {
        debugPrint(
            "DEBUG HomeScreen: didChangeDependencies: API Service unchanged or WeatherManager not ready, no data load triggered.");
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _clockTimer?.cancel();
    _weatherSubscription?.cancel();
    // Supprimer l'annulation de _apiServiceSubscription
    _animationController.dispose();
    super.dispose();
  }

  // Charger toutes les données nécessaires (prend le service en argument)
  Future<void> _loadData(SolarEdgeApiService solarEdgeService) async {
    debugPrint("DEBUG HomeScreen:_loadData: Début du chargement des données.");
    if (!mounted) {
      debugPrint("DEBUG HomeScreen:_loadData: Widget non monté, retour.");
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    debugPrint("DEBUG HomeScreen:_loadData: isLoading mis à true.");

    try {
      debugPrint("INFO HomeScreen: Chargement des données SolarEdge...");
      // Charger les données SolarEdge en utilisant le service fourni
      final powerDataFuture = solarEdgeService.getCurrentPowerData();
      final todayDataFuture = solarEdgeService.getDailyEnergy(DateTime.now());

      // Récupérer les données de puissance d'hier UNIQUEMENT si elles ne sont pas déjà chargées
      Future<List<SolarData>?> yesterdayPowerDetailsFuture;
      if (_yesterdayPowerDetails == null) {
        debugPrint("INFO HomeScreen: Chargement des détails de puissance d'hier (première fois).");
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        yesterdayPowerDetailsFuture =
            solarEdgeService.getPowerDetailsForDate(yesterday);
      } else {
        debugPrint("INFO HomeScreen: Détails de puissance d'hier déjà chargés, pas de nouvel appel.");
        yesterdayPowerDetailsFuture = Future.value(_yesterdayPowerDetails); // Retourner la valeur existante
      }


      // Récupérer les prévisions météo
      final weatherForecastFuture = _weatherManager.getWeatherForecast(
          forceRefresh: true); // Forcer le refresh pour les prévisions

      debugPrint("DEBUG HomeScreen:_loadData: Appels API lancés.");

      // Attendre que toutes les requêtes soient terminées
      final results = await Future.wait([
        powerDataFuture,
        todayDataFuture,
        yesterdayPowerDetailsFuture, // Attendre aussi les données d'hier (conditionnel)
        weatherForecastFuture, // Attendre aussi les prévisions météo
      ]);
      debugPrint("DEBUG HomeScreen:_loadData: Appels API terminés.");

      debugPrint("INFO HomeScreen: Données SolarEdge et Météo chargées.");
      // Mettre à jour l'état avec les nouvelles données
      if (mounted) {
        setState(() {
          _currentPowerData = results[0] as SolarData;
          _todayData = results[1] as DailySolarData;
          // Mettre à jour _yesterdayPowerDetails UNIQUEMENT si elles ont été chargées (results[2] ne sera pas null si la future a été créée)
          if (_yesterdayPowerDetails == null) {
             _yesterdayPowerDetails = results[2] as List<SolarData>; // Stocker les données d'hier
          }
          _weatherForecast =
              results[3] as WeatherForecast?; // Stocker les prévisions météo
          _currentTime =
              DateTime.now(); // Mettre à jour l'heure de la dernière maj
          _isLoading = false;
          debugPrint(
              "DEBUG HomeScreen:_loadData: isLoading mis à false, données mises à jour.");

          // Démarrer l'animation
          _animationController.forward(from: 0.0);
        });
      } else {
        debugPrint(
            "DEBUG HomeScreen:_loadData: Widget non monté après appels API, impossible de mettre à jour l'état.");
      }
    } catch (e) {
      debugPrint(
          "ERROR HomeScreen: Erreur lors du chargement des données SolarEdge ou Météo: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = e.toString();
          debugPrint(
              "DEBUG HomeScreen:_loadData: isLoading mis à false, erreur enregistrée.");
        });
      } else {
        debugPrint(
            "DEBUG HomeScreen:_loadData: Widget non monté après erreur, impossible de mettre à jour l'état.");
      }
    }
    debugPrint("DEBUG HomeScreen:_loadData: Fin du chargement des données.");
  }

  @override
  Widget build(BuildContext context) {
    // Écouter le service API ici en accédant à la valeur du ValueNotifier
    final solarEdgeService =
        Provider.of<ValueNotifier<SolarEdgeApiService?>>(context).value;
    // Obtenir l'instance du ServiceManager pour vérifier l'état de configuration
    final serviceManager = Provider.of<ServiceManager>(context, listen: false);

    // Écouter les changements dans les préférences utilisateur
    final userPreferencesNotifier =
        Provider.of<ValueNotifier<UserPreferences?>>(context,
            listen: true); // <-- listen: true ajouté
    final userPreferences = userPreferencesNotifier.value;

    Widget body;

    if (solarEdgeService == null) {
      // Clé / ID pas encore configurés
      body =
          _isLoading ? _buildLoadingView() : _buildApiConfigurationNeededView();
    } else if (_hasError) {
      body = _buildErrorView();
    } else if (!_hasInitialData) {
      // Premier chargement complet : écran plein
      body = _buildLoadingView();
    } else {
      // Données déjà présentes — on laisse l’UI affichée,
      // mais on montre un petit loader lorsqu’un refresh est en cours
      body = Stack(
        children: [
          _buildContentView(),
          if (_isLoading)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('SolarEdge Monitor'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          // Afficher l'heure actuelle dans l'appbar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Center(
              child: Text(
                DateFormat('HH:mm').format(_currentTime),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              Navigator.of(context).pushNamed('/notifications');
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).pushNamed('/settings');
            },
          ),
        ],
      ),
      body: body, // Utiliser le widget body déterminé ci-dessus
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0, // L'index Home est sélectionné
        onDestinationSelected: (index) {
          // Naviguer vers les autres écrans quand les onglets sont cliqués
          switch (index) {
            case 0:
              // Home déjà sélectionné
              break;
            case 1:
              Navigator.of(context).pushNamed('/daily', arguments: {'selectedDate': DateTime.now()});
              break;
            case 2:
              Navigator.of(context).pushNamed('/monthly');
              break;
            case 3:
              Navigator.of(context).pushNamed('/yearly');
              break;
            case 4:
              Navigator.of(context).pushNamed('/ai_assistant');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today),
            label: 'Jour',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Mois',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_available_outlined),
            selectedIcon: Icon(Icons.event_available),
            label: 'Année',
          ),
          NavigationDestination(
            icon: Icon(Icons.assistant_outlined),
            selectedIcon: Icon(Icons.assistant),
            label: 'Assistant',
          ),
        ],
      ),
    );
  }

  // Construire l'écran de chargement
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
          ),
          const SizedBox(height: 20),
          const Text(
            'Chargement des données...',
            style: TextStyle(
              color: AppTheme.textSecondaryColor,
              fontSize: 16,
            ),
          ),
          Text(
            DateFormat('HH:mm:ss').format(_currentTime),
            style: const TextStyle(
              color: AppTheme.textSecondaryColor,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // Construire la vue indiquant que la configuration API est nécessaire
  Widget _buildApiConfigurationNeededView() {
    return ApiConfigurationScreen(
      errorMessage:
          'Veuillez configurer votre clé API SolarEdge et l\'ID de votre site.',
      onRetry: () async {
        // Rendre async car initializeApiServiceFromPreferences est async
        // Tenter de réinitialiser le service API via ServiceManager
        setState(() {
          _isLoading = true; // Repasser en chargement
          _hasError = false;
        });
        // Obtenir l'instance du ServiceManager
        final serviceManager =
            Provider.of<ServiceManager>(context, listen: false);
        // Appeler la méthode pour initialiser le service API depuis les préférences
        await serviceManager.initializeApiServiceFromPreferences();
        // Le listener dans main.dart mettra à jour le ValueNotifier,
        // ce qui déclenchera didChangeDependencies et le chargement des données si l'API est valide.
      },
      isApiKeyMissing: true,
    );
  }

  // Construire la vue en cas d'erreur (autre que config manquante)
  Widget _buildErrorView() {
    // Détecter si l'erreur est liée à une clé API invalide (différent de manquante)
    bool isApiConfigError = false;
    String cleanErrorMessage = _errorMessage;

    if (_errorMessage.contains('SolarEdgeApiException')) {
      if (_errorMessage.contains('INVALID_API_KEY')) {
        isApiConfigError = true;
        cleanErrorMessage =
            'Votre clé API SolarEdge est invalide ou a expiré. Veuillez la vérifier dans les paramètres.';
      } else if (_errorMessage.contains('INVALID_SITE_ID')) {
        isApiConfigError = true;
        cleanErrorMessage =
            'L\'ID de site SolarEdge est invalide. Veuillez le vérifier dans les paramètres.';
      }
      // Garder le message d'erreur réseau ou autre tel quel
    }

    // Si c'est une erreur de config (clé/ID invalide), rediriger vers l'écran de config
    if (isApiConfigError) {
      return ApiConfigurationScreen(
        errorMessage: cleanErrorMessage,
        onRetry: () {
          // Tenter de recharger les données (didChangeDependencies devrait détecter le nouveau service)
          setState(() {
            _isLoading = true; // Repasser en chargement
            _hasError = false;
          });
          // didChangeDependencies sera appelé après setState
        },
        isApiKeyMissing:
            false, // Indiquer que la clé/ID existe mais est peut-être invalide
      );
    }

    // Afficher l'écran d'erreur générique pour les autres types d'erreurs (ex: réseau)
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.red,
              size: 60,
            ),
            const SizedBox(height: 20),
            const Text(
              'Erreur de chargement des données',
              style: TextStyle(
                color: AppTheme.textPrimaryColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              cleanErrorMessage, // Afficher le message d'erreur réseau ou autre
              style: const TextStyle(
                color: AppTheme.textSecondaryColor,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                // Action pour le bouton Réessayer de l'erreur générique
                // Obtenir l'instance du service API via le Provider pour le rafraîchissement
                final solarEdgeService =
                    Provider.of<SolarEdgeApiService?>(context, listen: false);
                if (solarEdgeService != null) {
                  _loadData(solarEdgeService);
                } else {
                  // Si le service est toujours null, forcer un recheck dans didChangeDependencies
                  setState(() {
                    _isLoading = true;
                    _hasError = false;
                  });
                  // didChangeDependencies sera appelé après setState
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Construire la vue principale avec les données
  Widget _buildContentView() {
    // Vérifier si toutes les données sont disponibles (le service est forcément non-null ici)
    if (_currentPowerData == null ||
        _currentWeather == null ||
        _todayData == null ||
        _yesterdayPowerDetails == null || // Vérifier aussi les données d'hier
        _weatherForecast == null) {
      // Vérifier aussi les prévisions météo
      // Si on arrive ici alors que _isLoading est false, c'est un état inattendu
      // Afficher chargement par sécurité
      return _buildLoadingView();
    }

    final powerData = _currentPowerData!;
    final currentWeather = _currentWeather!; // Données météo actuelles
    final weatherForecast = _weatherForecast!; // Prévisions météo
    final todayData = _todayData!;
    final yesterdayPowerDetails = _yesterdayPowerDetails!; // Données d'hier

    // Formater les données
    final currentPower = powerData
        .power; // Valeur en W (déjà convertie dans SolarEdgeApiService)
    final totalEnergyToday = todayData.totalEnergy / 1000; // Convertir en kWh

    // Obtenir la puissance maximale de l'installation depuis les UserPreferences (Firestore)
    final userPreferencesNotifier =
        Provider.of<ValueNotifier<UserPreferences?>>(context);
    final userPreferences = userPreferencesNotifier.value;
    // Utiliser la puissance crête des préférences, avec une valeur par défaut si non définie
    final peakPowerKw =
        userPreferences?.peakPowerKw ?? 10.0; // Valeur par défaut: 10kW

    // Convertir en W pour l'affichage
    final maxPowerW = peakPowerKw * 1000; // Conversion kW -> W

    // Calculer le pourcentage par rapport à la puissance maximale
    // Gérer la division par zéro si maxPowerW est 0 ou négatif
    final powerPercent =
        (maxPowerW > 0) ? (currentPower / maxPowerW).clamp(0.0, 1.0) : 0.0;

    // --- Calcul de la production d'yesterday à l'heure actuelle ---
    double totalEnergyYesterdayUntilNow = 0;
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1);

    // Vérifier si les données d'yesterday sont disponibles
    if (yesterdayPowerDetails.isNotEmpty) {
      // Parcourir les données de puissance d'yesterdayPowerDetails
      for (var dataPoint in yesterdayPowerDetails) {
        // Créer un DateTime pour le point de données d'yesterday avec l'année, le mois et le jour d'yesterday,
        // mais l'heure et la minute du point de données.
        final dataPointTime = DateTime(
          yesterday.year,
          yesterday.month,
          yesterday.day,
          dataPoint.timestamp.hour,
          dataPoint.timestamp.minute,
          dataPoint.timestamp.second,
        );

        // Si le timestamp du point de données d'yesterday est avant ou égal à l'heure actuelle d'aujourd'hui
        if (dataPointTime.isBefore(now) ||
            dataPointTime.isAtSameMomentAs(now)) {
          // Estimer l'énergie produite pendant l'intervalle.
          // L'API powerDetails donne la puissance instantanée à un timestamp.
          // Pour estimer l'énergie sur un intervalle, on peut prendre la moyenne de la puissance
          // entre deux points consécutifs et multiplier par la durée de l'intervalle.
          // Ou, plus simplement pour une estimation rapide, on peut considérer que la valeur
          // de puissance est représentative de l'intervalle précédent ou suivant.
          // L'API SolarEdge powerDetails a généralement une granularité de 15 minutes.
          // On peut donc considérer que la puissance à un point T est la puissance moyenne
          // sur les 15 minutes précédant T.
          // L'énergie (Wh) = Puissance (W) * Durée (h)
          // Pour un intervalle de 15 minutes (0.25h), l'énergie est Puissance * 0.25
          // On va cumuler l'énergie estimée pour chaque point de données jusqu'à l'heure actuelle.

          // Trouver l'index du point de données actuel
          final index = yesterdayPowerDetails.indexOf(dataPoint);
          if (index > 0) {
            // Calculer la durée entre ce point et le précédent
            final previousDataPoint = yesterdayPowerDetails[index - 1];
            final duration =
                dataPoint.timestamp.difference(previousDataPoint.timestamp);
            // Utiliser la puissance moyenne de l'intervalle (moyenne entre le point actuel et le précédent)
            final averagePower =
                (dataPoint.power + previousDataPoint.power) / 2;
            // Calculer l'énergie pour cet intervalle en Wh
            final energyInWh = averagePower * duration.inMinutes / 60;
            totalEnergyYesterdayUntilNow += energyInWh;
          } else {
            // Pour le premier point, on peut estimer l'énergie sur l'intervalle
            // entre le début de la journée (ou le premier point) et ce point.
            // Si le premier point n'est pas à 00:00, c'est une approximation.
            // On peut utiliser la puissance du premier point et une durée estimée (ex: 15 min si c'est la granularité typique)
            if (yesterdayPowerDetails.length > 1) {
              final nextDataPoint = yesterdayPowerDetails[index + 1];
              final duration =
                  nextDataPoint.timestamp.difference(dataPoint.timestamp);
              final energyInWh = dataPoint.power * duration.inMinutes / 60;
              totalEnergyYesterdayUntilNow += energyInWh;
            } else {
              // Si un seul point, difficile d'estimer l'énergie. On peut l'ignorer ou utiliser une durée par défaut.
            }
          }
        } else {
          // Si le timestamp du point de données d'yesterday est après l'heure actuelle d'aujourd'hui, on arrête.
          break;
        }
      }
    }
    // Convertir l'énergie cumulée d'yesterday en kWh
    totalEnergyYesterdayUntilNow /= 1000; // Wh -> kWh

    // Calculer la différence de production
    final energyDifference = totalEnergyToday - totalEnergyYesterdayUntilNow;
    final differencePercentage = (totalEnergyYesterdayUntilNow > 0)
        ? (energyDifference / totalEnergyYesterdayUntilNow) * 100
        : (totalEnergyToday > 0
            ? 100.0 // Si hier = 0 et aujourd'hui > 0, c'est 100% d'augmentation (ou infini)
            : 0.0); // Si hier = 0 et aujourd'hui = 0, c'est 0% de différence

    String insightText;
    IconData insightIcon;
    Color insightColor;

    if (yesterdayPowerDetails.isEmpty) {
      insightText =
          'Données de production d\'hier non disponibles pour comparaison.';
      insightIcon = Icons.info_outline;
      insightColor = Colors.grey;
    } else if (energyDifference > 0) {
      insightText =
          'Production aujourd\'hui (${totalEnergyToday.toStringAsFixed(2)} kWh) est ${differencePercentage.toStringAsFixed(1)}% supérieure à hier (${totalEnergyYesterdayUntilNow.toStringAsFixed(2)} kWh).';
      insightIcon = Icons.trending_up;
      insightColor = Colors.green; // Vert pour une meilleure production
    } else if (energyDifference < 0) {
      insightText =
          'Production aujourd\'hui (${totalEnergyToday.toStringAsFixed(2)} kWh) est ${differencePercentage.abs().toStringAsFixed(1)}% inférieure à hier (${totalEnergyYesterdayUntilNow.toStringAsFixed(2)} kWh).';
      insightIcon = Icons.trending_down;
      insightColor = Colors.red; // Rouge pour une production inférieure
    } else {
      insightText =
          'Production aujourd\'hui (${totalEnergyToday.toStringAsFixed(2)} kWh) est similaire à hier (${totalEnergyYesterdayUntilNow.toStringAsFixed(2)} kWh).';
      insightIcon = Icons.trending_flat;
      insightColor = Colors.orange; // Orange pour similaire
    }

    // --- Informations Météo pour les Recommandations ---
    String weatherInsightText = '';
    List<String> weatherParts = [];

    // 1) Condition actuelle
    // Utiliser currentWeather qui est garanti non-null ici
    weatherParts.add(
        'Météo actuelle : ${currentWeather.condition ?? "N/A"}'); // Ajout de ?? "N/A" par sécurité pour condition

    // 2) Prévisions heures à venir
    // Utiliser weatherForecast qui est garanti non-null ici
    if (weatherForecast.hourlyForecast.isNotEmpty) {
      final now = DateTime.now();
      // Utiliser WeatherData car c'est le type correct pour les prévisions horaires
      final next3h = <int, WeatherData>{}; // Correction: Utiliser WeatherData

      // Prendre le **premier** enregistrement pour chaque heure,
      // pendant les 3 heures qui suivent.
      for (final h in weatherForecast.hourlyForecast) {
        // h est bien de type HourlyWeather
        final diff = h.timestamp.difference(now).inHours;
        if (diff >= 0 && diff <= 3) {
          // Inclure l'heure actuelle (diff >= 0)
          next3h.putIfAbsent(h.timestamp.hour, () => h); // garde 1 valeur/h
        }
        // S'arrêter si on a potentiellement 4 heures (heure actuelle + 3 suivantes)
        if (next3h.length >= 4) break;
      }

      // Filtrer pour ne garder que les heures strictement après maintenant si besoin
      final futureHoursMap =
          <int, WeatherData>{}; // Correction: Utiliser WeatherData
      for (final entry in next3h.entries) {
        // entry.value est WeatherData
        if (entry.value.timestamp.isAfter(now) && futureHoursMap.length < 3) {
          futureHoursMap[entry.key] = entry.value;
        }
      }

      if (futureHoursMap.isNotEmpty) {
        final buffer = StringBuffer('Prévision prochaines heures : ');
        // futureHoursMap.values est Iterable<WeatherData>
        final sorted =
            futureHoursMap.values.toList(); // sorted est List<WeatherData>

        // Tri robuste (gère nulls même si non attendus)
        // a et b sont maintenant correctement inférés comme WeatherData?
        sorted.sort((a, b) {
          if (a == null && b == null) return 0;
          if (a == null) return -1;
          if (b == null) return 1;
          // a et b sont WeatherData ici, donc a.timestamp est valide
          return a.timestamp.compareTo(b.timestamp);
        });

        for (var i = 0; i < sorted.length; i++) {
          final item = sorted[i]; // item est WeatherData?
          if (item != null) {
            // Vérification de nullité
            // item est WeatherData ici
            buffer.write(
                '${DateFormat.Hm().format(item.timestamp)} : ${item.condition ?? 'N/A'}' // Gérer condition nullable
                );
            if (i < sorted.length - 1) buffer.write(', ');
          }
        }
        weatherParts.add(buffer.toString());
      }
    }

    // 3) Assemblage
    weatherInsightText = weatherParts.join('. ');
    if (weatherInsightText.isEmpty) {
      weatherInsightText = 'Informations météo non disponibles.';
    } else {
      weatherInsightText += '.'; // point final
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Action pour le RefreshIndicator
        final solarEdgeService =
            Provider.of<SolarEdgeApiService?>(context, listen: false);
        if (solarEdgeService != null) {
          await _loadData(solarEdgeService);
        } else {
          debugPrint("RefreshIndicator: Service API non disponible.");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Impossible de rafraîchir: Service API non configuré.')),
            );
          }
        }
      },
      color: AppTheme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Panneau d'heure et date
          Card(
            elevation: 0,
            color: AppTheme.primaryColor.withOpacity(0.1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Date complète
                  Text(
                    DateFormat('EEEE dd MMMM yyyy', 'fr_FR')
                        .format(_currentTime), // Formatage en français
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  // Heure actuelle
                  Text(
                    DateFormat('HH:mm').format(_currentTime),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ).animate(controller: _animationController).fadeIn(),

          const SizedBox(height: 20),

          // Carte de puissance instantanée
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              side:
                  const BorderSide(color: AppTheme.cardBorderColor, width: 0.5),
            ),
            color: AppTheme.cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const Text(
                    'Production Instantanée',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 20),
                  PowerGaugeWidget(
                    powerValue: currentPower,
                    percentage: powerPercent,
                    maxPower: maxPowerW, // Valeur en W (10000W)
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(
                        label: 'Aujourd\'hui',
                        value: '${totalEnergyToday.toStringAsFixed(2)} kWh',
                        icon: Icons.power,
                        color: AppTheme.chartLine1,
                      ),
                      _buildStatItem(
                        label: 'Puissance Crête', // Changé de Max à Crête
                        value: PowerUtils.formatWatts(todayData.peakPower),
                        icon: Icons.show_chart,
                        color: AppTheme.chartLine2,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
              .animate(controller: _animationController)
              .slideY(
                  begin: 0.2,
                  end: 0,
                  duration: 500.ms,
                  curve: Curves.easeOutQuad)
              .fadeIn(duration: 500.ms),

          const SizedBox(height: 20),

          // Ligne Météo et Production
          Row(
            children: [
              // Météo actuelle
              Expanded(
                child: Stack(
                  children: [
                    // Widget météo
                    WeatherInfoWidget(
                        weatherData:
                            currentWeather), // currentWeather est WeatherData

                    // Bouton de configuration de localisation en superposition
                    Positioned(
                      top: 8,
                      right: 8,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context)
                              .pushNamed('/location_config')
                              .then((_) {
                            // Recharger les données météo au retour
                            _weatherManager.updateLocationAndWeather();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.edit_location_alt,
                              color: Colors.white, size: 16),
                        ),
                      ),
                    ),
                  ],
                )
                    .animate(controller: _animationController)
                    .slideY(begin: 0.2, end: 0, delay: 200.ms, duration: 500.ms)
                    .fadeIn(delay: 200.ms, duration: 500.ms),
              ),

              const SizedBox(width: 16),

              // Production du jour
              Expanded(
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                    side: const BorderSide(
                        color: AppTheme.cardBorderColor, width: 0.5),
                  ),
                  color: AppTheme.cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Production',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                                Icons
                                    .wb_sunny_outlined, // Icône de soleil pour production
                                color: AppTheme.chartLine1),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${totalEnergyToday.toStringAsFixed(2)} kWh',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.textPrimaryColor,
                                  ),
                                ),
                                Text(
                                  'Aujourd\'hui',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
                    .animate(controller: _animationController)
                    .slideY(begin: 0.2, end: 0, delay: 300.ms, duration: 500.ms)
                    .fadeIn(delay: 300.ms, duration: 500.ms),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Recommandations / Insights
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Comparaison & Prévisions', // Titre modifié
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 10),

              // Carte combinée (Production vs Hier ET Météo)
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                  side: const BorderSide(
                      color: AppTheme.cardBorderColor, width: 0.5),
                ),
                color: AppTheme.cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(insightIcon,
                          color: insightColor,
                          size: 30), // Icône légèrement plus grande
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              insightText, // Comparaison Hier/Aujourd'hui
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.textPrimaryColor,
                                height: 1.4, // Améliorer lisibilité
                              ),
                            ),
                            const SizedBox(height: 12), // Plus d'espace
                            const Divider(
                                height: 1, thickness: 0.5), // Séparateur visuel
                            const SizedBox(height: 12),
                            Text(
                              weatherInsightText, // Météo actuelle et prévisions
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondaryColor,
                                height: 1.4, // Améliorer lisibilité
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Informations de mise à jour
              Align(
                // Aligner à droite
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text(
                    'Dernière mise à jour: ${DateFormat('dd/MM/yyyy HH:mm').format(_currentTime)}',
                    style: const TextStyle(
                      color: AppTheme.textSecondaryColor,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ],
          )
              .animate(controller: _animationController)
              .slideY(begin: 0.2, end: 0, delay: 400.ms, duration: 500.ms)
              .fadeIn(delay: 400.ms, duration: 500.ms),
        ],
      ),
    );
  }

  // Widget pour afficher un élément statistique
  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimaryColor,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textSecondaryColor,
          ),
        ),
      ],
    );
  }
}
