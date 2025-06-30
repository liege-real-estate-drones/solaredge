import 'package:flutter/material.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';

class MonthYearSelector extends StatefulWidget {
  // Valeurs par défaut statiques
  static final DateTime _defaultMinDate = DateTime(2010, 1, 1);
  static final DateTime _defaultMaxDate = DateTime(2050, 12, 31);
  
  final DateTime initialDate;
  final DateTime minDate;
  final DateTime maxDate;
  final Function(DateTime) onMonthYearChanged;
  final bool showComparisonOptions;
  final List<int> availableYears;
  final List<int> selectedComparisonYears;
  final Function(List<int>)? onComparisonYearsChanged;

  MonthYearSelector({
    super.key,
    required this.initialDate,
    required this.onMonthYearChanged,
    DateTime? minDate,
    DateTime? maxDate,
    this.showComparisonOptions = true,
    this.availableYears = const [],
    this.selectedComparisonYears = const [],
    this.onComparisonYearsChanged,
  }) : 
    minDate = minDate ?? _defaultMinDate,
    maxDate = maxDate ?? _defaultMaxDate;

  @override
  State<MonthYearSelector> createState() => _MonthYearSelectorState();
}

class _MonthYearSelectorState extends State<MonthYearSelector> {
  late DateTime _selectedDate;
  late List<int> _comparisonYears;
  
  // Liste des noms de mois en français
  final List<String> _months = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _comparisonYears = List.from(widget.selectedComparisonYears);
  }

  // Passer au mois précédent
  void _previousMonth() {
    final newDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
    if (newDate.isAfter(widget.minDate) || isSameMonth(newDate, widget.minDate)) {
      setState(() {
        _selectedDate = newDate;
      });
      widget.onMonthYearChanged(newDate);
    }
  }

  // Passer au mois suivant
  void _nextMonth() {
    final newDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
    if (newDate.isBefore(widget.maxDate) || isSameMonth(newDate, widget.maxDate)) {
      setState(() {
        _selectedDate = newDate;
      });
      widget.onMonthYearChanged(newDate);
    }
  }
  
  // Vérifier si deux dates sont le même mois
  bool isSameMonth(DateTime date1, DateTime date2) {
    return date1.year == date2.year && date1.month == date2.month;
  }

  // Gérer le changement d'année
  void _handleYearChanged(int? year) {
    if (year != null) {
      final newDate = DateTime(year, _selectedDate.month, 1);
      setState(() {
        _selectedDate = newDate;
      });
      widget.onMonthYearChanged(newDate);
    }
  }

  // Gérer le changement de mois
  void _handleMonthChanged(int? month) {
    if (month != null) {
      final newDate = DateTime(_selectedDate.year, month, 1);
      setState(() {
        _selectedDate = newDate;
      });
      widget.onMonthYearChanged(newDate);
    }
  }
  
  // Gérer les années de comparaison
  void _handleComparisonYearToggle(int year, bool selected) {
    setState(() {
      if (selected) {
        if (!_comparisonYears.contains(year)) {
          _comparisonYears.add(year);
        }
      } else {
        _comparisonYears.remove(year);
      }
    });
    
    if (widget.onComparisonYearsChanged != null) {
      widget.onComparisonYearsChanged!(_comparisonYears);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculer la liste des années disponibles pour le dropdown
    final currentYear = DateTime.now().year;
    final yearList = List<int>.generate(
      currentYear - widget.minDate.year + 1,
      (i) => widget.minDate.year + i,
    ).reversed.toList();

    // Liste des années disponibles pour la comparaison
    // Par défaut, ce sont les 5 années précédant l'année sélectionnée
    final comparisonYearsList = widget.availableYears.isEmpty
        ? List<int>.generate(
            5,
            (i) => _selectedDate.year - i - 1,
          ).where((year) => year >= widget.minDate.year).toList()
        : widget.availableYears.where((year) => year != _selectedDate.year).toList();

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
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sélecteur de mois et d'année
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _previousMonth,
                  tooltip: 'Mois précédent',
                ),
                
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Dropdown pour le mois
                      DropdownButton<int>(
                        value: _selectedDate.month,
                        underline: Container(
                          height: 1,
                          color: AppTheme.primaryColor,
                        ),
                        items: List.generate(12, (index) {
                          final month = index + 1;
                          return DropdownMenuItem(
                            value: month,
                            child: Text(_months[index]),
                          );
                        }),
                        onChanged: _handleMonthChanged,
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Dropdown pour l'année
                      DropdownButton<int>(
                        value: _selectedDate.year,
                        underline: Container(
                          height: 1,
                          color: AppTheme.primaryColor,
                        ),
                        items: yearList.map((year) {
                          return DropdownMenuItem(
                            value: year,
                            child: Text(year.toString()),
                          );
                        }).toList(),
                        onChanged: _handleYearChanged,
                      ),
                    ],
                  ),
                ),
                
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _nextMonth,
                  tooltip: 'Mois suivant',
                ),
              ],
            ),
            
            // Options de comparaison (optionnel)
            if (widget.showComparisonOptions && comparisonYearsList.isNotEmpty) ...[
              const Divider(height: 24),
              
              const Text(
                'Comparer avec:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimaryColor,
                ),
              ),
              
              const SizedBox(height: 8),
              
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: comparisonYearsList.map((year) {
                  final isSelected = _comparisonYears.contains(year);
                  return FilterChip(
                    label: Text(year.toString()),
                    selected: isSelected,
                    onSelected: (selected) => _handleComparisonYearToggle(year, selected),
                    backgroundColor: AppTheme.cardColor,
                    selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                    checkmarkColor: AppTheme.primaryColor,
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondaryColor,
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
