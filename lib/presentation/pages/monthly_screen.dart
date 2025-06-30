import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart'; // Import corrigé
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:solaredge_monitor/presentation/widgets/month_year_selector.dart';
import 'package:solaredge_monitor/presentation/widgets/monthly_production_chart.dart';
import 'package:solaredge_monitor/utils/power_utils.dart';
import 'package:intl/intl.dart';
import 'dart:math'; // Importer pour max()
import 'package:solaredge_monitor/data/models/user_preferences.dart'; // Import UserPreferences
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Import ServiceManager pour accéder au ValueNotifier
import 'package:solaredge_monitor/presentation/pages/api_configuration_screen.dart'; // Import ApiConfigurationScreen
import 'package:share_plus/share_plus.dart'; // Import pour la fonctionnalité de partage

class MonthlyScreen extends StatefulWidget {
  final DateTime? initialDate;

  const MonthlyScreen({super.key, this.initialDate});

  @override
  State<MonthlyScreen> createState() => _MonthlyScreenState();
}

class _MonthlyScreenState extends State<MonthlyScreen> {
  late DateTime _selectedDate;
  MonthlySolarData? _monthlyData;
  final Map<int, MonthlySolarData> _comparisonData = {};
  List<int> _selectedComparisonYears = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _showComparisonAsOverlay = false;

  // Instance du service API et son écouteur
  SolarEdgeApiService? _solarEdgeServiceInstance;
  VoidCallback?
      _apiServiceListener; // Utiliser VoidCallback pour l'écouteur du ValueNotifier

  @override
  void initState() {
    super.initState();
    // Normaliser la date initiale au premier jour du mois
    final DateTime initial = widget.initialDate ?? DateTime.now();
    _selectedDate = DateTime(initial.year, initial.month, 1);
    // Le chargement des données est maintenant déclenché par didChangeDependencies
  }

  // Define the listener callback function
  void _onApiServiceChanged() {
    final currentApiService =
        _solarEdgeServiceInstance; // Use the stored instance
    debugPrint(
        "DEBUG MonthlyScreen: _onApiServiceChanged called. New API Service is ${currentApiService == null ? 'null' : 'instance'}.");
    // Déclencher le chargement des données si le service API change
    if (_solarEdgeServiceInstance != currentApiService) {
      // This check might be redundant now, but keep for safety
      debugPrint(
          "INFO MonthlyScreen: Service API détecté/mis à jour, déclenchement du chargement.");
      _solarEdgeServiceInstance =
          currentApiService; // Stocker la nouvelle instance
      // Charger les données si le nouveau service n'est pas null
      if (_solarEdgeServiceInstance != null) {
        unawaited(_loadData()); // Utiliser unawaited car _loadData est async
      } else {
        // Si le service devient null, afficher l'erreur de configuration
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage =
                'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
          });
        }
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    debugPrint("DEBUG MonthlyScreen: didChangeDependencies called.");

    // Nouvelle logique pour détecter le changement du service API
    // Écouter le ValueNotifier<SolarEdgeApiService?> fourni par ServiceManager
    final serviceManager = Provider.of<ServiceManager>(context, listen: false);
    final apiServiceNotifier =
        serviceManager.apiServiceNotifier; // Obtenir le ValueNotifier

    // Remove the old listener if present
    if (_apiServiceListener != null) {
      apiServiceNotifier.removeListener(_apiServiceListener!);
    }

    // Store the callback and add the new listener
    _apiServiceListener = () {
      final currentApiService = apiServiceNotifier.value;
      debugPrint(
          "DEBUG MonthlyScreen: apiServiceNotifier changed. New API Service is ${currentApiService == null ? 'null' : 'instance'}.");
      // Déclencher le chargement des données si le service API change
      if (_solarEdgeServiceInstance != currentApiService) {
        debugPrint(
            "INFO MonthlyScreen: Service API détecté/mis à jour, déclenchement du chargement.");
        _solarEdgeServiceInstance =
            currentApiService; // Stocker la nouvelle instance
        // Charger les données si le nouveau service n'est pas null
        if (_solarEdgeServiceInstance != null) {
          unawaited(_loadData()); // Utiliser unawaited car _loadData est async
        } else {
          // Si le service devient null, afficher l'erreur de configuration
          if (mounted) {
            setState(() {
              _isLoading = false;
              _hasError = true;
              _errorMessage =
                  'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
            });
          }
        }
      }
    };
    apiServiceNotifier.addListener(_apiServiceListener!);

