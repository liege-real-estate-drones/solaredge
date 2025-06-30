import 'package:flutter/material.dart';
import 'package:solaredge_monitor/data/models/weather_data.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';

class WeatherInfoWidget extends StatelessWidget {
  final WeatherData weatherData;
  
  const WeatherInfoWidget({
    super.key,
    required this.weatherData,
  });

  @override
  Widget build(BuildContext context) {
    // Récupérer l'icône correspondant à la condition météo
    final IconData weatherIcon = _getWeatherIcon(weatherData.iconCode);
    
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        side: const BorderSide(color: AppTheme.cardBorderColor, width: 0.5),
      ),
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Météo',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 10),
            // Utilisation d'un LayoutBuilder pour s'adapter à l'espace disponible
            LayoutBuilder(
              builder: (context, constraints) {
                // Calcul de la largeur disponible pour le texte
                final iconWidth = 36.0; // Taille de l'icône
                final iconPadding = 8.0; // Espacement
                final availableTextWidth = constraints.maxWidth - iconWidth - iconPadding;
                
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icône météo
                    Icon(
                      weatherIcon,
                      color: _getWeatherIconColor(weatherData.iconCode),
                      size: 36,
                    ),
                    const SizedBox(width: 8),
                    // Contenu (température + condition) qui s'adapte à l'espace disponible
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Température
                          Text(
                            '${weatherData.temperature.toStringAsFixed(1)}°C',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Condition météo
                          Text(
                            _capitalizeFirstLetter(weatherData.condition),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildWeatherDetail(
                  icon: Icons.water_drop_outlined,
                  value: '${weatherData.humidity.toInt()}%',
                  label: 'Humidité',
                ),
                _buildWeatherDetail(
                  icon: Icons.air,
                  value: '${weatherData.windSpeed.toStringAsFixed(1)} km/h',
                  label: 'Vent',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  // Widget pour afficher un détail météo
  Widget _buildWeatherDetail({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.textSecondaryColor, size: 16),
        const SizedBox(height: 4),
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
            fontSize: 11,
            color: AppTheme.textSecondaryColor,
          ),
        ),
      ],
    );
  }
  
  // Mettre en majuscule la première lettre
  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
  
  // Obtenir l'icône correspondant au code météo
  IconData _getWeatherIcon(String iconCode) {
    // Les codes d'OpenWeatherMap sont au format "01d", "02n", etc.
    // où le nombre représente la condition et d/n représente jour/nuit
    
    final bool isDay = iconCode.endsWith('d');
    final String condition = iconCode.substring(0, 2);
    
    switch (condition) {
      case '01': // Clear sky
        return isDay ? Icons.wb_sunny_rounded : Icons.nights_stay_rounded;
      case '02': // Few clouds
        return isDay ? Icons.wb_cloudy_rounded : Icons.nights_stay_rounded;
      case '03': // Scattered clouds
      case '04': // Broken clouds
        return Icons.cloud_rounded;
      case '09': // Shower rain
        return Icons.grain_rounded;
      case '10': // Rain
        return isDay ? Icons.wb_cloudy_rounded : Icons.grain_rounded;
      case '11': // Thunderstorm
        return Icons.flash_on_rounded;
      case '13': // Snow
        return Icons.ac_unit_rounded;
      case '50': // Mist
        return Icons.blur_on_rounded;
      default:
        return Icons.wb_sunny_rounded;
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
}
