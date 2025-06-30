// lib/data/models/user_preferences.dart
// Version complète avec le getter formattedActiveDaysShort ajouté

import 'package:flutter/material.dart'; // Import pour TimeOfDay
import 'package:uuid/uuid.dart'; // Pour générer les IDs

class UserPreferences {
  final String? solarEdgeApiKey;

  final String? siteId;

  // --- Nouveau champ pour la clé API Gemini ---
  final String? geminiApiKey;
  // --- Fin nouveau champ ---

  final bool darkMode;

  final String displayUnit; // 'kW', 'W', etc.

  final String currency; // 'EUR', 'USD', etc.

  double? _energyRate; // Private backing field
  double? get energyRate => _energyRate; // Explicit getter
  set energyRate(double? value) => _energyRate = value; // Explicit setter (optional, but good practice)

  final NotificationSettings notificationSettings;

  final DisplaySettings displaySettings;

  final String selectedLanguage; // 'fr', 'en', etc.

  final List<String> favoriteCharts; // Graphiques favoris à afficher

  // --- Nouveau champ pour la puissance crête ---
  double? _peakPowerKw; // Private backing field
  double? get peakPowerKw => _peakPowerKw; // Explicit getter
  set peakPowerKw(double? value) => _peakPowerKw = value; // Explicit setter
  // --- Fin nouveau champ ---

  // --- Nouveaux champs pour l'installation physique ---
  double? _panelTilt; // Private backing field
  double? get panelTilt => _panelTilt; // Explicit getter
  set panelTilt(double? value) => _panelTilt = value; // Explicit setter

  String? _panelOrientation; // Private backing field
  String? get panelOrientation => _panelOrientation; // Explicit getter
  set panelOrientation(String? value) => _panelOrientation = value; // Explicit setter
  // --- Fin nouveaux champs ---

  // --- Nouveau champ pour la puissance de la machine à laver ---
  double? _washingMachineKw; // Private backing field
  double? get washingMachineKw => _washingMachineKw; // Explicit getter
  set washingMachineKw(double? value) => _washingMachineKw = value; // Explicit setter
  // --- Fin nouveau champ ---

  // --- Nouveau champ pour la durée de la machine à laver ---
  int? _defaultWashingMachineDurationMin; // Private backing field
  int? get defaultWashingMachineDurationMin => _defaultWashingMachineDurationMin; // Explicit getter
  set defaultWashingMachineDurationMin(int? value) => _defaultWashingMachineDurationMin = value; // Explicit setter
  // --- Fin nouveau champ ---

  // --- Nouveau champ pour la puissance de la deuxième machine à laver ---
  double? _washingMachine2Kw; // Private backing field
  double? get washingMachine2Kw => _washingMachine2Kw; // Explicit getter
  set washingMachine2Kw(double? value) => _washingMachine2Kw = value; // Explicit setter
  // --- Fin nouveau champ ---

  // --- Nouveau champ pour la durée de la deuxième machine à laver ---
  int? _defaultWashingMachine2DurationMin; // Private backing field
  int? get defaultWashingMachine2DurationMin => _defaultWashingMachine2DurationMin; // Explicit getter
  set defaultWashingMachine2DurationMin(int? value) => _defaultWashingMachine2DurationMin = value; // Explicit setter
  // --- Fin nouveau champ ---

  // --- Nouveau champ pour la puissance du sèche-linge ---
  double? _dryerKw; // Private backing field
  double? get dryerKw => _dryerKw; // Explicit getter
  set dryerKw(double? value) => _dryerKw = value; // Explicit setter
  // --- Fin nouveau champ ---

  // --- Nouveau champ pour la durée du sèche-linge ---
  int? _defaultDryerDurationMin; // Private backing field
  int? get defaultDryerDurationMin => _defaultDryerDurationMin; // Explicit getter
  set defaultDryerDurationMin(int? value) => _defaultDryerDurationMin = value; // Explicit setter
  // --- Fin nouveau champ ---

  // --- Nouveaux champs pour la localisation (pour calcul solaire) ---
  double? _latitude; // Private backing field
  double? get latitude => _latitude; // Explicit getter
  set latitude(double? value) => _latitude = value; // Explicit setter

  double? _longitude; // Private backing field
  double? get longitude => _longitude; // Explicit getter
  set longitude(double? value) => _longitude = value; // Explicit setter
  // --- Fin nouveaux champs ---

