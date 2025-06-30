import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Pour accéder aux services
import 'package:solaredge_monitor/utils/power_utils.dart'; // Pour formater la puissance/énergie
import 'package:solaredge_monitor/data/models/solar_data.dart'; // Pour les modèles de données solaires
import 'package:intl/intl.dart'; // Pour formater les dates et nombres
import 'package:solaredge_monitor/utils/file_logger.dart'; // Pour le logging
import 'package:solaredge_monitor/data/models/weather_data.dart'; // Importer WeatherForecast
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart'; // Importer WeeklySolarData

class StatsContextBuilder {
  final ServiceManager _serviceManager = ServiceManager();
  final FileLogger _logger = FileLogger();

  // Cache pour le contexte généré
  String? _cachedContext;
  DateTime? _lastContextBuildTime;
  static const Duration _contextCacheDuration = Duration(minutes: 10); // Rafraîchir toutes les 10 min

  /// Construit et retourne une chaîne de caractères formatée contenant les statistiques clés
  /// et les prévisions météo pour servir de contexte au modèle LLM.
  Future<String> buildContext({bool forceRefresh = false}) async {
    final now = DateTime.now();

    // Utiliser le cache si valide et non forcé
    if (!forceRefresh &&
        _cachedContext != null &&
        _lastContextBuildTime != null &&
        now.difference(_lastContextBuildTime!) < _contextCacheDuration) {
      _logger.log('INFO: 📋 Utilisation contexte IA cache.', stackTrace: StackTrace.current);
      return _cachedContext!;
    }

    _logger.log('INFO: 🔄 Construction contexte IA...', stackTrace: StackTrace.current);

    final solaredgeService = _serviceManager.apiService; // Utiliser le getter correct
    final weatherManager = _serviceManager.weatherManager; // Utiliser le getter correct

    if (solaredgeService == null || !_serviceManager.isApiConfigured) { // Utiliser _serviceManager.isApiConfigured
       _logger.log('WARNING: Services SolarEdge non configurés. Contexte limité.', stackTrace: StackTrace.current);
       return "Je n'ai pas accès aux données SolarEdge pour l'instant ; configure ta clé API dans les réglages.";
    }
     if (weatherManager == null) {
        _logger.log('WARNING: WeatherManager non disponible. Contexte météo limité.', stackTrace: StackTrace.current);
        // Continuer sans météo
     }

    final StringBuffer contextBuffer = StringBuffer();
    final DateFormat dateFormat = DateFormat('dd/MM'); // Format jour/mois
    final DateFormat timeFormat = DateFormat('HH:mm'); // Format heure
    final today = DateTime.now();
    final currentMonth = DateTime.now();

    // Récupérer les préférences utilisateur pour la puissance crête
    final userPrefs = _serviceManager.userPreferences;
    final double? peakPowerKw = userPrefs?.peakPowerKw;


    // Lancer les appels API en parallèle
    final Future<DailySolarData> dailyDataFuture = solaredgeService.getDailyEnergy(today);
    final Future<SolarData> currentPowerFuture = solaredgeService.getCurrentPowerData();
    final Future<WeeklySolarData> weeklyDataFuture = solaredgeService.getWeeklyEnergy(today);
    final Future<MonthlySolarData> monthlyDataFuture = solaredgeService.getMonthlyEnergy(currentMonth);
    final Future<WeatherForecast?> weatherForecastFuture = weatherManager != null ? weatherManager.getWeatherForecast(forceRefresh: false) : Future.value(null);


    // Attendre les résultats
    final results = await Future.wait([
      dailyDataFuture,
      currentPowerFuture,
      weeklyDataFuture,
      monthlyDataFuture,
      weatherForecastFuture,
    ], eagerError: true); // eagerError: true pour échouer rapidement si une future échoue

    final DailySolarData? dailyData = results[0] as DailySolarData?;
    final SolarData? currentPower = results[1] as SolarData?;
    final WeeklySolarData? weeklyData = results[2] as WeeklySolarData?;
    final MonthlySolarData? monthlyData = results[3] as MonthlySolarData?;
    final WeatherForecast? forecast = results[4] as WeatherForecast?;

    // 0. Informations sur l'installation
    contextBuffer.writeln('# Installation');
    if (peakPowerKw != null && peakPowerKw > 0) {
       contextBuffer.writeln('- Puissance crête : ${peakPowerKw.toStringAsFixed(1)} kWc');
    } else {
       contextBuffer.writeln('- Puissance crête : Non configurée');
    }
    // On pourrait ajouter l'adresse ici si on le souhaite, en appelant locationService.getSavedAddress()
    // Pour l'instant, on se limite à la puissance crête.
    contextBuffer.writeln();


    // 1. Données du jour
    if (dailyData != null && currentPower != null) {
      contextBuffer.writeln('# Production aujourd\'hui');
      contextBuffer.writeln('- Énergie : ${PowerUtils.formatEnergyKWh(dailyData.totalEnergy)} (à ${timeFormat.format(now)})'); // Utiliser formatEnergyKWh
      contextBuffer.writeln('- Pic : ${PowerUtils.formatWatts(dailyData.peakPower)}');
      contextBuffer.writeln('- Puissance actuelle : ${PowerUtils.formatWatts(currentPower.power)}'); // Ajouter puissance actuelle
      contextBuffer.writeln(); // Ligne vide pour la clarté
    } else {
      _logger.log('ERROR: ❌ Erreur récupération données jour ou puissance actuelle pour contexte.', stackTrace: StackTrace.current);
      contextBuffer.writeln('# Production aujourd\'hui');
      contextBuffer.writeln('- Données non disponibles.');
      contextBuffer.writeln();
    }


    // 2. Agrégats 7 jours / 30 jours
    if (weeklyData != null && monthlyData != null) {
      // Agrégat 7 jours
      final daysWithDataWeek = weeklyData.dailyData
          .where((d) => d.totalEnergy > 0).length;
      final divisorWeek = daysWithDataWeek == 0 ? 1 : daysWithDataWeek;
      final double avgDailyWeek = weeklyData.totalEnergy / divisorWeek;

      contextBuffer.writeln('# Semaine glissante (${dateFormat.format(weeklyData.startDate)} au ${dateFormat.format(weeklyData.endDate)})');
      contextBuffer.writeln('- Total : ${PowerUtils.formatEnergyKWh(weeklyData.totalEnergy)}'); // Utiliser formatEnergyKWh
      contextBuffer.writeln('- Moyenne journalière : ${PowerUtils.formatEnergyKWh(avgDailyWeek)}/j'); // Utiliser formatEnergyKWh
      // Trouver le jour record de la semaine
      DailySolarData? recordDayWeek;
      for(var day in weeklyData.dailyData) {
        if (recordDayWeek == null || day.totalEnergy > recordDayWeek.totalEnergy) {
          recordDayWeek = day;
        }
      }
      if (recordDayWeek != null && recordDayWeek.totalEnergy > 0) {
         contextBuffer.writeln('- Record : ${PowerUtils.formatEnergyKWh(recordDayWeek.totalEnergy)} (${dateFormat.format(recordDayWeek.date)})'); // Utiliser formatEnergyKWh
      } else {
         contextBuffer.writeln('- Record : Non disponible');
      }
      contextBuffer.writeln(); // Ligne vide manquante ici

      // Agrégat 30 jours
      final daysWithDataMonth = monthlyData.dailyData
          .where((d) => d.totalEnergy > 0).length;
      final divisorMonth = daysWithDataMonth == 0 ? 1 : daysWithDataMonth;
      final double avgDailyMonth = monthlyData.totalEnergy / divisorMonth;


      contextBuffer.writeln('# Mois en cours (${DateFormat('MM/yyyy').format(currentMonth)})');
      contextBuffer.writeln('- Total : ${PowerUtils.formatEnergyKWh(monthlyData.totalEnergy)} sur $daysWithDataMonth j'); // Utiliser formatEnergyKWh
      contextBuffer.writeln('- Moyenne journalière : ${PowerUtils.formatEnergyKWh(avgDailyMonth)}/j'); // Utiliser formatEnergyKWh
       // Trouver le jour record du mois
      DailySolarData? recordDayMonth;
      for(var day in monthlyData.dailyData) {
        if (recordDayMonth == null || day.totalEnergy > recordDayMonth.totalEnergy) {
          recordDayMonth = day;
        }
      }
      if (recordDayMonth != null && recordDayMonth.totalEnergy > 0) {
         contextBuffer.writeln('- Record : ${PowerUtils.formatEnergyKWh(recordDayMonth.totalEnergy)} (${dateFormat.format(recordDayMonth.date)})'); // Utiliser formatEnergyKWh
      } else {
         contextBuffer.writeln('- Record : Non disponible');
      }
      contextBuffer.writeln();
    } else {
       _logger.log('ERROR: ❌ Erreur récupération agrégats pour contexte.', stackTrace: StackTrace.current);
       contextBuffer.writeln('# Agrégats (7j / 30j)');
       contextBuffer.writeln('- Données non disponibles.');
       contextBuffer.writeln();
    }


    // 3. Météo des 24h prochaines
    if (forecast != null && forecast.hourlyForecast.isNotEmpty) {
      contextBuffer.writeln('# Prévisions météo (prochaines 24h)');
      // Résumer les prévisions horaires
      // On peut lister quelques points clés ou une tendance
      // Exemple: Température min/max, conditions principales, précipitations
      final DateTime nowPlus24h = now.add(const Duration(hours: 24));
      // Accéder au timestamp via h.timestamp
      final relevantHourly = forecast.hourlyForecast.where((h) => h.timestamp.isAfter(now) && h.timestamp.isBefore(nowPlus24h)).toList();

      if (relevantHourly.isNotEmpty) {
         // Gérer la nullabilité de temperature et precipitation
         double minTemp = relevantHourly.first.temperature;
         double maxTemp = relevantHourly.first.temperature;
         double totalPrecipitation = 0;
         Set<String> conditions = {}; // Utiliser String pour la description de la condition

         for(var h in relevantHourly) {
            if (h.temperature < minTemp) minTemp = h.temperature;
            if (h.temperature > maxTemp) maxTemp = h.temperature;
            totalPrecipitation += h.precipitation ?? 0.0; // Gérer nullabilité
            if (h.condition.isNotEmpty) { // Vérifier si la condition n'est pas vide
               conditions.add(h.condition);
            }
         }

         contextBuffer.writeln('- Températures : ${minTemp.toStringAsFixed(1)}°C à ${maxTemp.toStringAsFixed(1)}°C');
         if (totalPrecipitation > 0.1) { // Seuil pour afficher les précipitations
            contextBuffer.writeln('- Précipitations : ${totalPrecipitation.toStringAsFixed(1)} mm');
         }
         // Lister les conditions principales (éviter les doublons)
         final conditionsList = conditions.join(', '); // Joindre les descriptions
         if (conditionsList.isNotEmpty) {
            contextBuffer.writeln('- Conditions : $conditionsList');
         }

      } else {
         contextBuffer.writeln('- Prévisions horaires non disponibles pour les prochaines 24h.');
      }
      contextBuffer.writeln();

    } else {
      _logger.log('WARNING: Prévisions météo non disponibles pour contexte.', stackTrace: StackTrace.current);
      contextBuffer.writeln('# Prévisions météo');
      contextBuffer.writeln('- Données non disponibles.');
      contextBuffer.writeln();
    }


    // Stocker et retourner le contexte généré
    _cachedContext = contextBuffer.toString();
    _lastContextBuildTime = now;
    _logger.log('INFO: ✅ Contexte IA construit.', stackTrace: StackTrace.current);
    return _cachedContext!;
  }
}
