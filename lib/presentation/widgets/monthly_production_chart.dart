import 'package:flutter/material.dart';
import 'package:solaredge_monitor/data/models/solar_data.dart'; // Contient DailySolarData et HourlySolarData
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:solaredge_monitor/utils/power_utils.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math'; // Pour max

class MonthlyProductionChart extends StatefulWidget {
  final MonthlySolarData monthlyData;
  final Map<int, MonthlySolarData>? comparisonData;
  // Note: showDailyBreakdown n'est pas utilisé dans le code fourni, mais conservé
  final bool showDailyBreakdown;
  final bool showComparisonAsOverlay;

  const MonthlyProductionChart({
    super.key,
    required this.monthlyData,
    this.comparisonData,
    this.showDailyBreakdown = true, // Conservé mais non utilisé
    this.showComparisonAsOverlay = false,
  });

  @override
  State<MonthlyProductionChart> createState() => _MonthlyProductionChartState();
}

class _MonthlyProductionChartState extends State<MonthlyProductionChart> {
  // _touchedIndex représente l'index du groupe de barres touché (0 pour jour 1, 1 pour jour 2, etc.)
  int? _touchedIndex;
  // _isDetailMode n'est pas utilisé pour la sélection sticky, conservé pour le moment
  final bool _isDetailMode = false;

