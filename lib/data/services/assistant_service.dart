import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/data/models/user_preferences.dart';
import 'package:solaredge_monitor/data/models/weather_data.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/data/services/weather_manager.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart';
import 'package:solaredge_monitor/data/services/stats_context_builder.dart'; // Import du nouveau service
import 'package:solaredge_monitor/utils/power_utils.dart'; // Pour formater la puissance/énergie
import 'package:intl/intl.dart'; // Pour formater les dates et nombres
import 'package:solaredge_monitor/data/services/ai_service.dart'; // Import AiService

// Modèle simple pour un insight
class AssistantInsight {
  final String title;
  final String message;
  final IconData icon;
  final Color? iconColor;

  AssistantInsight({
    required this.title,
    required this.message,
    required this.icon,
    this.iconColor,
  });
}

// Structure pour définir un intent rapide
class QuickIntent {
  final String id;
  final RegExp regex;
  final Future<String> Function(
      SolarEdgeApiService apiService,
      WeatherManager weatherManager,
      UserPreferences? prefs,
      RegExpMatch match) handler;

  QuickIntent({
    required this.id,
    required this.regex,
    required this.handler,
  });
}

class AssistantService with ChangeNotifier {
  final WeatherManager _weatherManager;
  final ValueNotifier<UserPreferences?> _userPreferencesNotifier;
  final ValueNotifier<SolarEdgeApiService?> _apiServiceNotifier;
  final StatsContextBuilder _statsContextBuilder =
      StatsContextBuilder(); // Instance du builder de contexte

  List<AssistantInsight> _insights = [];
  bool _isLoading = false;
  String? _errorMessage;
  VoidCallback? _apiServiceSubscription;
  VoidCallback? _userPreferencesSubscription;

  // Définition des intents rapides
  late final List<QuickIntent> _quickIntents;

  List<QuickIntent> get quickIntents => _quickIntents; // Ajouter le getter

  List<AssistantInsight> get insights => _insights;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  AssistantService({
    required WeatherManager weatherManager,
    required ValueNotifier<UserPreferences?> userPreferencesNotifier,
    required ValueNotifier<SolarEdgeApiService?> apiServiceNotifier,
  })  : _weatherManager = weatherManager,
        _userPreferencesNotifier = userPreferencesNotifier,
        _apiServiceNotifier = apiServiceNotifier {
    // Initialiser la liste des intents
    _quickIntents = _buildQuickIntents();

    _apiServiceSubscription = _onApiServiceChanged;
    _apiServiceNotifier.addListener(_apiServiceSubscription!);

    _userPreferencesSubscription = _onUserPreferencesChanged;
    _userPreferencesNotifier.addListener(_userPreferencesSubscription!);

    if (_apiServiceNotifier.value != null &&
        _userPreferencesNotifier.value != null) {
      generateInsights();
    } else if (_apiServiceNotifier.value != null) {
      generateInsights();
    }
  }

  // Méthode pour construire la liste des intents rapides
  List<QuickIntent> _buildQuickIntents() {
    return [
      QuickIntent(
        id: 'daily_energy',
        regex: RegExp(
            r'(combien|quelle).*(produit|énergie).*(aujourdhui|ce jour)',
            caseSensitive: false),
        handler: _handleDailyEnergyIntent,
      ),
      QuickIntent(
        id: 'weekly_summary',
        regex: RegExp(r'(bilan|énergie).*(semaine|cette semaine)',
            caseSensitive: false),
        handler: _handleWeeklySummaryIntent,
      ),
      QuickIntent(
        id: 'monthly_summary',
        regex: RegExp(r'(bilan|énergie).*(mois|ce mois)', caseSensitive: false),
        handler: _handleMonthlySummaryIntent,
      ),
      QuickIntent(
        id: 'last_week_summary',
        regex: RegExp(r'(bilan|énergie).*(semaine\s+(dernière|passée))',
            caseSensitive: false),
        handler: _handleLastWeekSummaryIntent,
      ),
      QuickIntent(
        id: 'yearly_summary',
        regex: RegExp(r'(résumé|bilan|énergie).*(année|an)(\s+en\s+cours)?',
            caseSensitive: false), // Ajout de 'résumé'
        handler: _handleYearlySummaryIntent,
      ),
      QuickIntent(
        id: 'best_time_washing_machine',
        regex: RegExp(r'(machine|lessive)',
            caseSensitive: false),
        handler: _handleBestTimeIntent,
      ),
      QuickIntent(
        id: 'best_time_dryer',
        regex: RegExp(r'(sèche-linge|sèche linge|seche-linge|seche linge)',
            caseSensitive: false),
        handler: _handleDryerBestTimeIntent,
      ),
      QuickIntent(
        id: 'tomorrow_production',
        regex: RegExp(r'(prod(?:uction)?|énergie).*(prévu[e]?|demain).*demain\s*\??$', caseSensitive: false),
        handler: _handleTomorrowProductionIntent,
      ),
      // Ajouter d'autres intents ici
    ];
  }

  // --- Handlers pour les intents rapides ---

  Future<String> _handleDailyEnergyIntent(
      SolarEdgeApiService apiService,
      WeatherManager weatherManager,
      UserPreferences? prefs,
      RegExpMatch match) async {
    try {
      final dailyData = await apiService.getDailyEnergy(DateTime.now());
      final currentPower = await apiService.getCurrentPowerData();
      final timeFmt = DateFormat('HH:mm');
      final now = DateTime.now();

    final buffer = StringBuffer()
      ..writeln("Aujourd'hui, vous avez produit "
          "${PowerUtils.formatEnergyKWh(dailyData.totalEnergy)} "
          "(mesuré à ${timeFmt.format(now)}).")
      ..writeln("Puissance actuelle : "
          "${PowerUtils.formatWatts(currentPower.power)}.");

    if (dailyData.peakPower > 0) {
      buffer.writeln("Pic de la journée : "
          "${PowerUtils.formatWatts(dailyData.peakPower)}.");
    }

      // Mini-prévision pour le reste de la journée
      final fc = weatherManager.weatherForecast;
      if (fc != null && fc.hourlyForecast.isNotEmpty) {
        final endOfDay = DateTime(now.year, now.month, now.day, 23, 59);
        final remaining = fc.hourlyForecast
            .where((h) => h.timestamp.isAfter(now) && h.timestamp.isBefore(endOfDay))
            .toList();
        if (remaining.isNotEmpty) {
          final summary = _summarizeForecast(
              remaining); // Réutiliser la méthode de résumé
          buffer.writeln("Prévisions pour le reste de la journée : $summary.");
        }
      }

      return buffer.toString();
    } catch (e) {
      debugPrint(
          "ERROR AssistantService: Erreur dans _handleDailyEnergyIntent: $e");
      return "Désolé, je n'ai pas pu récupérer les données de production pour aujourd'hui.";
    }
  }

