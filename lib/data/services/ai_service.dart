import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:solaredge_monitor/data/models/ai_assistant_model.dart';
import 'package:solaredge_monitor/data/models/user_preferences.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/data/services/weather_manager.dart';
import 'package:solaredge_monitor/data/services/stats_context_builder.dart'; // Import StatsContextBuilder
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Import ServiceManager
// Pour formater la puissance/énergie
import 'package:intl/intl.dart'; // Pour formater les dates et nombres
// Import LocationService

// --- Helper Functions (Global Scope) ---

String _monthName(DateTime date) {
  const monthNames = [
    "Janvier",
    "Février",
    "Mars",
    "Avril",
    "Mai",
    "Juin",
    "Juillet",
    "Août",
    "Septembre",
    "Octobre",
    "Novembre",
    "Décembre"
  ];
  if (date.month < 1 || date.month > 12) return "Mois Inconnu";
  return monthNames[date.month - 1];
}

double _solarElevation(DateTime ts, double latRad, double lonRad) {
  final d =
      ts.toUtc().difference(DateTime.utc(ts.year, 1, 1)).inSeconds / 86400.0;
  final g = 2 * math.pi / 365.25 * (d - 1);
  final declinationRad = 0.006918 -
      0.399912 * math.cos(g) +
      0.070257 * math.sin(g) -
      0.006758 * math.cos(2 * g) +
      0.000907 * math.sin(2 * g) -
      0.002697 * math.cos(3 * g) +
      0.00148 * math.sin(3 * g);
  final solarTimeCorrection = 0.0;
  final hourAngleRad = ((ts.toUtc().hour +
              ts.toUtc().minute / 60.0 +
              ts.toUtc().second / 3600.0) -
          12 +
          solarTimeCorrection) *
      15 *
      math.pi /
      180.0;

  final sinElevation = math.sin(latRad) * math.sin(declinationRad) +
      math.cos(latRad) * math.cos(declinationRad) * math.cos(hourAngleRad);
  final elevationRad = math.asin(math.max(-1.0, math.min(1.0, sinElevation)));

  return elevationRad * 180.0 / math.pi;
}

class AiService with ChangeNotifier {
  final String apiKey;
  final ValueNotifier<SolarEdgeApiService?> apiServiceNotifier;
  final WeatherManager weatherManager;
  final ValueNotifier<UserPreferences?> userPrefsNotifier;
  final StatsContextBuilder _statsContextBuilder =
      StatsContextBuilder(); // Instance du builder de contexte

  late GenerativeModel _model;
  // Box<AiConversation> _conversationsBox;

  final StreamController<AiConversation> _conversationStreamController =
      StreamController.broadcast();
  Stream<AiConversation> get conversationStream =>
      _conversationStreamController.stream;

  AiConversation? _activeConversation;
  UserPreferences? _userPreferences; // Champ pour stocker les préférences utilisateur