  // --- Nouveau champ pour la source de localisation météo ---
  final String weatherLocationSource; // 'site_primary', 'device_gps'
  // --- Fin nouveau champ ---


  UserPreferences({
    this.solarEdgeApiKey,
    this.siteId,
    this.geminiApiKey,
    this.weatherLocationSource = 'site_primary', // Valeur par défaut
    bool darkMode = true,
    String displayUnit = 'kW',
    String currency = 'EUR',
    double? energyRate,
    NotificationSettings? notificationSettings,
    DisplaySettings? displaySettings,
    String selectedLanguage = 'fr',
    List<String>? favoriteCharts,
    double? peakPowerKw,
    double? panelTilt,
    String? panelOrientation,
    double? washingMachineKw,
    int? defaultWashingMachineDurationMin,
    double? washingMachine2Kw, // Nouveau champ
    int? defaultWashingMachine2DurationMin, // Nouveau champ
    double? dryerKw,
    int? defaultDryerDurationMin,
    double? latitude,
    double? longitude,
  })  : darkMode = darkMode,
        displayUnit = displayUnit,
        currency = currency,
        _energyRate = energyRate,
        notificationSettings = notificationSettings ?? NotificationSettings(),
        displaySettings = displaySettings ?? DisplaySettings(),
        selectedLanguage = selectedLanguage,
        favoriteCharts = favoriteCharts ?? ['production', 'comparison', 'energy'],
        _peakPowerKw = peakPowerKw,
        _panelTilt = panelTilt,
        _panelOrientation = panelOrientation,
        _washingMachineKw = washingMachineKw,
        _defaultWashingMachineDurationMin = defaultWashingMachineDurationMin,
        _washingMachine2Kw = washingMachine2Kw, // Initialisation du nouveau champ
        _defaultWashingMachine2DurationMin = defaultWashingMachine2DurationMin, // Initialisation du nouveau champ
        _dryerKw = dryerKw,
        _defaultDryerDurationMin = defaultDryerDurationMin,
        _latitude = latitude,
        _longitude = longitude;


