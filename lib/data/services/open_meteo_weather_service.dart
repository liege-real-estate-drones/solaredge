import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:solaredge_monitor/data/models/weather_data.dart';

/// Service météo utilisant l'API Open-Meteo, qui ne nécessite pas de clé API
/// https://open-meteo.com/
class OpenMeteoWeatherService {
  // URL de base pour l'API Open-Meteo
  final String baseUrl = 'https://api.open-meteo.com/v1/forecast';

  // Convertir les codes WMO en icônes similaires à celles d'OpenWeatherMap
  String _mapWMOCodeToIcon(int wmoCode) {
    // Codes WMO: https://open-meteo.com/en/docs/
    if (wmoCode <= 3) return '01d'; // Ensoleillé à partiellement nuageux
    if (wmoCode <= 9) return '02d'; // Brumeux
    if (wmoCode <= 19) return '50d'; // Brouillard
    if (wmoCode <= 29) return '10d'; // Précipitations
    if (wmoCode <= 39) return '13d'; // Neige
    if (wmoCode <= 49) return '09d'; // Pluie - variées
    if (wmoCode <= 59) return '10d'; // Bruine
    if (wmoCode <= 69) return '13d'; // Précipitations gelées
    if (wmoCode <= 79) return '13d'; // Neige ou grêle 
    if (wmoCode <= 99) return '11d'; // Orages
    return '01d'; // Défaut
  }

  // Convertir code météo WMO en description en français
  String _getWeatherDescription(int wmoCode) {
    // Tableau de correspondance basé sur les codes météo WMO
    switch (wmoCode) {
      case 0: return 'Ciel dégagé';
      case 1: return 'Majoritairement dégagé';
      case 2: return 'Partiellement nuageux';
      case 3: return 'Nuageux';
      case 45: case 48: return 'Brouillard';
      case 51: return 'Bruine légère';
      case 53: return 'Bruine modérée';
      case 55: return 'Bruine dense';
      case 56: case 57: return 'Bruine verglaçante';
      case 61: return 'Pluie légère';
      case 63: return 'Pluie modérée';
      case 65: return 'Pluie forte';
      case 66: case 67: return 'Pluie verglaçante';
      case 71: return 'Neige légère';
      case 73: return 'Neige modérée';
      case 75: return 'Neige forte';
      case 77: return 'Grains de neige';
      case 80: case 81: case 82: return 'Averses de pluie';
      case 85: case 86: return 'Averses de neige';
      case 95: return 'Orage';
      case 96: case 99: return 'Orage avec grêle';
      default: return 'Conditions météo inconnues';
    }
  }
  
  // Récupérer les données météo actuelles pour une localisation
  Future<WeatherData> getCurrentWeather(double latitude, double longitude) async {
    try {
      // Construire l'URL avec tous les paramètres nécessaires
      final url = Uri.parse('$baseUrl?latitude=$latitude&longitude=$longitude'
          '&current=temperature_2m,relative_humidity_2m,rain,snowfall,weather_code,cloud_cover,wind_speed_10m'
          '&timezone=auto'
          '&forecast_days=1');
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final current = data['current'];
        
        // Extraire le code météo pour le convertir en description et icône
        final weatherCode = current['weather_code'] as int;
        
        // Créer l'objet WeatherData
        return WeatherData(
          timestamp: DateTime.parse(current['time']),
          temperature: current['temperature_2m'].toDouble(),
          humidity: current['relative_humidity_2m'].toDouble(),
          windSpeed: current['wind_speed_10m'].toDouble(),
          condition: _getWeatherDescription(weatherCode),
          iconCode: _mapWMOCodeToIcon(weatherCode),
          cloudCover: current['cloud_cover']?.toDouble(),
          // Convertir mm de pluie en volume équivalent
          precipitation: current['rain']?.toDouble() ?? 0.0,
          uvIndex: null, // Non disponible dans la version gratuite
        );
      } else {
        throw Exception('Échec du chargement des données météo: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Erreur lors de la récupération des données météo: $e');
      // Créer un objet par défaut en cas d'erreur pour éviter les crashes
      return WeatherData(
        timestamp: DateTime.now(),
        temperature: 0,
        humidity: 0,
        windSpeed: 0,
        condition: 'Données indisponibles',
        iconCode: '01d', // Icône par défaut
      );
    }
  }
  
