import 'package:flutter/foundation.dart';

/// Classe utilitaire pour la gestion des unités de puissance et d'énergie
/// Centralise toutes les conversions et le formatage pour assurer la cohérence dans l'application
///
/// IMPORTANT : L'API SolarEdge retourne déjà les valeurs en Watts (W), pas en kilowatts (kW).
/// Ne pas appliquer de conversion supplémentaire sur les données brutes de l'API !
class PowerUtils {
  // Constantes pour la conversion d'unités
  static const double _WATTS_TO_KILOWATTS = 0.001;
  static const double _KILOWATTS_TO_WATTS = 1000.0;
  
  /// Convertit une valeur de kW en W
  /// ATTENTION : À utiliser uniquement si vous êtes sûr que la valeur est en kW.
  /// Les données de l'API SolarEdge sont déjà en W et ne nécessitent pas cette conversion.
  static double kWtoW(double powerInKW) {
    // Vérifier que la valeur n'est pas négative
    if (powerInKW < 0) {
      debugPrint('⚠️ Tentative de conversion d\'une valeur négative de kW à W: $powerInKW');
      return 0.0;
    }
    
    final result = powerInKW * _KILOWATTS_TO_WATTS;
    debugPrint('🔄 Conversion kW → W: $powerInKW kW → $result W');
    return result;
  }
  
  /// Convertit une valeur de W en kW
  static double WtokW(double powerInW) {
    // Vérifier que la valeur n'est pas négative
    if (powerInW < 0) {
      debugPrint('⚠️ Tentative de conversion d\'une valeur négative de W à kW: $powerInW');
      return 0.0;
    }
    
    final result = powerInW * _WATTS_TO_KILOWATTS;
    debugPrint('🔄 Conversion W → kW: $powerInW W → $result kW');
    return result;
  }
  
  /// Convertit l'énergie en Wh (watt-heures) vers kWh (kilowatt-heures)
  static double WhTokWh(double energyInWh) {
    // Vérifier que la valeur n'est pas négative
    if (energyInWh < 0) {
      debugPrint('⚠️ Tentative de conversion d\'une valeur négative de Wh à kWh: $energyInWh');
      return 0.0;
    }
    
    return energyInWh * _WATTS_TO_KILOWATTS;
  }
  
  /// Convertit l'énergie en kWh (kilowatt-heures) vers Wh (watt-heures)
  static double kWhToWh(double energyInkWh) {
    // Vérifier que la valeur n'est pas négative
    if (energyInkWh < 0) {
      debugPrint('⚠️ Tentative de conversion d\'une valeur négative de kWh à Wh: $energyInkWh');
      return 0.0;
    }
    
    return energyInkWh * _KILOWATTS_TO_WATTS;
  }
  
  /// Formate une valeur de puissance en W pour l'affichage
  static String formatWatts(double powerInW, {int decimals = 2}) {
    // Arrondir à N décimales et formater
    final formattedValue = powerInW.toStringAsFixed(decimals);
    return '$formattedValue W';
  }
  
  /// Formate une valeur d'énergie en kWh pour l'affichage
  static String formatEnergyKWh(double energyInWh, {int decimals = 2}) {
    // Convertir en kWh, arrondir à N décimales et formater
    final energyInkWh = WhTokWh(energyInWh);
    final formattedValue = energyInkWh.toStringAsFixed(decimals);
    return '$formattedValue kWh';
  }
  
  /// Calcule le pourcentage par rapport à une puissance maximale
  static double calculatePowerPercentage(double currentPowerW, double maxPowerW) {
    if (maxPowerW <= 0) {
      debugPrint('⚠️ Calcul de pourcentage avec une puissance maximale invalide: $maxPowerW');
      return 0.0;
    }
    
    // Limiter le pourcentage à 1.0 (100%)
    final percentage = (currentPowerW / maxPowerW).clamp(0.0, 1.0);
    return percentage;
  }
  
  /// Obtient une estimation de la puissance crête de l'installation
  /// Basée sur les données stockées ou une valeur par défaut
  static double getDefaultPeakPowerW() {
    // Par défaut, on suppose une installation de 10kW
    return 10000.0; // 10kW = 10000W
  }
}