  Future<String> _handleWeeklySummaryIntent(
      SolarEdgeApiService apiService,
      WeatherManager weatherManager,
      UserPreferences? prefs,
      RegExpMatch match) async {
    try {
      final weeklyData = await apiService.getWeeklyEnergy(DateTime.now());
      // Réutiliser le helper pour formater la réponse
      return _formatWeeklyReply(weeklyData,
          completed: false); // Semaine courante n'est pas complète
    } catch (e) {
      debugPrint(
          "ERROR AssistantService: Erreur dans _handleWeeklySummaryIntent: $e");
      return "Désolé, je n'ai pas pu récupérer le bilan de la semaine.";
    }
  }

  Future<String> _handleMonthlySummaryIntent(
      SolarEdgeApiService apiService,
      WeatherManager weatherManager,
      UserPreferences? prefs,
      RegExpMatch match) async {
    try {
      final currentMonth = DateTime.now();
      final monthlyData = await apiService.getMonthlyEnergy(currentMonth);
      final int daysInMonthSoFar = DateTime.now().day;
      final double avgDailyMonth = monthlyData.totalEnergy / daysInMonthSoFar;
      final dateFormat = DateFormat('dd/MM');

      final buffer = StringBuffer();
      buffer.writeln(
          "Bilan du mois en cours (${DateFormat('MM/yyyy').format(currentMonth)}) :");
      buffer.writeln(
          "- Total produit : ${PowerUtils.formatEnergyKWh(monthlyData.totalEnergy)} sur $daysInMonthSoFar jours");
      buffer.writeln(
          "- Moyenne journalière : ${PowerUtils.formatEnergyKWh(avgDailyMonth)}/j");
      if (monthlyData.peakPower > 0) {
        buffer.writeln(
            "- Pic de puissance du mois : ${PowerUtils.formatWatts(monthlyData.peakPower)}");
      }
      DailySolarData? recordDayMonth;
      for (var day in monthlyData.dailyData) {
        if (recordDayMonth == null ||
            day.totalEnergy > recordDayMonth.totalEnergy) {
          recordDayMonth = day;
        }
      }
      if (recordDayMonth != null && recordDayMonth.totalEnergy > 0) {
        buffer.writeln(
            "- Jour record : ${PowerUtils.formatEnergyKWh(recordDayMonth.totalEnergy)} (${dateFormat.format(recordDayMonth.date)})");
      }

      return buffer.toString();
    } catch (e) {
      debugPrint(
          "ERROR AssistantService: Erreur dans _handleMonthlySummaryIntent: $e");
      return "Désolé, je n'ai pas pu récupérer le bilan du mois.";
    }
  }

  // Handler pour la semaine passée
  Future<String> _handleLastWeekSummaryIntent(
      SolarEdgeApiService apiService,
      WeatherManager weatherManager,
      UserPreferences? prefs,
      RegExpMatch match) async {
    try {
      final mondayLastWeek =
          DateTime.now().subtract(Duration(days: DateTime.now().weekday + 6));
      final weeklyData = await apiService.getWeeklyEnergy(mondayLastWeek);
      // Réutiliser la logique de formatage de la semaine, en indiquant que c'est une semaine complète
      return _formatWeeklyReply(weeklyData, completed: true);
    } catch (e) {
      debugPrint(
          "ERROR AssistantService: Erreur dans _handleLastWeekSummaryIntent: $e");
      return "Désolé, je n'ai pas pu récupérer le bilan de la semaine passée.";
    }
  }

  // Handler pour l'année en cours
  Future<String> _handleYearlySummaryIntent(
      SolarEdgeApiService apiService,
      WeatherManager weatherManager,
      UserPreferences? prefs,
      RegExpMatch match) async {
    try {
      final year = DateTime.now().year;
      final yearly = await apiService.getYearlyEnergy(year);
      // Calculer la moyenne sur les jours écoulés de l'année
      final daysInYearSoFar =
          DateTime.now().difference(DateTime(year, 1, 1)).inDays + 1;
      final double avgDaily = yearly.totalEnergy / daysInYearSoFar;
      final dateFormat = DateFormat('dd/MM'); // Pour le jour record

      final buffer = StringBuffer();
      buffer.writeln("Bilan ${year} :");
      buffer.writeln(
          "• Total : ${PowerUtils.formatEnergyKWh(yearly.totalEnergy)}");
      buffer
          .writeln("• Moyenne/jour : ${PowerUtils.formatEnergyKWh(avgDaily)}");
      if (yearly.peakPower > 0) {
        buffer.writeln("• Pic : ${PowerUtils.formatWatts(yearly.peakPower)}");
      }
      MonthlySolarData? recordMonthYear;
      if (yearly.monthlyData.isNotEmpty) {
        recordMonthYear = yearly.monthlyData.reduce((a, b) => a.totalEnergy > b.totalEnergy ? a : b);
      }
      if (recordMonthYear != null && recordMonthYear.totalEnergy > 0) {
        buffer.writeln("• Mois record : ${PowerUtils.formatEnergyKWh(recordMonthYear.totalEnergy)} (${DateFormat('MMMM yyyy', 'fr_FR').format(recordMonthYear.month)})");
      }
      // Supprimez ou commentez la partie concernant recordDayYear si vous ne la remplacez pas par le mois record.

      return buffer.toString();
    } catch (e) {
      debugPrint(
          "ERROR AssistantService: Erreur dans _handleYearlySummaryIntent: $e");
      return "Désolé, je n'ai pas pu récupérer le bilan de l'année en cours.";
    }
  }