  // Récupérer les prévisions météo pour une localisation
  Future<WeatherForecast> getWeatherForecast(double latitude, double longitude) async {
    try {
      // Construire l'URL avec tous les paramètres nécessaires pour les prévisions horaires et quotidiennes
      final url = Uri.parse('$baseUrl?latitude=$latitude&longitude=$longitude'
          '&hourly=temperature_2m,relative_humidity_2m,rain,snowfall,weather_code,cloud_cover,wind_speed_10m'
          '&daily=weather_code,temperature_2m_max,temperature_2m_min,wind_speed_10m_max,precipitation_sum'
          '&timezone=auto'
          '&forecast_days=5');
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<WeatherData> hourlyForecast = [];
        final List<WeatherData> dailyForecast = [];
        
        // Extraire les prévisions horaires
        final hourly = data['hourly'];
        final hourlyTimes = hourly['time'] as List;
        
        for (int i = 0; i < hourlyTimes.length; i++) {
          // Limiter aux 48 premières heures
          if (i >= 48) break;
          
          final weatherCode = hourly['weather_code'][i] as int;
          
          hourlyForecast.add(WeatherData(
            timestamp: DateTime.parse(hourlyTimes[i]),
            temperature: hourly['temperature_2m'][i].toDouble(),
            humidity: hourly['relative_humidity_2m'][i].toDouble(),
            windSpeed: hourly['wind_speed_10m'][i].toDouble(),
            condition: _getWeatherDescription(weatherCode),
            iconCode: _mapWMOCodeToIcon(weatherCode),
            cloudCover: hourly['cloud_cover'][i]?.toDouble(),
            precipitation: hourly['rain'][i]?.toDouble() ?? 0.0,
            uvIndex: null,
          ));
        }
        
        // Extraire les prévisions quotidiennes
        final daily = data['daily'];
        final dailyTimes = daily['time'] as List;
        
        for (int i = 0; i < dailyTimes.length; i++) {
          final weatherCode = daily['weather_code'][i] as int;
          
          dailyForecast.add(WeatherData(
            timestamp: DateTime.parse(dailyTimes[i]),
            // Utiliser la température moyenne du jour
            temperature: (daily['temperature_2m_max'][i].toDouble() + 
                         daily['temperature_2m_min'][i].toDouble()) / 2,
            humidity: 0, // Non disponible au niveau quotidien
            windSpeed: daily['wind_speed_10m_max'][i].toDouble(),
            condition: _getWeatherDescription(weatherCode),
            iconCode: _mapWMOCodeToIcon(weatherCode),
            cloudCover: null, // Non disponible au niveau quotidien
            precipitation: daily['precipitation_sum'][i]?.toDouble() ?? 0.0,
            uvIndex: null,
          ));
        }
        
        return WeatherForecast(
          timestamp: DateTime.now(),
          hourlyForecast: hourlyForecast,
          dailyForecast: dailyForecast,
        );
      } else {
        throw Exception('Échec du chargement des prévisions météo: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Erreur lors de la récupération des prévisions météo: $e');
      // Créer un objet par défaut
      return WeatherForecast(
        timestamp: DateTime.now(),
        hourlyForecast: [],
        dailyForecast: [],
      );
    }
  }
  