    // Déclencher le chargement initial si le service API est déjà disponible
    final initialApiService = apiServiceNotifier.value;
    debugPrint(
        "DEBUG MonthlyScreen: didChangeDependencies - initialApiService from ValueNotifier is ${initialApiService == null ? 'null' : 'instance'}.");
    if (initialApiService != null && _solarEdgeServiceInstance == null) {
      debugPrint(
          "INFO MonthlyScreen: Service API disponible au démarrage, déclenchement du chargement initial.");
      _solarEdgeServiceInstance = initialApiService;
      unawaited(_loadData());
    } else if (initialApiService == null && !_hasError && !_isLoading) {
      // Si le service est null au démarrage et qu'on n'est pas déjà en erreur/chargement
      debugPrint(
          "INFO MonthlyScreen: Service API null au démarrage, affichage de la config requise.");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage =
              'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
        });
      }
    }
  }

  @override
  void dispose() {
    // Remove the listener using the stored callback
    final serviceManager = Provider.of<ServiceManager>(context, listen: false);
    final apiServiceNotifier = serviceManager.apiServiceNotifier;
    if (_apiServiceListener != null) {
      apiServiceNotifier.removeListener(_apiServiceListener!);
    }
    super.dispose();
  }

  /// Gère le changement de mois/année depuis le sélecteur.
  void _onMonthYearChanged(DateTime date) {
    // Normaliser la date au premier jour du mois
    final DateTime newSelectedDate = DateTime(date.year, date.month, 1);
    // Vérifier si la date a réellement changé pour éviter rechargement inutile
    if (newSelectedDate != _selectedDate) {
      setState(() {
        _selectedDate = newSelectedDate;
        _isLoading = true;
        _hasError = false; // Réinitialiser l'erreur lors du changement de date
        _monthlyData = null; // Vider les données pour indiquer chargement
        _comparisonData.clear(); // Vider aussi la comparaison
      });
      // Lancer le chargement si le service API est disponible
      if (_solarEdgeServiceInstance != null) {
        unawaited(_loadData());
      } else {
        // Si le service API n'est pas disponible, afficher l'erreur de configuration
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage =
                'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
          });
        }
      }
    }
  }

  /// Charge les données pour le mois sélectionné et les années de comparaison.
  Future<void> _loadData() async {
    // Si le widget n'est plus dans l'arbre, ne rien faire
    if (!mounted) return;

    // Utiliser l'instance stockée du service API
    final SolarEdgeApiService? solarEdgeService = _solarEdgeServiceInstance;

    // Vérifier si le service API est disponible avant de continuer
    if (solarEdgeService == null) {
      debugPrint(
          '⚠️ _loadData: Service SolarEdgeAPI non disponible. Affichage de l\'écran de configuration.');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage =
              'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
        });
      }
      return;
    }

    // Activer le chargement et réinitialiser l'erreur
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      // Créer les Futures pour les appels API en parallèle
      debugPrint(
          "Chargement des données pour ${_selectedDate.year}-${_selectedDate.month}");
      final Future<MonthlySolarData?> monthlyDataFuture =
          solarEdgeService.getMonthlyEnergy(_selectedDate);

      final Map<int, Future<MonthlySolarData>> comparisonFutures = {};
      for (int year in _selectedComparisonYears) {
        if (year != _selectedDate.year) {
          debugPrint(
              "Chargement comparaison pour $year-${_selectedDate.month}");
          comparisonFutures[year] = solarEdgeService
              .getMonthlyEnergy(DateTime(year, _selectedDate.month, 1));
        }
      }

      // Attendre le résultat du mois principal
      final MonthlySolarData? monthlyDataResult = await monthlyDataFuture;

      // Attendre les résultats de comparaison
      final Map<int, MonthlySolarData> newComparisonData = {};
      final List<int> comparisonYears = comparisonFutures.keys.toList();
      // Utiliser Future.wait pour attendre toutes les requêtes de comparaison
      final List<MonthlySolarData> comparisonResults =
          await Future.wait(comparisonFutures.values);

      // Mapper les résultats aux années correspondantes
      for (int i = 0; i < comparisonYears.length; i++) {
        // Vérifier la cohérence de l'index (même si Future.wait préserve l'ordre)
        if (i < comparisonResults.length) {
          newComparisonData[comparisonYears[i]] = comparisonResults[i];
        } else {
          debugPrint(
              "Avertissement : résultat de comparaison manquant pour l'année ${comparisonYears[i]}");
        }
      }

      // Mettre à jour l'état si le widget est toujours monté
      if (mounted) {
        setState(() {
          _monthlyData = monthlyDataResult;
          _comparisonData.clear();
          _comparisonData.addAll(newComparisonData);
          _isLoading = false;
          _hasError =
              false; // Réinitialiser l'erreur si les données ont été chargées avec succès
        });
      }
    } catch (e, stacktrace) {
      debugPrint('❌ Erreur lors du chargement des données mensuelles: $e');
      debugPrint(stacktrace.toString());
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = (e is Exception)
              ? e.toString().replaceFirst('Exception: ', '')
              : 'Une erreur inconnue est survenue.';
        });
      }
    }
  }

  /// Gère le changement des années sélectionnées pour la comparaison.
  void _onComparisonYearsChanged(List<int> years) {
    setState(() {
      // Mettre à jour la liste des années de comparaison sélectionnées
      _selectedComparisonYears = years;
      // Indiquer qu'un rechargement est nécessaire pour les nouvelles données de comparaison
      _isLoading = true;
      _hasError =
          false; // Réinitialiser l'erreur lors du changement de comparaison
      // Vider les anciennes données de comparaison
      _comparisonData.clear();
    });
    // Lancer le rechargement des données si le service API est disponible
    if (_solarEdgeServiceInstance != null) {
      unawaited(_loadData());
    } else {
      // Si le service API n'est pas disponible, afficher l'erreur de configuration
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage =
              'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
        });
      }
    }
  }

  /// Bascule le mode d'affichage de la comparaison (superposé / juxtaposé).
  void _toggleComparisonMode() {
    setState(() {
      _showComparisonAsOverlay = !_showComparisonAsOverlay;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Écouter le ValueNotifier de l'API pour déclencher les mises à jour via didChangeDependencies
    // On écoute ici pour que build soit appelé lorsque le ValueNotifier change,
    // ce qui déclenche didChangeDependencies.
    // On n'utilise PAS l'instance retournée directement ici pour le chargement des données,
    // car _loadData est appelé par didChangeDependencies.
    Provider.of<ValueNotifier<SolarEdgeApiService?>>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Production mensuelle'),
        actions: <Widget>[
          // Afficher le bouton de mode de comparaison seulement si des données de comparaison existent
          if (_comparisonData.isNotEmpty)
            IconButton(
              icon: Icon(_showComparisonAsOverlay
                  ? Icons.layers_outlined
                  : Icons.view_column_outlined),
              tooltip: _showComparisonAsOverlay
                  ? 'Mode juxtaposition'
                  : 'Mode superposition',
              onPressed: _toggleComparisonMode,
            ),
          // Bouton Partager (fonctionnalité future)
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Partager',
            onPressed: _shareMonthlyData, // Appeler la fonction de partage
          ),
          // Bouton Rafraîchir
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
            onPressed: _isLoading
                ? null
                : _loadData, // Désactivé pendant le chargement
          ),
        ],
      ),
      // Affichage conditionnel du corps
      body: _isLoading
          ? _buildLoadingView()
          : _hasError
              ? _buildErrorView()
              : _buildContentView(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 2, // L'index Mois est sélectionné
        onDestinationSelected: (index) {
          // Naviguer vers les autres écrans quand les onglets sont cliqués
          switch (index) {
            case 0:
              Navigator.of(context).pushNamed('/'); // Naviguer vers Home
              break;
            case 1:
              Navigator.of(context).pushNamed('/daily', arguments: {'selectedDate': DateTime.now()});
              break;
            case 2:
              // Mois déjà sélectionné
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

  /// Widget affiché pendant le chargement.
  Widget _buildLoadingView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text(
            'Chargement des données...',
            style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 16),
          ),
        ],
      ),
    );
  }

  /// Widget affiché en cas d'erreur.
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
      isApiConfigError =
          true; // C'est l'erreur que l'on affiche quand le service est null
      cleanErrorMessage =
          'Service SolarEdge API non initialisé. Veuillez configurer votre clé API et ID de site.';
    }

    // Si c'est une erreur de config (clé/ID invalide ou service null), rediriger vers l'écran de config
    if (isApiConfigError) {
      return ApiConfigurationScreen(
        // Utiliser le widget ApiConfigurationScreen
        errorMessage: cleanErrorMessage,
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
          // Le listener dans didChangeDependencies mettra à jour l'état et déclenchera _loadData si l'API est valide.
        },
        isApiKeyMissing: _errorMessage.contains(
            'Service SolarEdge API non initialisé'), // Indiquer si la clé/ID est manquante vs invalide
      );
    }

    // Afficher l'écran d'erreur générique pour les autres types d'erreurs (ex: réseau)
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline, color: Colors.red, size: 60),
            const SizedBox(height: 20),
            const Text(
              'Erreur de chargement',
              style: TextStyle(
                  color: AppTheme.textPrimaryColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              cleanErrorMessage, // Message d'erreur détaillé
              style: const TextStyle(
                  color: AppTheme.textSecondaryColor, fontSize: 14),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construit la vue principale avec le contenu (données chargées).
  Widget _buildContentView() {
    // Cas où le chargement est terminé mais aucune donnée pour le mois principal
    if (_monthlyData == null && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.cloud_off,
                size: 60, color: AppTheme.textSecondaryColor),
            const SizedBox(height: 16),
            Text(
              'Aucune donnée trouvée pour ${DateFormat('MMMM yyyy', 'fr_FR').format(_selectedDate)}.',
              style: const TextStyle(
                  color: AppTheme.textSecondaryColor, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }

    // Calculer les années disponibles pour la sélection de comparaison
    final List<int> availableYearsForComparison = List<int>.generate(
            5, (i) => _selectedDate.year - i - 1)
        .where((year) => year >= 2010) // Limiter à partir de 2010 par exemple
        .toList();

    // Construire la ListView principale
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          // Sélecteur de Mois/Année et Options de Comparaison
          MonthYearSelector(
            initialDate: _selectedDate,
            onMonthYearChanged: _onMonthYearChanged,
            showComparisonOptions: true,
            availableYears: availableYearsForComparison,
            selectedComparisonYears: _selectedComparisonYears,
            onComparisonYearsChanged: _onComparisonYearsChanged,
          ),
          const SizedBox(height: 20),

          // Titre de la section Statistiques
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              'Statistiques pour ${DateFormat('MMMM yyyy', 'fr_FR').format(_selectedDate)}',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimaryColor),
            ),
          ),
          const SizedBox(height: 12),

          // Afficher la carte de statistiques si les données sont disponibles
          if (_monthlyData != null)
            _buildMonthlyStats()
          // Sinon, si pas en chargement, afficher un message indiquant l'absence de stats
          else if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Center(
                child: Text(
                  'Statistiques non disponibles pour ${DateFormat('MMMM yyyy', 'fr_FR').format(_selectedDate)}.',
                  style: const TextStyle(
                      color: AppTheme.textSecondaryColor, fontSize: 15),
                ),
              ),
            ),

          const SizedBox(height: 20),

          // --- Section Graphique (avec if/else corrigé) ---
          // Afficher la carte du graphique seulement si les données sont disponibles
          if (_monthlyData != null)
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                  side: const BorderSide(
                      color: AppTheme.cardBorderColor, width: 0.5)),
              color: AppTheme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('Production quotidienne',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimaryColor)),
                    const SizedBox(height: 8),
                    const Text(
                        'Touchez une barre pour afficher les détails de ce jour.',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textSecondaryColor)),
                    const SizedBox(height: 20),
                    MonthlyProductionChart(
                      key: ValueKey(
                          'monthly_chart_${_selectedDate.year}_${_selectedDate.month}_$_showComparisonAsOverlay'),
                      monthlyData:
                          _monthlyData!, // On sait que ce n'est pas null ici
                      comparisonData:
                          _comparisonData.isEmpty ? null : _comparisonData,
                      showComparisonAsOverlay: _showComparisonAsOverlay,
                    ),
                  ],
                ),
              ),
            )
          // **CORRECTION ICI**: Le else if est maintenant correctement lié au if
          else if (!_isLoading)
            // Message affiché si pas de données après chargement
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 30.0), // Ajouter du padding
                child: Text(
                  "Aucune donnée graphique disponible pour ${DateFormat('MMMM yyyy', 'fr_FR').format(_selectedDate)}.",
                  style: const TextStyle(
                      color: AppTheme.textSecondaryColor, fontSize: 15),
                  textAlign: TextAlign.center, // Centrer le texte
                ),
              ),
            ),
          // --- Fin Section Graphique Corrigée ---

          const SizedBox(height: 30),
          // Information de mise à jour
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              'Données mises à jour: ${DateFormat('dd/MM/yyyy HH:mm', 'fr_BE').format(DateTime.now())}',
              style: const TextStyle(
                  color: AppTheme.textSecondaryColor, fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  /// Construit la carte des statistiques pour le mois sélectionné.
  Widget _buildMonthlyStats() {
    // _monthlyData ne peut pas être null ici car vérifié avant appel

    final double totalEnergyKWh = PowerUtils.WhTokWh(_monthlyData!.totalEnergy);

    // *** NOUVEAU: Récupérer les préférences pour le tarif ***
    final userPreferencesNotifier = Provider.of<ValueNotifier<UserPreferences?>>(context);
    final userPreferences = userPreferencesNotifier.value;
    final double? energyRate = userPreferences?.energyRate;
    String estimatedSavingsText = 'Prix kWh non défini';
    Color savingsColor = AppTheme.textSecondaryColor;
    IconData savingsIcon = Icons.info_outline;

    if (energyRate != null && energyRate > 0) {
      final double estimatedSavings = totalEnergyKWh * energyRate;
      // Utiliser NumberFormat pour le format monétaire localisé
      estimatedSavingsText = NumberFormat.currency(locale: 'fr_BE', symbol: '€', decimalDigits: 2).format(estimatedSavings);
      savingsColor = Colors.green;
      savingsIcon = Icons.euro_symbol;
    }
    // *** FIN NOUVEAU ***

    // *** Logique CORRIGÉE pour la moyenne quotidienne ***
    final DateTime now = DateTime.now();
    // Vérifier si le mois sélectionné est le mois actuel de l'année actuelle
    final bool isCurrentMonthAndYear =
        (_selectedDate.year == now.year && _selectedDate.month == now.month);
    int divisor; // Le nombre par lequel on divise pour la moyenne
    String averageDailyLabel = 'Moyenne par jour'; // Libellé par défaut

    if (isCurrentMonthAndYear) {
      // Si c'est le mois en cours, diviser par le jour actuel
      divisor = now.day;
      averageDailyLabel = 'Moyenne (en cours)'; // Adapter le libellé
    } else {
      // Si c'est un mois passé, diviser par le nombre total de jours de ce mois
      divisor =
          DateUtils.getDaysInMonth(_selectedDate.year, _selectedDate.month);
    }
    // Sécurité : s'assurer que le diviseur est au moins 1
    divisor = max(1, divisor);
    // Calculer la moyenne
    final double averageDailyKWh = (divisor == 0)
        ? 0
        : totalEnergyKWh / divisor; // Sécurité division par zéro
    // *** Fin Logique CORRIGÉE ***

    // Rechercher la meilleure journée (logique inchangée)
    double bestDayEnergy = 0;
    DateTime? bestDayDate;
    if (_monthlyData!.dailyData.isNotEmpty) {
      bestDayDate = _monthlyData!.dailyData.reduce((curr, next) {
        if (next.totalEnergy > curr.totalEnergy) {
          bestDayEnergy = next.totalEnergy; // Garder l'énergie max
          return next;
        } else {
          bestDayEnergy = curr.totalEnergy; // Garder l'énergie max
          return curr;
        }
      }).date;
      // S'assurer que bestDayEnergy a la bonne valeur après reduce
      bestDayEnergy =
          _monthlyData!.dailyData.map((d) => d.totalEnergy).reduce(max);
    }

    // Formater la date du meilleur jour
    final String bestDayFormatted = bestDayDate != null
        ? DateFormat('d MMMM', 'fr_FR').format(bestDayDate) // Format plus court
        : 'N/A';
    // Calculer l'énergie du meilleur jour en kWh
    final double bestDayEnergyKWh = PowerUtils.WhTokWh(bestDayEnergy);

    // Construire la carte
    return Card(
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
          children: <Widget>[
            // Ligne Production totale du mois
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.calendar_month_outlined,
                    color: AppTheme.primaryColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Production totale du mois',
                          style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.textSecondaryColor),
                          softWrap: true, // Permet le retour à la ligne
                          overflow: TextOverflow.ellipsis, // Affiche des points de suspension si le texte est trop long
                      ),
                      const SizedBox(height: 4),
                      Text('${totalEnergyKWh.toStringAsFixed(1)} kWh',
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor),
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20), // Espace
            // Ligne Moyenne journalière + Meilleur jour + Économies
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                // Colonne Moyenne journalière
                Column(
                  children: <Widget>[
                    Text(averageDailyLabel, // Utiliser le libellé corrigé
                        style: const TextStyle(
                            fontSize: 14, color: AppTheme.textSecondaryColor)),
                    Text(
                        '${averageDailyKWh.toStringAsFixed(2)} kWh', // Utiliser la valeur corrigée
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimaryColor)),
                  ],
                ),
                // Colonne Meilleure journée
                Column(
                  children: <Widget>[
                    const Text('Meilleur jour',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textSecondaryColor)),
                    Text('${bestDayEnergyKWh.toStringAsFixed(2)} kWh',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                    // Afficher la date seulement si trouvée
                    if (bestDayDate != null)
                      Text(bestDayFormatted,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondaryColor)),
                  ],
                ),
                // *** NOUVEAU: Colonne Économies estimées ***
                Column(
                  children: <Widget>[
                    const Text('Économies (mois)',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textSecondaryColor)),
                    Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           Icon(savingsIcon, color: savingsColor, size: 18),
                           const SizedBox(width: 4),
                           Text(estimatedSavingsText,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: savingsColor)),
                        ],
                    ),
                  ],
                ),
                // *** FIN NOUVEAU ***
              ],
            ),
            // Afficher le résumé de la comparaison s'il y a des données
            // Le widget original l'avait ici, on le garde ici pour l'instant
            if (_comparisonData.isNotEmpty) _buildComparisonSummary(),
          ],
        ),
      ),
    );
  }

  /// Construit un résumé de la comparaison avec l'année précédente.
  Widget _buildComparisonSummary() {
    // Vérifier si on a les données nécessaires
    if (_comparisonData.isEmpty || _monthlyData == null) {
      return const SizedBox.shrink();
    }

    // Calculer l'énergie du mois en cours
    final double currentEnergyKWh =
        PowerUtils.WhTokWh(_monthlyData!.totalEnergy);
    // Déterminer l'année précédente
    final int previousYear = _selectedDate.year - 1;

    // Vérifier si on a les données pour l'année précédente
    if (_comparisonData.containsKey(previousYear)) {
      final MonthlySolarData? previousYearData = _comparisonData[
          previousYear]; // Peut être null si l'API a échoué pour cette année
      if (previousYearData == null) {
        return const SizedBox.shrink(); // Ne rien afficher si N-1 a échoué
      }

      final double previousEnergyKWh =
          PowerUtils.WhTokWh(previousYearData.totalEnergy);

      // Calculer la différence en pourcentage
      double percentDiff = 0;
      // Gérer la division par zéro et le cas où l'énergie actuelle est positive mais N-1 était 0
      if (previousEnergyKWh > 0) {
        percentDiff =
            ((currentEnergyKWh - previousEnergyKWh) / previousEnergyKWh) * 100;
      } else if (currentEnergyKWh > 0) {
        percentDiff = double.infinity; // Augmentation "infinie"
      } // Si les deux sont 0, percentDiff reste 0

      // Déterminer le style en fonction de l'augmentation/diminution
      final bool isIncrease = percentDiff >= 0; // >= pour inclure 0%
      // Formater le texte du pourcentage
      final String percentText = percentDiff.isFinite
          ? '${isIncrease ? '+' : ''}${percentDiff.toStringAsFixed(1)}%'
          : (isIncrease ? '+Inf%' : 'N/A'); // Gérer l'infini
      // Choisir couleur et icône
      final Color diffColor = isIncrease ? Colors.green : Colors.red;
      final IconData diffIcon =
          isIncrease ? Icons.arrow_upward : Icons.arrow_downward;

      // Retourner le widget formaté
      return Padding(
        padding: const EdgeInsets.only(top: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Divider(height: 1, thickness: 0.5), // Séparateur visuel
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.center, // Centrer la comparaison
              children: <Widget>[
                Text(
                  'Comparaison avec $previousYear: ',
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textSecondaryColor),
                ),
                const SizedBox(width: 8),
                // Afficher le pourcentage
                Text(
                  percentText,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: diffColor),
                ),
                const SizedBox(width: 4),
                // Afficher l'icône correspondante (si pas 0% et fini)
                if (percentDiff != 0 && percentDiff.isFinite)
                  Icon(diffIcon, size: 16, color: diffColor),
              ],
            ),
          ],
        ),
      );
    }

    // Ne rien afficher si pas de données pour N-1
    return const SizedBox.shrink();
  }

  // Fonction pour partager les données mensuelles
  void _shareMonthlyData() {
    if (_monthlyData == null) {
      // Ne rien faire si les données ne sont pas chargées
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune donnée à partager'),
        ),
      );
      return;
    }

    final String monthYear = DateFormat('MMMM yyyy', 'fr_FR').format(_selectedDate);
    final double totalEnergyKWh = PowerUtils.WhTokWh(_monthlyData!.totalEnergy);

    // Récupérer les préférences pour le tarif
    final userPreferencesNotifier = Provider.of<ValueNotifier<UserPreferences?>>(context, listen: false);
    final userPreferences = userPreferencesNotifier.value;
    final double? energyRate = userPreferences?.energyRate;
    String estimatedSavingsText = 'Prix kWh non défini';

    if (energyRate != null && energyRate > 0) {
      final double estimatedSavings = totalEnergyKWh * energyRate;
      estimatedSavingsText = NumberFormat.currency(locale: 'fr_BE', symbol: '€', decimalDigits: 2).format(estimatedSavings);
    }

    // Logique pour la moyenne quotidienne (reprise de _buildMonthlyStats)
    final DateTime now = DateTime.now();
    final bool isCurrentMonthAndYear =
        (_selectedDate.year == now.year && _selectedDate.month == now.month);
    int divisor;
    if (isCurrentMonthAndYear) {
      divisor = now.day;
    } else {
      divisor = DateUtils.getDaysInMonth(_selectedDate.year, _selectedDate.month);
    }
    divisor = max(1, divisor);
    final double averageDailyKWh = (divisor == 0) ? 0 : totalEnergyKWh / divisor;

    // Rechercher la meilleure journée (reprise de _buildMonthlyStats)
    double bestDayEnergy = 0;
    DateTime? bestDayDate;
    if (_monthlyData!.dailyData.isNotEmpty) {
      bestDayDate = _monthlyData!.dailyData.reduce((curr, next) {
        if (next.totalEnergy > curr.totalEnergy) {
          bestDayEnergy = next.totalEnergy;
          return next;
        } else {
          bestDayEnergy = curr.totalEnergy;
          return curr;
        }
      }).date;
       bestDayEnergy = _monthlyData!.dailyData.map((d) => d.totalEnergy).reduce(max);
    }
     final double bestDayEnergyKWh = PowerUtils.WhTokWh(bestDayEnergy);
     final String bestDayFormatted = bestDayDate != null
        ? DateFormat('d MMMM', 'fr_FR').format(bestDayDate)
        : 'N/A';


    final String shareText = """
Production solaire pour $monthYear :
Énergie totale produite : ${totalEnergyKWh.toStringAsFixed(1)} kWh
Moyenne par jour : ${averageDailyKWh.toStringAsFixed(2)} kWh
Meilleur jour : ${bestDayEnergyKWh.toStringAsFixed(2)} kWh${bestDayDate != null ? ' ($bestDayFormatted)' : ''}
Économies estimées : $estimatedSavingsText

Suivez votre production solaire avec SolarEdge Monitor !
""";

    Share.share(shareText, subject: 'Ma production solaire pour $monthYear');
  }
} // Fin de _MonthlyScreenState