  // Handler pour la machine à laver (meilleur moment)
  Future<String> _handleBestTimeIntent(
    SolarEdgeApiService api,
    WeatherManager meteo,
    UserPreferences? prefs,
    RegExpMatch _,
  ) async {
    return _handleApplianceBestTimeIntent(api, meteo, prefs, 'washing_machine');
  }

  // Handler pour le sèche-linge (meilleur moment)
  Future<String> _handleDryerBestTimeIntent(
    SolarEdgeApiService api,
    WeatherManager meteo,
    UserPreferences? prefs,
    RegExpMatch _,
  ) async {
    return _handleApplianceBestTimeIntent(api, meteo, prefs, 'dryer');
  }

  // Handler générique pour le meilleur moment d'un appareil
  Future<String> _handleApplianceBestTimeIntent(
    SolarEdgeApiService api,
    WeatherManager meteo,
    UserPreferences? prefs,
    String deviceType, // 'washing_machine' or 'dryer'
  ) async {
    // Check for location preferences first
    if (prefs?.latitude == null || prefs?.latitude == 0.0 || prefs?.longitude == null || prefs?.longitude == 0.0) {
      return "Pour vous donner le meilleur créneau, j'ai besoin de connaître la localisation de votre installation. Veuillez la configurer dans les paramètres.";
    }

    // Now we are sure prefs is not null and lat/lon are not null/0.0
    final double userLat = prefs!.latitude!; // Use non-null assertion as we've checked
    final double userLon = prefs!.longitude!; // Use non-null assertion as we've checked

    double? loadKw;
    int? durationMin;
    String deviceName;

    if (deviceType == 'washing_machine') {
      loadKw = prefs.washingMachineKw;
      durationMin = prefs.defaultWashingMachineDurationMin;
      deviceName = 'machine à laver';
    } else if (deviceType == 'dryer') {
      loadKw = prefs.dryerKw;
      durationMin = prefs.defaultDryerDurationMin;
      deviceName = 'sèche-linge';
    } else {
      return "Type d'appareil inconnu.";
    }

    // Vérifier si les préférences de l'appareil sont configurées
    if (loadKw == null || loadKw <= 0) {
      return "Pour vous suggérer le meilleur créneau pour votre $deviceName, veuillez configurer sa puissance (en kW) dans les paramètres de l'application.";
    }
    if (durationMin == null || durationMin <= 0) {
      return "Pour vous suggérer le meilleur créneau pour votre $deviceName, veuillez configurer la durée de son cycle (en minutes) dans les paramètres de l'application.";
    }

    final double peakKw = prefs.peakPowerKw ?? 3.0; // Utilise la valeur configurée ou une valeur par défaut si non configurée

    // 2. Forecast météo horaire
    final forecast = await meteo.getWeatherForecast(forceRefresh: false);
    if (forecast == null || forecast.hourlyForecast.isEmpty) {
      return "Je n'ai pas de prévisions météo pour aujourd'hui.";
    }

    // 3. Petite formule ≈ production = kWc × facteur ciel × sin(élévation)
    DateTime best = DateTime.now();
    double bestSurplus = -1;

    for (var h in forecast.hourlyForecast) {
      if (h.timestamp.day != DateTime.now().day)
        continue; // on reste sur aujourd'hui

      // Use the local non-nullable variables
      final double latRad = userLat * math.pi / 180.0;
      final double lonRad = userLon * math.pi / 180.0;

      // Utiliser la méthode _solarElevation de la classe
      final elev = _solarElevation(h.timestamp, latRad, lonRad);
      if (elev <= 0) continue; // nuit

      final skyFactor = 1.0 - ((h.cloudCover ?? 50.0) / 100.0); // Utilise 50% si cloudCover est null
      final prodKw = peakKw * skyFactor * (elev / 90.0); // ultra-simple
      final surplus = prodKw - loadKw;

      if (surplus > bestSurplus) {
        bestSurplus = surplus;
        best = h.timestamp;
      }
    }

    if (bestSurplus < 0) {
      return "Production insuffisante prévue aujourd'hui (pic < ${loadKw} kW).";
    }

    final heure =
        "${best.hour.toString().padLeft(2, '0')}h${best.minute.toString().padLeft(2, '0')}";
    return "Le meilleur créneau pour votre $deviceName est autour de **$heure** (production estimée ≈ ${(bestSurplus + loadKw).toStringAsFixed(1)} kW)."; // loadKw is non-null here
  }

