// solaredge_monitor/lib/presentation/widgets/daily_production_chart.dart
// Version corrigée pour fl_chart 0.71.0+
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:intl/intl.dart'; // Import pour le formatage

class DailyProductionChart extends StatefulWidget {
  final DailySolarData dailyData;

  const DailyProductionChart({
    super.key,
    required this.dailyData,
  });

  @override
  State<DailyProductionChart> createState() => _DailyProductionChartState();
}

class _DailyProductionChartState extends State<DailyProductionChart> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    if (widget.dailyData.hourlyData.isEmpty) {
      return const Center(
          child: Text(
              'Aucune donnée horaire pour ce graphique journalier.')); // Gérer cas vide
    }

    // Trier les données par heure (important pour les index FlSpot)
    final sortedData = List<SolarData>.from(widget.dailyData.hourlyData)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return LineChart(
      LineChartData(
        // Comportement du graphique
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            // --- CORRECTION : tooltipBgColor déplacé ici ---
            tooltipBgColor: AppTheme.cardColor.withOpacity(0.8), // Corrected syntax
            tooltipRoundedRadius: 8,
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots
                  .map((spot) {
                    // S'assurer que l'index est valide
                    if (spot.spotIndex < 0 ||
                        spot.spotIndex >= sortedData.length) {
                      return null; // Retourne null si l'index est hors limites
                    }
                    final dataPoint = sortedData[spot.spotIndex];
                    // Utiliser l'heure du timestamp original
                    final hourFormat =
                        DateFormat('HH:mm'); // Format heure:minute
                    final timeStr = hourFormat.format(dataPoint.timestamp);
                    final powerStr =
                        (dataPoint.power / 1000).toStringAsFixed(2); // en kW

                    // Personnaliser le tooltip
                    return LineTooltipItem(
                      '$timeStr\n', // Heure en haut
                      const TextStyle(
                        color: AppTheme.textPrimaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12, // Taille réduite pour plus d'espace
                      ),
                      children: [
                        TextSpan(
                          text: '$powerStr kW',
                          style: const TextStyle(
                            color:
                                AppTheme.chartLine1, // Couleur ligne production
                            fontWeight: FontWeight.bold,
                            fontSize:
                                14, // Taille légèrement plus grande pour la valeur
                          ),
                        ),
                      ],
                      textAlign: TextAlign.center,
                    );
                  })
                  .whereType<LineTooltipItem>()
                  .toList(); // Filtrer les nulls
            },
          ),
          touchCallback:
              (FlTouchEvent event, LineTouchResponse? touchResponse) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  touchResponse == null ||
                  touchResponse.lineBarSpots == null ||
                  touchResponse.lineBarSpots!.isEmpty) {
                _touchedIndex = -1;
                return;
              }
              // Utiliser spotIndex qui correspond à l'index dans la liste de spots
              final spotIndex = touchResponse.lineBarSpots!.first.spotIndex;
              _touchedIndex = spotIndex;
            });
          },
          handleBuiltInTouches: true,
        ),

        // Bordures du graphique
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(
              color: AppTheme.cardBorderColor.withOpacity(0.3),
              width: 1,
            ),
            left: BorderSide(
              color: AppTheme.cardBorderColor.withOpacity(0.3),
              width: 1,
            ),
            right: const BorderSide(color: Colors.transparent),
            top: const BorderSide(color: Colors.transparent),
          ),
        ),

        // Configuration des grilles
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          horizontalInterval:
              _calculateYInterval(sortedData), // Intervalle dynamique Y
          verticalInterval: 4, // Afficher toutes les 4 heures sur l'axe X
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: AppTheme.cardBorderColor.withOpacity(0.2),
              strokeWidth: 1,
              dashArray: [5, 5],
            );
          },
          getDrawingVerticalLine: (value) {
            // N'afficher que les lignes correspondant aux labels
            // Correction: la valeur X est l'index, pas l'heure directement
            if (value.toInt() % 4 != 0) {
              return const FlLine(color: Colors.transparent);
            }
            return FlLine(
              color: AppTheme.cardBorderColor.withOpacity(0.2),
              strokeWidth: 1,
              dashArray: [5, 5],
            );
          },
        ),

        // Titres des axes
        titlesData: FlTitlesData(
          show: true,
          rightTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1, // Vérifier chaque valeur entière pour le label
              // --- CORRECTION : Ajout `TitleMeta meta`, utilisation `meta.axisSide` ---
              getTitlesWidget: (double value, TitleMeta meta) {
                final index = value.toInt();
                // S'assurer que l'index est valide
                if (index < 0 || index >= sortedData.length) {
                  return const SizedBox.shrink();
                }
                // Afficher le label seulement toutes les 4 heures
                final hour = sortedData[index].timestamp.hour;
                if (hour % 4 != 0) {
                  return const SizedBox.shrink();
                }
                // Retourner le widget pour l'heure
                return SideTitleWidget(
                  axisSide: meta.axisSide, // Utilisation de meta.axisSide
                  space: 8.0, // Espace au-dessus du label
                  child: Text(
                    '${hour}h',
                    style: const TextStyle(
                      color: AppTheme.textSecondaryColor,
                      fontSize: 10,
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
              interval: _calculateYInterval(sortedData), // Intervalle dynamique
              // --- CORRECTION : Ajout `TitleMeta meta`, utilisation `meta.axisSide` ---
              getTitlesWidget: (double value, TitleMeta meta) {
                // Ne pas afficher le label pour la valeur 0 ou max pour éviter chevauchement
                if (value == meta.min || value == meta.max) {
                  return const SizedBox.shrink();
                }
                // Afficher seulement les multiples de l'intervalle
                final interval = _calculateYInterval(sortedData);
                if (value % interval != 0 && value != 0) {
                  // Garder le 0 ?
                  return const SizedBox.shrink();
                }
                // Formatter la valeur (ex: 1.0 kW, 2.5 kW)
                final text = '${value.toStringAsFixed(1)} kW';
                return SideTitleWidget(
                  axisSide: meta.axisSide, // Utilisation de meta.axisSide
                  space: 4.0, // Espace à droite du label
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: AppTheme.textSecondaryColor,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.right,
                  ),
                );
              },
              // --- FIN CORRECTION ---
              reservedSize: 40, // Ajuster si nécessaire
            ),
          ),
        ),

        // Configuration du graphique (min/max X et Y)
        minX: 0, // Commencer à l'index 0
        maxX: (sortedData.length - 1)
            .toDouble(), // Terminer au dernier index valide
        minY: 0,
        maxY: _getMaxY(sortedData), // Calculer dynamiquement

        // Données des lignes
        lineBarsData: [
          // Ligne de Production (Puissance)
          LineChartBarData(
            spots: List.generate(sortedData.length, (index) {
              // Utiliser l'index comme valeur X, la puissance en kW comme Y
              return FlSpot(
                index.toDouble(), // X = index dans la liste triée
                sortedData[index].power / 1000, // Y = puissance en kW
              );
            }),
            isCurved: true,
            color: AppTheme.chartLine1, // Utiliser chartLine1 pour puissance
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true, // Afficher les points
              getDotPainter: (spot, percent, barData, index) {
                // Mettre en évidence le point touché
                final isTouched = index == _touchedIndex;
                return FlDotCirclePainter(
                  radius: isTouched ? 5 : 3, // Plus grand si touché
                  color: isTouched
                      ? AppTheme
                          .accentColor // Utiliser accentColor pour le point touché
                      : AppTheme.chartLine1.withOpacity(0.8),
                  strokeWidth: 0,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.chartLine1.withOpacity(0.2),
            ),
          ),
        ],
      ),
    );
  }

  // Calculer la valeur maximale pour l'axe Y avec une marge
  double _getMaxY(List<SolarData> data) {
    if (data.isEmpty) return 5.0; // Valeur par défaut si pas de données

    double maxPowerKW = 0;
    for (var item in data) {
      final powerKW = item.power / 1000; // Convertir en kW
      if (powerKW > maxPowerKW) {
        maxPowerKW = powerKW;
      }
    }
    // Ajouter une marge (ex: 10% ou 1 unité) et arrondir
    // Augmente la marge pour une meilleure visibilité
    final maxY = (maxPowerKW * 1.15).ceil().toDouble();
    return maxY < 1.0 ? 1.0 : maxY; // Assurer un minimum de 1 kW
  }

  // Calculer l'intervalle pour l'axe Y
  double _calculateYInterval(List<SolarData> data) {
    final maxY = _getMaxY(data);
    if (maxY <= 0) return 1.0; // Intervalle par défaut

    // Viser environ 5-6 lignes de grille horizontales
    double interval = maxY / 5.0;

    // Arrondir à une valeur "jolie" (0.5, 1, 2, 5, 10...)
    if (interval <= 0.25) return 0.25; // Plus petit intervalle
    if (interval <= 0.5) return 0.5;
    if (interval <= 1.0) return 1.0;
    if (interval <= 2.0) return 2.0;
    if (interval <= 5.0) return 5.0;

    // Pour des valeurs plus grandes, arrondir à un multiple de 5 ou 10
    return (interval / 5.0).ceil() * 5.0;
  }
}
