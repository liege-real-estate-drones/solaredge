import 'package:flutter/material.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/data/models/weather_data.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class HourlyProductionChart extends StatefulWidget {
  final DailySolarData dailyData;
  final List<WeatherData>? hourlyWeather;
  final bool showWeatherOverlay;
  final bool showPowerCurve;
  final Function(bool)? onPowerCurveToggled;
  final Function(bool)? onWeatherOverlayToggled;

  const HourlyProductionChart({
    super.key,
    required this.dailyData,
    this.hourlyWeather,
    this.showWeatherOverlay = true,
    this.showPowerCurve = true,
    this.onPowerCurveToggled,
    this.onWeatherOverlayToggled,
  });

  @override
  HourlyProductionChartState createState() => HourlyProductionChartState();
}

class HourlyProductionChartState extends State<HourlyProductionChart> {
  int? touchedIndex;
  bool isDetailMode = false;

  @override
  Widget build(BuildContext context) {
    final hourlyData = widget.dailyData.hourlyData;

    // Vérifier si nous avons des données à afficher
    if (hourlyData.isEmpty) {
      return const Center(
        child: Text(
          'Aucune donnée disponible pour cette journée',
          style: TextStyle(
            color: AppTheme.textSecondaryColor,
            fontSize: 14,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Options du graphique
        Align(
          alignment: Alignment.centerRight,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              // Bouton pour activer/désactiver la courbe de puissance
              FilterChip(
                label: const Text('Production horaire'),
                selected: widget.showPowerCurve,
                onSelected: (selected) {
                  if (widget.onPowerCurveToggled != null) {
                    widget.onPowerCurveToggled!(selected);
                  }
                },
                backgroundColor: AppTheme.cardColor,
                selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                checkmarkColor: AppTheme.primaryColor,
                labelStyle: TextStyle(
                  color: widget.showPowerCurve
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondaryColor,
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),

              // Bouton pour activer/désactiver la météo
              FilterChip(
                label: const Text('Météo'),
                selected: widget.showWeatherOverlay,
                onSelected: (selected) {
                  if (widget.onWeatherOverlayToggled != null) {
                    widget.onWeatherOverlayToggled!(selected);
                  }
                },
                backgroundColor: AppTheme.cardColor,
                selectedColor: Colors.lightBlue.withOpacity(0.2),
                checkmarkColor: Colors.lightBlue,
                labelStyle: TextStyle(
                  color: widget.showWeatherOverlay
                      ? Colors.lightBlue
                      : AppTheme.textSecondaryColor,
                ),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4),
              ),

              // Le bouton pour la température a été retiré, car nous utilisons les icônes météo
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Graphique
        AspectRatio(
          aspectRatio: 1.8,
          child: BarChart(
            isDetailMode ? _buildDetailBarData() : _buildMainBarData(),
            swapAnimationDuration: const Duration(milliseconds: 250),
          ),
        ),

        // Icônes météo si disponibles et activées
        if (widget.showWeatherOverlay && widget.hourlyWeather != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: _buildWeatherIcons(),
          ),

        const SizedBox(height: 12),

        // Panneau d'information pour l'heure sélectionnée
        if (touchedIndex != null &&
            touchedIndex! >= 0 &&
            touchedIndex! < hourlyData.length)
          _buildTouchedInfoPanel(hourlyData[touchedIndex!]),
      ],
    );
  }

  // Construire le graphique principal
  BarChartData _buildMainBarData() {
    final hourlyData = widget.dailyData.hourlyData;
    final maxEnergy = _findMaxEnergy(hourlyData);

    return BarChartData(
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          // --- CORRECTION : tooltipBgColor déplacé ici ---
          tooltipBgColor: AppTheme.cardColor.withOpacity(0.8),
          tooltipPadding: const EdgeInsets.all(8),
          tooltipMargin: 8,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final hour = hourlyData[groupIndex].timestamp.hour;
            final String hourStr = hour < 10 ? '0$hour:00' : '$hour:00';
            final energyStr =
                (hourlyData[groupIndex].energy / 1000).toStringAsFixed(2);

            return BarTooltipItem(
              '$hourStr\n',
              const TextStyle(
                color: AppTheme.textPrimaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              children: <TextSpan>[
                TextSpan(
                  text: '$energyStr kWh',
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            );
          },
        ),
        touchCallback: (FlTouchEvent event, barTouchResponse) {
          setState(() {
            if (!event.isInterestedForInteractions ||
                barTouchResponse == null ||
                barTouchResponse.spot == null) {
              touchedIndex = -1;
              return;
            }
            touchedIndex = barTouchResponse.spot!.touchedBarGroupIndex;

            // Passer en mode détail au double-tap
            if (event is FlTapUpEvent) {
              // Note: FlTapUpEvent n'a pas de propriété tapCount, on utilise une simple bascule
              if (touchedIndex != null && touchedIndex! >= 0) {
                isDetailMode = !isDetailMode;
              }
            }
          });
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (double value, TitleMeta meta) {
              final index = value.toInt(); // Convertir value en index
              if (index >= hourlyData.length || index < 0) {
                return const SizedBox();
              }

              final hour = hourlyData[index].timestamp.hour;
              // N'afficher que quelques heures pour éviter l'encombrement
              if (hour % 4 != 0) {
                return const SizedBox();
              }

              return SideTitleWidget(
                axisSide: meta.axisSide, // Utilisation de meta.axisSide
                space: 16,
                child: Text(
                  hour < 10 ? '0$hour:00' : '$hour:00',
                  style: const TextStyle(
                    color: AppTheme.textSecondaryColor,
                    fontSize: 12,
                  ),
                ),
              );
            },
            // --- FIN CORRECTION ---
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (double value, TitleMeta meta) {
              if (value == 0) {
                return const SizedBox();
              }

              return SideTitleWidget(
                axisSide: meta.axisSide, // Utilisation de meta.axisSide
                space: 8,
                child: Text(
                  '${value.toInt()} kWh',
                  style: const TextStyle(
                    color: AppTheme.textSecondaryColor,
                    fontSize: 12,
                  ),
                ),
              );
            },
            // --- FIN CORRECTION ---
            reservedSize: 40,
          ),
        ),
        rightTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles:
                false, // Désactivation des titres à droite pour simplifier
            reservedSize: 0,
          ),
        ),
        topTitles: AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
      ),
      borderData: FlBorderData(
        show: false,
      ),
      barGroups: List.generate(hourlyData.length, (index) {
        final data = hourlyData[index];
        final energyKwh = data.energy / 1000; // Convertir en kWh

        return BarChartGroupData(
          x: index,
          barRods: [
            BarChartRodData(
              toY: energyKwh,
              color: touchedIndex == index
                  ? AppTheme.chartLine1
                  : AppTheme.chartLine1.withOpacity(0.7),
              width: 24,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
              // Ajouter une bordure pour plus de contraste
              borderSide: const BorderSide(
                color: Colors.transparent,
                width: 0,
              ),
            ),
          ],
          showingTooltipIndicators: touchedIndex == index ? [0] : [],
        );
      }),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 1,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: AppTheme.textSecondaryColor.withOpacity(0.1),
            strokeWidth: 1,
          );
        },
      ),
      minY: 0,
      maxY: maxEnergy * 1.1, // Ajouter 10% de marge en haut
    );
  }

  // Construire le graphique détaillé (similaire mais avec plus d'informations)
  BarChartData _buildDetailBarData() {
    // Pour le mode détaillé, nous utilisons le même graphique mais avec plus d'options
    // et une animation de transition
    final mainData = _buildMainBarData();

    // fl_chart a changé l'API pour copyWith, donc nous recréons de zéro
    return BarChartData(
      barTouchData: mainData.barTouchData,
      titlesData: mainData.titlesData,
      borderData: mainData.borderData,
      barGroups: mainData.barGroups,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: 0.5,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: AppTheme.textSecondaryColor.withOpacity(0.2),
            strokeWidth: 1,
            dashArray: value.toInt() == value ? null : [5, 5],
          );
        },
      ),
      minY: mainData.minY,
      maxY: mainData.maxY,
    );
  }

  // Trouver la valeur maximale d'énergie dans les données horaires
  double _findMaxEnergy(List<SolarData> data) {
    double max = 0;
    for (var item in data) {
      final energy = item.energy / 1000; // Convertir en kWh
      if (energy > max) {
        max = energy;
      }
    }
    // Retourner au moins 1 pour éviter un graphique vide
    return max > 0 ? max : 1.0;
  }

  // Trouver la valeur maximale de puissance dans les données horaires
  double _findMaxPower(List<SolarData> data) {
    double max = 0;
    for (var item in data) {
      // Les données de puissance sont déjà en W grâce à la conversion dans SolarEdgeApiService
      final power = item.power;
      if (power > max) {
        max = power;
      }
    }
    // Retourner au moins 1 pour éviter un graphique vide
    return max > 0 ? max : 1.0;
  }

  // Construire le panneau d'information pour l'heure sélectionnée
  Widget _buildTouchedInfoPanel(SolarData data) {
    final hourFormat = DateFormat('HH:mm');
    final startTime = hourFormat.format(data.timestamp);
    final endTime =
        hourFormat.format(data.timestamp.add(const Duration(hours: 1)));

    // --- Calcul SYSTÉMATIQUE de la puissance moyenne ---
    double averagePowerW = 0; // Initialiser à 0
    // Utiliser l'index de l'état (this.touchedIndex)
    if (this.touchedIndex != null && this.touchedIndex! >= 0) {
        // L'énergie retournée par l'API pour une heure est l'énergie produite PENDANT cette heure.
        // Donc, cette valeur en Wh est numériquement égale à la puissance moyenne en W sur cette heure.
        averagePowerW = data.energy; // Ex: 500 Wh produits en 1h = 500W en moyenne
    }
    // S'assurer que la puissance calculée n'est pas négative
    if (averagePowerW < 0) averagePowerW = 0;
    // --- FIN Calcul Puissance Moyenne ---


    // Trouver la donnée météo correspondante si disponible
    WeatherData? weatherData;
    if (widget.hourlyWeather != null) {
      for (var weather in widget.hourlyWeather!) {
        if (weather.timestamp.hour == data.timestamp.hour) {
          weatherData = weather;
          break;
        }
      }
    }

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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Détails $startTime - $endTime',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimaryColor,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    setState(() {
                      touchedIndex = -1;
                    });
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: AppTheme.textSecondaryColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDetailItem(
                  icon: Icons.electric_bolt,
                  label: 'Énergie',
                  value: '${(data.energy / 1000).toStringAsFixed(2)} kWh',
                  color: AppTheme.primaryColor,
                ),
                _buildDetailItem(
                  icon: Icons.speed,
                  label: 'Puiss. Moyenne', // <<--- CHANGER LE LIBELLÉ
                  // Utiliser averagePowerW calculé et formater sans décimales
                  value: '${averagePowerW.toStringAsFixed(0)} W', // <<--- AFFICHER averagePowerW
                  color: AppTheme.chartLine1,
                ),
                if (weatherData != null)
                  _buildDetailItem(
                    icon: Icons.thermostat,
                    label: 'Température',
                    value: '${weatherData.temperature.toStringAsFixed(1)}°C',
                    color: Colors.orange,
                  ),
              ],
            ),
            if (weatherData != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.wb_sunny, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    weatherData.condition,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textPrimaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Helper pour construire un élément de détail
  Widget _buildDetailItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
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
    );
  }

  // Construire la rangée d'icônes météo correspondant aux heures
  Widget _buildWeatherIcons() {
    if (widget.hourlyWeather == null || widget.hourlyWeather!.isEmpty) {
      return const SizedBox.shrink();
    }

    // On crée d'abord une liste qui associe les données horaires aux données météo
    final hourlyData = widget.dailyData.hourlyData;
    final List<WeatherData?> matchedWeather =
        List.filled(hourlyData.length, null);

    // Associer chaque heure de production à la donnée météo correspondante
    for (int i = 0; i < hourlyData.length; i++) {
      final hour = hourlyData[i].timestamp.hour;
      for (var weather in widget.hourlyWeather!) {
        if (weather.timestamp.hour == hour) {
          matchedWeather[i] = weather;
          break;
        }
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(hourlyData.length, (index) {
          final hour = hourlyData[index].timestamp.hour;
          final weather = matchedWeather[index];

          // Si pas de données météo pour cette heure, afficher uniquement l'heure
          if (weather == null) {
            return SizedBox(
              width: 40,
              child: Column(
                children: [
                  const SizedBox(
                      height: 24), // Espace pour aligner avec les icônes
                  Text(
                    '${hour}h',
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textSecondaryColor),
                  ),
                ],
              ),
            );
          }

          return SizedBox(
            width: 40,
            child: Column(
              children: [
                Icon(
                  _getWeatherIcon(weather.iconCode),
                  color: _getWeatherIconColor(weather.iconCode),
                  size: 20,
                ),
                Text(
                  '${hour}h',
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondaryColor),
                ),
                Text(
                  '${weather.temperature.toStringAsFixed(1)}°',
                  style: const TextStyle(fontSize: 10, color: Colors.orange),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // Récupérer l'icône météo en fonction du code
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

  // Récupérer la couleur de l'icône météo
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
