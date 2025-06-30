class SolarData {
  final DateTime timestamp;
  final double power; // Puissance en watts
  final double energy; // Énergie en watt-heures
  final double? temperature; // Température en degrés Celsius (optionnel)
  final double? voltage; // Tension en volts (optionnel)
  final double? current; // Courant en ampères (optionnel)

  SolarData({
    required this.timestamp,
    required this.power,
    required this.energy,
    this.temperature,
    this.voltage,
    this.current,
  });

  factory SolarData.fromJson(Map<String, dynamic> json) {
    return SolarData(
      timestamp: DateTime.parse(json['timestamp'] as String),
      power: json['power'] as double,
      energy: json['energy'] as double,
      temperature: json['temperature'] as double?,
      voltage: json['voltage'] as double?,
      current: json['current'] as double?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'power': power,
      'energy': energy,
      'temperature': temperature,
      'voltage': voltage,
      'current': current,
    };
  }
}

class DailySolarData {
  final DateTime date;
  final double totalEnergy; // Énergie totale du jour en watt-heures
  final double peakPower; // Puissance maximale du jour
  final List<SolarData> hourlyData; // Données par heure
  final double? revenue; // Revenus générés (si configuré)
  final double? carbonOffset; // Réduction d'émissions de CO2 en kg

  DailySolarData({
    required this.date,
    required this.totalEnergy,
    required this.peakPower,
    required this.hourlyData,
    this.revenue,
    this.carbonOffset,
  });

  factory DailySolarData.fromJson(Map<String, dynamic> json) {
    return DailySolarData(
      date: DateTime.parse(json['date'] as String),
      totalEnergy: json['totalEnergy'] as double,
      peakPower: json['peakPower'] as double,
      hourlyData: (json['hourlyData'] as List)
          .map((e) => SolarData.fromJson(e as Map<String, dynamic>))
          .toList(),
      revenue: json['revenue'] as double?,
      carbonOffset: json['carbonOffset'] as double?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date.toIso8601String(),
      'totalEnergy': totalEnergy,
      'peakPower': peakPower,
      'hourlyData': hourlyData.map((e) => e.toJson()).toList(),
      'revenue': revenue,
      'carbonOffset': carbonOffset,
    };
  }
}

class MonthlySolarData {
  final DateTime month;
  final double totalEnergy; // Énergie totale du mois en watt-heures
  final double peakPower; // Puissance maximale du mois
  final List<DailySolarData> dailyData; // Données quotidiennes
  final double? revenue; // Revenus générés (si configuré)
  final double? carbonOffset; // Réduction d'émissions de CO2 en kg

  MonthlySolarData({
    required this.month,
    required this.totalEnergy,
    required this.peakPower,
    required this.dailyData,
    this.revenue,
    this.carbonOffset,
  });

  factory MonthlySolarData.fromJson(Map<String, dynamic> json) {
    return MonthlySolarData(
      month: DateTime.parse(json['month'] as String),
      totalEnergy: json['totalEnergy'] as double,
      peakPower: json['peakPower'] as double,
      dailyData: (json['dailyData'] as List)
          .map((e) => DailySolarData.fromJson(e as Map<String, dynamic>))
          .toList(),
      revenue: json['revenue'] as double?,
      carbonOffset: json['carbonOffset'] as double?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'month': month.toIso8601String(),
      'totalEnergy': totalEnergy,
      'peakPower': peakPower,
      'dailyData': dailyData.map((e) => e.toJson()).toList(),
      'revenue': revenue,
      'carbonOffset': carbonOffset,
    };
  }
}

class YearlySolarData {
  final int year;
  final double totalEnergy; // Énergie totale de l'année en watt-heures
  final double peakPower; // Puissance maximale de l'année
  final List<MonthlySolarData> monthlyData; // Données mensuelles
  final double? revenue; // Revenus générés (si configuré)
  final double? carbonOffset; // Réduction d'émissions de CO2 en kg

  YearlySolarData({
    required this.year,
    required this.totalEnergy,
    required this.peakPower,
    required this.monthlyData,
    this.revenue,
    this.carbonOffset,
  });

  factory YearlySolarData.fromJson(Map<String, dynamic> json) {
    return YearlySolarData(
      year: json['year'] as int,
      totalEnergy: json['totalEnergy'] as double,
      peakPower: json['peakPower'] as double,
      monthlyData: (json['monthlyData'] as List)
          .map((e) => MonthlySolarData.fromJson(e as Map<String, dynamic>))
          .toList(),
      revenue: json['revenue'] as double?,
      carbonOffset: json['carbonOffset'] as double?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'year': year,
      'totalEnergy': totalEnergy,
      'peakPower': peakPower,
      'monthlyData': monthlyData.map((e) => e.toJson()).toList(),
      'revenue': revenue,
      'carbonOffset': carbonOffset,
    };
  }
}
