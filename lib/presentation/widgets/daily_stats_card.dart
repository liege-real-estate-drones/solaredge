import 'package:flutter/material.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:solaredge_monitor/utils/power_utils.dart';

class DailyStatsCard extends StatelessWidget {
  final DailySolarData dailyData;
  final DailySolarData? previousDayData;
  final double averageDailyProduction;
  final double co2PerKwh;
  final double pricePerKwh;

  const DailyStatsCard({
    super.key,
    required this.dailyData,
    this.previousDayData,
    this.averageDailyProduction = 0.0,
    this.co2PerKwh = 0.038, // kg CO2 par kWh en France (moyenne)
    this.pricePerKwh = 0.174, // Prix moyen en € par kWh en France
  });

  @override
  Widget build(BuildContext context) {
    // Convertir les données en kWh pour l'affichage
    final totalEnergyKwh = dailyData.totalEnergy / 1000;
    final previousDayEnergyKwh = previousDayData?.totalEnergy != null 
      ? previousDayData!.totalEnergy / 1000 
      : null;
    final averageEnergyKwh = averageDailyProduction / 1000;
    
    // Calculer les économies
    final co2Saved = totalEnergyKwh * co2PerKwh;
    final moneySaved = totalEnergyKwh * pricePerKwh;
    
    // Calculer les variations par rapport à la veille et à la moyenne
    double changeFromYesterday = 0;
    double changeFromAverage = 0;
    
    if (previousDayEnergyKwh != null && previousDayEnergyKwh > 0) {
      changeFromYesterday = ((totalEnergyKwh - previousDayEnergyKwh) / previousDayEnergyKwh) * 100;
    }
    
    if (averageEnergyKwh > 0) {
      changeFromAverage = ((totalEnergyKwh - averageEnergyKwh) / averageEnergyKwh) * 100;
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
            // Titre
            const Text(
              'Production du jour',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimaryColor,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Énergie totale
            Center(
              child: Column(
                children: [
                  Text(
                    '${totalEnergyKwh.toStringAsFixed(2)} kWh',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Puissance max: ${PowerUtils.formatWatts(dailyData.peakPower)}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Ligne 1: Comparaisons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildComparisonItem(
                  icon: Icons.history,
                  label: 'vs. hier',
                  value: changeFromYesterday,
                  isPositive: changeFromYesterday > 0,
                  showSign: true,
                ),
                _buildComparisonItem(
                  icon: Icons.bar_chart,
                  label: 'vs. moyenne',
                  value: changeFromAverage,
                  isPositive: changeFromAverage > 0,
                  showSign: true,
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Ligne 2: Économies
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildComparisonItem(
                  icon: Icons.euro,
                  label: 'Économies',
                  value: moneySaved,
                  format: '€',
                  isPositive: true,
                ),
                _buildComparisonItem(
                  icon: Icons.eco,
                  label: 'CO₂ évité',
                  value: co2Saved,
                  format: 'kg',
                  isPositive: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonItem({
    required IconData icon,
    required String label,
    required double value,
    String format = '%',
    bool isPositive = true,
    bool showSign = false,
  }) {
    final String formattedValue;
    final Color valueColor;
    
    // Formater la valeur en fonction du type
    if (format == '%') {
      final sign = showSign && value > 0 ? '+' : '';
      formattedValue = '$sign${value.toStringAsFixed(1)}$format';
      valueColor = value == 0 
        ? AppTheme.textSecondaryColor 
        : (isPositive ? Colors.green : Colors.red);
    } else {
      formattedValue = '${value.toStringAsFixed(1)} $format';
      valueColor = isPositive ? Colors.green : AppTheme.textPrimaryColor;
    }
    
    return Column(
      children: [
        Icon(icon, color: AppTheme.textSecondaryColor, size: 20),
        const SizedBox(height: 4),
        Text(
          formattedValue,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor,
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
}
