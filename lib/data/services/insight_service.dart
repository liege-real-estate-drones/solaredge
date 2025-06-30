// lib/data/services/insight_service.dart
// Version corrigée pour utiliser FileLogger correctement

import 'dart:math';
import 'package:flutter/material.dart'; // Pour IconData
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solaredge_monitor/data/models/api_exceptions.dart';
import 'package:solaredge_monitor/data/models/insight.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/data/models/weather_data.dart';
import 'package:solaredge_monitor/data/services/weather_manager.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/utils/file_logger.dart';

class InsightService {
  final SolarEdgeApiService _solarEdgeApiService;
  final WeatherManager _weatherManager;
  final FileLogger _logger = FileLogger(); // Instance du logger

  InsightService({
    required SolarEdgeApiService solarEdgeApiService,
    required WeatherManager weatherManager,
  })  : _solarEdgeApiService = solarEdgeApiService,
        _weatherManager = weatherManager;

  Future<List<Insight>> generateInsights() async {
    List<Insight> insights = [];
    SharedPreferences? prefs; // Rendre nullable pour le bloc try/catch initial
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // --- Initialisation Logger et SharedPreferences ---
    try {
      // Assurer l'initialisation du logger au début
      // Note: Normalement, il devrait être initialisé par ServiceManager ou main.dart
      // mais on peut ajouter un check ici par sécurité.
      if (!_logger.isInitialized) {
        // Nécessite isInitialized dans FileLogger
        await _logger.initialize();
      }
      _logger.log("INFO InsightService: Starting insight generation.",
          stackTrace: StackTrace.current); // Ajout stackTrace

      prefs = await SharedPreferences.getInstance();
      _logger.log("INFO InsightService: SharedPreferences loaded.",
          stackTrace: StackTrace.current); // Ajout stackTrace
    } catch (initError) {
      // Erreur critique si le logger ou prefs ne peuvent être initialisés
      print(
          "CRITICAL ERROR InsightService: Failed to initialize logger or SharedPreferences: $initError");
      // Pas de _logger.log ici car il pourrait être la cause
      insights.add(Insight(
        title: "Erreur Interne",
        message:
            "Impossible d'initialiser les services requis pour l'analyse ($initError).",
        type: InsightType.alert,
        icon: Icons.error,
      ));
      return insights; // Impossible de continuer
    }

    // --- Récupération des Préférences ---
    final String? apiKey = prefs.getString('solarEdgeApiKey');
    final String? siteId = prefs.getString('siteId');
    final double? latitude = prefs.getDouble('latitude');
    final double? longitude = prefs.getDouble('longitude');
    final double? energyRate = prefs.getDouble('energyRate');
    final String currency = prefs.getString('currency') ?? 'EUR';

    // Vérification Configuration Essentielle
    if (apiKey == null || siteId == null) {
      _logger.log(
          "WARNING: InsightService - API Key or Site ID missing in SharedPreferences.",
          stackTrace: StackTrace
              .current); // Remplacé ERROR par WARNING, ajout stackTrace
      insights.add(Insight(
        title: "Configuration requise",
        message:
            "Veuillez configurer votre clé API et votre Site ID dans les paramètres.",
        type: InsightType.alert,
        icon: Icons.settings_input_component,
      ));
      return insights; // Bloquant pour l'API SolarEdge
    }
    if (latitude == null || longitude == null) {
      _logger.log(
          "WARNING: InsightService - GPS coordinates missing. Weather insights will be unavailable.",
          stackTrace: StackTrace
              .current); // Remplacé ERROR par WARNING, ajout stackTrace
      insights.add(Insight(
        title: "Configuration requise",
        message:
            "Veuillez configurer votre localisation dans les paramètres pour obtenir des prévisions météo précises.",
        type: InsightType.alert, // Garder alert car c'est une config importante
        icon: Icons.location_off,
      ));
      // Non bloquant, on continue sans météo
    }

    // --- Corps principal de la génération ---
    try {
      SolarData? currentPower;
      DailySolarData? todayEnergy;
      DailySolarData? yesterdayEnergy;
      WeatherForecast? weatherForecastResult;

      // 1. Puissance actuelle
      try {
        currentPower = await _solarEdgeApiService.getCurrentPowerData();
        _logger.log(
            "INFO InsightService: Current power fetched: ${currentPower.power.toStringAsFixed(2)} W",
            stackTrace: StackTrace.current); // Ajout INFO:, stackTrace
      } catch (e, s) {
        // Capture stacktrace
        _logger.log(
            "WARNING: InsightService - Failed to fetch current power: $e",
            stackTrace: s); // Remplacé ERROR par WARNING, ajout stackTrace: s
        insights.add(Insight(
            title: "Données temps réel",
            message:
                "Impossible de récupérer la puissance actuelle.", // Message simplifié
            type: InsightType.alert,
            icon: Icons.power_off));
        // Non bloquant
      }

      // 2. Énergie Aujourd'hui & Hier (Considéré comme plus critique)
      try {
        todayEnergy = await _solarEdgeApiService.getDailyEnergy(today);
        _logger.log(
            "INFO InsightService: Today's energy fetched: ${todayEnergy.totalEnergy.toStringAsFixed(2)} Wh",
            stackTrace: StackTrace.current); // Ajout INFO:, stackTrace

        yesterdayEnergy = await _solarEdgeApiService.getDailyEnergy(yesterday);
        _logger.log(
            "INFO InsightService: Yesterday's energy fetched: ${yesterdayEnergy.totalEnergy.toStringAsFixed(2)} Wh",
            stackTrace: StackTrace.current); // Ajout INFO:, stackTrace
      } catch (e, s) {
        // Capture stacktrace
        _logger.log(
            "ERROR: InsightService - Failed to fetch recent energy data: $e",
            stackTrace: s); // Garder ERROR, ajout stackTrace: s
        insights.add(Insight(
          title: "Erreur Données Solaires",
          message:
              "Impossible de récupérer les données de production récentes. L'analyse est limitée.", // Message simplifié
          type: InsightType.alert,
          icon: Icons.error_outline,
        ));
        // On pourrait retourner ici si ces données sont essentielles pour *tous* les insights suivants
        // return insights;
        // Ou continuer avec les insights possibles (météo, config tarif...)
      }

      // 3. Prévisions Météo (si localisation OK)
      if (latitude != null && longitude != null) {
        try {
          weatherForecastResult = await _weatherManager.getWeatherForecast();
          _logger.log("INFO InsightService: Weather forecast fetched.",
              stackTrace: StackTrace.current); // Ajout INFO:, stackTrace
        } catch (e, s) {
          // Capture stacktrace
          _logger.log(
              "WARNING: InsightService - Failed to fetch weather forecast: $e",
              stackTrace: s); // Remplacé ERROR par WARNING, ajout stackTrace: s
          insights.add(Insight(
              title: "Données Météo",
              message:
                  "Impossible de récupérer les prévisions météo.", // Message simplifié
              type: InsightType.alert,
              icon: Icons.cloud_off));
          // Non bloquant
        }
      }

      // --- Analyse et Génération ---

      // Insight 1: Performance vs Hier (seulement si les deux jours OK)
      if (todayEnergy != null &&
          yesterdayEnergy != null &&
          yesterdayEnergy.totalEnergy > 0) {
        final double changePercent =
            ((todayEnergy.totalEnergy - yesterdayEnergy.totalEnergy) /
                    yesterdayEnergy.totalEnergy) *
                100;
        if (changePercent.abs() > 10) {
          // Seuil
          insights.add(Insight(
            title: "Production vs Hier",
            message: changePercent > 0
                ? "Production: +${changePercent.toStringAsFixed(0)}% vs hier (${(todayEnergy.totalEnergy / 1000).toStringAsFixed(1)} kWh vs ${(yesterdayEnergy.totalEnergy / 1000).toStringAsFixed(1)} kWh)."
                : "Production: ${changePercent.toStringAsFixed(0)}% vs hier (${(todayEnergy.totalEnergy / 1000).toStringAsFixed(1)} kWh vs ${(yesterdayEnergy.totalEnergy / 1000).toStringAsFixed(1)} kWh).",
            type: InsightType.performance,
            icon: changePercent > 0 ? Icons.trending_up : Icons.trending_down,
          ));
          _logger.log(
              "INFO InsightService: Generated 'vs Yesterday' insight (${changePercent.toStringAsFixed(0)}%).",
              stackTrace: StackTrace.current);
        } else {
          _logger.log(
              "INFO InsightService: 'vs Yesterday' change (${changePercent.toStringAsFixed(0)}%) below threshold.",
              stackTrace: StackTrace.current);
        }
      } else if (todayEnergy != null && yesterdayEnergy == null) {
        _logger.log(
            "INFO InsightService: Cannot compare vs yesterday (yesterday data missing).",
            stackTrace: StackTrace.current);
      } else if (todayEnergy != null &&
          yesterdayEnergy != null &&
          yesterdayEnergy.totalEnergy <= 0) {
        _logger.log(
            "INFO InsightService: Cannot compare vs yesterday (yesterday production was zero).",
            stackTrace: StackTrace.current);
      }

      // Insight 2: Prévision Météo Demain
      if (weatherForecastResult != null &&
          weatherForecastResult.hourlyForecast.isNotEmpty) {
        final tomorrowForecast =
            _getNextDayWeatherSummary(weatherForecastResult, now);
        if (tomorrowForecast != null) {
          insights.add(Insight(
            title: "Prévision Météo Demain",
            message:
                "Demain (${DateFormat('EEEE d', 'fr').format(now.add(const Duration(days: 1)))}): ${tomorrowForecast['summary']}. Temp: ${tomorrowForecast['minTemp']}°C à ${tomorrowForecast['maxTemp']}°C.",
            type: InsightType.weather,
            icon: _getWeatherIcon(tomorrowForecast['dominantCode']),
          ));
          _logger.log(
              "INFO InsightService: Generated 'Tomorrow Weather' insight.",
              stackTrace: StackTrace.current);
        } else {
          _logger.log(
              "INFO InsightService: No relevant weather data found for tomorrow.",
              stackTrace: StackTrace.current);
        }
      }

      // Insight 3: Gains Financiers
      if (energyRate != null && energyRate > 0) {
        if (todayEnergy != null && todayEnergy.totalEnergy > 0) {
          final double dailyGain =
              (todayEnergy.totalEnergy / 1000) * energyRate;
          insights.add(Insight(
            title: "Gains Estimés Aujourd'hui",
            message:
                "Économie/gain estimé: ${dailyGain.toStringAsFixed(2)} $currency (Prod: ${(todayEnergy.totalEnergy / 1000).toStringAsFixed(1)} kWh).",
            type: InsightType.savings,
            icon: Icons.euro_symbol, // ou currency icon?
          ));
          _logger.log(
              "INFO InsightService: Generated 'Financial Gain' insight.",
              stackTrace: StackTrace.current);
        } else {
          _logger.log(
              "INFO InsightService: Cannot calculate financial gain (today's energy missing or zero).",
              stackTrace: StackTrace.current);
        }
      } else {
        // Pas d'erreur si le tarif n'est pas mis, mais un conseil
        insights.add(Insight(
          title: "Gains Financiers",
          message:
              "Configurez votre tarif d'électricité (€/kWh) dans les paramètres pour estimer vos gains.",
          type: InsightType.tip,
          icon: Icons.price_check,
        ));
        _logger.log("INFO InsightService: Added 'Configure Tariff' tip.",
            stackTrace: StackTrace.current);
      }

      // Insight 4: Performance vs Météo Actuelle
      final currentWeather =
          _weatherManager.currentWeather; // Déjà récupéré par WeatherManager
      if (currentPower != null && currentWeather != null) {
        final currentWCode = currentWeather.iconCode;
        final isGoodWeather = _isGoodProductionWeather(currentWCode);
        final isProducingWell = currentPower.power > 500; // Seuil > 0.5 kW

        if (isGoodWeather &&
            !isProducingWell &&
            now.hour > 8 &&
            now.hour < 18) {
          insights.add(Insight(
            title: "Performance Actuelle",
            message:
                "Météo favorable (${_weatherCodeToString(currentWCode)}) mais production faible (${currentPower.power.toStringAsFixed(0)} W). Ombre ? Problème ?",
            type: InsightType.alert,
            icon: Icons.solar_power_outlined, // Ou warning
          ));
          _logger.log(
              "INFO InsightService: Generated 'Low Production in Good Weather' alert.",
              stackTrace: StackTrace.current);
        } else if (!isGoodWeather && isProducingWell) {
          insights.add(Insight(
            title: "Performance Actuelle",
            message:
                "Bonne production (${currentPower.power.toStringAsFixed(0)} W) malgré une météo moins favorable (${_weatherCodeToString(currentWCode)}).",
            type: InsightType.performance,
            icon: Icons.wb_sunny, // Ou check?
          ));
          _logger.log(
              "INFO InsightService: Generated 'Good Production in Poor Weather' insight.",
              stackTrace: StackTrace.current);
        } else {
          // Conditions normales, pas d'insight spécifique
          _logger.log(
              "INFO InsightService: Current weather/production combination does not warrant a specific insight.",
              stackTrace: StackTrace.current);
        }
      } else {
        _logger.log(
            "INFO InsightService: Cannot generate current performance vs weather insight (missing current power or weather data).",
            stackTrace: StackTrace.current);
      }

      // Insight Générique si aucun autre
      if (insights
          .where(
              (i) => i.type != InsightType.tip && i.type != InsightType.alert)
          .isEmpty) {
        // Ajoute un message général seulement s'il n'y a pas d'autres insights "positifs" ou informatifs (hors tips/alerts)
        if (todayEnergy != null || currentPower != null) {
          // S'assurer qu'on a au moins récupéré *quelques* données
          _logger.log(
              "INFO InsightService: No specific insights generated, adding default message.",
              stackTrace: StackTrace.current); // Ajout stackTrace
          insights.add(Insight(
            title: "Système Opérationnel",
            message: "Les données de production sont récupérées.",
            type: InsightType.general,
            icon: Icons.check_circle_outline,
          ));
        }
      }

      // --- Fin bloc try principal ---
    } on SolarEdgeApiException catch (e, s) {
      // Capture stacktrace
      _logger.log("ERROR: InsightService - SolarEdgeApiException: ${e.message}",
          stackTrace: s); // Ajout ERROR:, stackTrace: s
      insights.add(Insight(
        title: "Erreur API SolarEdge",
        message:
            "Erreur communication SolarEdge: ${e.message}.", // Message simplifié
        type: InsightType.alert,
        icon: Icons.cloud_off,
      ));
    } catch (e, s) {
      // Capture stacktrace
      _logger.log("ERROR: InsightService - Unexpected error: $e",
          stackTrace: s); // Ajout ERROR:, stackTrace: s
      insights.add(Insight(
        title: "Erreur Inattendue",
        message: "Une erreur interne est survenue: $e", // Message simplifié
        type: InsightType.alert,
        icon: Icons.bug_report,
      ));
    }

    _logger.log(
        "INFO InsightService: Finished generation, ${insights.length} insights created.",
        stackTrace: StackTrace.current); // Ajout stackTrace

    // Tri final
    insights.sort((a, b) {
      int priority(InsightType type) {
        switch (type) {
          case InsightType.alert:
            return 0;
          case InsightType.performance:
            return 1; // Performance avant savings/weather
          case InsightType.savings:
            return 2;
          case InsightType.weather:
            return 3;
          case InsightType.tip:
            return 4; // Tips moins importants
          case InsightType.general:
            return 5; // General en dernier
        }
      }

      return priority(a.type).compareTo(priority(b.type));
    });

    return insights;
  } // Fin generateInsights