  UserPreferences copyWith({
    String? solarEdgeApiKey,
    String? siteId,
    String? geminiApiKey,
    String? weatherLocationSource,
    bool? darkMode,
    String? displayUnit,
    String? currency,
    double? energyRate,
    NotificationSettings? notificationSettings,
    DisplaySettings? displaySettings,
    String? selectedLanguage,
    List<String>? favoriteCharts,
    double? peakPowerKw,
    double? panelTilt,
    String? panelOrientation,
    double? washingMachineKw,
    int? defaultWashingMachineDurationMin,
    double? washingMachine2Kw, // Nouveau champ
    int? defaultWashingMachine2DurationMin, // Nouveau champ
    double? dryerKw,
    int? defaultDryerDurationMin,
    double? latitude,
    double? longitude,
  }) {
    return UserPreferences(
      solarEdgeApiKey: solarEdgeApiKey ?? this.solarEdgeApiKey,
      siteId: siteId ?? this.siteId,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      darkMode: darkMode ?? this.darkMode,
      displayUnit: displayUnit ?? this.displayUnit,
      currency: currency ?? this.currency,
      energyRate: energyRate ?? this._energyRate, // Use private field
      notificationSettings: notificationSettings ?? this.notificationSettings.copyWith(),
      displaySettings: displaySettings ?? this.displaySettings.copyWith(),
      selectedLanguage: selectedLanguage ?? this.selectedLanguage,
      favoriteCharts: favoriteCharts ?? List.from(this.favoriteCharts),
      peakPowerKw: peakPowerKw ?? this._peakPowerKw, // Use private field
      panelTilt: panelTilt ?? this._panelTilt, // Use private field
      panelOrientation: panelOrientation ?? this._panelOrientation, // Use private field
      washingMachineKw: washingMachineKw ?? this._washingMachineKw, // Use private field
      defaultWashingMachineDurationMin: defaultWashingMachineDurationMin ?? this._defaultWashingMachineDurationMin, // Use private field
      washingMachine2Kw: washingMachine2Kw ?? this._washingMachine2Kw, // Copie du nouveau champ
      defaultWashingMachine2DurationMin: defaultWashingMachine2DurationMin ?? this._defaultWashingMachine2DurationMin, // Copie du nouveau champ
      dryerKw: dryerKw ?? this._dryerKw, // Copie du nouveau champ
      defaultDryerDurationMin: defaultDryerDurationMin ?? this._defaultDryerDurationMin, // Copie du nouveau champ
      latitude: latitude ?? this._latitude, // Use private field
      longitude: longitude ?? this._longitude, // Use private field
      weatherLocationSource: weatherLocationSource ?? this.weatherLocationSource,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'solarEdgeApiKey': solarEdgeApiKey,
      'siteId': siteId,
      'geminiApiKey': geminiApiKey, // Inclure dans toJson
      'darkMode': darkMode,
      'displayUnit': displayUnit,
      'currency': currency,
      'energyRate': energyRate,
      'notificationSettings': notificationSettings.toJson(),
      'displaySettings': displaySettings.toJson(),
      'selectedLanguage': selectedLanguage,
      'favoriteCharts': favoriteCharts,
      'peakPowerKw': peakPowerKw, // Inclure dans toJson
      'panelTilt': panelTilt, // Inclure dans toJson
      'panelOrientation': panelOrientation, // Inclure dans toJson
      'washingMachineKw': washingMachineKw, // Inclure dans toJson
      'defaultWashingMachineDurationMin': defaultWashingMachineDurationMin, // Inclure dans toJson
      'washingMachine2Kw': washingMachine2Kw, // Inclure dans toJson
      'defaultWashingMachine2DurationMin': defaultWashingMachine2DurationMin, // Inclure dans toJson
      'dryerKw': dryerKw, // Inclure dans toJson
      'defaultDryerDurationMin': defaultDryerDurationMin, // Inclure dans toJson
      'latitude': latitude, // Inclure dans toJson
      'longitude': longitude, // Inclure dans toJson
      'weatherLocationSource': weatherLocationSource, // Inclure dans toJson
    };
  }

  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    return UserPreferences(
      solarEdgeApiKey: json['solarEdgeApiKey'] as String?,
      siteId: json['siteId'] as String?,
      geminiApiKey: json['geminiApiKey'] as String?, // Inclure dans fromJson
      darkMode: json['darkMode'] as bool? ?? true,
      displayUnit: json['displayUnit'] as String? ?? 'kW',
      currency: json['currency'] as String? ?? 'EUR',
      energyRate: (json['energyRate'] as num?)?.toDouble(), // Gérer num?
      notificationSettings: json['notificationSettings'] != null
          ? NotificationSettings.fromJson(
              json['notificationSettings'] as Map<String, dynamic>)
          : NotificationSettings(),
      displaySettings: json['displaySettings'] != null
          ? DisplaySettings.fromJson(
              json['displaySettings'] as Map<String, dynamic>)
          : DisplaySettings(),
      selectedLanguage: json['selectedLanguage'] as String? ?? 'fr',
      favoriteCharts: json['favoriteCharts'] != null
          ? List<String>.from(json['favoriteCharts'] as List)
          : ['production', 'comparison', 'energy'],
      peakPowerKw:
          (json['peakPowerKw'] as num?)?.toDouble(), // Inclure dans fromJson
      panelTilt: (json['panelTilt'] as num?)?.toDouble(), // Inclure dans fromJson
      panelOrientation: json['panelOrientation'] as String?, // Inclure dans fromJson
      washingMachineKw: (json['washingMachineKw'] as num?)?.toDouble(), // Inclure dans fromJson
      defaultWashingMachineDurationMin: json['defaultWashingMachineDurationMin'] as int?, // Inclure dans fromJson
      washingMachine2Kw: (json['washingMachine2Kw'] as num?)?.toDouble(), // Inclure dans fromJson
      defaultWashingMachine2DurationMin: json['defaultWashingMachine2DurationMin'] as int?, // Inclure dans fromJson
      dryerKw: (json['dryerKw'] as num?)?.toDouble(), // Inclure dans fromJson
      defaultDryerDurationMin: json['defaultDryerDurationMin'] as int?, // Inclure dans fromJson
      latitude: (json['latitude'] as num?)?.toDouble(), // Inclure dans fromJson
      longitude: (json['longitude'] as num?)?.toDouble(), // Inclure dans fromJson
      weatherLocationSource: json['weatherLocationSource'] as String? ?? 'site_primary', // Inclure dans fromJson
    );
  }
}

class NotificationSettings {
  final String id; // ID unique (UUID) - AJOUTÉ ICI
  final bool enablePowerNotifications;

  final bool enableEnergyNotifications;

  final bool enableWeatherNotifications;

  final bool enablePredictionNotifications;

  final List<NotificationCriteria> powerCriteria;

