import 'package:flutter/material.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/data/models/user_preferences.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:solaredge_monitor/utils/power_utils.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math'; // Pour pow, log, max
import 'package:intl/intl.dart'; // Import nécessaire pour formater les mois et devises
// *** AJOUTS POUR ACCÉDER AUX PREFS VIA PROVIDER ***
// 'package:solaredge_monitor/data/services/service_manager.dart'; // Plus besoin de GetIt ici

class YearlyProductionChart extends StatefulWidget {
  final List<YearlySolarData> yearsData;
  final int selectedYear;

  final UserPreferences? userPreferences;

  const YearlyProductionChart({
    super.key,
    required this.yearsData,
    required this.selectedYear,
    this.userPreferences,  
  });

  @override
  State<YearlyProductionChart> createState() => _YearlyProductionChartState();
}

class _YearlyProductionChartState extends State<YearlyProductionChart> {
  int? _touchedIndex;
  bool _showMonthlyView = false;

  @override
  void initState() {
    super.initState();
    _showMonthlyView = false;
  }

  @override
  void didUpdateWidget(covariant YearlyProductionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.yearsData != oldWidget.yearsData ||
        widget.selectedYear != oldWidget.selectedYear) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _touchedIndex = null;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.yearsData.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Aucune donnée annuelle disponible',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Section des boutons Toggle
        Padding(
          padding: const EdgeInsets.only(bottom: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              const Text(
                'Affichage: ',
                style: TextStyle(
                  color: AppTheme.textSecondaryColor,
                  fontSize: 14,
                ),
              ),
              ToggleButtons(
                isSelected: [!_showMonthlyView, _showMonthlyView],
                onPressed: (int index) {
                  if ((index == 1) != _showMonthlyView) {
                    setState(() {
                      _touchedIndex = null;
                      _showMonthlyView = (index == 1);
                    });
                  }
                },
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                selectedColor: AppTheme.primaryColor,
                fillColor: AppTheme.primaryColor.withOpacity(0.1),
                color: AppTheme.textSecondaryColor,
                constraints: const BoxConstraints(minWidth: 100, minHeight: 36),
                children: const <Widget>[
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('Par année'),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text('Par mois'),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Section du graphique
        AspectRatio(
          aspectRatio: 1.7,
          child: Padding(
            padding: const EdgeInsets.only(right: 18.0, top: 8, bottom: 12),
            child: BarChart(
              key: ValueKey(_showMonthlyView), // Clé pour forcer reconstruction
              _showMonthlyView ? _buildMonthlyBarData() : _buildYearlyBarData(),
              swapAnimationDuration: const Duration(milliseconds: 250),
              swapAnimationCurve: Curves.linear,
            ),
          ),
        ),
        // Section de la légende
        _buildLegend(),
        // Section du panneau d'information animé
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1.0,
              child: child,
            );
          },
          child: (_touchedIndex != null && _touchedIndex! >= 0)
              ? Padding(
                  key: ValueKey<String>('${_showMonthlyView}_$_touchedIndex'),
                  padding: const EdgeInsets.only(top: 8.0),
                  child:
                      _buildTouchedInfoPanel(), // Construit le panel approprié
                )
              : SizedBox.shrink(
                  key: ValueKey<String>('empty_$_showMonthlyView')),
        ),
      ],
    );
  }

  /// Fonction commune pour configurer les interactions tactiles (touch) du graphique.
  BarTouchData _getBarTouchData() {
    return BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        // --- CORRECTION : tooltipBgColor déplacé ici ---
        tooltipBgColor: Colors.transparent,
        getTooltipItem: (BarChartGroupData group, int groupIndex,
                BarChartRodData rod, int rodIndex) =>
            null,
      ),
      handleBuiltInTouches: false,
      touchCallback: (FlTouchEvent event, BarTouchResponse? barTouchResponse) {
        if (event is FlTapDownEvent && barTouchResponse?.spot != null) {
          final int currentTouchedIndex =
              barTouchResponse!.spot!.touchedBarGroupIndex;
          final int limit = _showMonthlyView ? 12 : widget.yearsData.length;
          if (currentTouchedIndex >= 0 && currentTouchedIndex < limit) {
            if (_touchedIndex != currentTouchedIndex) {
              setState(() {
                _touchedIndex = currentTouchedIndex;
              });
            }
          }
        }
      },
    );
  }

  /// Construit les données pour le graphique en vue annuelle.
  BarChartData _buildYearlyBarData() {
    final List<YearlySolarData> sortedYears =
        List<YearlySolarData>.from(widget.yearsData)
          ..sort((a, b) => a.year.compareTo(b.year));
    final List<BarChartGroupData> barGroups = [];
    List<double> allYearlyValues = [];

    for (int i = 0; i < sortedYears.length; i++) {
      final YearlySolarData yearData = sortedYears[i];
      final bool isSelectedYear = yearData.year == widget.selectedYear;
      final double totalEnergyInKWh = PowerUtils.WhTokWh(yearData.totalEnergy);
      allYearlyValues.add(totalEnergyInKWh);
      final Color color = isSelectedYear
          ? AppTheme.primaryColor
          : _getColorForYearIndex(i, sortedYears.length, yearData.year);

      final BarChartGroupData group = BarChartGroupData(
        x: yearData.year, // Utiliser l'entier
        barRods: [
          BarChartRodData(
            toY: totalEnergyInKWh,
            color: color,
            width: 22,
            borderRadius: BorderRadius.circular(4),
            borderSide: _touchedIndex == i
                ? const BorderSide(color: AppTheme.accentColor, width: 2)
                : BorderSide.none,
          ),
        ],
        showingTooltipIndicators: [],
      );
      barGroups.add(group);
    }

    return BarChartData(
      barTouchData: _getBarTouchData(),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (double value, TitleMeta meta) {
              final int year = value.toInt();
              if (value != year.toDouble()) return const SizedBox.shrink();
              final bool isSelected = year == widget.selectedYear;
              return SideTitleWidget(
                axisSide: meta.axisSide, // Utilisation de meta.axisSide
                space: 16,
                child: Text(year.toString(),
                    style: TextStyle(
                        color: isSelected
                            ? AppTheme.primaryColor
                            : AppTheme.textSecondaryColor,
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal)),
              );
            },
            // --- FIN CORRECTION ---
            // interval: 1, // Commenté car getTitlesWidget gère la logique
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 60,
            interval: _calculateYInterval(allYearlyValues),
            getTitlesWidget: (double value, TitleMeta meta) {
              if (value == meta.min || value == meta.max) {
                return const SizedBox.shrink();
              }
              String label;
              if (value >= 1000) {
                label =
                    '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)} MWh';
              } else {
                label = '${value.toInt()} kWh';
              }
              return SideTitleWidget(
                  axisSide: meta.axisSide, // Utilisation de meta.axisSide
                  space: 8,
                  child: Text(label,
                      style: const TextStyle(
                          color: AppTheme.textSecondaryColor, fontSize: 10)));
            },
            // --- FIN CORRECTION ---
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      barGroups: barGroups,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: _calculateYInterval(allYearlyValues),
        getDrawingHorizontalLine: (double value) => FlLine(
            color: AppTheme.textSecondaryColor.withOpacity(0.1),
            strokeWidth: 1),
      ),
    );
  }

  /// Construit les données pour le graphique en vue mensuelle comparative.
  BarChartData _buildMonthlyBarData() {
    final List<YearlySolarData> sortedYears =
        List<YearlySolarData>.from(widget.yearsData)
          ..sort((a, b) => a.year.compareTo(b.year));
    final List<BarChartGroupData> barGroups = [];
    List<double> allMonthlyValues = [];

    for (int month = 1; month <= 12; month++) {
      final List<BarChartRodData> rods = [];
      final double rodWidth = max(
          4.0, 18.0 / max(1, sortedYears.length)); // Eviter division par zéro
      final bool isTouched = (_touchedIndex == month - 1);

      for (int i = 0; i < sortedYears.length; i++) {
        final YearlySolarData yearData = sortedYears[i];
        MonthlySolarData? monthData;
        for (var md in yearData.monthlyData) {
          if (md.month.month == month) {
            monthData = md;
            break;
          }
        }
        double monthlyEnergyInKWh =
            monthData != null ? PowerUtils.WhTokWh(monthData.totalEnergy) : 0;
        if (monthData != null) allMonthlyValues.add(monthlyEnergyInKWh);
        final Color color = yearData.year == widget.selectedYear
            ? AppTheme.primaryColor
            : _getColorForYearIndex(i, sortedYears.length, yearData.year);
        rods.add(BarChartRodData(
          toY: monthlyEnergyInKWh,
          color: color,
          width: rodWidth,
          borderRadius: BorderRadius.circular(2),
          borderSide: isTouched
              ? BorderSide(
                  color: AppTheme.accentColor.withOpacity(0.7), width: 1)
              : BorderSide.none,
        ));
      }
      barGroups.add(BarChartGroupData(
        x: month, // Utilise l'entier du mois comme valeur X
        barRods: rods,
        showingTooltipIndicators: [],
      ));
    }

    return BarChartData(
      barTouchData: _getBarTouchData(),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 30,
          interval: 1,
          // --- CORRECTION : Ajout `TitleMeta meta`, utilisation `meta.axisSide` ---
          getTitlesWidget: (double value, TitleMeta meta) {
            final int month = value.toInt();
            if (value != month.toDouble() || month < 1 || month > 12) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
                axisSide: meta.axisSide, // Utilisation de meta.axisSide
                space: 16,
                child: Text(_getMonthAbbreviation(month),
                    style: const TextStyle(
                        color: AppTheme.textSecondaryColor, fontSize: 10)));
          },
          // --- FIN CORRECTION ---
        )),
        leftTitles: AxisTitles(
            sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 60,
          interval: _calculateYInterval(allMonthlyValues),
          // --- CORRECTION : Ajout `TitleMeta meta`, utilisation `meta.axisSide` ---
          getTitlesWidget: (double value, TitleMeta meta) {
            if (value == meta.min || value == meta.max) {
              return const SizedBox.shrink();
            }
            return SideTitleWidget(
                axisSide: meta.axisSide, // Utilisation de meta.axisSide
                space: 8,
                child: Text('${value.toInt()} kWh',
                    style: const TextStyle(
                        color: AppTheme.textSecondaryColor, fontSize: 10)));
          },
          // --- FIN CORRECTION ---
        )),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      barGroups: barGroups,
      gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _calculateYInterval(allMonthlyValues),
          getDrawingHorizontalLine: (value) => FlLine(
              color: AppTheme.textSecondaryColor.withOpacity(0.1),
              strokeWidth: 1)),
      alignment: BarChartAlignment.spaceAround,
    );
  }

  /// Calcule un intervalle "logique" pour l'axe Y basé sur les valeurs fournies.
  double _calculateYInterval(List<double> values) {
    if (values.isEmpty) return 1000;
    double maxValue = 0;
    for (var v in values) {
      if (v > maxValue) maxValue = v;
    }
    if (maxValue <= 0) return 500;
    double interval = maxValue / 5.0;
    if (interval <= 0) return 500;

    // Ajout d'une petite valeur epsilon pour éviter les problèmes de log(0)
    interval = interval + 1e-9;

    double magnitude = pow(10, (log(interval) / log(10)).floor()).toDouble();
    double residual = interval / magnitude;
    double niceInterval;
    if (residual > 5) {
      niceInterval = 10 * magnitude;
    } else if (residual > 2) {
      niceInterval = 5 * magnitude;
    } else if (residual > 1) {
      niceInterval = 2 * magnitude;
    } else {
      niceInterval = magnitude;
    }
    // Assurer un intervalle minimum raisonnable
    return max(niceInterval, maxValue / 10 > 0 ? maxValue / 10 : 1.0);
  }

  /// Construit la légende des années sous le graphique.
  Widget _buildLegend() {
    final List<YearlySolarData> sortedYears =
        List<YearlySolarData>.from(widget.yearsData)
          ..sort((a, b) => a.year.compareTo(b.year));
    final List<Widget> legendItems = [];
    for (int i = 0; i < sortedYears.length; i++) {
      final YearlySolarData yearData = sortedYears[i];
      final bool isSelectedYear = yearData.year == widget.selectedYear;
      final Color color = isSelectedYear
          ? AppTheme.primaryColor
          : _getColorForYearIndex(i, sortedYears.length, yearData.year);
      legendItems.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 8),
            Text(
              yearData.year.toString(),
              style: TextStyle(
                  color: isSelectedYear
                      ? AppTheme.primaryColor
                      : AppTheme.textSecondaryColor,
                  fontSize: 12,
                  fontWeight:
                      isSelectedYear ? FontWeight.bold : FontWeight.normal),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: legendItems,
      ),
    );
  }

  /// Trouve le mois avec la production la plus élevée pour une année donnée.
  MonthlySolarData? _findBestMonth(YearlySolarData yearData) {
    if (yearData.monthlyData.isEmpty) return null;
    return yearData.monthlyData.reduce((currentMax, month) =>
        month.totalEnergy > currentMax.totalEnergy ? month : currentMax);
  }

  /// Construit le panneau d'information qui apparaît au toucher.
  Widget _buildTouchedInfoPanel() {
    if (_touchedIndex == null || _touchedIndex! < 0) {
      return const SizedBox.shrink();
    }

    // --- Panel Vue Mensuelle ---
    if (_showMonthlyView) {
      if (_touchedIndex! >= 12) return const SizedBox.shrink();
      final int month = _touchedIndex! + 1;
      final String monthName = _getMonthName(month);
      final List<YearlySolarData> sortedYears =
          List<YearlySolarData>.from(widget.yearsData)
            ..sort((a, b) => a.year.compareTo(b.year));
      final List<Widget> monthDataWidgets = [];
      for (final YearlySolarData yearData in sortedYears) {
        MonthlySolarData? monthData;
        for (var md in yearData.monthlyData) {
          if (md.month.month == month) {
            monthData = md;
            break;
          }
        }
        final bool isSelectedYear = yearData.year == widget.selectedYear;
        final Color color = isSelectedYear
            ? AppTheme.primaryColor
            : _getColorForYearIndex(sortedYears.indexOf(yearData),
                sortedYears.length, yearData.year);
        if (monthData != null) {
          final double energyKWh = PowerUtils.WhTokWh(monthData.totalEnergy);
          monthDataWidgets.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.0),
              child: Row(children: <Widget>[
                Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text('${yearData.year}: ',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelectedYear
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelectedYear
                            ? AppTheme.primaryColor
                            : AppTheme.textSecondaryColor)),
                Expanded(
                    child: Text('${energyKWh.toStringAsFixed(2)} kWh',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isSelectedYear
                                ? AppTheme.primaryColor
                                : AppTheme.textPrimaryColor),
                        textAlign: TextAlign.right))
              ])));
        } else {
          monthDataWidgets.add(Padding(
              padding: const EdgeInsets.symmetric(vertical: 3.0),
              child: Row(children: <Widget>[
                Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(2))),
                const SizedBox(width: 8),
                Text('${yearData.year}: ',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelectedYear
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelectedYear
                            ? AppTheme.primaryColor
                            : AppTheme.textSecondaryColor)),
                const Expanded(
                    child: Text('- kWh',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textSecondaryColor),
                        textAlign: TextAlign.right))
              ])));
        }
      }
      return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadius),
              side: const BorderSide(
                  color: AppTheme.cardBorderColor, width: 0.5)),
          color: AppTheme.cardColor,
          child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Expanded(
                              child: Text('Production - $monthName',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.textPrimaryColor),
                                  overflow: TextOverflow.ellipsis)),
                          IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () {
                                setState(() {
                                  _touchedIndex = null;
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              color: AppTheme.textSecondaryColor,
                              tooltip: 'Fermer')
                        ]),
                    const SizedBox(height: 12),
                    ...monthDataWidgets,
                    const SizedBox(height: 12),
                    Align(
                        alignment: Alignment.center,
                        child: OutlinedButton.icon(
                            icon: const Icon(Icons.arrow_forward),
                            label: const Text('Détails du mois'),
                            onPressed: () {
                              final DateTime selectedDate =
                                  DateTime(widget.selectedYear, month, 1);
                              Navigator.pushNamed(context, '/monthly',
                                  arguments: {'selectedDate': selectedDate});
                            },
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primaryColor,
                                side: BorderSide(
                                    color:
                                        AppTheme.primaryColor.withOpacity(0.5)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                textStyle: const TextStyle(fontSize: 12))))
                  ])));
    }
    // --- Panel Vue Annuelle (MODIFIÉ pour utiliser Provider) ---
    else {
      if (_touchedIndex! >= widget.yearsData.length) {
        return const SizedBox.shrink();
      }
      final List<YearlySolarData> sortedYears =
          List<YearlySolarData>.from(widget.yearsData)
            ..sort((a, b) => a.year.compareTo(b.year));
      final YearlySolarData yearData = sortedYears[_touchedIndex!];
      final double energyKWh = PowerUtils.WhTokWh(yearData.totalEnergy);
      final bool isSelectedYearStyle = yearData.year == widget.selectedYear;

      // Meilleur mois
      final MonthlySolarData? bestMonthData = _findBestMonth(yearData);
      String bestMonthText = 'N/A';
      if (bestMonthData != null) {
        final String bestMonthName = _getMonthName(bestMonthData.month.month);
        final double bestMonthEnergy =
            PowerUtils.WhTokWh(bestMonthData.totalEnergy);
        bestMonthText =
            '$bestMonthName (${bestMonthEnergy.toStringAsFixed(1)} kWh)';
      }

      // *** CALCUL DES ÉCONOMIES EN UTILISANT userPreferences ***
      String savingsText = 'Prix kWh non défini'; // Texte par défaut
      Color savingsColor = AppTheme.textSecondaryColor; // Couleur par défaut
      double? energyRate =
          widget.userPreferences?.energyRate; // Récupérer le tarif via widget

      if (energyRate != null && energyRate > 0) {
        final double estimatedSavings = energyKWh * energyRate; // Calcul
        savingsText = NumberFormat.currency(
                locale: 'fr_BE', symbol: '€', decimalDigits: 2)
            .format(estimatedSavings); // Formatage
        savingsColor = Colors.green; // Vert pour les économies
      }
      // *** FIN CALCUL ÉCONOMIES ***

      // Carte Panel Annuel
      return Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
            side:
                const BorderSide(color: AppTheme.cardBorderColor, width: 0.5)),
        color: AppTheme.cardColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // Titre + Fermer
              Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                        child: Text('Production - Année ${yearData.year}',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimaryColor),
                            overflow: TextOverflow.ellipsis)),
                    IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          setState(() {
                            _touchedIndex = null;
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        color: AppTheme.textSecondaryColor,
                        tooltip: 'Fermer')
                  ]),
              const SizedBox(height: 12),
              // Prod Totale
              Row(children: <Widget>[
                Icon(Icons.electric_bolt,
                    color: isSelectedYearStyle
                        ? AppTheme.primaryColor
                        : AppTheme.chartLine1,
                    size: 20),
                const SizedBox(width: 8),
                const Flexible(
                    child: Text('Prod. totale: ',
                        style: TextStyle(
                            fontSize: 16, color: AppTheme.textPrimaryColor),
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    child: Text(
                        '${energyKWh.toStringAsFixed(0)} kWh', // Arrondi pour l'année
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isSelectedYearStyle
                                ? AppTheme.primaryColor
                                : AppTheme.chartLine1),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis))
              ]),
              const SizedBox(height: 6),
              // Meilleur Mois
              Row(children: <Widget>[
                const Icon(Icons.star_outline,
                    color: AppTheme.chartLine2, size: 20),
                const SizedBox(width: 8),
                const Flexible(
                    child: Text('Meilleur mois: ',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textPrimaryColor),
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    child: Text(bestMonthText,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.chartLine2),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis))
              ]),
              const SizedBox(height: 6),
              // Economies
              Row(children: <Widget>[
                const Icon(Icons.euro, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                const Flexible(
                    child: Text('Économies estimées: ',
                        style: TextStyle(
                            fontSize: 14, color: AppTheme.textPrimaryColor),
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    child: Text(savingsText,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: (energyRate != null && energyRate > 0)
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontStyle: (energyRate != null && energyRate > 0)
                                ? FontStyle.normal
                                : FontStyle.italic,
                            color: savingsColor),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis))
              ]),
              const SizedBox(height: 12),
              // Bouton Voir par mois
              Align(
                  alignment: Alignment.center,
                  child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Voir par mois'),
                      onPressed: () {
                        setState(() {
                          _touchedIndex = null;
                          _showMonthlyView = true;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryColor,
                          side: BorderSide(
                              color: AppTheme.primaryColor.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12))))
            ],
          ),
        ),
      );
    }
  }

  /// Retourne une couleur pour la légende ou les barres.
  Color _getColorForYearIndex(int index, int totalYears, int year) {
    if (year == widget.selectedYear) return AppTheme.primaryColor;
    final List<Color> colors = [
      AppTheme.chartLine1,
      AppTheme.chartLine2,
      AppTheme.chartLine3,
      AppTheme.chartLine4,
      Colors.teal.shade300,
      Colors.orange.shade300,
      Colors.purple.shade300
    ];
    return colors[index % colors.length];
  }

  /// Retourne le nom complet du mois.
  String _getMonthName(int month) {
    final List<String> monthNames = [
      'Janvier',
      'Février',
      'Mars',
      'Avril',
      'Mai',
      'Juin',
      'Juillet',
      'Août',
      'Septembre',
      'Octobre',
      'Novembre',
      'Décembre'
    ];
    return (month >= 1 && month <= 12) ? monthNames[month - 1] : '';
  }

  /// Retourne l'abréviation du mois.
  String _getMonthAbbreviation(int month) {
    final List<String> monthAbbreviations = [
      'Jan',
      'Fév',
      'Mar',
      'Avr',
      'Mai',
      'Juin',
      'Jui',
      'Aoû',
      'Sep',
      'Oct',
      'Nov',
      'Déc'
    ];
    return (month >= 1 && month <= 12) ? monthAbbreviations[month - 1] : '';
  }
} // Fin _YearlyProductionChartState