  // --- Méthodes utilitaires ---

  Map<String, dynamic>? _getNextDayWeatherSummary(
      WeatherForecast forecast, DateTime currentTime) {
    // ... (Logique inchangée, mais s'assurer qu'elle n'utilise pas _logger directement si elle peut échouer)
    try {
      final tomorrow =
          DateTime(currentTime.year, currentTime.month, currentTime.day)
              .add(const Duration(days: 1));
      List<String> tomorrowCodes = [];
      List<double> tomorrowTemps = [];

      for (WeatherData dataPoint in forecast.hourlyForecast) {
        final forecastTime = dataPoint.timestamp;
        if (forecastTime.year == tomorrow.year &&
            forecastTime.month == tomorrow.month &&
            forecastTime.day == tomorrow.day &&
            forecastTime.hour >= 6 &&
            forecastTime.hour <= 20) {
          tomorrowCodes.add(dataPoint.iconCode);
          tomorrowTemps.add(dataPoint.temperature);
        }
      }
      if (tomorrowCodes.isEmpty) return null;

      var frequencyMap = <String, int>{};
      String dominantCode = tomorrowCodes[0];
      int maxFrequency = 0;
      for (var code in tomorrowCodes) {
        frequencyMap[code] = (frequencyMap[code] ?? 0) + 1;
        if (frequencyMap[code]! > maxFrequency) {
          maxFrequency = frequencyMap[code]!;
          dominantCode = code;
        }
      }
      return {
        'dominantCode': dominantCode,
        'summary': _weatherCodeToString(dominantCode),
        'minTemp': tomorrowTemps.reduce(min).toStringAsFixed(0),
        'maxTemp': tomorrowTemps.reduce(max).toStringAsFixed(0),
      };
    } catch (e, s) {
      _logger.log(
          "ERROR _getNextDayWeatherSummary: Failed to process forecast data: $e",
          stackTrace: s); // Log l'erreur ici
      return null; // Retourne null en cas d'erreur
    }
  }