  @override
  void didUpdateWidget(covariant MonthlyProductionChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Si les données principales ou de comparaison changent, réinitialiser l'index touché
    if (widget.monthlyData != oldWidget.monthlyData ||
        widget.comparisonData != oldWidget.comparisonData) {
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
    if (widget.monthlyData.dailyData.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Aucune donnée journalière disponible pour ce mois',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondaryColor, fontSize: 14),
          ),
        ),
      );
    }

    // Mapper les données quotidiennes par jour pour un accès facile
    final Map<int, DailySolarData> dataMap = {
      for (var dataPoint in widget.monthlyData.dailyData)
        dataPoint.date.day: dataPoint
    };
    final int daysInMonth = DateTime(widget.monthlyData.month.year,
            widget.monthlyData.month.month + 1, 0)
        .day;

    // Calculer une largeur minimale pour le graphique
    final double minChartWidth = daysInMonth * 40.0; // Ex: 40 pixels par jour (à ajuster)

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio( // Garder ou ajuster l'aspect ratio si besoin
          aspectRatio: 1.7,
          child: SingleChildScrollView( // <<=== AJOUT
            scrollDirection: Axis.horizontal, // <<=== AJOUT
            child: Padding(
              padding: const EdgeInsets.only(right: 18.0, top: 16, bottom: 12),
              child: SizedBox( // <<=== AJOUT: Pour contraindre la largeur minimale
                width: minChartWidth, // <<=== AJOUT
                child: BarChart(
                  // Le mode détail ne change que l'apparence de la grille ici, pas le touch handling
                  _isDetailMode
                      ? _buildDetailBarData(dataMap, daysInMonth)
                      : _buildMainBarData(dataMap, daysInMonth),
                  swapAnimationDuration: const Duration(milliseconds: 250),
                ),
              ),
            ),
          ),
        ),

        // Panneau d'information animé pour le jour sélectionné
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return SizeTransition(
                sizeFactor: animation, axisAlignment: -1.0, child: child);
          },
          child: (_touchedIndex != null && _touchedIndex! >= 0)
              ? Padding(
                  // Utiliser une clé qui change quand l'index change
                  key: ValueKey<int>(_touchedIndex!),
                  padding: const EdgeInsets.only(top: 8.0),
                  // Passer l'index au panel builder
                  child: _buildTouchedInfoPanel(_touchedIndex!),
                )
              : const SizedBox.shrink(key: ValueKey<int>(-1)), // Widget vide
        ),
      ],
    );
  }

  // Construire le graphique principal (ou détaillé, car la logique de base est similaire)
  BarChartData _buildChartDataBase(
      Map<int, DailySolarData> dataMap, int daysInMonth,
      {bool isDetail = false}) {
    final List<BarChartGroupData> barGroups = [];
    List<double> allValues = []; // Pour calculer l'intervalle Y

    // Préparer les données de comparaison pour un accès facile par jour et année
    final Map<int, Map<int, DailySolarData>> comparisonByDayAndYear = {};
    if (widget.comparisonData != null) {
      for (var entry in widget.comparisonData!.entries) {
        final year = entry.key;
        final yearData = entry.value;
        for (var dailyItem in yearData.dailyData) {
          final day = dailyItem.date.day;
          comparisonByDayAndYear.putIfAbsent(day, () => {})[year] = dailyItem;
        }
      }
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final currentDayData = dataMap[day];
      final todayValue = currentDayData != null
          ? PowerUtils.WhTokWh(currentDayData.totalEnergy)
          : 0.0;
      if (currentDayData != null) allValues.add(todayValue);

      final List<BarChartRodData> rods = [];
      final bool isTouched = (_touchedIndex == day - 1); // Index base 0

      final comparisonAvailableForDay = widget.comparisonData != null &&
          comparisonByDayAndYear.containsKey(day);

      if (comparisonAvailableForDay) {
        final comparisonMapForDay = comparisonByDayAndYear[day]!;
        final comparisonYears = comparisonMapForDay.keys.toList()
          ..sort(); // Années triées

        if (widget.showComparisonAsOverlay) {
          // Mode superposition: Barre principale devant
          rods.add(BarChartRodData(
            toY: todayValue,
            color: AppTheme.primaryColor,
            width: 10,
            borderRadius: BorderRadius.circular(2),
            borderSide: isTouched
                ? const BorderSide(color: AppTheme.accentColor, width: 1.5)
                : BorderSide.none,
          ));
          // Ajouter les barres de comparaison derrière (couleurs plus claires)
          int colorIndex = 0;
          for (var year in comparisonYears) {
            final comparisonValue =
                PowerUtils.WhTokWh(comparisonMapForDay[year]!.totalEnergy);
            allValues.add(comparisonValue);
            final color =
                _getComparisonColor(colorIndex++, comparisonYears.length);
            rods.add(BarChartRodData(
              toY: comparisonValue,
              color: color,
              width: 10, // Même largeur
              borderRadius: BorderRadius.circular(2),
              // Pas de bordure sur les barres de comparaison
            ));
          }
        } else {
          // Mode juxtaposition
          final totalBars = 1 + comparisonYears.length;
          // Ajuster la largeur des barres pour une meilleure lisibilité avec le scrolling
          final double baseRodWidth = 8.0; // Largeur de base par barre (à ajuster)
          final double rodWidth = baseRodWidth;
          // Calculer l'espace entre les barres pour remplir l'espace du groupe
          final double barsSpace = totalBars > 1 ? max(0.5, (baseRodWidth * 0.5)) : 0.0; // Ex: 50% de la largeur de la barre

          // Barre principale (année en cours)
          rods.add(BarChartRodData(
            toY: todayValue,
            color: AppTheme.primaryColor,
            width: rodWidth,
            borderRadius: BorderRadius.circular(1),
            borderSide: isTouched
                ? const BorderSide(color: AppTheme.accentColor, width: 1)
                : BorderSide.none,
          ));

          // Barres de comparaison
          int colorIndex = 0;
          for (var year in comparisonYears) {
            final comparisonValue =
                PowerUtils.WhTokWh(comparisonMapForDay[year]!.totalEnergy);
            allValues.add(comparisonValue);
            final color =
                _getComparisonColor(colorIndex++, comparisonYears.length);
            rods.add(BarChartRodData(
              toY: comparisonValue,
              color: color,
              width: rodWidth,
              borderRadius: BorderRadius.circular(1),
            ));
          }

           final group = BarChartGroupData(
            x: day,
            barRods: rods,
            barsSpace: barsSpace, // Utiliser l'espace calculé
            showingTooltipIndicators: [], // Tooltip géré par le panel
          );
          barGroups.add(group);

        }
      } else {
        // Pas de comparaison, juste la barre du jour
        rods.add(BarChartRodData(
          toY: todayValue,
          color: AppTheme.primaryColor
              .withOpacity(currentDayData != null ? 1.0 : 0.3),
          width: 8,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          borderSide: isTouched
              ? const BorderSide(color: AppTheme.accentColor, width: 1.5)
              : BorderSide.none,
        ));

         final group = BarChartGroupData(
          x: day,
          barRods: rods,
          barsSpace: 2, // Espace standard
          showingTooltipIndicators: [], // Tooltip géré par le panel
        );
        barGroups.add(group);
      }

      // Ancien code déplacé ou supprimé car la création du groupe est maintenant dans les blocs if/else
      // final group = BarChartGroupData(
      //   x: day,
      //   barRods: rods,
      //   barsSpace: comparisonAvailableForDay && !widget.showComparisonAsOverlay
      //       ? max(
      //           0.5,
      //           (12.0 - (rods.length * rods.first.width)) /
      //               (rods.length > 1
      //                   ? rods.length - 1
      //                   : 1) // Éviter division par zéro si rods.length == 1
      //           )
      //       : 2, // Espace standard sinon
      //   showingTooltipIndicators: [], // Tooltip géré par le panel
      // );
      // barGroups.add(group);
    }

    // Utiliser la même instance de BarTouchData pour les deux modes
    final touchData = BarTouchData(
      touchTooltipData: BarTouchTooltipData(
        // --- CORRECTION : tooltipBgColor déplacé ici ---
        tooltipBgColor: Colors.transparent, // Pas de tooltip intégré
        getTooltipItem: (group, groupIndex, rod, rodIndex) => null,
      ),
      handleBuiltInTouches: true, // <<< MODIFIÉ : Laisser handleBuiltInTouches gérer les taps de base
      touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
        debugPrint("Monthly Chart Touch - Event: ${event.runtimeType}, GroupIndex: ${response?.spot?.touchedBarGroupIndex}");

        // --- MISE À JOUR DE LA LOGIQUE DE TOUCH ---
        if (response?.spot != null && event.isInterestedForInteractions) {
           // Mettre à jour l'index touché pour le feedback visuel (panel + bordure)
           if (_touchedIndex != response!.spot!.touchedBarGroupIndex) {
             setState(() {
               _touchedIndex = response.spot!.touchedBarGroupIndex;
             });
           }

           // *** Gérer la navigation au TAP UP ***
           if (event is FlTapUpEvent) {
             final int touchedGroupIndex = response.spot!.touchedBarGroupIndex;
             if (touchedGroupIndex >= 0) {
                final int dayOfMonth = touchedGroupIndex + 1; // Convertir 0-based index to day
                // Ensure day is valid for the month (though the chart should handle this)
                final int daysInMonthCheck = DateTime(widget.monthlyData.month.year, widget.monthlyData.month.month + 1, 0).day;
                 if (dayOfMonth <= daysInMonthCheck) {
                    final DateTime selectedDate = DateTime(
                     widget.monthlyData.month.year,
                     widget.monthlyData.month.month,
                     dayOfMonth,
                    );
                   debugPrint("Monthly Chart: Navigating to Daily Screen for date: $selectedDate");
                   // Navigate to DailyScreen with the selected date
                   Navigator.pushNamed(
                     context,
                     '/daily',
                     arguments: {'selectedDate': selectedDate}, // Pass date as argument
                   );
                 } else {
                   debugPrint("Monthly Chart: Invalid day selected: $dayOfMonth");
                 }
             }
           }
           // *** FIN GESTION NAVIGATION ***
        } else if (!event.isInterestedForInteractions) {
           // Optionnel: Effacer la sélection si le toucher sort du graphique
           // ou si ce n'est pas un événement intéressant.
           // Si vous voulez garder la sélection "sticky", commentez la ligne suivante.
           // setState(() { _touchedIndex = null; });
        }
        // --- FIN MISE À JOUR LOGIQUE TOUCH ---
      },
    );

    return BarChartData(
      barTouchData: touchData, // Utiliser l'instance commune
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            // Calculer l'intervalle dynamiquement en fonction de la largeur de l'écran
            interval: max(1.0, (daysInMonth / (MediaQuery.of(context).size.width / 60)).ceil()).toDouble(), // Ajuster 60 selon la densité souhaitée
            getTitlesWidget: (double value, TitleMeta meta) {
              final day = value.toInt();
              // Afficher le label si c'est le premier jour, le dernier jour, ou un multiple de l'intervalle calculé
              // TODO: Fixer l'accès à l'intervalle dynamique. meta.interval n'existe pas.
            // Pour l'instant, on utilise un intervalle fixe pour éviter l'erreur.
            // final dynamicInterval = max(1.0, (daysInMonth / (MediaQuery.of(context).size.width / 60)).ceil()).toDouble();
            // if (day == 1 || day == daysInMonth || (value % dynamicInterval) == 0) {
            //      return SideTitleWidget(
            //         axisSide: meta.axisSide,
            //         space: 8,
            //         child: Text(day.toString(),
            //             style: const TextStyle(
            //                 color: AppTheme.textSecondaryColor, fontSize: 10)),
            //       );
            //   }
            //   return const SizedBox.shrink(); // Cacher les autres labels

            // --- MODIFICATION : Afficher CHAQUE jour ---
            // Vérifier si la valeur est bien un jour valide du mois
            // 'value' représente l'index du groupe (jour - 1) + 1, donc 'day' est le jour du mois.
            if (day < 1 || day > daysInMonth) {
              return const SizedBox.shrink(); // Ne rien afficher si hors limites
            }
            // Afficher CHAQUE jour
            return SideTitleWidget(
              axisSide: meta.axisSide,
              space: 4.0, // <<== Réduire l'espace si nécessaire
              child: Text(
                day.toString(), // Affiche le numéro du jour
                style: const TextStyle(
                  color: AppTheme.textSecondaryColor,
                  fontSize: 9, // <<== Réduire la taille de police
                ),
              ),
            );
            // --- FIN MODIFICATION ---
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (double value, TitleMeta meta) {
              if (value == meta.min || value == meta.max) {
                return const SizedBox();
              }
              return SideTitleWidget(
                axisSide: meta.axisSide, // Utilisation de meta.axisSide
                space: 8,
                child: Text('${value.toInt()} kWh',
                    style: const TextStyle(
                        color: AppTheme.textSecondaryColor, fontSize: 10)),
              );
            },
            // --- FIN CORRECTION ---
            reservedSize: 50,
            interval: _calculateYInterval(allValues), // Calcul dynamique
          ),
        ),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      barGroups: barGroups,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval:
            _calculateYInterval(allValues), // Utiliser le même intervalle
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color:
                AppTheme.textSecondaryColor.withOpacity(isDetail ? 0.2 : 0.1),
            strokeWidth: 1,
            dashArray: (isDetail && value.toInt() != value)
                ? [3, 3]
                : null, // Pointillés en mode détail
          );
        },
      ),
      alignment: widget.comparisonData == null || widget.showComparisonAsOverlay
          ? BarChartAlignment.spaceBetween // Espacer quand 1 barre/jour
          : BarChartAlignment
              .center, // Centrer quand plusieurs barres juxtaposées
    );
  }

  // Construire le graphique principal en appelant la base
  BarChartData _buildMainBarData(
      Map<int, DailySolarData> dataMap, int daysInMonth) {
    return _buildChartDataBase(dataMap, daysInMonth, isDetail: false);
  }

  // Construire le graphique détaillé en appelant la base
  BarChartData _buildDetailBarData(
      Map<int, DailySolarData> dataMap, int daysInMonth) {
    // Peut avoir des différences mineures (ex: grille) mais utilise la même base
    return _buildChartDataBase(dataMap, daysInMonth, isDetail: true);
  }

  // Afficher les détails pour le jour sélectionné (prend l'index en paramètre)
  Widget _buildTouchedInfoPanel(int touchedIndex) {
    final dayOfMonth =
        touchedIndex + 1; // Convertir index 0-based en jour 1-based
    final dateForPanel = DateTime(widget.monthlyData.month.year,
        widget.monthlyData.month.month, dayOfMonth);

    // Retrouver les données pour ce jour spécifique
    DailySolarData? selectedDayData;
    for (var data in widget.monthlyData.dailyData) {
      if (data.date.day == dayOfMonth) {
        selectedDayData = data;
        break;
      }
    }

    // Gérer si aucune donnée n'est trouvée pour cet index (ne devrait pas arriver si index est valide)
    if (selectedDayData == null) {
      debugPrint(
          "Erreur: Aucune donnée trouvée pour l'index $touchedIndex (jour $dayOfMonth)");
      return Card(
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
            side:
                const BorderSide(color: AppTheme.cardBorderColor, width: 0.5)),
        color: AppTheme.cardColor.withOpacity(0.8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  'Données non disponibles pour le ${DateFormat('d MMMM', 'fr_FR').format(dateForPanel)}',
                  style: const TextStyle(
                      color: AppTheme.textSecondaryColor, fontSize: 14)),
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
                  tooltip: 'Fermer'),
            ],
          ),
        ),
      );
    }

    final dateFormat =
        DateFormat('EEEE d MMMM yyyy', 'fr_FR'); // Formatage année ajoutée
    final formattedDate = dateFormat.format(selectedDayData.date);
    final energyKWh = PowerUtils.WhTokWh(selectedDayData.totalEnergy);

    // --- Calcul FIABLE de l'estimation du pic basé sur l'énergie horaire max ---
    double estimatedPeakW = 0;
    if (selectedDayData.hourlyData.isNotEmpty) {
      // Trouver l'énergie horaire maximale (en Wh)
      estimatedPeakW = selectedDayData.hourlyData
          .map((h) => h.energy) // Prend l'énergie de chaque heure
          .reduce(max); // Trouve le maximum
      // Cette énergie horaire max (Wh) est une bonne approximation de la puissance moyenne max (W) sur une heure.
    }
     // Optionnellement, on pourrait prendre le max entre le peakPower fourni (s'il est non nul) et l'estimation
     // estimatedPeakW = max(selectedDayData.peakPower, estimatedPeakW);
     // Mais pour éviter le 0W, on se base principalement sur l'estimation horaire :
    if (selectedDayData.peakPower > estimatedPeakW) {
        // Si le peakPower de l'API (qui vient de powerDetails) est supérieur
        // (et non nul), on le préfère car plus précis.
        estimatedPeakW = selectedDayData.peakPower;
    }
    if (estimatedPeakW < 0) estimatedPeakW = 0; // Sécurité
    // --- FIN Calcul ---

    // Récupérer les valeurs de production des années précédentes pour le même jour
    final List<Widget> comparisonWidgets = [];
    if (widget.comparisonData != null) {
      // Trier les années de comparaison pour un affichage cohérent
      final sortedComparisonYears = widget.comparisonData!.keys.toList()
        ..sort();

      for (var year in sortedComparisonYears) {
        final yearData = widget.comparisonData![year]!;
        DailySolarData? comparableDayData;
        for (var dayData in yearData.dailyData) {
          // Comparer jour ET mois pour être sûr (ex: 29 février)
          if (dayData.date.day == selectedDayData.date.day &&
              dayData.date.month == selectedDayData.date.month) {
            comparableDayData = dayData;
            break;
          }
        }

        if (comparableDayData != null) {
          final comparisonEnergy =
              PowerUtils.WhTokWh(comparableDayData.totalEnergy);
          // Calcul de la différence en % (gérer division par zéro)
          final double percentDiffValue = (comparisonEnergy != 0)
              ? ((energyKWh - comparisonEnergy) / comparisonEnergy * 100)
              : (energyKWh > 0 ? double.infinity : 0.0);
          String percentDiff = 'N/A';
          Color diffColor = AppTheme.textSecondaryColor;
          if (percentDiffValue.isFinite) {
            percentDiff =
                '${percentDiffValue > 0 ? '+' : ''}${percentDiffValue.toStringAsFixed(1)}%';
            diffColor = percentDiffValue > 0 ? Colors.green : Colors.red;
          } else if (percentDiffValue.isInfinite) {
            percentDiff = '+Inf%'; // Produit mais pas l'année d'avant
            diffColor = Colors.green;
          }

          comparisonWidgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_outlined,
                      size: 16,
                      color: _getComparisonColor(
                          sortedComparisonYears.indexOf(year),
                          sortedComparisonYears.length)),
                  const SizedBox(width: 8),
                  Text('$year: ',
                      style: const TextStyle(
                          fontSize: 14, color: AppTheme.textSecondaryColor)),
                  Expanded(
                      child: Text('${comparisonEnergy.toStringAsFixed(2)} kWh',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTheme.textPrimaryColor),
                          textAlign: TextAlign.left)),
                  const SizedBox(width: 8),
                  Text(percentDiff,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: diffColor)),
                ],
              ),
            ),
          );
        }
      }
    }

    return Card(
      elevation: 2, // Un peu d'ombre
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        side: const BorderSide(color: AppTheme.cardBorderColor, width: 0.5),
      ),
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // Important
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  // Pour que le titre prenne la place et gère l'overflow
                  child: Text(
                    'Détail du $formattedDate',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    setState(() {
                      _touchedIndex = null;
                    });
                  }, // Utiliser null est plus propre que -1
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  color: AppTheme.textSecondaryColor, tooltip: 'Fermer',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.electric_bolt,
                    color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: 8),
                const Text('Production: ',
                    style: TextStyle(
                        fontSize: 16, color: AppTheme.textPrimaryColor)),
                Expanded(
                    child: Text('${energyKWh.toStringAsFixed(2)} kWh',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis)),
              ],
            ),
            // const SizedBox(height: 6), // Espacement plus nécessaire

            if (comparisonWidgets.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(
                  height: 1, thickness: 0.5, color: AppTheme.cardBorderColor),
              const SizedBox(height: 8),
              const Text('Comparaison:',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor)),
              ...comparisonWidgets,
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.center,
              child: OutlinedButton.icon(
                icon: const Icon(
                    Icons.access_time), // Icône plus adaptée pour l'horaire
                label: const Text('Voir détail horaire'),
                onPressed: () {
                  Navigator.pushNamed(context, '/daily',
                      arguments: {'selectedDate': selectedDayData!.date});
                },
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    side: BorderSide(
                        color: AppTheme.primaryColor.withOpacity(0.5)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Fonction pour calculer un intervalle Y raisonnable
  double _calculateYInterval(List<double> values) {
    if (values.isEmpty) return 10;
    double maxValue = 0;
    for (var v in values) {
      if (v > maxValue) maxValue = v;
    }
    if (maxValue <= 0) return 10;
    double interval = maxValue / 5.0;
    if (interval <= 0) return 10;

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
    // Assurer un intervalle minimum (par exemple 1) pour éviter des valeurs trop petites
    return max(niceInterval, 1.0);
  }

  // Obtenir une couleur pour les années de comparaison
  Color _getComparisonColor(int index, int total) {
    // Utiliser un set de couleurs prédéfinies pour éviter les HSL complexes
    final colors = [
      AppTheme.chartLine2,
      AppTheme.chartLine3,
      AppTheme.chartLine4,
      Colors.teal.shade300,
      Colors.orange.shade300,
      Colors.purple.shade300,
    ];
    // Ajouter une opacité dégressive pour les années plus anciennes si souhaité
    // double opacity = 0.8 - (index * 0.1).clamp(0.0, 0.5);
    // return colors[index % colors.length].withOpacity(opacity);
    return colors[index % colors.length];
  }

  // Obtenir le nom du mois (inchangé)
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
} // Fin de la classe _MonthlyProductionChartState