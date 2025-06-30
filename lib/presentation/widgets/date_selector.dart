import 'package:flutter/material.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:intl/intl.dart';

class DateSelector extends StatelessWidget {
  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;
  final DateTime? minDate;
  final DateTime? maxDate;
  
  const DateSelector({
    super.key,
    required this.selectedDate,
    required this.onDateChanged,
    this.minDate,
    this.maxDate,
  });

  @override
  Widget build(BuildContext context) {
    // Formater les dates pour l'affichage
    final dateFormat = DateFormat.yMMMMd('fr_FR');
    final dayFormat = DateFormat('EEEE', 'fr_FR');
    
    // Vérifier si c'est aujourd'hui, hier, ou un autre jour
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final selectedDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
    
    String dateLabel;
    if (selectedDay == today) {
      dateLabel = "Aujourd'hui";
    } else if (selectedDay == yesterday) {
      dateLabel = "Hier";
    } else {
      dateLabel = _capitalizeFirstLetter(dayFormat.format(selectedDate));
    }
    
    return Card(
      elevation: 0,
      margin: const EdgeInsets.all(0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.borderRadius),
        side: const BorderSide(color: AppTheme.cardBorderColor, width: 0.5),
      ),
      color: AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Bouton pour naviguer au jour précédent
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _canGoToPreviousDay() 
                ? () => _goToPreviousDay() 
                : null,
              color: _canGoToPreviousDay() 
                ? AppTheme.primaryColor 
                : AppTheme.textSecondaryColor.withOpacity(0.5),
            ),
            
            // Affichage de la date actuelle et accès au calendrier
            Expanded(
              child: InkWell(
                onTap: () => _showDatePicker(context),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                    ),
                    Text(
                      dateFormat.format(selectedDate),
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Bouton pour naviguer au jour suivant
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _canGoToNextDay() 
                ? () => _goToNextDay() 
                : null,
              color: _canGoToNextDay() 
                ? AppTheme.primaryColor 
                : AppTheme.textSecondaryColor.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }
  
  // Vérifier si on peut naviguer au jour précédent
  bool _canGoToPreviousDay() {
    if (minDate == null) return true;
    
    final previousDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day - 1,
    );
    
    return !previousDay.isBefore(minDate!);
  }
  
  // Vérifier si on peut naviguer au jour suivant
  bool _canGoToNextDay() {
    if (maxDate == null) return true;
    
    final nextDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day + 1,
    );
    
    return !nextDay.isAfter(maxDate!);
  }
  
  // Naviguer au jour précédent
  void _goToPreviousDay() {
    final previousDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day - 1,
    );
    
    onDateChanged(previousDay);
  }
  
  // Naviguer au jour suivant
  void _goToNextDay() {
    final nextDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day + 1,
    );
    
    onDateChanged(nextDay);
  }
  
  // Afficher le sélecteur de date
  void _showDatePicker(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: minDate ?? DateTime(2010),
      lastDate: maxDate ?? DateTime.now(),
      locale: const Locale('fr', 'FR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryColor,
              surface: AppTheme.cardColor,
              onSurface: AppTheme.textPrimaryColor,
            ),
            dialogBackgroundColor: AppTheme.backgroundColor,
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null && picked != selectedDate) {
      onDateChanged(picked);
    }
  }
  
  // Mettre en majuscule la première lettre
  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}