  // Handler pour la production de demain
  Future<String> _handleTomorrowProductionIntent(
    SolarEdgeApiService api,
    WeatherManager meteo,
    UserPreferences? prefs,
    RegExpMatch _,
  ) async {
    // Dans _handleTomorrowProductionIntent
    debugPrint("AssistantService._handleTomorrowProductionIntent: UserPrefs latitude=${prefs?.latitude}, longitude=${prefs?.longitude}, weatherLocationSource=${prefs?.weatherLocationSource}");
    // Check for location preferences first
    if (prefs?.latitude == null || prefs?.latitude == 0.0 || prefs?.longitude == null || prefs?.longitude == 0.0) {
      debugPrint("AssistantService: Condition de localisation non remplie. Lat: ${prefs?.latitude}, Lon: ${prefs?.longitude}");
      return "Pour estimer la production de demain, j'ai besoin de connaître la localisation de votre installation. Veuillez la configurer dans les paramètres.";
    }

    // 1. Capacité installée (kWc)
    final double peakKw = prefs!.peakPowerKw ?? 3.0; // ex. 3 kWc

    // 2. Forecast météo horaire
    final forecast = await meteo.getWeatherForecast(forceRefresh: false);
    if (forecast == null || forecast.hourlyForecast.isEmpty) {
      return "Je n'ai pas de prévisions météo pour demain.";
    }

    // 3. Calculer la production estimée pour demain (06:00 à 20:00)
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    double totalEnergyTomorrowWh = 0;

    // Récupérer lat/lon depuis les préférences utilisateur (garanti non-null après le check)
    final double latRad = prefs.latitude! * math.pi / 180.0; // Non-null assertion is safe due to the check above
    final double lonRad = prefs.longitude! * math.pi / 180.0; // Non-null assertion is safe

    for (var h in forecast.hourlyForecast) {
      // Ne considérer que les heures de demain entre 06:00 et 20:00
      if (h.timestamp.day == tomorrow.day &&
          h.timestamp.hour >= 6 &&
          h.timestamp.hour <= 20) {
        final elev = _solarElevation(h.timestamp, latRad, lonRad);
        if (elev > 0) {
          // Ne pas calculer la nuit
          final skyFactor = 1.0 - ((h.cloudCover ?? 50.0) / 100.0); // Utilise 50% si cloudCover est null
          // Estimation simple : production horaire = kWc * facteur ciel * sin(élévation) * durée (1h)
          // Convertir en Wh (kW * 1000 * 1h)
          final prodWh = peakKw * 1000 * skyFactor * (elev / 90.0);
          totalEnergyTomorrowWh += prodWh;
        }
      }
    }

    final totalEnergyTomorrowKwh = totalEnergyTomorrowWh / 1000.0;

    if (totalEnergyTomorrowKwh <= 0) {
      return "Aucune production significative n'est prévue pour demain.";
    }

    // TODO: Ajouter le créneau pic si le calcul le permet
    // Pour l'instant, on retourne juste l'énergie totale estimée.
    return "Production estimée pour demain : ${PowerUtils.formatEnergyKWh(totalEnergyTomorrowKwh * 1000)}."; // Convertir kWh en Wh pour le formatage
  }

  // Helper pour formater la réponse hebdomadaire (réutilisé par les handlers semaine courante et semaine passée)
  String _formatWeeklyReply(WeeklySolarData weeklyData,
      {bool completed = false}) {
    final dateFormat = DateFormat('dd/MM');
    // Calculer la moyenne sur les jours avec données si la semaine n'est pas complète
    final daysWithData =
        weeklyData.dailyData.where((d) => d.totalEnergy > 0).length;
    final divisor = daysWithData == 0 ? 1 : daysWithData;
    final double avgDailyWeek = weeklyData.totalEnergy / divisor;

    final buffer = StringBuffer();
    buffer.writeln(
        "Bilan de la semaine (${dateFormat.format(weeklyData.startDate)} au ${dateFormat.format(weeklyData.endDate)}) :");
    buffer.writeln(
        "- Total produit : ${PowerUtils.formatEnergyKWh(weeklyData.totalEnergy)}");
    buffer.writeln(
        "- Moyenne journalière : ${PowerUtils.formatEnergyKWh(avgDailyWeek)}/j${completed ? '' : ' (sur ${daysWithData} jours)'}"); // Indiquer si la semaine n'est pas complète
    if (weeklyData.peakPower > 0) {
      buffer.writeln(
          "- Pic de puissance de la semaine : ${PowerUtils.formatWatts(weeklyData.peakPower)}");
    }
    DailySolarData? recordDayWeek;
    for (var day in weeklyData.dailyData) {
      if (recordDayWeek == null ||
          day.totalEnergy > recordDayWeek.totalEnergy) {
        recordDayWeek = day;
      }
    }
    if (recordDayWeek != null && recordDayWeek.totalEnergy > 0) {
      buffer.writeln(
          "- Jour record : ${PowerUtils.formatEnergyKWh(recordDayWeek.totalEnergy)} (${dateFormat.format(recordDayWeek.date)})");
    }

    return buffer.toString();
  }

  // Helper pour calculer l'élévation solaire (copié depuis AiService)
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

  // Helper pour formater la date (pour l'affichage)
  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  // Nouvelle fonction de parsing des périodes utilisant DateTime et DateFormat
  PeriodRange? smartParse(String text) {
    final lc = text.toLowerCase();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day); // Début du jour actuel

    if (lc.contains('aujourd') || lc.contains('ce jour')) return PeriodRange(today, today);
    if (lc.contains('hier')) {
      final yesterday = today.subtract(const Duration(days: 1));
      return PeriodRange(yesterday, yesterday);
    }
    if (lc.contains('avant-hier')) {
      final dayBeforeYesterday = today.subtract(const Duration(days: 2));
      return PeriodRange(dayBeforeYesterday, dayBeforeYesterday);
    }

    // Semaine
    if (lc.contains('cette semaine')) {
      final startOfWeek = today.subtract(Duration(days: today.weekday - 1)); // Lundi
      return PeriodRange(startOfWeek, today); // Jusqu'à aujourd'hui
    }
    if (lc.contains('semaine dernière')) {
      final endOfLastWeek = today.subtract(Duration(days: today.weekday)); // Dimanche dernier
      final startOfLastWeek = endOfLastWeek.subtract(const Duration(days: 6)); // Lundi dernier
      return PeriodRange(startOfLastWeek, endOfLastWeek);
    }

    // Mois
    if (lc.contains('ce mois')) {
      final startOfMonth = DateTime(today.year, today.month, 1);
      return PeriodRange(startOfMonth, today); // Jusqu'à aujourd'hui
    }
    if (lc.contains('mois dernier')) {
      final startOfCurrentMonth = DateTime(today.year, today.month, 1);
      final endOfLastMonth = startOfCurrentMonth.subtract(const Duration(days: 1));
      final startOfLastMonth = DateTime(endOfLastMonth.year, endOfLastMonth.month, 1);
      return PeriodRange(startOfLastMonth, endOfLastMonth);
    }

    // Année
    if (lc.contains('cette année') || lc.contains('an en cours')) {
      final startOfYear = DateTime(today.year, 1, 1);
      return PeriodRange(startOfYear, today); // Jusqu'à aujourd'hui
    }
    if (lc.contains('année dernière')) {
      final lastYear = today.year - 1;
      final startOfLastYear = DateTime(lastYear, 1, 1);
      final endOfLastYear = DateTime(lastYear, 12, 31);
      return PeriodRange(startOfLastYear, endOfLastYear);
    }

