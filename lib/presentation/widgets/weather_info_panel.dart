import 'package:flutter/material.dart';
import 'package:solaredge_monitor/data/models/weather_data.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';

class WeatherInfoPanel extends StatelessWidget {
  final List<WeatherData>? hourlyWeather;
  
  const WeatherInfoPanel({
    super.key,
    required this.hourlyWeather,
  });

  @override
  Widget build(BuildContext context) {
    // Si pas de données météo, afficher un message
    if (hourlyWeather == null || hourlyWeather!.isEmpty) {
      return const Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppTheme.borderRadius)),
          side: BorderSide(color: AppTheme.cardBorderColor, width: 0.5),
        ),
        color: AppTheme.cardColor,
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              'Aucune information météo disponible',
              style: TextStyle(
                color: AppTheme.textSecondaryColor,
                fontSize: 14,
              ),
            ),
          ),
        ),
      );
    }

    // Récupérer la donnée météo actuelle
    final currentWeather = _getCurrentWeather();
    
    if (currentWeather == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppTheme.borderRadius)),
        side: BorderSide(color: AppTheme.cardBorderColor, width: 0.5),
      ),
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Conditions météo',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimaryColor,
                  ),
                ),
                // Info sur la mise à jour des données
                Text(
                  'Dernière mise à jour: ${_getUpdateTimeString(currentWeather)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Infos météo principales
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icône météo
                Icon(
                  _getWeatherIcon(currentWeather.iconCode),
                  color: _getWeatherIconColor(currentWeather.iconCode),
                  size: 48,
                ),
                const SizedBox(width: 16),
                
                // Températures et conditions
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${currentWeather.temperature.toStringAsFixed(1)}°C',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimaryColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _getTemperatureRange(),
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _capitalizeFirstLetter(currentWeather.condition),
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppTheme.textSecondaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            
            // Détails supplémentaires
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildWeatherDetailChip(
                  icon: Icons.air,
                  label: 'Vent',
                  value: '${currentWeather.windSpeed.toStringAsFixed(1)} km/h',
                ),
                _buildWeatherDetailChip(
                  icon: Icons.water_drop,
                  label: 'Humidité',
                  value: '${currentWeather.humidity.toInt()}%',
                ),
                _buildWeatherDetailChip(
                  icon: Icons.cloud,
                  label: 'Nuages',
                  value: '${currentWeather.cloudCover?.toInt() ?? 0}%',
                ),
                _buildWeatherDetailChip(
                  icon: Icons.opacity,
                  label: 'Précip.',
                  value: '${currentWeather.precipitation?.toStringAsFixed(1) ?? "0.0"} mm',
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Impact sur la production
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _getProductionImpactColor(currentWeather).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _getProductionImpactColor(currentWeather).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _getProductionImpactIcon(currentWeather),
                    color: _getProductionImpactColor(currentWeather),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _getProductionImpactText(currentWeather),
                      style: TextStyle(
                        fontSize: 14,
                        color: _getProductionImpactColor(currentWeather),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Récupérer la donnée météo actuelle ou la plus récente
  WeatherData? _getCurrentWeather() {
    if (hourlyWeather == null || hourlyWeather!.isEmpty) {
      return null;
    }
    
    // Récupérer l'heure actuelle
    final now = DateTime.now();
    
    // Trouver la donnée météo la plus proche de l'heure actuelle
    WeatherData? closestWeather;
    Duration closestDuration = const Duration(days: 1);
    
    for (var weather in hourlyWeather!) {
      final duration = now.difference(weather.timestamp).abs();
      if (duration < closestDuration) {
        closestDuration = duration;
        closestWeather = weather;
      }
    }
    
    return closestWeather;
  }
  
  // Obtenir la plage de température (min-max) pour la journée
  String _getTemperatureRange() {
    if (hourlyWeather == null || hourlyWeather!.isEmpty) {
      return '';
    }
    
    double minTemp = double.infinity;
    double maxTemp = double.negativeInfinity;
    
    for (var weather in hourlyWeather!) {
      if (weather.temperature < minTemp) {
        minTemp = weather.temperature;
      }
      if (weather.temperature > maxTemp) {
        maxTemp = weather.temperature;
      }
    }
    
    return '${minTemp.toStringAsFixed(1)}° - ${maxTemp.toStringAsFixed(1)}°';
  }
  
  // Obtenir l'heure de mise à jour des données météo
  String _getUpdateTimeString(WeatherData data) {
    final hour = data.timestamp.hour.toString().padLeft(2, '0');
    final minute = data.timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  
  // Construire un chip pour les détails météo
  Widget _buildWeatherDetailChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.cardBorderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondaryColor),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // Obtenir la couleur en fonction de l'impact sur la production
  Color _getProductionImpactColor(WeatherData weather) {
    // Analyse basée sur les conditions météo
    if (weather.condition.toLowerCase().contains('clear') ||
        weather.condition.toLowerCase().contains('sun')) {
      return Colors.green;
    } else if (weather.condition.toLowerCase().contains('cloud') ||
               weather.condition.toLowerCase().contains('part')) {
      return Colors.orange;
    } else if (weather.condition.toLowerCase().contains('rain') ||
               weather.condition.toLowerCase().contains('storm') ||
               weather.condition.toLowerCase().contains('snow')) {
      return Colors.red;
    }
    
    return Colors.blue;
  }
  
  // Obtenir l'icône en fonction de l'impact sur la production
  IconData _getProductionImpactIcon(WeatherData weather) {
    // Analyse basée sur les conditions météo
    if (weather.condition.toLowerCase().contains('clear') ||
        weather.condition.toLowerCase().contains('sun')) {
      return Icons.trending_up;
    } else if (weather.condition.toLowerCase().contains('cloud') ||
               weather.condition.toLowerCase().contains('part')) {
      return Icons.trending_flat;
    } else if (weather.condition.toLowerCase().contains('rain') ||
               weather.condition.toLowerCase().contains('storm') ||
               weather.condition.toLowerCase().contains('snow')) {
      return Icons.trending_down;
    }
    
    return Icons.info_outline;
  }
  
  // Obtenir le texte d'impact sur la production
  String _getProductionImpactText(WeatherData weather) {
    // Analyse basée sur les conditions météo
    if (weather.condition.toLowerCase().contains('clear') ||
        weather.condition.toLowerCase().contains('sun')) {
      return 'Conditions idéales pour une production optimale';
    } else if (weather.condition.toLowerCase().contains('cloud') ||
               weather.condition.toLowerCase().contains('part')) {
      return 'Production légèrement réduite en raison de la couverture nuageuse';
    } else if (weather.condition.toLowerCase().contains('rain') ||
               weather.condition.toLowerCase().contains('storm') ||
               weather.condition.toLowerCase().contains('snow')) {
      return 'Production significativement réduite en raison des conditions défavorables';
    }
    
    return 'Impossible d\'évaluer l\'impact sur la production';
  }
  
  // Obtenir l'icône correspondant au code météo
  IconData _getWeatherIcon(String iconCode) {
    // Les codes d'OpenWeatherMap sont au format "01d", "02n", etc.
    // où le nombre représente la condition et d/n représente jour/nuit
    
    final bool isDay = iconCode.endsWith('d');
    final String condition = iconCode.substring(0, 2);
    
    switch (condition) {
      case '01': // Clear sky
        return isDay ? Icons.wb_sunny : Icons.nights_stay;
      case '02': // Few clouds
        return isDay ? Icons.wb_cloudy : Icons.nights_stay;
      case '03': // Scattered clouds
      case '04': // Broken clouds
        return Icons.cloud;
      case '09': // Shower rain
        return Icons.grain;
      case '10': // Rain
        return isDay ? Icons.wb_cloudy : Icons.grain;
      case '11': // Thunderstorm
        return Icons.flash_on;
      case '13': // Snow
        return Icons.ac_unit;
      case '50': // Mist
        return Icons.blur_on;
      default:
        return Icons.wb_sunny;
    }
  }
  
  // Obtenir la couleur de l'icône météo
  Color _getWeatherIconColor(String iconCode) {
    final String condition = iconCode.substring(0, 2);
    
    switch (condition) {
      case '01': // Clear sky
      case '02': // Few clouds
        return Colors.amber;
      case '03': // Scattered clouds
      case '04': // Broken clouds
        return Colors.grey;
      case '09': // Shower rain
      case '10': // Rain
        return Colors.lightBlue;
      case '11': // Thunderstorm
        return Colors.deepPurple;
      case '13': // Snow
        return Colors.lightBlueAccent;
      case '50': // Mist
        return Colors.blueGrey;
      default:
        return Colors.amber;
    }
  }
  
  // Mettre en majuscule la première lettre
  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}