  final List<NotificationCriteria> energyCriteria;

  final List<String>
      notificationTime; // Obsolète ? Remplacé par startTime/endTime dans Criteria

  final List<int>
      notificationDays; // Obsolète ? Remplacé par activeDays dans Criteria

  final bool enableDailySummary; // Activer le récapitulatif quotidien

  final String
      dailySummaryTime; // Heure du récapitulatif quotidien (format: 'HH:mm')

  NotificationSettings({
    String? id, // Rendre optionnel ici
    this.enablePowerNotifications = true,
    this.enableEnergyNotifications = true, // Gardé pour future extension
    this.enableWeatherNotifications = true, // Gardé pour future extension
    this.enablePredictionNotifications = true, // Gardé pour future extension
    this.enableDailySummary = true,
    this.dailySummaryTime = '18:00',
    List<NotificationCriteria>? powerCriteria,
    List<NotificationCriteria>? energyCriteria, // Gardé pour future extension
    List<String>?
        notificationTime, // Obsolète mais gardé pour compatibilité lecture ?
    List<int>?
        notificationDays, // Obsolète mais gardé pour compatibilité lecture ?
  })  : id = id ?? const Uuid().v4(), // Générer ID si non fourni
        powerCriteria = powerCriteria ?? [],
        energyCriteria = energyCriteria ?? [],
        notificationTime =
            notificationTime ?? ['08:00', '20:00'], // Garder défaut si lu
        notificationDays =
            notificationDays ?? [1, 2, 3, 4, 5, 6, 7]; // Garder défaut si lu

  NotificationSettings copyWith({
    String? id,
    bool? enablePowerNotifications,
    bool? enableEnergyNotifications,
    bool? enableWeatherNotifications,
    bool? enablePredictionNotifications,
    List<NotificationCriteria>? powerCriteria,
    List<NotificationCriteria>? energyCriteria,
    List<String>? notificationTime, // Garder pour la copie
    List<int>? notificationDays, // Garder pour la copie
    bool? enableDailySummary,
    String? dailySummaryTime,
  }) {
    return NotificationSettings(
      id: id ?? this.id,
      enablePowerNotifications:
          enablePowerNotifications ?? this.enablePowerNotifications,
      enableEnergyNotifications:
          enableEnergyNotifications ?? this.enableEnergyNotifications,
      enableWeatherNotifications:
          enableWeatherNotifications ?? this.enableWeatherNotifications,
      enablePredictionNotifications:
          enablePredictionNotifications ?? this.enablePredictionNotifications,
      // Copier la liste pour éviter modification par référence
      powerCriteria: powerCriteria != null
          ? List.from(powerCriteria)
          : List.from(this.powerCriteria),
      energyCriteria: energyCriteria != null
          ? List.from(energyCriteria)
          : List.from(this.energyCriteria),
      notificationTime: notificationTime ?? this.notificationTime,
      notificationDays: notificationDays ?? this.notificationDays,
      enableDailySummary: enableDailySummary ?? this.enableDailySummary,
      dailySummaryTime: dailySummaryTime ?? this.dailySummaryTime,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'enablePowerNotifications': enablePowerNotifications,
      'enableEnergyNotifications': enableEnergyNotifications,
      'enableWeatherNotifications': enableWeatherNotifications,
      'enablePredictionNotifications': enablePredictionNotifications,
      'enableDailySummary': enableDailySummary,
      'dailySummaryTime': dailySummaryTime,
      'powerCriteria': powerCriteria.map((e) => e.toJson()).toList(),
      'energyCriteria': energyCriteria.map((e) => e.toJson()).toList(),
      'notificationTime':
          notificationTime, // Garder pour sérialisation si besoin
      'notificationDays':
          notificationDays, // Garder pour sérialisation si besoin
    };
  }