  // Récupérer l'historique météo pour une date spécifique
  // Note: Open-Meteo propose un service d'historique gratuit mais avec des limitations
  Future<WeatherData> getHistoricalWeather(double latitude, double longitude, DateTime date) async {
    try {
      // Formatage des dates selon le format ISO 8601 (YYYY-MM-DD)
      final formattedDate = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      // Construire l'URL pour l'historique
      final url = Uri.parse('https://archive-api.open-meteo.com/v1/archive'
          '?latitude=$latitude&longitude=$longitude'
          '&start_date=$formattedDate&end_date=$formattedDate'
          '&daily=temperature_2m_max,temperature_2m_min,rain_sum,snowfall_sum,wind_speed_10m_max,weather_code');
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final daily = data['daily'];
        final weatherCode = daily['weather_code'][0] as int;
        
        return WeatherData(
          timestamp: date,
          // Utiliser la température moyenne du jour
          temperature: (daily['temperature_2m_max'][0].toDouble() + 
                       daily['temperature_2m_min'][0].toDouble()) / 2,
          humidity: 0, // Non disponible dans les données historiques
          windSpeed: daily['wind_speed_10m_max'][0].toDouble(),
          condition: _getWeatherDescription(weatherCode),
          iconCode: _mapWMOCodeToIcon(weatherCode),
          cloudCover: null, // Non disponible
          precipitation: daily['rain_sum'][0]?.toDouble() ?? 0.0,
          uvIndex: null, // Non disponible
        );
      } else {
        // En cas d'erreur, retourner des données par défaut
        debugPrint('Échec du chargement des données historiques: ${response.statusCode}');
        return WeatherData(
          timestamp: date,
          temperature: 0,
          humidity: 0,
          windSpeed: 0,
          condition: 'Données historiques indisponibles',
          iconCode: '01d', // Icône par défaut
        );
      }
    } catch (e) {
      debugPrint('Erreur lors de la récupération des données historiques: $e');
      // Retourner des données par défaut en cas d'erreur
      return WeatherData(
        timestamp: date,
        temperature: 0,
        humidity: 0,
        windSpeed: 0,
        condition: 'Données historiques indisponibles',
        iconCode: '01d', // Icône par défaut
      );
    }
  }
  
  // Analyser l'impact de la météo sur la production solaire
  // Cette méthode simule une analyse simple basée sur les prévisions
  Future<ProductionForecast> getPredictedProduction(double latitude, double longitude, double installedCapacityKW) async {
    try {
      // Obtenir les prévisions météo
      final forecast = await getWeatherForecast(latitude, longitude);
      
      // Prendre la prévision pour demain midi (ou la plus proche)
      final tomorrowNoon = DateTime.now().add(const Duration(days: 1));
      final targetDateTime = DateTime(tomorrowNoon.year, tomorrowNoon.month, tomorrowNoon.day, 12);
      
      WeatherData? tomorrowWeather;
      for (var hourly in forecast.hourlyForecast) {
        if (tomorrowWeather == null || 
            (hourly.timestamp.difference(targetDateTime).abs() < 
            tomorrowWeather.timestamp.difference(targetDateTime).abs())) {
          tomorrowWeather = hourly;
        }
      }
      
      // Si aucune prévision n'est trouvée, utiliser la météo actuelle
      tomorrowWeather ??= await getCurrentWeather(latitude, longitude);
      
      // Calculer une estimation de production basée sur la météo
      // C'est un algorithme simplifié, en production réelle il faudrait un modèle ML plus sophistiqué
      
      // Facteur de base: capacité installée x 5 heures (équivalent plein soleil moyen)
      double baseProduction = installedCapacityKW * 5 * 1000; // en Wh
      
      // Facteurs de correction basés sur la météo
      double cloudFactor = 1.0;
      if (tomorrowWeather.cloudCover != null) {
        cloudFactor = 1.0 - (tomorrowWeather.cloudCover! / 100.0) * 0.7; // 0.3 - 1.0
      } else {
        // Estimation basée sur la description
        if (tomorrowWeather.condition.contains('nuage') || 
            tomorrowWeather.condition.contains('couvert')) {
          cloudFactor = 0.6;
        } else if (tomorrowWeather.condition.contains('pluie') || 
                  tomorrowWeather.condition.contains('averse')) {
          cloudFactor = 0.3;
        }
      }
      
      // Facteur température (les panneaux sont moins efficaces à haute température)
      double tempFactor = 1.0;
      if (tomorrowWeather.temperature > 25) {
        tempFactor = 1.0 - ((tomorrowWeather.temperature - 25) * 0.005); // -0.5% par degré au-dessus de 25°C
      }
      
      // Production estimée
      double predictedEnergy = baseProduction * cloudFactor * tempFactor;
      
      // Niveau de confiance basé sur la proximité de la prévision
      double confidence = 0.7; // Confiance de base à 70%
      
      return ProductionForecast(
        date: targetDateTime,
        predictedEnergy: predictedEnergy,
        confidence: confidence,
        weatherData: tomorrowWeather,
      );
    } catch (e) {
      debugPrint('Erreur lors de la prédiction de production: $e');
      // Retourner une prédiction par défaut en cas d'erreur
      return ProductionForecast(
        date: DateTime.now().add(const Duration(days: 1)),
        predictedEnergy: 0,
        confidence: 0.1,
      );
    }
  }
}