  String _weatherCodeToString(String code) {
    // ... (Logique inchangée)
    switch (code) {
      case '01d':
        return "Ciel dégagé"; // Simplifié
      case '01n':
        return "Ciel dégagé (nuit)";
      case '02d':
        return "Peu nuageux"; // Simplifié
      case '02n':
        return "Peu nuageux (nuit)";
      case '03d':
      case '03n':
        return "Nuageux";
      case '04d':
      case '04n':
        return "Très nuageux / Couvert";
      case '09d':
      case '09n':
        return "Averses / Pluie légère";
      case '10d':
        return "Pluie"; // Simplifié
      case '10n':
        return "Pluie (nuit)";
      case '11d':
      case '11n':
        return "Orage";
      case '13d':
      case '13n':
        return "Neige";
      case '50d':
      case '50n':
        return "Brouillard";
      default:
        _logger.log(
            "WARNING _weatherCodeToString: Unknown weather code '$code'",
            stackTrace: StackTrace.current); // Log code inconnu
        return "Météo inconnue ($code)";
    }
  }

  // InsightType _getInsightTypeForWeather(String code) { ... } // Supprimé car non utilisé

  bool _isGoodProductionWeather(String code) {
    // '01d', '02d', '03d'
    return ['01d', '02d', '03d'].contains(code);
  }