  AiService({
    required this.apiKey,
    required this.apiServiceNotifier,
    required this.weatherManager,
    required this.userPrefsNotifier,
  }) {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash-latest',
      apiKey: apiKey,
      tools: _defineTools(), // Passer les outils définis
    );
    _userPreferences = userPrefsNotifier.value; // Initialiser avec la valeur actuelle
    debugPrint("AiService constructor: Initial _userPreferences.washingMachineKw=${_userPreferences?.washingMachineKw}, defaultWashingMachineDurationMin=${_userPreferences?.defaultWashingMachineDurationMin}");
    userPrefsNotifier.addListener(_onUserPreferencesChanged); // Écouter les changements
  }

  void _onUserPreferencesChanged() {
    _userPreferences = userPrefsNotifier.value;
    debugPrint("AiService: User preferences updated via notifier. washingMachineKw=${_userPreferences?.washingMachineKw}, defaultWashingMachineDurationMin=${_userPreferences?.defaultWashingMachineDurationMin}");
  }

  @override
  void dispose() {
    userPrefsNotifier.removeListener(_onUserPreferencesChanged); // Retirer l'écouteur
    _conversationStreamController.close();
    super.dispose();
  }

  // Méthode pour définir les outils disponibles pour le modèle
  List<Tool> _defineTools() {
    // Schéma pour getEnergyRange(startDate, endDate)
    final getEnergyRangeSchema = Schema(
      SchemaType.object,
      properties: {
        'startDate': Schema.string(
          description: 'Start date in YYYY-MM-DD format',
        ),
        'endDate': Schema.string(
          description: 'End date in YYYY-MM-DD format',
        ),
      },
      // requiredProperties: ['startDate', 'endDate'], // Removed
    );

    // Schéma pour getDailyEnergy(date)
    final getDailyEnergySchema = Schema(
      SchemaType.object,
      properties: {
        'date': Schema.string(
          description: 'Date in YYYY-MM-DD format',
        ),
      },
      // requiredProperties: ['date'], // Removed
    );

    // Schéma pour getForecast(hoursAhead)
    final getForecastSchema = Schema(
      SchemaType.object,
      properties: {
        'hoursAhead': Schema.integer(
          description: 'Number of hours ahead for the forecast',
        ),
      },
      // requiredProperties: ['hoursAhead'], // Removed
    );

    // Schéma pour suggestBestSlot(loadKw, start, end, durationMin)
    final suggestBestSlotSchema = Schema(
      SchemaType.object,
      properties: {
        'loadKw': Schema.number(
          description: 'Load in kW',
        ),
        
        'durationMin': Schema.integer(
          description: 'Duration in minutes',
        ),
      },
      // requiredProperties: ['loadKw', 'start', 'end', 'durationMin'], // Removed
    );

    // Schéma pour getSiteLocation()
    final getSiteLocationSchema = Schema(
      SchemaType.object,
      properties: {}, // Pas de paramètres requis
    );

    return [
      Tool(
        functionDeclarations: [
          FunctionDeclaration(
            'getEnergyRange',
            'Get total energy produced and peak power between two dates.',
            getEnergyRangeSchema,
          ),
          FunctionDeclaration(
            'getDailyEnergy',
            'Get total energy produced and peak power for a specific date.',
            getDailyEnergySchema,
          ),
          FunctionDeclaration(
            'getForecast',
            'Get weather forecast for a specified number of hours ahead.',
            getForecastSchema,
          ),
          FunctionDeclaration(
            'suggestBestSlot',
            'Suggest the best time slot to run an appliance based on solar production forecast.',
            suggestBestSlotSchema,
          ),
          // Removed comparePeriod tool
          FunctionDeclaration(
            'getSiteLocation',
            'Get the registered location (address and coordinates) of the solar installation site.',
            getSiteLocationSchema,
          ),
        ],
      ),
    ];
  }

  // Méthode pour exécuter un appel de fonction demandé par le modèle
  Future<Map<String, Object?>> _executeTool(FunctionCall functionCall) async {
    final solarService = apiServiceNotifier.value;
    final userPrefs = _userPreferences; // Utiliser la copie interne des préférences
    final solarEstimator =
        ServiceManager().solarEstimator; // Accéder via ServiceManager
    final locationService =
        ServiceManager().locationService; // Accéder au LocationService
    // weatherManager est un champ de la classe, pas besoin de le récupérer via ServiceManager ici

    switch (functionCall.name) {
      case 'getEnergyRange':
        if (solarService == null) {
          return {
            'error':
                'SolarEdge API service is not available for getEnergyRange.'
          };
        }
        final startDateStr = functionCall.args['startDate'] as String?;
        final endDateStr = functionCall.args['endDate'] as String?;

        if (startDateStr == null || endDateStr == null) {
          return {'error': 'Missing startDate or endDate for getEnergyRange.'};
        }

        try {
          final startDate = DateTime.parse(startDateStr);
          final endDate = DateTime.parse(endDateStr);

          final energyDataRange = await solarService
              .getEnergyRange(startDate, endDate, timeUnit: 'DAY');

          final totalEnergyKwh = energyDataRange.totalEnergy / 1000.0;
          final maxPeakPowerW = 0; // API limitation

          final result = {
            'startDate': DateFormat('yyyy-MM-dd').format(startDate),
            'endDate': DateFormat('yyyy-MM-DD').format(endDate),
            'totalEnergyKwh': totalEnergyKwh,
            'maxPeakPowerW': maxPeakPowerW,
          };
          return result;
        } catch (e) {
          debugPrint("Error executing getEnergyRange tool: $e");
          return {
            'error':
                'Could not retrieve energy data for the specified range: ${e.toString()}'
          }; // More specific error
        }

      case 'getDailyEnergy':
        if (solarService == null) {
          return {
            'error':
                'SolarEdge API service is not available for getDailyEnergy.'
          };
        }
        final dateStr = functionCall.args['date'] as String?;

        if (dateStr == null) {
          return {'error': 'Missing date for getDailyEnergy.'};
        }

        try {
          final date = DateTime.parse(dateStr);
          final dailyData = await solarService.getDailyEnergy(date);
          final result = {
            'date': DateFormat('yyyy-MM-dd').format(date),
            'totalEnergyKwh': dailyData.totalEnergy / 1000.0,
            'peakPowerW': dailyData.peakPower,
          };
          return result;
        } catch (e) {
          debugPrint("Error executing getDailyEnergy tool: $e");
          return {
            'error':
                'Could not retrieve daily energy data for the specified date: ${e.toString()}'
          }; // More specific error
        }

      case 'getForecast':
        // weatherManager is a non-nullable field, so no null check needed here.
        final hoursAhead = functionCall.args['hoursAhead'] as int?;
        final int effectiveHoursAhead = math.min(hoursAhead ?? 24, 24);

        try {
          final forecast =
              await weatherManager.getWeatherForecast(forceRefresh: false);
          if (forecast == null || forecast.hourlyForecast.isEmpty) {
            return {'error': 'Could not retrieve weather forecast data.'};
          }

          final now = DateTime.now();
          final relevantForecast = forecast.hourlyForecast
              .where((h) =>
                  h.timestamp.isAfter(now) &&
                  h.timestamp
                      .isBefore(now.add(Duration(hours: effectiveHoursAhead))))
              .toList();

          final List<Map<String, dynamic>> simplifiedForecast = relevantForecast
              .map((h) => {
                    'time': h.timestamp.toIso8601String(),
                    'temperature': h.temperature,
                    'precipitation': h.precipitation,
                    'condition': h.condition,
                    'solarIrradiance': h.shortwaveRadiation,
                  })
              .toList();

          return {'forecast': simplifiedForecast};
        } catch (e) {
          debugPrint("Error executing getForecast tool: $e");
          return {
            'error': 'Could not retrieve weather forecast: ${e.toString()}'
          }; // More specific error
        }

      case 'suggestBestSlot':
        debugPrint(
            "AiService._executeTool suggestBestSlot: UserPrefs washingMachineKw=${userPrefs?.washingMachineKw}, defaultWashingMachineDurationMin=${userPrefs?.defaultWashingMachineDurationMin}");
        if (solarEstimator == null) {
          return {
            'error': 'Le service d\'estimation solaire n\'est pas disponible.'
          };
        }
        // userPrefs est déjà récupéré au début de _executeTool
        if (userPrefs == null) {
          return {
            'error': 'Les préférences utilisateur ne sont pas disponibles.'
          };
        }

        double? loadKwFromArgs = functionCall.args['loadKw'] as double?;
        int? durationMinFromArgs = functionCall.args['durationMin'] as int?;
        debugPrint("AiService._executeTool suggestBestSlot: loadKwFromArgs=$loadKwFromArgs, durationMinFromArgs=$durationMinFromArgs");
        debugPrint("AiService._executeTool suggestBestSlot: userPrefs (internal _userPreferences) is ${userPrefs == null ? 'NULL' : 'NOT NULL'}. washingMachineKw=${userPrefs?.washingMachineKw}, defaultWashingMachineDurationMin=${userPrefs?.defaultWashingMachineDurationMin}");

        double finalLoadKw;
        // Si le LLM fournit une valeur valide, l'utiliser. Sinon, vérifier les préférences.
        if (loadKwFromArgs != null && loadKwFromArgs > 0) {
          finalLoadKw = loadKwFromArgs;
        } else if (userPrefs.washingMachineKw != null &&
            userPrefs.washingMachineKw! > 0) {
          finalLoadKw = userPrefs.washingMachineKw!;
        } else {
          // Si ni le LLM ni les préférences ne fournissent la puissance, demander à l'utilisateur.
          return {
            'error':
                'Veuillez préciser la puissance de votre lave-linge en kW (par exemple, 1.2).',
            'missing_param': 'loadKw'
          };
        }

        int finalDurationMin;
        // Si le LLM fournit une valeur valide, l'utiliser. Sinon, vérifier les préférences.
        if (durationMinFromArgs != null && durationMinFromArgs > 0) {
          finalDurationMin = durationMinFromArgs;
        } else if (userPrefs.defaultWashingMachineDurationMin != null &&
            userPrefs.defaultWashingMachineDurationMin! > 0) {
          finalDurationMin = userPrefs.defaultWashingMachineDurationMin!;
        } else {
          // Si ni le LLM ni les préférences ne fournissent la durée, demander à l'utilisateur.
          return {
            'error':
                'Veuillez préciser la durée du cycle de lavage en minutes (par exemple, 75).',
            'missing_param': 'durationMin'
          };
        }

        // Déterminer les heures de début et de fin (par défaut aujourd'hui si non fournies)
        final DateTime now = DateTime.now();
        final DateTime start = DateTime(now.year, now.month, now.day,
            now.hour, now.minute); // Commence à partir de maintenant
        final DateTime end = DateTime(now.year, now.month, now.day,
            23, 59, 59); // Jusqu'à la fin de la journée

        if (start.isAfter(end)) {
          return {
            'error': 'L\'heure de début doit être avant l\'heure de fin.'
          };
        }

        try {
          final slots = await solarEstimator.bestSlotBetween(
              start, end, finalLoadKw, finalDurationMin, userPrefs);

          if (slots.isEmpty) {
            return {
              'suggested': [],
              'message':
                  "Je n'ai pas trouvé de créneau optimal pour un appareil de ${finalLoadKw.toStringAsFixed(1)} kW durant $finalDurationMin minutes entre ${DateFormat.Hm('fr_FR').format(start)} et ${DateFormat.Hm('fr_FR').format(end)} avec les prévisions actuelles."
            };
          }
          final String formattedSlots = slots
              .map((s) => DateFormat('HH:mm').format(s))
              .join(', ');
          return {
            'suggested': slots
                .map((s) => DateFormat('yyyy-MM-ddTHH:mm:ss').format(s))
                .toList(),
            'message': "Les meilleurs créneaux pour lancer votre appareil de ${finalLoadKw.toStringAsFixed(1)} kW pendant $finalDurationMin minutes sont : $formattedSlots."
          };
        } catch (e) {
          debugPrint(
              "Error executing suggestBestSlot tool (solarEstimator.bestSlotBetween): $e");
          return {
            'error': 'Erreur lors de la suggestion de créneau: ${e.toString()}'
          };
        }

      // Removed comparePeriod case

      case 'getSiteLocation':
        if (locationService == null) {
          return {
            'error': 'Location service is not available for getSiteLocation.'
          };
        }
        try {
          final address = await locationService.getSavedAddress();
          final coords = await locationService.getSavedCoordinates();

          final result = {
            'address': address ?? 'Adresse non configurée',
            'latitude': coords.$1,
            'longitude': coords.$2,
            'source': coords.$3 ?? 'Source inconnue',
          };
          return result;
        } catch (e) {
          debugPrint("Error executing getSiteLocation tool: $e");
          return {
            'error': 'Could not retrieve site location data: ${e.toString()}'
          }; // More specific error
        }

      default:
        return {'error': 'Unknown tool called: ${functionCall.name}'};
    }
  }

  Future<void> setActiveConversation(String conversationId) async {
    // Logique pour charger depuis Hive ou créer si n'existe pas
    // _activeConversation = _conversationsBox.get(conversationId);
    // Pour l'exemple, on crée une nouvelle conversation vide
    _activeConversation =
        AiConversation.create(title: "Conversation $conversationId");
    _conversationStreamController.add(_activeConversation!);
    notifyListeners(); // Notify listeners after setting active conversation
  }

  AiConversation? get activeConversation => _activeConversation;

  // Méthode publique pour ajouter un message de l'IA à la conversation (utilisée par AssistantService)
  void addBotMessage(String content) {
    _addBotMessage(content); // Appelle la méthode interne
  }

  // Méthode interne pour ajouter un message de l'IA à la conversation
  void _addBotMessage(String content) {
    if (_activeConversation == null) return;
    final aiMessage = AiMessage(
      content: content,
      timestamp: DateTime.now(),
      isUser: false,
    );
    _activeConversation = _activeConversation!.addMessage(aiMessage);
    _conversationStreamController.add(_activeConversation!);
    notifyListeners();
    debugPrint("Réponse IA ajoutée à la conversation.");
  }

  Future<void> sendMessage(String message) async {
    if (_activeConversation == null) {
      debugPrint("Erreur: Aucune conversation active.");
      return;
    }

    // 1. Ajouter le message utilisateur à la conversation et notifier l'UI
    final userMessage = AiMessage(
      content: message,
      timestamp: DateTime.now(),
      isUser: true,
    );
    _activeConversation = _activeConversation!.addMessage(userMessage);
    _conversationStreamController.add(_activeConversation!);
    notifyListeners();

    // Lancer la collecte du contexte en parallèle
    final Future<String> contextFuture = _statsContextBuilder.buildContext();

    // Définir le system-prompt (amélioré)
    const String systemPrompt = """
Vous êtes Solar-Bot, un assistant spécialisé dans le suivi et l'analyse de la production d'énergie solaire via l'API SolarEdge et les données météo. Votre objectif est de fournir des informations précises et utiles aux utilisateurs concernant leur installation solaire.

Vous avez accès aux outils suivants pour récupérer des données et effectuer des calculs :
- getEnergyRange(startDate: YYYY-MM-DD, endDate: YYYY-MM-DD): Récupère l'énergie totale produite sur une plage de dates. Utilisez cet outil pour les demandes de bilan sur plusieurs jours, semaines, mois ou années.
- getDailyEnergy(date: YYYY-MM-DD): Récupère l'énergie totale produite et le pic de puissance pour une journée spécifique. Utilisez cet outil pour les demandes concernant un jour précis (aujourd'hui, hier, une date spécifique).
- getForecast(hoursAhead: int): Récupère les prévisions météo horaires pour les prochaines heures (maximum 24h). Utilisez cet outil pour les questions sur la météo future ou l'impact de la météo sur la production future.
- suggestBestSlot(loadKw: double, start: ISO 8601, end: ISO 8601, durationMin: int): Suggère le meilleur créneau horaire pour utiliser un appareil énergivore en se basant sur les prévisions de production solaire.
  **ATTENTION : N'incluez les paramètres `loadKw` et `durationMin` dans l'appel à cet outil UNIQUEMENT si l'utilisateur les mentionne EXPLICITEMENT dans sa requête (ex: "ma machine à laver de 2kW qui dure 90 minutes").**
  **Si l'utilisateur demande un créneau sans spécifier la puissance ou la durée (ex: "quand lancer ma machine à laver ?"), vous DEVEZ appeler `suggestBestSlot` SANS les paramètres `loadKw` et `durationMin`. L'outil utilisera alors les valeurs par défaut configurées par l'utilisateur.**
  - **TRÈS IMPORTANT : N'incluez JAMAIS `start` et `end` dans l'appel à l'outil `suggestBestSlot` à moins que l'utilisateur ne spécifie EXPLICITEMENT une plage horaire (ex: "entre 10h et 14h").** Si l'utilisateur ne donne PAS de plage horaire, l'outil `suggestBestSlot` utilisera les heures par défaut (maintenant jusqu'à la fin de la journée).
  - Si l'outil `suggestBestSlot` retourne une erreur avec `missing_param` (ex: `{'error': 'Veuillez préciser la puissance...', 'missing_param': 'loadKw'}`), cela signifie que l'information n'est ni dans la requête de l'utilisateur, ni dans ses préférences. Dans ce cas, vous devez poliment demander à l'utilisateur de fournir cette information spécifique. Par exemple: "Pour vous suggérer le meilleur moment, pourriez-vous me donner la puissance (en kW) de votre machine à laver ?" **Exemple de réponse attendue de l'IA :** "Pour vous suggérer le meilleur moment, pourriez-vous me donner la puissance (en kW) de votre machine à laver ?"

- getSiteLocation(): Récupère l'adresse et les coordonnées enregistrées du site de l'installation solaire. Utilisez cet outil si l'utilisateur pose une question sur l'emplacement de son installation.

Directives importantes :
1.  **Priorité aux outils :** Si une question peut être répondue en utilisant un ou plusieurs outils, utilisez-les en priorité. N'inventez pas de données.
2.  **Format des dates :** Lorsque vous appelez un outil qui nécessite une date, utilisez toujours le format YYYY-MM-DD. Pour l'outil `suggestBestSlot`, utilisez le format ISO 8601 (YYYY-MM-DDTHH:mm:ss) pour les heures de début et de fin.
3.  **Interprétation des requêtes et utilisation des préférences :** Analysez attentivement la demande de l'utilisateur. Pour `suggestBestSlot`, suivez les instructions spécifiques ci-dessus. Si d'autres informations manquent pour d'autres outils (comme une date pour `getDailyEnergy`), demandez poliment à l'utilisateur de les préciser.
4.  **Gestion des erreurs des outils :**
    *   Si l'outil `suggestBestSlot` retourne une erreur avec `missing_param`, suivez la directive spécifique pour cet outil (demander le paramètre manquant à l'utilisateur).
    *   Si `suggestBestSlot` ne trouve aucun créneau (`{'suggested': []}` mais sans erreur de paramètre), répondez : "Je n'ai pas trouvé de créneau optimal pour votre appareil avec les prévisions actuelles et les paramètres que vous avez fournis ou configurés."
    *   Pour les autres erreurs d'outils ou d'autres outils, expliquez pourquoi vous ne pouvez pas répondre (par exemple, "Je n'ai pas pu récupérer les données pour cette période via l'API SolarEdge."). N'essayez pas de deviner la réponse.
5.  **Formatage des réponses :**
    *   Formatez toujours les valeurs d'énergie en kWh (avec une décimale, ex: 12.3 kWh) et les valeurs de puissance en W ou kW (en choisissant l'unité la plus appropriée, ex: 500 W ou 2.5 kW).
    *   Répondez toujours en français.
    *   Soyez concis et allez droit au but, tout en étant amical et serviable.
6.  **Questions hors sujet ou incompréhensibles :** Si la question de l'utilisateur n'est pas liée à l'énergie solaire, à la météo ou aux fonctionnalités disponibles via vos outils, ou si vous ne comprenez pas la demande, répondez poliment que vous êtes spécialisé dans le suivi solaire et que vous ne pouvez pas répondre à cette question spécifique. Évitez les réponses génériques comme "Désolé, je n'ai pas pu générer de réponse".

Soyez précis, fiable et utile.
""";

    // Ajouter des exemples (few-shot examples) pour aider le modèle à comprendre les requêtes en texte libre
    const String fewShotExamples = """
Voici quelques exemples d'interactions :

Utilisateur: Production hier ?
Outil: getDailyEnergy({"date": "YYYY-MM-DD"})

Utilisateur: Meilleur moment machine à laver 2kW 1h30 aujourd'hui ?
Outil: suggestBestSlot({"loadKw": 2.0, "durationMin": 90})

Utilisateur: Adresse installation ?
Outil: getSiteLocation({})

Utilisateur: Météo 12h ?
Outil: getForecast({"hoursAhead": 12})

Utilisateur: Quel est le bilan de l'année 2024 ?
Outil: getEnergyRange({"startDate": "2024-01-01", "endDate": "2024-12-31"})

Utilisateur: Résumé de cette année ?
Outil: getEnergyRange({"startDate": "YYYY-01-01", "endDate": "YYYY-MM-DD"}) // où YYYY-MM-DD est la date actuelle

Utilisateur: Quand puis-je faire tourner ma machine à laver aujourd'hui ? Elle consomme 1.5kW et dure 2 heures.
Outil: suggestBestSlot({"loadKw": 1.5, "durationMin": 120})

Utilisateur: Quand lancer ma machine à laver ?
Outil: suggestBestSlot({})

Utilisateur: Raconte blague.
Votre réponse: Je suis spécialisé dans le suivi solaire.

Utilisateur: Comment fonctionne panneau solaire ?
Votre réponse: Je suis spécialisé dans le suivi solaire.

---
Contexte actuel :
"""; // Fermer la chaîne fewShotExamples ici

    // Attendre que le contexte soit prêt
    final String contextPrompt = await contextFuture;

    // Construire le prompt final pour Gemini (System Prompt + Few-shot Examples + Contexte + Message Utilisateur)
    // Le message utilisateur est passé comme un Content.text séparé, pas concaténé dans le prompt.
    // Le system prompt et les exemples sont passés comme des messages initiaux.
    final initialMessages = [
      Content.text(systemPrompt +
          fewShotExamples +
          contextPrompt +
          "---"), // Concaténer system prompt, exemples, contexte et séparateur
      Content.text(message), // Le VRAI message utilisateur
    ];

    debugPrint(
        "--- Prompt Initial Envoyé à Gemini (system + exemples + contexte + message) ---");
    debugPrint(
        "System Prompt + Examples + Context:\n$systemPrompt$fewShotExamples$contextPrompt---");
    debugPrint("User Message:\n$message");
    debugPrint("--------------------------");

    GenerateContentResponse response;
    late ChatSession chat; // Déclarer la variable chat ici

    try {
      // Utiliser sendMessage pour envoyer le premier message (qui inclut le system prompt et les exemples via l'historique ou la configuration du modèle si possible)
      // L'approche recommandée par la doc Gemini est de passer l'historique à startChat.
      // Le system prompt et les exemples peuvent être passés dans la configuration du modèle si supporté, sinon ils doivent être les premiers messages de l'historique.
      // Pour l'instant, je vais supposer que passer l'historique à startChat est suffisant et envoyer le message utilisateur avec sendMessage.
      chat = _model.startChat(
          history: _buildChatHistory(_activeConversation!.messages));
      response = await chat.sendMessage(
          Content.text(message)); // Envoyer seulement le message utilisateur
    } catch (e) {
      debugPrint("ERROR AiService: Erreur lors du premier appel à Gemini: $e");
      _addBotMessage(
          "Désolé, une erreur est survenue lors de la communication avec l'IA.");
      return;
    }

    // --- Gérer la chaîne d'appels d'outils ---
    int safety = 0;
    String lastToolName = "";
    Map<String, Object?> lastToolResult = {};

    // Boucle tant que le modèle demande d'exécuter des fonctions et que la limite de sécurité n'est pas atteinte
    while (response.functionCalls.isNotEmpty && safety++ < 3) {
      debugPrint(
          "INFO AiService: Received function calls: ${response.functionCalls}");
      final functionCall =
          response.functionCalls.first; // Exécuter le premier appel
      lastToolName = functionCall.name; // Stocker le nom de l'outil appelé

      Map<String, Object?> toolResult;
      try {
        toolResult = await _executeTool(functionCall);
        lastToolResult = toolResult; // Stocker le résultat de l'outil
        debugPrint(
            "INFO AiService: Tool '${functionCall.name}' executed, result: $toolResult");
      } catch (e) {
        debugPrint(
            "ERROR AiService: Erreur lors de l'exécution de l'outil '${functionCall.name}': $e");
        toolResult = {
          'error': 'Erreur lors de l\'exécution de l\'outil: ${e.toString()}'
        };
        lastToolResult = toolResult; // Stocker aussi le résultat d'erreur
      }

      // Envoyer le résultat de l'outil au modèle
      final toolResponse =
          Content.functionResponse(functionCall.name, toolResult);
      try {
        response = await chat.sendMessage(toolResponse);
      } catch (e) {
        debugPrint(
            "ERROR AiService: Erreur lors de l'envoi du résultat de l'outil à Gemini: $e");
        _addBotMessage(
            "Désolé, une erreur est survenue après l'exécution de l'outil.");
        return;
      }
    }

    // --- Traiter la réponse finale (texte ou erreur) ---
    String aiResponseText = response.text ?? "";

    // Vérification spécifique pour suggestBestSlot si c'était le dernier outil appelé
    if (lastToolName == 'suggestBestSlot') {
      final suggestedSlots = lastToolResult['suggested'] as List?;
      final toolError = lastToolResult['error'] as String?;
      final toolMessage = lastToolResult['message'] as String?;

      if (toolError != null) {
        // Si l'outil a retourné une erreur explicite
        aiResponseText =
            "Je n'ai pas pu déterminer de créneau optimal car une erreur s'est produite : ${toolError.replaceFirst('Could not process suggestBestSlot request: ', '')}";
      } else if (suggestedSlots != null && suggestedSlots.isEmpty) {
        // Si l'outil a retourné une liste vide de suggestions
        aiResponseText =
            "Je n'ai pas trouvé de créneau optimal pour votre appareil avec les prévisions actuelles et les paramètres fournis.";
      } else if (toolMessage != null && toolMessage.isNotEmpty) {
        // Si l'outil a retourné un message formaté
        aiResponseText = toolMessage;
      }
    }

    if (aiResponseText.isEmpty) {
      aiResponseText = "Désolé, je n'ai pas trouvé de réponse pertinente.";
    }

    // Ajouter la réponse finale de l'IA à la conversation
    _addBotMessage(aiResponseText);

    // Si la boucle s'est terminée à cause de la limite de sécurité
    if (safety >= 3) {
      debugPrint(
          "WARNING AiService: Boucle d'appels d'outils arrêtée par limite de sécurité (3 appels).");
      // On pourrait ajouter un message à l'utilisateur ici si nécessaire
    }
  }

  // Construit l'historique pour l'API Gemini
  List<Content> _buildChatHistory(List<AiMessage> messages) {
    final history = <Content>[];
    // Le modèle flash ne supporte pas le rôle 'system'.
    // Les instructions de guidage sont ajoutées au prompt utilisateur dans sendMessage.

    // Limiter l'historique aux N derniers messages pour éviter de dépasser la fenêtre de contexte
    // Le plan suggère 20 messages. On prend les 20 derniers.
    final int historyLength = math.min(messages.length, 20);
    // Exclure le dernier message utilisateur car il est envoyé séparément dans sendMessage
    final recentMessages = messages.sublist(
        math.max(0, messages.length - historyLength), messages.length - 1);

    for (final message in recentMessages) {
      // Alterner entre 'user' et 'model'
      history.add(message.isUser
          ? Content.text(message.content)
          : Content.model([TextPart(message.content)]));
    }

    // TODO: Implémenter la logique de résumé si l'historique est encore trop long
    // Cela nécessiterait un appel supplémentaire au modèle pour générer un résumé.
    // Pour l'instant, on se contente de tronquer.

    return history;
  }

  // Helper pour formater la date (copié depuis SolarEdgeApiService pour éviter la dépendance directe)
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // Helper pour parser une plage de dates ou une date unique à partir d'une chaîne de caractères
  // Retourne un Map avec 'startDate' et 'endDate' au format YYYY-MM-DD, ou null si non parsable.
  // Removed _parsePeriod method
}