    // Regex pour dates explicites (YYYY-MM-DD ou JJ/MM/YYYY ou JJ/MM)
    final explicitRangeRegex = RegExp(r'du\s+(\d{1,2}\/\d{1,2}(?:\/\d{4})?|\d{4}-\d{2}-\d{2})\s+au\s+(\d{1,2}\/\d{1,2}(?:\/\d{4})?|\d{4}-\d{2}-\d{2})');
    final explicitSingleRegex = RegExp(r'le\s+(\d{1,2}\/\d{1,2}(?:\/\d{4})?|\d{4}-\d{2}-\d{2})');
    final monthYearRegex = RegExp(r'(janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre)\s+(\d{4})', caseSensitive: false);
    final yearRegex = RegExp(r'en\s+(\d{4})');


    // Tenter de parser une plage explicite
    final rangeMatch = explicitRangeRegex.firstMatch(lc);
    if (rangeMatch != null) {
      try {
        final date1 = _tryParseDate(rangeMatch.group(1)!, now.year);
        final date2 = _tryParseDate(rangeMatch.group(2)!, now.year);
        if (date1 != null && date2 != null) {
          // Assurer que date1 est avant date2
          final start = date1.isBefore(date2) ? date1 : date2;
          final end = date1.isBefore(date2) ? date2 : date1;
          return PeriodRange(start, end);
        }
      } catch (_) {}
    }

    // Tenter de parser une date unique
    final singleMatch = explicitSingleRegex.firstMatch(lc);
    if (singleMatch != null) {
      try {
        final date = _tryParseDate(singleMatch.group(1)!, now.year);
        if (date != null) {
          return PeriodRange(date, date);
        }
      } catch (_) {}
    }

    // Tenter de parser mois et année
    final monthYearMatch = monthYearRegex.firstMatch(lc);
    if (monthYearMatch != null) {
      try {
        final monthName = monthYearMatch.group(1)!;
        final year = int.parse(monthYearMatch.group(2)!);
        final monthMap = {
          'janvier': 1, 'février': 2, 'mars': 3, 'avril': 4, 'mai': 5, 'juin': 6,
          'juillet': 7, 'août': 8, 'septembre': 9, 'octobre': 10, 'novembre': 11, 'décembre': 12
        };
        final month = monthMap[monthName];
        if (month != null) {
          final startDate = DateTime(year, month, 1);
          final endDate = DateTime(year, month + 1, 1).subtract(const Duration(days: 1)); // Dernier jour du mois
          return PeriodRange(startDate, endDate);
        }
      } catch (_) {}
    }

    // Tenter de parser année seule
    final yearMatch = yearRegex.firstMatch(lc);
    if (yearMatch != null) {
      try {
        final year = int.parse(yearMatch.group(1)!);
        final startDate = DateTime(year, 1, 1);
        final endDate = DateTime(year, 12, 31);
        return PeriodRange(startDate, endDate);
      } catch (_) {}
    }


