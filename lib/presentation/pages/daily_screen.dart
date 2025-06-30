import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/data/models/weather_data.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/data/services/weather_manager.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:solaredge_monitor/presentation/widgets/date_selector.dart';
import 'package:solaredge_monitor/presentation/widgets/daily_stats_card.dart';
import 'package:solaredge_monitor/presentation/widgets/hourly_production_chart.dart';
import 'package:solaredge_monitor/presentation/widgets/weather_info_panel.dart';
import 'package:solaredge_monitor/utils/power_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Import ServiceManager pour accéder au ValueNotifier
import 'package:solaredge_monitor/presentation/pages/api_configuration_screen.dart'; // Import ApiConfigurationScreen
import 'package:share_plus/share_plus.dart'; // Import pour la fonctionnalité de partage

class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  DateTime _selectedDate = DateTime.now();
  DailySolarData? _dailyData;
  DailySolarData? _previousDayData;
  List<WeatherData>? _hourlyWeather;
  double _averageDailyProduction = 0.0;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Options du graphique
  bool _showPowerCurve = true;
  bool _showWeatherOverlay = true;

  // Gestionnaire de météo centralisé
  late WeatherManager _weatherManager;
  StreamSubscription? _weatherSubscription;
  StreamSubscription? _forecastSubscription;

  // Instance du service API et son écouteur
  SolarEdgeApiService? _solarEdgeServiceInstance;
  VoidCallback? _apiServiceListener; // Utiliser VoidCallback pour l'écouteur du ValueNotifier

  // Références pour dispose()
  ServiceManager? _serviceManager;
  ValueNotifier<SolarEdgeApiService?>? _apiServiceNotifier;


  @override
  void initState() {
    super.initState();
    // La date sélectionnée est maintenant initialisée dans didChangeDependencies
    // en fonction des arguments de route ou par défaut à DateTime.now().
    // Le chargement des données est également déclenché dans didChangeDependencies.
  }

  // Define the listener callback function
  void _onApiServiceChanged() {
    // Utiliser la référence stockée au ValueNotifier
    final currentApiService = _apiServiceNotifier?.value;
    debugPrint("DEBUG DailyScreen: _onApiServiceChanged called. New API Service is ${currentApiService == null ? 'null' : 'instance'}.");
    // Déclencher le chargement des données si le service API change
    if (_solarEdgeServiceInstance != currentApiService) { // This check might be redundant now, but keep for safety
      debugPrint("INFO DailyScreen: Service API détecté/mis à jour, déclenchement du chargement.");
      _solarEdgeServiceInstance = currentApiService; // Stocker la nouvelle instance
      // Charger les données si le nouveau service n'est pas null
      if (_solarEdgeServiceInstance != null) {
         unawaited(_loadData()); // Utiliser unawaited car _loadData est async
      } else {
         // Si le service devient null, afficher l'erreur de configuration
         if (mounted) {
           setState(() {
             _isLoading = false;
             _hasError = true;
             _errorMessage = 'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
           });
         }
      }
    }
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint("DEBUG DailyScreen: didChangeDependencies called.");

    // Récupérer les arguments de route
    final args = ModalRoute.of(context)?.settings.arguments;
    DateTime? initialDateFromArgs;
    if (args is Map && args.containsKey('selectedDate') && args['selectedDate'] is DateTime) {
      initialDateFromArgs = args['selectedDate'] as DateTime;
      debugPrint("DEBUG DailyScreen: Date reçue via arguments: $initialDateFromArgs");
    } else {
      debugPrint("DEBUG DailyScreen: Aucun argument 'selectedDate' valide reçu.");
    }

    // Initialiser _selectedDate si ce n'est pas déjà fait ou si la date des arguments est différente
    // On vérifie si _selectedDate a déjà été initialisée (par exemple, si l'utilisateur change la date via le DateSelector)
    // ou si la date des arguments est différente de la date actuelle sélectionnée.
    // Cependant, pour ce cas d'utilisation (navigation depuis le graphique mensuel),
    // didChangeDependencies est appelé après la navigation, et _selectedDate sera encore DateTime.now()
    // si initState n'a pas été modifié.
    // La logique la plus simple est de toujours utiliser la date des arguments si elle est présente,
    // sinon utiliser la date actuelle.
    // Retirer la déclaration explicite de type pour laisser Dart inférer le type non-nullable
    final newSelectedDate = initialDateFromArgs ?? DateTime.now();

    // Si une date est passée via les arguments, l'utiliser et déclencher le chargement.
    // Cela gère la navigation depuis d'autres pages.
    if (initialDateFromArgs != null) {
       debugPrint("INFO DailyScreen: Date reçue via arguments ($initialDateFromArgs). Mise à jour de _selectedDate et déclenchement du chargement.");
       // Mettre à jour _selectedDate si elle est différente de la date actuelle
       // Utiliser newSelectedDate qui est non-nullable ici
       if (_selectedDate.year != newSelectedDate.year ||
           _selectedDate.month != newSelectedDate.month ||
           _selectedDate.day != newSelectedDate.day) {
          if (mounted) {
             setState(() {
               _selectedDate = newSelectedDate; // Utiliser newSelectedDate
               _isLoading = true; // Déclencher le chargement pour la nouvelle date
               _hasError = false; // Réinitialiser l'erreur
               _dailyData = null; // Vider les données précédentes
               _previousDayData = null;
               _hourlyWeather = null;
             });
          }
       }
       // Déclencher le chargement des données, même si la date n'a pas changé (ex: navigation vers le jour actuel)
       final currentApiService = _apiServiceNotifier?.value;
       if (currentApiService != null) {
          debugPrint("INFO DailyScreen: Service API disponible, déclenchement du chargement après réception arguments.");
          _solarEdgeServiceInstance = currentApiService; // S'assurer que l'instance est à jour
          unawaited(_loadData()); // Utiliser unawaited car _loadData est async
       } else {
          debugPrint("INFO DailyScreen: Service API non disponible, affichage de la config requise.");
          if (mounted) {
            setState(() {
              _isLoading = false; // Arrêter le chargement si l'API n'est pas prête
              _hasError = true;
              _errorMessage = 'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
            });
          }
       }
    } else {
       // Si aucune date n'est passée via les arguments, utiliser la date actuelle par défaut.
       // La logique de chargement initial pour ce cas est gérée plus bas.
       debugPrint("DEBUG DailyScreen: Aucune date reçue via arguments. Utilisation de la date actuelle par défaut.");
       // Assurez-vous que _selectedDate est bien la date actuelle si aucun argument n'est passé
       // Utiliser newSelectedDate qui est non-nullable ici
       if (_selectedDate.year != newSelectedDate.year ||
           _selectedDate.month != newSelectedDate.month ||
           _selectedDate.day != newSelectedDate.day) {
           if (mounted) {
              setState(() {
                 _selectedDate = newSelectedDate; // Utiliser newSelectedDate
              });
           }
       }
    }


    // Initialiser le WeatherManager et s'abonner ici
    // car context est disponible de manière fiable
    if (_weatherSubscription == null) {
      _weatherManager = Provider.of<WeatherManager>(context, listen: false);

      // S'abonner aux mises à jour des prévisions météo
      _forecastSubscription = _weatherManager.forecastStream.listen((forecast) {
        if (forecast != null && mounted) {
          setState(() {
            _hourlyWeather = forecast.hourlyForecast;

            // Si on était en chargement, on peut l'arrêter maintenant
            if (_isLoading && _dailyData != null && _previousDayData != null) {
              _isLoading = false;
            }
          });
        }
      });
      debugPrint("DEBUG DailyScreen: WeatherManager initialized and subscribed.");
    }

    // Nouvelle logique pour détecter le changement du service API
    // Écouter le ValueNotifier<SolarEdgeApiService?> fourni par ServiceManager
    // Obtenir et stocker les références pour une utilisation future (dispose)
    _serviceManager = Provider.of<ServiceManager>(context, listen: false);
    _apiServiceNotifier = _serviceManager!.apiServiceNotifier; // Obtenir le ValueNotifier

    // Remove the old listener if present
    if (_apiServiceListener != null && _apiServiceNotifier != null) {
      _apiServiceNotifier!.removeListener(_apiServiceListener!);
    }

    // Store the callback and add the new listener
    _apiServiceListener = () {
      // Utiliser la référence stockée au ValueNotifier
      final currentApiService = _apiServiceNotifier?.value;
      debugPrint("DEBUG DailyScreen: apiServiceNotifier changed. New API Service is ${currentApiService == null ? 'null' : 'instance'}.");
      // Déclencher le chargement des données si le service API change
      if (_solarEdgeServiceInstance != currentApiService) {
        debugPrint("INFO DailyScreen: Service API détecté/mis à jour, déclenchement du chargement.");
        _solarEdgeServiceInstance = currentApiService; // Stocker la nouvelle instance
        // Charger les données si le nouveau service n'est pas null
        if (_solarEdgeServiceInstance != null) {
           unawaited(_loadData()); // Utiliser unawaited car _loadData est async
        } else {
           // Si le service devient null, afficher l'erreur de configuration
           if (mounted) {
             setState(() {
               _isLoading = false;
               _hasError = true;
               _errorMessage = 'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
             });
           }
        }
      }
    };
    // Utiliser la référence stockée au ValueNotifier
    _apiServiceNotifier!.addListener(_apiServiceListener!);


    // Déclencher le chargement initial si le service API est déjà disponible
    // Utiliser la référence stockée au ValueNotifier
    final initialApiService = _apiServiceNotifier?.value;
     debugPrint("DEBUG DailyScreen: didChangeDependencies - initialApiService from ValueNotifier is ${initialApiService == null ? 'null' : 'instance'}.");
    // Charger les données si le service API est disponible ET si les données n'ont pas encore été chargées
    if (initialApiService != null && _dailyData == null && !_isLoading) {
      debugPrint("INFO DailyScreen: Service API disponible et données manquantes, déclenchement du chargement initial.");
      _solarEdgeServiceInstance = initialApiService;
      unawaited(_loadData()); // Utiliser unawaited car _loadData est async
    } else if (initialApiService == null && !_hasError && !_isLoading) {
       // Si le service est null au démarrage et qu'on n'est pas déjà en erreur/chargement
       debugPrint("INFO DailyScreen: Service API null au démarrage, affichage de la config requise.");
       if (mounted) {
         setState(() {
           _isLoading = false;
           _hasError = true;
           _errorMessage = 'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
         });
       }
    }
  }


  @override
  void dispose() {
    _weatherSubscription?.cancel();
    _forecastSubscription?.cancel();
    // Remove the listener using the stored callback and references
    if (_apiServiceListener != null && _apiServiceNotifier != null) {
      _apiServiceNotifier!.removeListener(_apiServiceListener!);
    }
    super.dispose();
  }




  // Changer la date sélectionnée
  void _onDateChanged(DateTime date) {
    setState(() {
      _selectedDate = date;
      _isLoading = true;
      _hasError = false; // Réinitialiser l'erreur lors du changement de date
    });
    // Charger les données pour la nouvelle date si le service API est disponible
    if (_solarEdgeServiceInstance != null) {
      unawaited(_loadData());
    } else {
       // Si le service API n'est pas disponible, afficher l'erreur de configuration
       if (mounted) {
         setState(() {
           _isLoading = false;
           _hasError = true;
           _errorMessage = 'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
         });
       }
    }
  }

  // Charger les données pour la date sélectionnée
  Future<void> _loadData() async {
    // Utiliser l'instance stockée du service API
    final solarEdgeService = _solarEdgeServiceInstance;

    // Vérifier si le service API est disponible avant de continuer
    if (solarEdgeService == null) {
      debugPrint('⚠️ _loadData: Service SolarEdgeAPI non disponible. Affichage de l\'écran de configuration.');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
        });
      }
      return;
    }

    // Mettre isLoading à true au début du chargement
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _errorMessage = ''; // Réinitialiser le message d'erreur
      });
    }


    try {
      debugPrint("DailyScreen: Chargement des données SolarEdge pour $_selectedDate...");
      // Calculer la date du jour précédent
      final previousDay = _selectedDate.subtract(const Duration(days: 1));

      // Rafraîchir les données météo via le WeatherManager
      // On ne rafraîchit la météo que pour la date du jour
      debugPrint("DailyScreen: Lancement des appels API en parallèle...");
      // Charger les données SolarEdge, la production moyenne et les prévisions météo en parallèle
      final results = await Future.wait([
        solarEdgeService.getDailyEnergy(_selectedDate).then((data) {
          debugPrint("DailyScreen: getDailyEnergy pour $_selectedDate terminé.");
          return data;
        }).catchError((e) {
           debugPrint('❌ DailyScreen: Erreur getDailyEnergy pour $_selectedDate: $e');
           throw e; // Rejeter l'erreur pour que Future.wait la capture
        }),
        solarEdgeService.getDailyEnergy(previousDay).then((data) {
          debugPrint("DailyScreen: getDailyEnergy pour $previousDay terminé.");
          return data;
        }).catchError((e) {
           debugPrint('❌ DailyScreen: Erreur getDailyEnergy pour $previousDay: $e');
           throw e; // Rejeter l'erreur
        }),
        _loadAverageProduction(solarEdgeService).then((avg) {
           debugPrint("DailyScreen: _loadAverageProduction terminé.");
           return avg;
        }).catchError((e) {
           debugPrint('❌ DailyScreen: Erreur _loadAverageProduction: $e');
           throw e; // Rejeter l'erreur
        }),
        // Add weather forecast fetch here
        _weatherManager.getWeatherForecast(forceRefresh: true).catchError((e) {
           debugPrint('❌ DailyScreen: Erreur récupération prévisions dans Future.wait: $e');
           return null; // Return null on error so Future.wait doesn't fail
        }),
      ]);
      debugPrint("DailyScreen: Future.wait terminé.");

      // Mettre à jour l'état une seule fois après que toutes les données soient prêtes
      if (mounted) {
        setState(() {
          _dailyData = results[0] as DailySolarData?; // Safer cast
          _previousDayData = results[1] as DailySolarData?; // Safer cast
          _averageDailyProduction = results[2] as double; // Récupérer la moyenne

          // Récupérer le WeatherForecast directement depuis les résultats de Future.wait
          final WeatherForecast? fetchedForecast = results[3] as WeatherForecast?;

          // Mettre à jour _hourlyWeather directement ici
          if (fetchedForecast != null) {
            _hourlyWeather = fetchedForecast.hourlyForecast;
            debugPrint("DailyScreen: _hourlyWeather mis à jour directement depuis fetchedForecast. Nombre d'heures: ${_hourlyWeather?.length}");
          } else {
            _hourlyWeather = null; // Ou une liste vide: [];
            debugPrint("DailyScreen: fetchedForecast était null, _hourlyWeather mis à null.");
          }

          _isLoading = false; // Assurer que isLoading est false en cas de succès
          _hasError = false; // Réinitialiser l'erreur si les données ont été chargées avec succès
        });
        debugPrint("DailyScreen: Chargement réussi, setState(_isLoading = false) appelé.");
      }
    } catch (e) {
      debugPrint('❌ DailyScreen: Erreur lors du chargement des données: $e');
      // Mettre à jour l'état en cas d'erreur
      if (mounted) {
        setState(() {
          _isLoading = false; // Assurer que isLoading est false en cas d'erreur
          _hasError = true;
          _errorMessage = e.toString();
        });
        debugPrint("DailyScreen: Erreur de chargement, setState(_isLoading = false, _hasError = true) appelé.");
      }
    }
  } // <-- Accolade fermante manquante ajoutée ici

  // Charger la production moyenne quotidienne (basée sur les 30 derniers jours)
  Future<double> _loadAverageProduction(SolarEdgeApiService service) async {
    debugPrint("DailyScreen: Début _loadAverageProduction.");
    try {
      // Déterminer la plage de 30 jours pour calculer la moyenne
      // final endDate = DateTime.now(); // Pas utilisé dans cette version simplifiée

      // Pour simplifier, on pourrait stocker cette valeur dans les préférences
      // et la mettre à jour périodiquement plutôt que de la recalculer à chaque fois
      debugPrint("DailyScreen: _loadAverageProduction - Appel SharedPreferences.getInstance().");
      final prefs = await SharedPreferences.getInstance();
      debugPrint("DailyScreen: _loadAverageProduction - SharedPreferences.getInstance() terminé.");
      final storedAverage = prefs.getDouble('average_daily_production');
      debugPrint("DailyScreen: _loadAverageProduction - storedAverage: $storedAverage");


      if (storedAverage != null) {
        // Ne pas appeler setState ici, car cela pourrait interférer avec le setState principal dans _loadData
        // setState(() {
        //   _averageDailyProduction = storedAverage;
        // });
        debugPrint("DailyScreen: _loadAverageProduction - Retourne valeur stockée.");
        return storedAverage;
      }

      // Si pas de valeur stockée, on utilise une valeur par défaut
      // Dans une implémentation complète, on calculerait la vraie moyenne
      const defaultAverage = 15000.0; // 15 kWh par jour par défaut

      // Ne pas appeler setState ici
      // setState(() {
      //   _averageDailyProduction = defaultAverage;
      // });
      debugPrint("DailyScreen: _loadAverageProduction - Retourne valeur par défaut.");
      return defaultAverage;
    } catch (e) {
      debugPrint('❌ DailyScreen: Erreur dans _loadAverageProduction: $e');
      // Rejeter l'erreur pour qu'elle soit capturée par le Future.wait dans _loadData
      throw e;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Écouter le ServiceManager pour déclencher les mises à jour via didChangeDependencies
    // L'écoute ici permet de reconstruire le widget lorsque le ServiceManager (ou son ValueNotifier interne) change,
    // ce qui déclenche didChangeDependencies où la logique de chargement est gérée.
    Provider.of<ServiceManager>(context);


    return Scaffold(
      appBar: AppBar(
        title: const Text('Production journalière'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            onPressed: _shareDailyData, // Appeler la fonction de partage
          ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingView()
          : _hasError
              ? _buildErrorView()
              : _buildContentView(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1, // L'index Jour est sélectionné
        onDestinationSelected: (index) {
          // Naviguer vers les autres écrans quand les onglets sont cliqués
          switch (index) {
            case 0:
              Navigator.of(context).pushNamed('/'); // Naviguer vers Home
              break;
            case 1:
              // Jour déjà sélectionné
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

  // Construire la vue de chargement
  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text(
            'Chargement des données...',
            style: TextStyle(
              color: AppTheme.textSecondaryColor,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  // Construire la vue d'erreur
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
    } else if (_errorMessage.contains('Service SolarEdge API non initialisé')) {
       isApiConfigError = true; // C'est l'erreur que l'on affiche quand le service est null
       cleanErrorMessage = 'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
    }


    // Si c'est une erreur de config (clé/ID invalide ou service null), rediriger vers l'écran de config
    if (isApiConfigError) {
      return ApiConfigurationScreen( // Utiliser le widget ApiConfigurationScreen
        errorMessage: cleanErrorMessage,
        onRetry: () async { // Rendre async car initializeApiServiceFromPreferences est async
          // Tenter de réinitialiser le service API via ServiceManager
          setState(() {
            _isLoading = true; // Repasser en chargement
            _hasError = false;
          });
          // Obtenir l'instance du ServiceManager
          final serviceManager = Provider.of<ServiceManager>(context, listen: false);
          // Appeler la méthode pour initialiser le service API depuis les préférences
          await serviceManager.initializeApiServiceFromPreferences();
          // Le listener dans didChangeDependencies mettra à jour l'état et déclenchera _loadData si l'API est valide.
        },
        isApiKeyMissing:
            _errorMessage.contains('Service SolarEdge API non initialisé'), // Indiquer si la clé/ID est manquante vs invalide
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
                // Tenter de recharger les données (didChangeDependencies devrait détecter le service si dispo)
                 setState(() {
                   _isLoading = true;
                   _hasError = false;
                 });
                 // didChangeDependencies sera appelé après setState
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
    if (_dailyData == null) {
      // Si on arrive ici alors que _isLoading est false, c'est un état inattendu
      // Afficher chargement par sécurité
      return _buildLoadingView();
    }

    final dailyData = _dailyData!;


    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Sélecteur de date
          DateSelector(
            selectedDate: _selectedDate,
            onDateChanged: _onDateChanged,
            maxDate: DateTime.now(),
          ),

          const SizedBox(height: 20),

          // Carte de statistiques journalières
          DailyStatsCard(
            dailyData: dailyData,
            previousDayData: _previousDayData,
            averageDailyProduction: _averageDailyProduction,
          ),

          const SizedBox(height: 20),

          // Titre de la section graphique
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Production horaire',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Graphique de production horaire
          if (dailyData.hourlyData.isNotEmpty)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                side: const BorderSide(color: AppTheme.cardBorderColor, width: 0.5),
              ),
              color: AppTheme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: HourlyProductionChart(
                  dailyData: dailyData,
                  hourlyWeather: _hourlyWeather,
                  showPowerCurve: _showPowerCurve,
                  showWeatherOverlay: _showWeatherOverlay,
                  onPowerCurveToggled: (value) {
                    setState(() {
                      _showPowerCurve = value;
                    });
                  },
                  onWeatherOverlayToggled: (value) {
                    setState(() {
                      _showWeatherOverlay = value;
                    });
                  },
                ),
              ),
            )
          else
            const Card(
              elevation: 0,
              child: Padding(
                padding: EdgeInsets.all(30.0),
                child: Center(
                  child: Text(
                    'Aucune donnée horaire disponible pour cette journée',
                    style: TextStyle(
                      color: AppTheme.textSecondaryColor,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 20),

          // Panneau météo
          if (_selectedDate.day == DateTime.now().day && _selectedDate.month == DateTime.now().month && _selectedDate.year == DateTime.now().year)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Météo',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    // Bouton de configuration de localisation
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushNamed('/location_config').then((_) {
                          // Recharger les données météo au retour
                          _weatherManager.updateLocationAndWeather();
                        });
                      },
                      icon: const Icon(Icons.location_on, size: 18),
                      label: const Text('Configurer la localisation'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                WeatherInfoPanel(hourlyWeather: _hourlyWeather),
                const SizedBox(height: 20),
              ],
            ),

          // Section de performances et recommandations
          _buildPerformanceSection(),
        ],
      ),
    );
  }

  // Construire la section de performances et recommandations
  Widget _buildPerformanceSection() {
    // Calculer l'efficacité de la journée
    // (Production réelle / Production théorique optimale)
    final double theoreticalMax = 40000.0; // Production théorique max en Wh
    final double efficiencyPercent = (_dailyData!.totalEnergy / theoreticalMax) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Performance',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimaryColor,
          ),
        ),

        const SizedBox(height: 12),

        // Carte de performance
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
            side: const BorderSide(color: AppTheme.cardBorderColor, width: 0.5),
          ),
          color: AppTheme.cardColor,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Jauge d'efficacité
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      children: [
                        // Fond de la jauge
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.red.withOpacity(0.7),
                                Colors.orange.withOpacity(0.7),
                                Colors.yellow.withOpacity(0.7),
                                Colors.green.withOpacity(0.7),
                              ],
                              stops: const [0.3, 0.5, 0.7, 0.9],
                            ),
                          ),
                        ),

                        // Indicateur de position
                        Positioned(
                          left: (efficiencyPercent / 100) * MediaQuery.of(context).size.width * 0.8,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 3,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Valeur de l'efficacité
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Efficacité du jour',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                    Text(
                      '${efficiencyPercent.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _getEfficiencyColor(efficiencyPercent),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Analyse des heures optimales
                const Text(
                  'Heures les plus productives',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                _buildTopHoursWidget(),

                const SizedBox(height: 16),

                // Recommandation personnalisée
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.lightbulb,
                        color: AppTheme.primaryColor,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Recommandation',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getRecommendation(),
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppTheme.textPrimaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Afficher les heures les plus productives
  Widget _buildTopHoursWidget() {
    if (_dailyData == null || _dailyData!.hourlyData.isEmpty) {
      return const Text(
        'Aucune donnée disponible',
        style: TextStyle(
          color: AppTheme.textSecondaryColor,
          fontSize: 14,
        ),
      );
    }

    // Trier les heures par production
    final sortedHours = List.from(_dailyData!.hourlyData);
    sortedHours.sort((a, b) => b.energy.compareTo(a.energy));

    // Prendre les 3 meilleures heures
    final topHours = sortedHours.take(3).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: topHours.map((hour) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${hour.timestamp.hour < 10 ? '0${hour.timestamp.hour}' : hour.timestamp.hour}:00 - ${PowerUtils.formatEnergyKWh(hour.energy)}',
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  // Obtenir une recommandation en fonction des données
  String _getRecommendation() {
    if (_dailyData == null) return '';

    // Trouver l'heure de production maximale
    int maxHour = 12; // Par défaut midi
    double maxEnergy = 0;

    for (var hourData in _dailyData!.hourlyData) {
      if (hourData.energy > maxEnergy) {
        maxEnergy = hourData.energy;
        maxHour = hourData.timestamp.hour;
      }
    }

    if (_selectedDate.day == DateTime.now().day) {
      // Pour aujourd'hui
      if (DateTime.now().hour < maxHour) {
        return 'La production sera maximale vers ${maxHour}h aujourd\'hui. Programmez vos appareils énergivores pour cette période.';
      } else {
        return 'La production a été maximale à ${maxHour}h. Si possible, décalez vos consommations importantes vers cette heure demain.';
      }
    } else {
      // Pour les autres jours
      return 'Cette journée a eu sa production maximale à ${maxHour}h. Retenez cette tranche horaire pour optimiser votre consommation.';
    }
  }

  // Obtenir la couleur en fonction du pourcentage d'efficacité
  // Fonction pour partager les données journalières
  void _shareDailyData() {
    if (_dailyData == null) {
      // Ne rien faire si les données ne sont pas chargées
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune donnée à partager'),
        ),
      );
      return;
    }

    final String date = "${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}";
    final String totalEnergy = PowerUtils.formatEnergyKWh(_dailyData!.totalEnergy);
    final String peakPower = PowerUtils.formatWatts(_dailyData!.peakPower);
    final String averageProduction = PowerUtils.formatEnergyKWh(_averageDailyProduction);
    final double efficiencyPercent = (_dailyData!.totalEnergy / 40000.0) * 100; // Utiliser la même base que pour la jauge

    final String shareText = """
Production solaire du $date :
Énergie totale produite : $totalEnergy
Puissance de crête : $peakPower
Efficacité du jour : ${efficiencyPercent.toStringAsFixed(1)}%
Production moyenne quotidienne (estimée) : $averageProduction

Suivez votre production solaire avec SolarEdge Monitor !
""";

    Share.share(shareText, subject: 'Ma production solaire du $date');
  }

  // Obtenir la couleur en fonction du pourcentage d'efficacité
  Color _getEfficiencyColor(double percent) {
    if (percent < 30) return Colors.red;
    if (percent < 50) return Colors.orange;
    if (percent < 70) return Colors.yellow.shade800;
    return Colors.green;
  }
}