  // bool _isPoorProductionWeather(String code) { ... } // Supprimé car non utilisé directement pour type

  IconData _getWeatherIcon(String code) {
    // ... (Logique inchangée)
    switch (code) {
      case '01d':
        return Icons.wb_sunny;
      case '01n':
        return Icons.nightlight_round;
      case '02d':
        return Icons.wb_cloudy_outlined;
      case '02n':
        return Icons.cloudy_snowing; // Approx
      case '03d':
      case '03n':
        return Icons.cloud;
      case '04d':
      case '04n':
        return Icons.cloud_queue; // Couvert
      case '09d':
      case '09n':
        return Icons.water_drop; // Averses
      case '10d':
      case '10n':
        return Icons.umbrella; // Pluie
      case '11d':
      case '11n':
        return Icons.thunderstorm; // Orage
      case '13d':
      case '13n':
        return Icons.ac_unit; // Neige
      case '50d':
      case '50n':
        return Icons.foggy; // Brouillard
      default:
        return Icons.help_outline;
    }
  }
} // Fin classe InsightService

// Ajout potentiel à FileLogger (file_logger.dart) si nécessaire:
/*
class FileLogger {
  // ... autres membres ...
  File? _logFile;
  bool _isInitializing = false;
  bool _isInitialized = false; // Nouveau flag

  // ... initialize() ...
  Future<void> initialize() async {
    if (_logFile != null || _isInitializing) return;
    _isInitializing = true;
    try {
      // ... logique d'initialisation ...
      _logFile = File(path);
      if (!await _logFile!.exists()) {
         // ... création et log initial ...
      }
      _isInitialized = true; // Mettre à true ici
      print('FileLogger Initialized: Log file at $path');
    } catch (e) {
      print('FileLogger Error Initializing: $e');
      _logFile = null;
      _isInitialized = false; // Assurer false en cas d'erreur
    } finally {
      _isInitializing = false;
    }
  }

  bool get isInitialized => _isInitialized; // Getter pour le flag

  // ... log(), readLog(), clearLog() ...
}
*/