  factory NotificationSettings.fromJson(Map<String, dynamic> json) {
    return NotificationSettings(
      id: json['id'] as String? ?? const Uuid().v4(), // Lire ou générer ID
      enablePowerNotifications:
          json['enablePowerNotifications'] as bool? ?? true,
      enableEnergyNotifications:
          json['enableEnergyNotifications'] as bool? ?? true,
      enableWeatherNotifications:
          json['enableWeatherNotifications'] as bool? ?? true,
      enablePredictionNotifications:
          json['enablePredictionNotifications'] as bool? ?? true,
      enableDailySummary: json['enableDailySummary'] as bool? ?? true,
      dailySummaryTime: json['dailySummaryTime'] as String? ?? '18:00',
      powerCriteria: json['powerCriteria'] != null
          ? (json['powerCriteria'] as List)
              .map((e) =>
                  NotificationCriteria.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      energyCriteria: json['energyCriteria'] != null
          ? (json['energyCriteria'] as List)
              .map((e) =>
                  NotificationCriteria.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      // Lire les anciens champs s'ils existent, sinon utiliser défaut
      notificationTime: json['notificationTime'] != null
          ? List<String>.from(json['notificationTime'] as List)
          : ['08:00', '20:00'],
      notificationDays: json['notificationDays'] != null
          ? List<int>.from(json['notificationDays'] as List)
          : [1, 2, 3, 4, 5, 6, 7],
    );
  }
}

class NotificationCriteria {
  final String type; // 'above', 'below', 'change'

  final double threshold;

  final String unit; // 'kW', 'W', 'kWh', '%'

  // final int frequency; // Fréquence minimale entre notifications (minutes) - SUPPRIMÉ

  final String? message; // Message personnalisé

  final String startTime; // Heure de début (format: 'HH:mm')

  final String endTime; // Heure de fin (format: 'HH:mm')

  final List<int> activeDays; // Jours actifs (1-7, lundi-dimanche)

  final int maxNotificationsPerDay; // Limite de notifications par jour

  final DateTime?
      lastTriggered; // Dernière fois que la notification a été déclenchée

  // --- Nouveaux Champs ---

  final String id; // ID unique (UUID)

  final bool isEnabled;

  NotificationCriteria({
    String? id, // Rendre optionnel ici
    required this.type,
    required this.threshold,
    required this.unit,
    // this.frequency = 60, // SUPPRIMÉ
    this.message,
    this.startTime = '00:00', // Défaut 00:00
    this.endTime = '23:59', // Défaut 23:59
    List<int>? activeDays,
    this.maxNotificationsPerDay = 5,
    this.lastTriggered,
    this.isEnabled = true, // Valeur par défaut
  })  : id = id ?? const Uuid().v4(), // Générer ID si non fourni
        activeDays =
            activeDays ?? [1, 2, 3, 4, 5, 6, 7]; // Tous les jours par défaut

  NotificationCriteria copyWith({
    String? id,
    String? type,
    double? threshold,
    String? unit,
    // int? frequency, // SUPPRIMÉ
    ValueGetter<String?>? message, // Gérer null
    String? startTime,
    String? endTime,
    List<int>? activeDays,
    int? maxNotificationsPerDay,
    ValueGetter<DateTime?>? lastTriggered, // Gérer null
    bool? isEnabled,
  }) {
    return NotificationCriteria(
      id: id ?? this.id,
      type: type ?? this.type,
      threshold: threshold ?? this.threshold,
      unit: unit ?? this.unit,
      // frequency: frequency ?? this.frequency, // SUPPRIMÉ
      message:
          message != null ? message() : this.message, // Utiliser ValueGetter
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      activeDays: activeDays ?? List.from(this.activeDays), // Assurer copie
      maxNotificationsPerDay:
          maxNotificationsPerDay ?? this.maxNotificationsPerDay,
      lastTriggered: lastTriggered != null
          ? lastTriggered()
          : this.lastTriggered, // Utiliser ValueGetter
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'isEnabled': isEnabled,
      'type': type,
      'threshold': threshold,
      'unit': unit,
      // 'frequency': frequency, // SUPPRIMÉ
      'message': message,
      'startTime': startTime,
      'endTime': endTime,
      'activeDays': activeDays,
      'maxNotificationsPerDay': maxNotificationsPerDay,
      'lastTriggered': lastTriggered?.toIso8601String(),
    };
  }

  factory NotificationCriteria.fromJson(Map<String, dynamic> json) {
    return NotificationCriteria(
      id: json['id'] as String? ?? const Uuid().v4(), // Lire ou générer ID
      isEnabled: json['isEnabled'] as bool? ?? true, // Lire ou défaut
      type: json['type'] as String? ??
          'above', // Fournir défaut si type peut manquer
      threshold:
          (json['threshold'] as num?)?.toDouble() ?? 0.0, // Fournir défaut
      unit: json['unit'] as String? ?? 'W', // Fournir défaut
      // frequency: json['frequency'] as int? ?? 60, // SUPPRIMÉ
      message: json['message'] as String?,
      startTime: json['startTime'] as String? ?? '00:00', // Fournir défaut
      endTime: json['endTime'] as String? ?? '23:59', // Fournir défaut
      activeDays: json['activeDays'] != null
          ? List<int>.from(json['activeDays'] as List)
          : [1, 2, 3, 4, 5, 6, 7], // Défaut si null
      maxNotificationsPerDay: json['maxNotificationsPerDay'] as int? ?? 5,
      lastTriggered: json['lastTriggered'] != null
          ? DateTime.tryParse(
              json['lastTriggered'] as String) // Utiliser tryParse
          : null,
    );
  }

  // --- Getters pour TimeOfDay ---
  TimeOfDay? get startTimeOfDay {
    try {
      final parts = startTime.split(':');
      if (parts.length != 2) return null;
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return null; // Retourner null en cas d'erreur de parsing
    }
  }

  TimeOfDay? get endTimeOfDay {
    try {
      final parts = endTime.split(':');
      if (parts.length != 2) return null;
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return null; // Retourner null en cas d'erreur de parsing
    }
  }

  // --- GETTER AJOUTÉ ICI ---
  String get formattedActiveDaysShort {
    // Vérifier si activeDays est null ou vide avant d'y accéder
    if (activeDays.isEmpty) return 'Jamais'; // Ou 'Aucun jour'
    if (activeDays.length == 7) return 'Tous les jours';

    const dayChars = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    // Filtrer les jours invalides et mapper
    return activeDays
        .where((day) => day >= 1 && day <= 7) // Filtrer jours valides
        .map((day) => dayChars[day - 1]) // Mapper vers caractère
        .join(' '); // Joindre avec espace
  }
// --- FIN GETTER AJOUTÉ ---
}

class DisplaySettings {
  final bool showCarbonOffset;

  final bool showFinancialData;

  final bool showWeatherData;

  final String graphType; // 'line', 'bar', 'area'

  final List<String> visibleMetrics; // Métriques à afficher dans les graphiques

  final Map<String, bool>
      comparisonEnabled; // Comparaisons activées (jour/mois/année précédent)

  DisplaySettings({
    this.showCarbonOffset = true,
    this.showFinancialData = true,
    this.showWeatherData = true,
    this.graphType = 'line',
    List<String>? visibleMetrics,
    Map<String, bool>? comparisonEnabled,
  })  : visibleMetrics = visibleMetrics ?? ['power', 'energy', 'temperature'],
        comparisonEnabled = comparisonEnabled ??
            {
              'previousDay': true,
              'previousWeek': true,
              'previousMonth': true,
              'previousYear': true,
            };

  DisplaySettings copyWith({
    bool? showCarbonOffset,
    bool? showFinancialData,
    bool? showWeatherData,
    String? graphType,
    List<String>? visibleMetrics,
    Map<String, bool>? comparisonEnabled,
  }) {
    return DisplaySettings(
      showCarbonOffset: showCarbonOffset ?? this.showCarbonOffset,
      showFinancialData: showFinancialData ?? this.showFinancialData,
      showWeatherData: showWeatherData ?? this.showWeatherData,
      graphType: graphType ?? this.graphType,
      visibleMetrics: visibleMetrics ?? List.from(this.visibleMetrics), // Copie
      comparisonEnabled:
          comparisonEnabled ?? Map.from(this.comparisonEnabled), // Copie
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'showCarbonOffset': showCarbonOffset,
      'showFinancialData': showFinancialData,
      'showWeatherData': showWeatherData,
      'graphType': graphType,
      'visibleMetrics': visibleMetrics,
      'comparisonEnabled': comparisonEnabled,
    };
  }

  factory DisplaySettings.fromJson(Map<String, dynamic> json) {
    return DisplaySettings(
      showCarbonOffset: json['showCarbonOffset'] as bool? ?? true,
      showFinancialData: json['showFinancialData'] as bool? ?? true,
      showWeatherData: json['showWeatherData'] as bool? ?? true,
      graphType: json['graphType'] as String? ?? 'line',
      visibleMetrics: json['visibleMetrics'] != null
          ? List<String>.from(json['visibleMetrics'] as List)
          : ['power', 'energy', 'temperature'],
      comparisonEnabled: json['comparisonEnabled'] != null
          ? Map<String, bool>.from(json['comparisonEnabled'] as Map)
          : {
              'previousDay': true,
              'previousWeek': true,
              'previousMonth': true,
              'previousYear': true,
            },
    );
  }
}
