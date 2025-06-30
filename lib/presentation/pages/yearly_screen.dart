import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/data/models/user_preferences.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:solaredge_monitor/presentation/widgets/yearly_production_chart.dart';
import 'package:solaredge_monitor/utils/power_utils.dart';
import 'package:intl/intl.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Import ServiceManager pour accéder au ValueNotifier
import 'package:solaredge_monitor/presentation/pages/api_configuration_screen.dart'; // Import ApiConfigurationScreen
import 'package:share_plus/share_plus.dart'; // Import pour la fonctionnalité de partage

class YearlyScreen extends StatefulWidget {
  final int? initialYear;

  const YearlyScreen({super.key, this.initialYear});

  @override
  State<YearlyScreen> createState() => _YearlyScreenState();
}

class _YearlyScreenState extends State<YearlyScreen> {
  late int _selectedYear;
  List<YearlySolarData> _yearsData = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  List<int> _yearsToDisplay = [];

  // Instance du service API et son écouteur
  SolarEdgeApiService? _solarEdgeServiceInstance;
  VoidCallback?
      _apiServiceListener; // Utiliser VoidCallback pour l'écouteur du ValueNotifier

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialYear ?? DateTime.now().year;
    _updateYearsToDisplay(); // Calculer les années initiales à charger
    // Le chargement des données est maintenant déclenché par didChangeDependencies
  }

  // Define the listener callback function
  void _onApiServiceChanged() {
    final currentApiService =
        _solarEdgeServiceInstance; // Use the stored instance
    debugPrint(
        "DEBUG YearlyScreen: _onApiServiceChanged called. New API Service is ${currentApiService == null ? 'null' : 'instance'}.");
    // Déclencher le chargement des données si le service API change
    if (_solarEdgeServiceInstance != currentApiService) {
      // This check might be redundant now, but keep for safety
      debugPrint(
          "INFO YearlyScreen: Service API détecté/mis à jour, déclenchement du chargement.");
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
    debugPrint("DEBUG YearlyScreen: didChangeDependencies called.");

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
          "DEBUG YearlyScreen: apiServiceNotifier changed. New API Service is ${currentApiService == null ? 'null' : 'instance'}.");
      // Déclencher le chargement des données si le service API change
      if (_solarEdgeServiceInstance != currentApiService) {
        debugPrint(
            "INFO YearlyScreen: Service API détecté/mis à jour, déclenchement du chargement.");
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
        "DEBUG YearlyScreen: didChangeDependencies - initialApiService from ValueNotifier is ${initialApiService == null ? 'null' : 'instance'}.");
    if (initialApiService != null && _solarEdgeServiceInstance == null) {
      debugPrint(
          "INFO YearlyScreen: Service API disponible au démarrage, déclenchement du chargement initial.");
      _solarEdgeServiceInstance = initialApiService;
      unawaited(_loadData());
    } else if (initialApiService == null && !_hasError && !_isLoading) {
      // Si le service est null au démarrage et qu'on n'est pas déjà en erreur/chargement
      debugPrint(
          "INFO YearlyScreen: Service API null au démarrage, affichage de la config requise.");
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

  /// Met à jour la liste [_yearsToDisplay] qui contient les années
  /// dont les données doivent être chargées (5 dernières + année sélectionnée).
  void _updateYearsToDisplay() {
    final currentYear = DateTime.now().year;
    // Utiliser un Set pour gérer facilement les doublons
    final yearsSet = <int>{};
    // Ajouter les 5 dernières années (année actuelle incluse)
    for (int i = 0; i < 5; i++) {
      yearsSet.add(currentYear - i);
    }
    // Ajouter l'année sélectionnée (si elle n'y est pas déjà)
    yearsSet.add(_selectedYear);

    // Convertir en liste et trier par ordre décroissant pour l'affichage/logique
    _yearsToDisplay = yearsSet.toList()..sort((a, b) => b.compareTo(a));
    // Pas besoin de setState ici car cette fonction est appelée depuis des endroits
    // qui gèrent déjà le setState (initState ou _onYearChanged).
  }

  /// Gère le changement d'année sélectionnée par l'utilisateur.
  void _onYearChanged(int year) {
    // Éviter de recharger si l'année sélectionnée est la même
    if (year == _selectedYear) return;

    setState(() {
      _selectedYear = year;
      _isLoading = true; // Activer l'indicateur de chargement
      _hasError = false; // Réinitialiser l'erreur lors du changement d'année
      _yearsData = []; // Optionnel: Vider les anciennes données immédiatement
      _updateYearsToDisplay(); // Recalculer les années à charger (inclut la nouvelle)
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

  /// Charge les données annuelles depuis le service API pour les années nécessaires.
  Future<void> _loadData() async {
    // Si le widget n'est plus dans l'arbre, ne rien faire
    if (!mounted) return;

    // Utiliser l'instance stockée du service API
    final solarEdgeService = _solarEdgeServiceInstance;

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

    // S'assurer que l'état de chargement est bien actif au début de l'appel
    // et réinitialiser l'état d'erreur.
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      debugPrint("Chargement des données pour les années : $_yearsToDisplay");

      // Créer une liste de Futures pour chaque appel API
      final List<Future<YearlySolarData>> yearDataFutures = _yearsToDisplay
          .map((year) => solarEdgeService.getYearlyEnergy(year))
          .toList();

      // Attendre que tous les appels API se terminent
      final List<YearlySolarData> yearlyResults =
          await Future.wait(yearDataFutures);

      // Si le widget est toujours monté après les appels asynchrones
      if (mounted) {
        setState(() {
          // Filtrer les résultats pour ne garder que ceux avec une année valide (sécurité)
          _yearsData = yearlyResults.where((data) => data.year > 0).toList();
          _isLoading = false; // Fin du chargement
          _hasError =
              false; // Réinitialiser l'erreur si les données ont été chargées avec succès
          // On pourrait ajouter une vérification ici si _yearsData est vide après le filtre
        });
      }
    } catch (e, stacktrace) {
      // Capturer l'erreur et la stacktrace
      debugPrint('❌ Erreur lors du chargement des données annuelles: $e');
      debugPrint(
          stacktrace.toString()); // Afficher la stacktrace pour le débogage
      if (mounted) {
        setState(() {
          _isLoading = false; // Fin du chargement (même si erreur)
          _hasError = true; // Indiquer qu'il y a eu une erreur
          // Formater le message d'erreur pour l'utilisateur
          _errorMessage = (e is Exception)
              ? e.toString().replaceFirst('Exception: ', '')
              : 'Une erreur inconnue est survenue.';
        });
      }
    }
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
        title: const Text('Production annuelle'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Partager',
            onPressed: _shareYearlyData, // Appeler la fonction de partage
          ),
          // Bouton pour rafraîchir manuellement les données
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraîchir',
            // Désactiver le bouton pendant le chargement
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
      ),
      // Afficher conditionnellement la vue de chargement, d'erreur ou de contenu
      body: _isLoading
          ? _buildLoadingView()
          : _hasError
              ? _buildErrorView()
              : _buildContentView(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 3, // L'index Année est sélectionné
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
              Navigator.of(context).pushNamed('/monthly');
              break;
            case 3:
              // Année déjà sélectionnée
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

  /// Construit le widget affiché pendant le chargement des données.
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

  /// Construit le widget affiché en cas d'erreur de chargement.
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
    } else if (_errorMessage.contains('Service SolarEdgeAPI non disponible')) {
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
              cleanErrorMessage, // Afficher le message d'erreur spécifique
              style: const TextStyle(
                  color: AppTheme.textSecondaryColor, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            // Bouton pour permettre à l'utilisateur de réessayer
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

  /// Construit la vue principale lorsque les données sont chargées (ou en partie).
  Widget _buildContentView() {
    // Vérifier si on n'a absolument aucune donnée après chargement
    final bool hasDataForSelectedYear =
        _yearsData.any((data) => data.year == _selectedYear);
    if (!_isLoading && _yearsData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.cloud_off,
                size: 60, color: AppTheme.textSecondaryColor),
            const SizedBox(height: 16),
            const Text('Aucune donnée de production trouvée.',
                style: TextStyle(
                    color: AppTheme.textSecondaryColor, fontSize: 16)),
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

    // Construire la liste scrollable du contenu
    return RefreshIndicator(
      onRefresh: _loadData, // Permet de rafraîchir en tirant vers le bas
      color: AppTheme.primaryColor,
      child: ListView(
        padding: const EdgeInsets.all(16.0), // Padding global
        children: <Widget>[
          // Sélecteur d'année
          _buildYearSelector(),
          const SizedBox(height: 20),

          // Titre de la section statistiques
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              'Statistiques $_selectedYear',
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimaryColor),
            ),
          ),
          const SizedBox(height: 12),

          // Afficher les statistiques seulement si des données existent pour l'année sélectionnée
          if (hasDataForSelectedYear)
            _buildYearlyStats()
          else if (!_isLoading) // Si chargement terminé et pas de données
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Center(
                child: Text(
                  'Aucune donnée trouvée pour l\'année $_selectedYear.',
                  style: const TextStyle(
                      color: AppTheme.textSecondaryColor, fontSize: 15),
                ),
              ),
            ),

          const SizedBox(height: 20),

          // Afficher le graphique seulement si on a des données (même si pas pour l'année sélectionnée)
          if (_yearsData.isNotEmpty)
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
                    const Text('Analyse de la production',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimaryColor)),
                    const SizedBox(height: 8),
                    const Text(
                        'Touchez une barre pour afficher les détails de cette année.',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textSecondaryColor)),
                    const SizedBox(height: 20),
                    // Widget du graphique
                    YearlyProductionChart(
                      // Clé unique pour forcer la reconstruction si les données ou l'année changent
                      key: ValueKey('yearly_chart_$_selectedYear'),
                      yearsData: _yearsData, // Passer les données chargées
                      selectedYear:
                          _selectedYear, // Passer l'année sélectionnée
                      // Passer les préférences utilisateur au graphique
                      userPreferences: Provider.of<ValueNotifier<UserPreferences?>>(context).value,
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 30),
          // Informations de mise à jour (Exemple)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              // Utiliser la date/heure actuelle pour l'exemple
              'Données mises à jour: ${DateFormat('dd/MM/yyyy HH:mm', 'fr_BE').format(DateTime.now())}',
              style: const TextStyle(
                  color: AppTheme.textSecondaryColor, fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
    // Ajouter un retour par défaut pour éviter l'erreur de non-nullabilité
    return const SizedBox.shrink();
  }

  /// Construit le widget de sélection de l'année.
  Widget _buildYearSelector() {
    final currentYear = DateTime.now().year;
    // Déterminer la première année possible (ex: 2010 ou la plus ancienne dans les données si disponible)
    int firstYear = 2010; // Valeur par défaut
    // Générer la liste des années pour le Dropdown
    final List<int> allAvailableYears =
        List<int>.generate(currentYear - firstYear + 1, (i) => firstYear + i)
            .reversed // Pour afficher les plus récentes en premier
            .toList();

    // S'assurer que l'année sélectionnée est bien dans la liste, sinon prendre la plus récente
    final int validSelectedYear = allAvailableYears.contains(_selectedYear)
        ? _selectedYear
        : allAvailableYears.first;

    return Card(
      elevation: 0, // Pas d'ombre
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          side: const BorderSide(color: AppTheme.cardBorderColor, width: 0.5)),
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Sélectionner une année',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimaryColor)),
            const SizedBox(height: 12),
            // Widget Dropdown pour choisir l'année
            DropdownButtonFormField<int>(
              value: validSelectedYear, // Utiliser la valeur validée
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                labelText: 'Année',
              ),
              // Générer les items du dropdown
              items: allAvailableYears
                  .map((year) => DropdownMenuItem<int>(
                      value: year, child: Text(year.toString())))
                  .toList(),
              // Callback appelé quand une année est sélectionnée
              onChanged: (int? year) {
                // Vérifier si une année a été sélectionnée et si elle est différente
                if (year != null && year != _selectedYear) {
                  _onYearChanged(
                      year); // Appeler la fonction de changement d'année
                }
              },
            ),
            const SizedBox(height: 12),
            const Text(
                'Comparaison avec les 5 dernières années affichée dans le graphique.',
                style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondaryColor,
                    fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  /// Construit la carte des statistiques pour l'année sélectionnée.
  Widget _buildYearlyStats() {
    // Trouver les données pour l'année sélectionnée dans la liste chargée
    YearlySolarData? selectedYearData;
    try {
      selectedYearData =
          _yearsData.firstWhere((data) => data.year == _selectedYear);
    } catch (e) {
      // Gérer le cas où l'année n'est pas trouvée (ne devrait pas arriver si hasDataForSelectedYear est true)
      debugPrint(
          "Avertissement: Données non trouvées pour l'année $_selectedYear dans _buildYearlyStats");
      return const SizedBox.shrink(); // Ne rien afficher si pas de données
    }

    // Calculer l'énergie totale en kWh
    final double totalEnergyKWh =
        PowerUtils.WhTokWh(selectedYearData.totalEnergy);

    // Trouver le meilleur mois de production
    MonthlySolarData? bestMonthData;
    if (selectedYearData.monthlyData.isNotEmpty) {
      // Utiliser reduce pour trouver le mois avec l'énergie maximale
      bestMonthData = selectedYearData.monthlyData.reduce((currentMax, month) =>
          month.totalEnergy > currentMax.totalEnergy ? month : currentMax);
    }
    // Formater le nom du meilleur mois
    final String bestMonthName = bestMonthData != null
        ? DateFormat('MMMM', 'fr_FR').format(bestMonthData.month)
        : 'N/A';
    // Calculer l'énergie du meilleur mois en kWh
    final double bestMonthEnergyKWh = bestMonthData != null
        ? PowerUtils.WhTokWh(bestMonthData.totalEnergy)
        : 0;

    // Comparaison avec l'année précédente (N-1)
    final int previousYear = _selectedYear - 1;
    YearlySolarData? previousYearData;
    try {
      // Trouver les données de l'année précédente
      previousYearData =
          _yearsData.firstWhere((data) => data.year == previousYear);
    } catch (e) {
      previousYearData = null; // Pas de données pour N-1
    }

    double? percentChange; // Pourcentage de changement par rapport à N-1
    // Calculer le pourcentage si les données N-1 existent et sont valides
    if (previousYearData != null) {
      final double previousEnergyKWh =
          PowerUtils.WhTokWh(previousYearData.totalEnergy);
      if (previousEnergyKWh > 0) {
        // Éviter la division par zéro
        percentChange =
            ((totalEnergyKWh - previousEnergyKWh) / previousEnergyKWh) * 100;
      }
    }

    // *** Logique CORRIGÉE pour la moyenne mensuelle ***
    final int currentSystemYear = DateTime.now().year;
    final bool isCurrentYear = (_selectedYear == currentSystemYear);
    String averageMonthlyText;
    String averageMonthlyLabel = 'Moyenne mensuelle';

    if (isCurrentYear) {
      // Année en cours : afficher un placeholder car la moyenne sur 12 mois n'est pas calculable
      averageMonthlyLabel = 'Moyenne (en cours)';
      averageMonthlyText = '- kWh'; // Placeholder
    } else {
      // Années passées : calculer la moyenne sur 12 mois
      final double averageMonthlyKWh = totalEnergyKWh / 12.0;
      averageMonthlyText = '${averageMonthlyKWh.toStringAsFixed(0)} kWh';
    }
    // *** Fin Logique CORRIGÉE ***

    // --- Calcul et affichage des Économies estimées ---
    // Accéder aux préférences utilisateur via le ValueNotifier
    final userPreferencesNotifier =
        Provider.of<ValueNotifier<UserPreferences?>>(context);
    final userPreferences = userPreferencesNotifier.value;

    double? energyRate = userPreferences?.energyRate; // Récupérer le tarif (nom corrigé)
    String estimatedSavingsText;
    IconData savingsIcon;
    Color savingsColor;

    if (energyRate != null && energyRate > 0) { // Utiliser energyRate
      final double estimatedSavings = totalEnergyKWh * energyRate; // Calcul
      estimatedSavingsText =
          '${estimatedSavings.toStringAsFixed(2)} €'; // Formatage
      savingsIcon = Icons.euro_symbol_outlined;
      savingsColor = Colors.green; // Vert pour les économies
    } else {
      estimatedSavingsText = 'Prix kWh non défini'; // Message si tarif manquant
      savingsIcon = Icons.info_outline;
      savingsColor = Colors.grey; // Gris si non défini
    }
    // --- Fin Calcul et affichage des Économies estimées ---

    // Construire la carte de statistiques
    return Card(
      elevation: 0, // Pas d'ombre
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          side: const BorderSide(color: AppTheme.cardBorderColor, width: 0.5)),
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Ligne : Production totale + Variation N-1
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Icône
                const Icon(Icons.solar_power_outlined,
                    color: AppTheme.primaryColor, size: 24),
                const SizedBox(width: 12),
                // Texte Production totale
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Production totale',
                          style: TextStyle(
                              fontSize: 16,
                              color: AppTheme.textSecondaryColor),
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text('${totalEnergyKWh.toStringAsFixed(0)} kWh',
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
                // Afficher la variation seulement si elle a été calculée
                if (percentChange != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: (percentChange >= 0 ? Colors.green : Colors.red)
                            .withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Icône flèche haut/bas
                        Icon(
                            percentChange >= 0
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            color:
                                percentChange >= 0 ? Colors.green : Colors.red,
                            size: 14),
                        const SizedBox(width: 4),
                        // Texte du pourcentage
                        Text(
                            '${percentChange >= 0 ? '+' : ''}${percentChange.toStringAsFixed(1)}%',
                            style: TextStyle(
                                color: percentChange >= 0
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20), // Espace vertical
            // Ligne : Moyenne mensuelle + Meilleur mois + Économies estimées
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceAround, // Espacer les éléments
              children: <Widget>[
                // Colonne Moyenne mensuelle
                Expanded( // Utiliser Expanded
                  child: Column(
                    children: <Widget>[
                      const Text('Moyenne mensuelle', // Utiliser le libellé corrigé
                          style: TextStyle(
                              fontSize: 14, color: AppTheme.textSecondaryColor)),
                      Text(averageMonthlyText, // Utiliser le texte corrigé
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimaryColor)),
                    ],
                  ),
                ),

                // Colonne Meilleur mois
                Expanded( // Utiliser Expanded
                  child: Column(
                    children: <Widget>[
                      const Text('Meilleur mois',
                          style: TextStyle(
                              fontSize: 14, color: AppTheme.textSecondaryColor)),
                      Text('${bestMonthEnergyKWh.toStringAsFixed(0)} kWh',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                      Text(bestMonthName,
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondaryColor)),
                    ],
                  ),
                ),

                // Colonne Économies estimées
                Expanded( // Utiliser Expanded
                  child: Column(
                    children: <Widget>[
                      const Text('Économies estimées',
                          style: TextStyle(
                              fontSize: 14, color: AppTheme.textSecondaryColor)),
                      Row(
                        // Utiliser un Row pour l'icône et le texte
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(savingsIcon,
                              color: savingsColor, size: 18), // Icône
                          const SizedBox(width: 4),
                          Text(estimatedSavingsText, // Texte des économies
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      savingsColor)), // Couleur basée sur l'état
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Fonction pour partager les données annuelles
  void _shareYearlyData() {
    // Trouver les données pour l'année sélectionnée
    YearlySolarData? selectedYearData;
    try {
      selectedYearData =
          _yearsData.firstWhere((data) => data.year == _selectedYear);
    } catch (e) {
      // Si pas de données pour l'année sélectionnée, ne rien faire
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune donnée à partager pour cette année'),
        ),
      );
      return;
    }

    final double totalEnergyKWh = PowerUtils.WhTokWh(selectedYearData.totalEnergy);

    // Trouver le meilleur mois de production (reprise de _buildYearlyStats)
    MonthlySolarData? bestMonthData;
    if (selectedYearData.monthlyData.isNotEmpty) {
      bestMonthData = selectedYearData.monthlyData.reduce((currentMax, month) =>
          month.totalEnergy > currentMax.totalEnergy ? month : currentMax);
    }
    final String bestMonthName = bestMonthData != null
        ? DateFormat('MMMM', 'fr_FR').format(bestMonthData.month)
        : 'N/A';
    final double bestMonthEnergyKWh = bestMonthData != null
        ? PowerUtils.WhTokWh(bestMonthData.totalEnergy)
        : 0;

    // Comparaison avec l'année précédente (N-1) (reprise de _buildYearlyStats)
    final int previousYear = _selectedYear - 1;
    YearlySolarData? previousYearData;
    try {
      previousYearData =
          _yearsData.firstWhere((data) => data.year == previousYear);
    } catch (e) {
      previousYearData = null;
    }

    double? percentChange;
    if (previousYearData != null) {
      final double previousEnergyKWh =
          PowerUtils.WhTokWh(previousYearData.totalEnergy);
      if (previousEnergyKWh > 0) {
        percentChange =
            ((totalEnergyKWh - previousEnergyKWh) / previousEnergyKWh) * 100;
      }
    }
    final String percentChangeText = percentChange != null
        ? '${percentChange >= 0 ? '+' : ''}${percentChange.toStringAsFixed(1)}%'
        : 'N/A';


    // Récupérer les préférences pour le tarif (reprise de _buildYearlyStats)
    final userPreferencesNotifier =
        Provider.of<ValueNotifier<UserPreferences?>>(context, listen: false);
    final userPreferences = userPreferencesNotifier.value;
    double? energyRate = userPreferences?.energyRate;
    String estimatedSavingsText;

    if (energyRate != null && energyRate > 0) {
      final double estimatedSavings = totalEnergyKWh * energyRate;
      estimatedSavingsText = '${estimatedSavings.toStringAsFixed(2)} €';
    } else {
      estimatedSavingsText = 'Prix kWh non défini';
    }


    final String shareText = """
Production solaire pour l'année $_selectedYear :
Énergie totale produite : ${totalEnergyKWh.toStringAsFixed(0)} kWh
Meilleur mois : ${bestMonthEnergyKWh.toStringAsFixed(0)} kWh ($bestMonthName)
Variation par rapport à ${previousYear} : $percentChangeText
Économies estimées : $estimatedSavingsText

Suivez votre production solaire avec SolarEdge Monitor !
""";

    Share.share(shareText, subject: 'Ma production solaire pour l\'année $_selectedYear');
  }
} // Fin de _YearlyScreenState
