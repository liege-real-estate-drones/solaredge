import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:solaredge_monitor/data/models/weather_data.dart';
import 'package:flutter/foundation.dart';

class WeatherService {
  // Utiliser OpenWeatherMap API pour les données météo
  final String baseUrl = 'https://api.openweathermap.org/data/2.5';
  final String apiKey;
  
  WeatherService({required this.apiKey});
  
  // Récupérer les données météo actuelles pour une localisation
  Future<WeatherData> getCurrentWeather(double latitude, double longitude) async {
    try {
      final url = Uri.parse('$baseUrl/weather?lat=$latitude&lon=$longitude&units=metric&lang=fr&appid=$apiKey');
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        return WeatherData(
          timestamp: DateTime.now(),
          temperature: data['main']['temp'] as double,
          humidity: data['main']['humidity'] as double,
          windSpeed: data['wind']['speed'] as double,
          condition: data['weather'][0]['description'] as String,
          iconCode: data['weather'][0]['icon'] as String,
          cloudCover: data['clouds']?['all'] as double?,
          precipitation: data['rain']?['1h'] as double?,
          uvIndex: null, // OpenWeatherMap API gratuite ne fournit pas d'indice UV
        );
      } else {
        throw Exception('Échec du chargement des données météo: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Erreur lors de la récupération des données météo: $e');
      rethrow;
    }
  }
  
  // Récupérer les prévisions météo pour une localisation
  Future<WeatherForecast> getWeatherForecast(double latitude, double longitude) async {
    try {
      final url = Uri.parse('$baseUrl/forecast?lat=$latitude&lon=$longitude&units=metric&lang=fr&appid=$apiKey');
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List forecastList = data['list'] as List;
        
        // Prévisions horaires (48 heures)
        final List<WeatherData> hourlyForecast = [];
        
        // Prévisions journalières (5 jours)
        final List<WeatherData> dailyForecast = [];
        final Map<String, WeatherData> dailyMap = {}; // Pour regrouper par jour
        
        DateTime now = DateTime.now();
        
        for (var item in forecastList) {
          final DateTime forecastTime = DateTime.fromMillisecondsSinceEpoch(item['dt'] * 1000);
          
          // Créer l'objet WeatherData
          final weatherData = WeatherData(
            timestamp: forecastTime,
            temperature: item['main']['temp'] as double,
            humidity: item['main']['humidity'] as double,
            windSpeed: item['wind']['speed'] as double,
            condition: item['weather'][0]['description'] as String,
            iconCode: item['weather'][0]['icon'] as String,
            cloudCover: item['clouds']?['all'] as double?,
            precipitation: item['rain']?['3h'] as double?,
            uvIndex: null,
          );
          
          // Ajouter aux prévisions horaires (48 heures max)
          if (forecastTime.difference(now).inHours < 48) {
            hourlyForecast.add(weatherData);
          }
          
          // Regrouper par jour pour les prévisions journalières
          String dateKey = '${forecastTime.year}-${forecastTime.month.toString().padLeft(2, '0')}-${forecastTime.day.toString().padLeft(2, '0')}';
          
          // Prendre la prévision de midi (ou la plus proche) pour représenter la journée
          if (!dailyMap.containsKey(dateKey) || 
              (forecastTime.hour >= 12 && dailyMap[dateKey]!.timestamp.hour < 12) || 
              (forecastTime.hour < 12 && forecastTime.hour > dailyMap[dateKey]!.timestamp.hour)) {
            dailyMap[dateKey] = weatherData;
          }
        }
        
        // Convertir la map en liste pour les prévisions journalières
        dailyForecast.addAll(dailyMap.values);
        
        // Trier par date
        dailyForecast.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        
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
      rethrow;
    }
  }
  
  // Récupérer l'historique météo pour une date spécifique (nécessite un abonnement OpenWeatherMap payant)
  Future<WeatherData> getHistoricalWeather(double latitude, double longitude, DateTime date) async {
    try {
      final int timestamp = (date.millisecondsSinceEpoch ~/ 1000);
      final url = Uri.parse('$baseUrl/onecall/timemachine?lat=$latitude&lon=$longitude&dt=$timestamp&units=metric&lang=fr&appid=$apiKey');
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final historicalData = data['current'];
        
        return WeatherData(
          timestamp: date,
          temperature: historicalData['temp'] as double,
          humidity: historicalData['humidity'] as double,
          windSpeed: historicalData['wind_speed'] as double,
          condition: historicalData['weather'][0]['description'] as String,
          iconCode: historicalData['weather'][0]['icon'] as String,
          cloudCover: historicalData['clouds'] as double?,
          precipitation: historicalData['rain']?['1h'] as double?,
          uvIndex: historicalData['uvi'] as double?,
        );
      } else {
        // En cas d'erreur ou si l'API payante n'est pas disponible, retourner des données par défaut
        debugPrint('Échec du chargement des données historiques: ${response.statusCode}');
        return WeatherData(
          timestamp: date,
          temperature: 0,
          humidity: 0,
          windSpeed: 0,
          condition: 'Données indisponibles',
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
        condition: 'Données indisponibles',
        iconCode: '01d', // Icône par défaut
      );
    }
  }
  
  // Analyser l'impact de la météo sur la production solaire
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
