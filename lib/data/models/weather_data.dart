class WeatherData {
  final DateTime timestamp;
  final double temperature; // Température en degrés Celsius
  final double humidity; // Humidité en pourcentage
  final double windSpeed; // Vitesse du vent en km/h
  final String condition; // Description textuelle (ex: "ensoleillé", "nuageux")
  final String iconCode; // Code de l'icône météo à afficher
  final double? cloudCover; // Couverture nuageuse en pourcentage
  final double? precipitation; // Précipitations en mm
  final double? uvIndex; // Indice UV
  final double? shortwaveRadiation; // Irradiance globale horizontale (GHI) en W/m²

  WeatherData({
    required this.timestamp,
    required this.temperature,
    required this.humidity,
    required this.windSpeed,
    required this.condition,
    required this.iconCode,
    this.cloudCover,
    this.precipitation,
    this.uvIndex,
    this.shortwaveRadiation, // Add shortwaveRadiation to constructor
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    // Helper to safely get radiation value as num?
    num? getRadiationValue() {
      return json['shortwave_radiation'] ??
             json['global_horizontal_irradiance'] ??
             json['solar_radiation'] ??
             json['ghi'];
    }

    final radiationValue = getRadiationValue();

    return WeatherData(
      timestamp: DateTime.parse(json['timestamp'] as String),
      temperature: (json['temperature'] as num).toDouble(), // Safe cast
      humidity: (json['humidity'] as num).toDouble(), // Safe cast
      windSpeed: (json['windSpeed'] as num).toDouble(), // Safe cast
      condition: json['condition'] as String,
      iconCode: json['iconCode'] as String,
      cloudCover: (json['cloudCover'] as num?)?.toDouble(), // Safe cast (nullable)
      precipitation: (json['precipitation'] as num?)?.toDouble(), // Safe cast (nullable)
      uvIndex: (json['uvIndex'] as num?)?.toDouble(), // Safe cast (nullable)
      // Safe cast for radiation (nullable)
      shortwaveRadiation: radiationValue?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'temperature': temperature,
      'humidity': humidity,
      'windSpeed': windSpeed,
      'condition': condition,
      'iconCode': iconCode,
      'cloudCover': cloudCover,
      'precipitation': precipitation,
      'uvIndex': uvIndex,
      'shortwave_radiation': shortwaveRadiation, // Add shortwaveRadiation to JSON
    };
  }
}

class WeatherForecast {
  final DateTime timestamp;
  final List<WeatherData> hourlyForecast; // Prévisions horaires
  final List<WeatherData> dailyForecast; // Prévisions journalières

  WeatherForecast({
    required this.timestamp,
    required this.hourlyForecast,
    required this.dailyForecast,
  });

  factory WeatherForecast.fromJson(Map<String, dynamic> json) {
    return WeatherForecast(
      timestamp: DateTime.parse(json['timestamp'] as String),
      hourlyForecast: (json['hourlyForecast'] as List)
          .map((e) => WeatherData.fromJson(e as Map<String, dynamic>))
          .toList(),
      dailyForecast: (json['dailyForecast'] as List)
          .map((e) => WeatherData.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'hourlyForecast': hourlyForecast.map((e) => e.toJson()).toList(),
      'dailyForecast': dailyForecast.map((e) => e.toJson()).toList(),
    };
  }
}

class ProductionForecast {
  final DateTime date;
  final double predictedEnergy; // Énergie prévue en watt-heures
  final double confidence; // Niveau de confiance de la prédiction (0-1)
  final WeatherData? weatherData; // Données météo associées à la prédiction

  ProductionForecast({
    required this.date,
    required this.predictedEnergy,
    required this.confidence,
    this.weatherData,
  });

  factory ProductionForecast.fromJson(Map<String, dynamic> json) {
    return ProductionForecast(
      date: DateTime.parse(json['date'] as String),
      predictedEnergy: json['predictedEnergy'] as double,
      confidence: json['confidence'] as double,
      weatherData: json['weatherData'] != null
          ? WeatherData.fromJson(json['weatherData'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'predictedEnergy': predictedEnergy,
      'confidence': confidence,
      'weatherData': weatherData?.toJson(),
    };
  }
}