    // Si aucun format reconnu
    return null;
  }

  // Helper interne pour smartParse pour gérer différents formats de date
  DateTime? _tryParseDate(String dateStr, int currentYear) {
     // Tenter YYYY-MM-DD
     try {
        return DateTime.parse(dateStr);
     } catch (_) {}

     // Tenter JJ/MM/YYYY
     final slashFullMatch = RegExp(r'(\d{1,2})\/(\d{1,2})\/(\d{4})').firstMatch(dateStr);
     if (slashFullMatch != null) {
        try {
           final day = int.parse(slashFullMatch.group(1)!);
           final month = int.parse(slashFullMatch.group(2)!);
           final year = int.parse(slashFullMatch.group(3)!);
           return DateTime(year, month, day);
        } catch (_) {}
     }

     // Tenter JJ/MM (assumer année courante, ajuster si dans le futur)
     final slashMonthMatch = RegExp(r'(\d{1,2})\/(\d{1,2})').firstMatch(dateStr);
     if (slashMonthMatch != null) {
        try {
           final day = int.parse(slashMonthMatch.group(1)!);
           final month = int.parse(slashMonthMatch.group(2)!);
           var date = DateTime(currentYear, month, day);
           // Si la date est dans le futur, essayer l'année précédente
           if (date.isAfter(DateTime.now())) {
              date = DateTime(currentYear - 1, month, day);
           }
           return date;
        } catch (_) {}
     }

     return null; // Échec du parsing
  }


  // --- Méthode principale pour traiter le texte utilisateur ---
  Future<void> processUserText(String text) async {
    // Obtenir l'instance actuelle du service API depuis le ValueNotifier
    final SolarEdgeApiService? solarEdgeApiService = _apiServiceNotifier.value;
    // Obtenir les préférences utilisateur actuelles depuis le ValueNotifier
    final UserPreferences? userPreferences = _userPreferencesNotifier.value;
    // Obtenir l'instance de l'AiService
    final aiService = ServiceManager().aiService;


    // Vérifier si les services nécessaires sont disponibles
    if (solarEdgeApiService == null) {
       // Si l'API SolarEdge n'est pas configurée, on ne peut pas répondre, même avec l'IA.
       // On pourrait potentiellement laisser l'IA répondre à des questions générales non liées à SolarEdge,
       // mais pour l'instant, on bloque si l'API principale manque.
       // On pourrait aussi vérifier si l'AiService est disponible ici pour donner un message plus précis.
       if (aiService != null) {
          // Si l'IA est là, on peut lui demander de répondre à la place du message statique.
          // Cependant, le plan est que l'IA utilise les outils SolarEdge, donc sans l'API, elle sera limitée.
          // Pour l'instant, on garde le message statique pour indiquer le problème de configuration API.
          // Une amélioration future pourrait être de laisser l'IA répondre si elle n'a pas besoin des outils SolarEdge.
       }
       // Ajouter un message à la conversation via AiService si disponible, sinon via une méthode locale si AssistantService gère aussi l'affichage des messages.
       // D'après le plan, AiService gère l'ajout des messages.
       // On ne peut pas retourner une String ici car la signature a changé en Future<void>.
       // Il faut notifier l'UI via AiService ou un mécanisme partagé.
       // Pour l'instant, on va supposer que l'UI écoute AiService.conversationStream.
       // On ne fait rien ici, car le message d'erreur sera géré par l'absence de données dans le contexte ou par l'échec des appels d'outils dans AiService.
       // Si on veut un message immédiat, il faudrait que AssistantService puisse ajouter des messages à la conversation.
       _addBotMessage("Je n'ai pas accès aux données SolarEdge pour l'instant ; configure ta clé API dans les réglages.");
       return;
    }
    // WeatherManager est injecté et devrait toujours être disponible, mais on peut vérifier
    if (_weatherManager == null) {
       debugPrint("ERROR AssistantService: WeatherManager is null in processUserText.");
       _addBotMessage("Un problème est survenu avec le service météo.");
       return;
    }

    // 0. Tenter de parser la période avec smartParse
    final parsedPeriod = smartParse(text);
    if (parsedPeriod != null) {
       debugPrint("INFO AssistantService: Period parsed with smartParse: ${DateFormat('yyyy-MM-dd').format(parsedPeriod.start)} to ${DateFormat('yyyy-MM-dd').format(parsedPeriod.end)}");
       try {
          // Appeler directement getEnergyRange si une période est parsée
          final startDate = parsedPeriod.start;
          final endDate = parsedPeriod.end;
          final energyDataRange = await solarEdgeApiService.getEnergyRange(startDate, endDate, timeUnit: 'DAY');

          final totalEnergyKwh = energyDataRange.totalEnergy / 1000.0;
          final maxPeakPowerW = energyDataRange.peakPower; // Peut être 0 si l'endpoint /energy ne le fournit pas

          final buffer = StringBuffer();
          buffer.writeln("Bilan du ${DateFormat('dd/MM/yyyy').format(startDate)} au ${DateFormat('dd/MM/yyyy').format(endDate)} :");
          buffer.writeln("- Total produit : ${PowerUtils.formatEnergyKWh(totalEnergyKwh * 1000)}"); // Utiliser totalEnergyKwh (en kWh) et le convertir en Wh pour le formatage
          if (maxPeakPowerW > 0) {
             buffer.writeln("- Pic de puissance : ${PowerUtils.formatWatts(maxPeakPowerW)}");
          } else {
             buffer.writeln("- Pic de puissance : Non disponible (Total: ${totalEnergyKwh.toStringAsFixed(1)} kWh).");

          }

          _addBotMessage(buffer.toString()); // Afficher le résultat via _addBotMessage
          return; // Sortir après avoir géré la période parsée
       } catch (e) {
          debugPrint("ERROR AssistantService: Erreur lors de l'appel getEnergyRange après smartParse: $e");
          _addBotMessage("Désolé, je n'ai pas pu récupérer les données pour la période demandée.");
          return; // Sortir après l'erreur
       }
    }


    // 1. Tenter de faire correspondre un intent rapide
    for (var intent in _quickIntents) {
      final match = intent.regex.firstMatch(text);
      if (match != null) {
        debugPrint("INFO AssistantService: Quick intent matched: ${intent.id}");
        // Exécuter le handler et obtenir la réponse
        final quickIntentResponse = await intent.handler(solarEdgeApiService, _weatherManager, userPreferences, match);
        // Ajouter la réponse de l'intent rapide à la conversation via _addBotMessage
        _addBotMessage(quickIntentResponse);
        return; // Sortir après avoir géré l'intent rapide
      }
    }

    // 2. Si aucun intent rapide ne correspond et aucune période parsée, utiliser le LLM (AiService)
    debugPrint("INFO AssistantService: No quick intent or parsed period matched. Falling back to LLM.");

    if (aiService == null) {
       // Si l'AiService n'est pas disponible (par exemple, clé Gemini manquante)
       debugPrint("WARNING AssistantService: AiService is null. Cannot fall back to LLM.");
       _addBotMessage("Désolé, l'assistant IA n'est pas configuré. Veuillez vérifier vos paramètres.");
       return;
    }

    // Appeler le service LLM (AiService) avec le texte utilisateur
    // AiService.sendMessage gère déjà la construction du prompt (contexte + system prompt)
    // et la gestion de la conversation (ajout message utilisateur, boucle d'outils, ajout réponse IA).
    await aiService.sendMessage(text);
  }

  // Méthode interne pour ajouter un message de l'IA à la conversation (pour les cas d'erreur avant l'appel à l'IA)
  // Cette méthode est un ajout pour gérer les messages d'erreur immédiats dans AssistantService.
  // Si AiService gère déjà l'ajout des messages, cette méthode pourrait être redondante ou utilisée différemment.
  // Pour l'instant, on la garde pour les messages d'erreur avant l'appel à AiService.
  void _addBotMessage(String content) {
     // On a besoin d'accéder à la conversation active.
     // Si AssistantService ne gère pas la conversation, il faut un autre mécanisme.
     // Le plan indique que AiService gère l'ajout des messages.
     // On va donc supposer qu'on peut appeler une méthode sur AiService pour ajouter un message bot.
     final aiService = ServiceManager().aiService;
     if (aiService != null) {
        aiService.addBotMessage(content); // Supposant une méthode publique addBotMessage dans AiService
     } else {
        debugPrint("WARNING AssistantService: AiService is null, cannot add bot message to conversation.");
        // Logguer ou gérer l'erreur autrement si AiService n'est pas disponible.
     }
  }


  // Méthode appelée lorsque le service API change
  void _onApiServiceChanged() {
    debugPrint("DEBUG AssistantService: _onApiServiceChanged called. New API Service is ${_apiServiceNotifier.value == null ? 'null' : 'instance'}.");
    // Si le service API devient disponible, générer les insights
    if (_apiServiceNotifier.value != null) {
      generateInsights();
    } else {
      // Si le service API devient null, vider les insights
      clearInsights();
    }
  }

  // Méthode appelée lorsque les préférences utilisateur changent
  void _onUserPreferencesChanged() {
     debugPrint("DEBUG AssistantService: _onUserPreferencesChanged called. New Preferences are ${_userPreferencesNotifier.value == null ? 'null' : 'instance'}.");
     // Régénérer les insights lorsque les préférences changent
     generateInsights();
  }


  Future<void> generateInsights() async {
    // Obtenir l'instance actuelle du service API depuis le ValueNotifier
    final SolarEdgeApiService? solarEdgeApiService = _apiServiceNotifier.value;
    // Obtenir les préférences utilisateur actuelles depuis le ValueNotifier
    final UserPreferences? userPreferences = _userPreferencesNotifier.value;

    // Ne pas générer d'insights si le service API n'est pas disponible
    if (solarEdgeApiService == null) {
      debugPrint("INFO AssistantService: generateInsights called but SolarEdgeApiService is null. Clearing insights.");
      clearInsights(); // S'assurer que les insights sont vides
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    _insights = [];
    notifyListeners();

    try {
      debugPrint("INFO AssistantService: Generating insights...");
      // --- Récupération des données nécessaires ---
      // Obtenir le prix et la puissance crête depuis les préférences utilisateur
      final double? priceKwh = userPreferences?.energyRate; // Correction: Utiliser energyRate
      final double? peakPower = userPreferences?.peakPowerKw; // En kWc

      // Données solaires
      DailySolarData? dailySolarData;
      SolarData? currentSolarData;
      try {
        // Correction: Utiliser les méthodes existantes via l'instance obtenue
        dailySolarData =
            await solarEdgeApiService.getDailyEnergy(DateTime.now());
        currentSolarData = await solarEdgeApiService.getCurrentPowerData();
        debugPrint("DEBUG AssistantService: Solar data retrieved.");
      } catch (e) {
        debugPrint("ERROR AssistantService: Erreur récupération données solaires pour Assistant: $e");
        _errorMessage = "Impossible de récupérer les données solaires.";
      }

      // Données météo
      // Correction: Utiliser les getters publics de WeatherManager
      final WeatherData? currentWeatherData = _weatherManager.currentWeather;
      // Correction: Accéder à la liste via weatherForecast.hourlyForecast
      final List<WeatherData>? forecastHourly =
          _weatherManager.weatherForecast?.hourlyForecast;
      debugPrint("DEBUG AssistantService: Weather data retrieved.");

      // --- Génération des Insights ---
      List<AssistantInsight> generatedInsights = [];

      // 1. Insight Météo Actuelle
      if (currentWeatherData != null) {
        // Correction: Utiliser 'condition' et '_getWeatherIcon' adapté
        generatedInsights.add(AssistantInsight(
          title: "Météo Actuelle",
          message:
              "${currentWeatherData.temperature.toStringAsFixed(1)}°C, ${currentWeatherData.condition}.", // Utiliser .condition
          icon: _getWeatherIconFromCode(
              currentWeatherData.iconCode), // Utiliser .iconCode
          iconColor: Colors.blue,
        ));
      }

      // 2. Insight Économies du Jour
      // Correction: Utiliser dailySolarData.totalEnergy (qui est en Wh)
      if (priceKwh != null &&
          priceKwh > 0 &&
          dailySolarData != null &&
          dailySolarData.totalEnergy > 0) {
        // Convertir Wh en kWh pour le calcul
        final dailyEnergyKWh = dailySolarData.totalEnergy / 1000.0;
        final dailySaving = dailyEnergyKWh * priceKwh;
        generatedInsights.add(AssistantInsight(
          title: "Économies du Jour",
          message:
              "Aujourd'hui, vous avez produit ${dailyEnergyKWh.toStringAsFixed(2)} kWh, "
              "économisant environ ${dailySaving.toStringAsFixed(2)} €.",
          icon: Icons.euro_symbol,
          iconColor: Colors.green,
        ));
      } else if (userPreferences != null && (priceKwh == null || priceKwh <= 0)) {
        // Afficher l'insight si les préférences existent mais que le prix n'est pas configuré
         generatedInsights.add(AssistantInsight(
           title: "Économies",
           message: "Entrez votre prix du kWh dans les paramètres pour calculer vos économies.",
           icon: Icons.settings_outlined,
           iconColor: Colors.orange,
         ));
      }


      // 3. Insight Performance vs. Pic
      // Correction: Utiliser currentSolarData.power (en W) et peakPower (en kWc)
      if (peakPower != null && peakPower > 0 && currentSolarData != null) {
        // Convertir la puissance crête en W pour comparer
        final peakPowerW = peakPower * 1000.0;
        final currentPowerW = currentSolarData.power; // Déjà en W

        if (peakPowerW > 0) {
          // Eviter division par zéro
          final currentPercentage = (currentPowerW / peakPowerW) * 100;
          // Convertir la puissance actuelle en kW pour l'affichage
          final currentPowerKW = currentPowerW / 1000.0;

          generatedInsights.add(AssistantInsight(
            title: "Performance Actuelle",
            message:
                "Votre installation produit ${currentPowerKW.toStringAsFixed(2)} kW, "
                "soit ${currentPercentage.toStringAsFixed(0)}% de votre puissance crête (${peakPower.toStringAsFixed(2)} kWc).",
            icon: Icons.flash_on_outlined,
            iconColor: Colors.orange,
          ));
        }
      } else if (userPreferences != null && (peakPower == null || peakPower <= 0)) {
         // Afficher l'insight si les préférences existent mais que la puissance crête n'est pas configurée
         generatedInsights.add(AssistantInsight(
           title: "Puissance Crête",
           message: "Entrez la puissance crête de votre installation dans les paramètres pour une analyse plus précise.",
           icon: Icons.settings_outlined,
           iconColor: Colors.orange,
         ));
      }


      // 4. Insight Prévisions Météo (Simple)
      // Correction: Utiliser forecastHourly et la méthode _summarizeForecast adaptée
      if (forecastHourly != null && forecastHourly.isNotEmpty) {
        String forecastSummary = _summarizeForecast(forecastHourly);
        generatedInsights.add(AssistantInsight(
            title: "Prévisions (24h)",
            message: forecastSummary,
            // Correction: Utiliser une icône basée sur le résumé
            icon: _getIconForForecastSummary(forecastSummary),
            iconColor: Colors.blueGrey));
      }

      // 5. Conseil Basique (Basé sur la puissance actuelle)
      // Correction: Utiliser currentSolarData et peakPower (en W)
      if (currentSolarData != null && peakPower != null && peakPower > 0) {
        final peakPowerW = peakPower * 1000.0;
        final currentPowerW = currentSolarData.power;

        if (currentPowerW > peakPowerW * 0.5) {
          // Si production > 50% du pic
          generatedInsights.add(AssistantInsight(
              title: "Conseil",
              message:
                  "Bonne production en cours ! C'est le moment idéal pour utiliser vos appareils énergivores.",
              icon: Icons.power_outlined,
              iconColor: Colors.lightGreen));
        } else if (currentPowerW < peakPowerW * 0.1 &&
            currentWeatherData != null &&
            currentWeatherData.condition.toLowerCase().contains("pluie")) {
          generatedInsights.add(AssistantInsight(
              title: "Conseil",
              message:
                  "Production faible et temps pluvieux. Pensez à reporter l'utilisation des appareils non essentiels.",
              icon: Icons.power_off_outlined,
              iconColor: Colors.redAccent));
        }
      }

      _insights = generatedInsights;
      debugPrint("INFO AssistantService: Insights generated successfully.");
    } catch (e, stacktrace) {
      _errorMessage = "Erreur lors de la génération des insights: $e";
      debugPrint(_errorMessage);
      debugPrint(stacktrace.toString());
      // Ajouter un insight d'erreur
      _insights.add(AssistantInsight(
          title: "Erreur",
          message:
              "Impossible de générer les informations pour le moment. Veuillez réessayer.",
          icon: Icons.error_outline,
          iconColor: Colors.red));
    } finally {
      _isLoading = false;
      notifyListeners();
      debugPrint(
          "DEBUG AssistantService: generateInsights finished. isLoading: $_isLoading");
    }
  }

  /// Vide la liste des insights et notifie les listeners.
  void clearInsights() {
    _insights = [];
    _errorMessage = null; // Effacer aussi les messages d'erreur potentiels
    notifyListeners();
    debugPrint("ℹ️ AssistantService insights cleared.");
  }

  // Correction: Helper pour obtenir une icône basée sur l'iconCode (String) de WeatherData
  IconData _getWeatherIconFromCode(String? iconCode) {
    if (iconCode == null) return Icons.help_outline;
    // Mapping simplifié basé sur les codes OpenWeatherMap-like fournis par OpenMeteoWeatherService
    switch (iconCode) {
      case '01d':
        return Icons.wb_sunny; // Jour clair
      case '01n':
        return Icons.nightlight_round; // Nuit claire
      case '02d':
        return Icons.cloud_outlined; // Jour peu nuageux
      case '02n':
        return Icons.cloudy_snowing; // Nuit peu nuageuse (approximation)
      case '03d':
      case '03n':
        return Icons.cloud; // Nuageux
      case '04d':
      case '04n':
        return Icons.cloud_queue; // Très nuageux / couvert
      case '09d':
      case '09n':
        return Icons.water_drop; // Averses / Pluie légère
      case '10d':
        return Icons.beach_access; // Pluie jour (approximation)
      case '10n':
        return Icons.nights_stay; // Pluie nuit (approximation)
      case '11d':
      case '11n':
        return Icons.flash_on; // Orage
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

  // Correction: Helper pour résumer les prévisions basé sur 'condition' (String)
  String _summarizeForecast(List<WeatherData> forecast) {
    if (forecast.isEmpty) return "Prévisions non disponibles.";

    Map<String, int> conditionCounts = {};
    int totalHours = 0;
    DateTime now = DateTime.now();
    DateTime endForecast = now.add(const Duration(hours: 24));

    for (var data in forecast) {
      // Correction: Utiliser .timestamp
      if (data.timestamp.isAfter(now) && data.timestamp.isBefore(endForecast)) {
        // Correction: Utiliser .condition
        conditionCounts[data.condition] =
            (conditionCounts[data.condition] ?? 0) + 1;
        totalHours++;
      }
      if (totalHours >= 24) break; // Limiter à 24h
    }

    if (conditionCounts.isEmpty) return "Données de prévision incomplètes.";

    // Trouver la condition la plus fréquente
    var sortedConditions = conditionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    String dominantCondition = sortedConditions.first.key;

    // Retourner un résumé basé sur la condition dominante
    // Simplification : on retourne juste la condition dominante
    // On pourrait améliorer en groupant les conditions (ex: "Pluie" pour "Pluie légère", "Pluie modérée", etc.)
    return dominantCondition;
  }

  // Helper pour choisir une icône basée sur le texte du résumé des prévisions
  IconData _getIconForForecastSummary(String summary) {
    summary = summary.toLowerCase();
    if (summary.contains('ensoleillé') || summary.contains('dégagé')) {
      return Icons.wb_sunny_outlined;
    }
    if (summary.contains('nuage')) return Icons.cloud_outlined;
    if (summary.contains('pluie') ||
        summary.contains('averse') ||
        summary.contains('bruine')) {
      return Icons.water_drop_outlined;
    }
    if (summary.contains('orage')) return Icons.thunderstorm_outlined;
    if (summary.contains('neige')) return Icons.ac_unit_outlined;
    if (summary.contains('brouillard')) return Icons.foggy;
    return Icons.schedule; // Icône par défaut
  }

  // Ajouter une méthode dispose pour annuler l'abonnement
  @override
  void dispose() {
    _apiServiceSubscription
        ?.call(); // Utiliser .call() pour exécuter la VoidCallback
    _userPreferencesSubscription?.call(); // Annuler l'abonnement aux préférences
    super.dispose();
  }
}

// Classe simple pour représenter une plage de périodes (utilisée par smartParse)
class PeriodRange {
  final DateTime start;
  final DateTime end;

  PeriodRange(this.start, this.end);
}
