// lib/data/services/solar_estimator.dart
import 'dart:math' as math; // Use 'as math' for clarity
import 'package:flutter/foundation.dart'; // For debugPrint
import 'package:intl/intl.dart'; // For DateFormat
import 'package:solaredge_monitor/data/services/weather_manager.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart'; // Import SolarEdgeApiService
import 'package:solaredge_monitor/data/models/user_preferences.dart';
import 'package:solaredge_monitor/data/models/weather_data.dart'; // Import HourlyWeatherData


/// Calculates solar elevation in degrees for a given timestamp, latitude, and longitude.
/// Latitude and longitude should be in RADIANS.
double _solarElevation(DateTime ts, double latRad, double lonRad) {
  // Simplified Julian day calculation
  final d = ts.toUtc().difference(DateTime.utc(ts.year, 1, 1)).inSeconds / 86400.0;
  // Simplified calculation for equation of time components (approximation)
  final g = 2 * math.pi / 365.25 * (d - 1);
  // Solar declination calculation (approximation)
  final declinationRad = 0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g)
                         - 0.006758 * math.cos(2 * g) + 0.000907 * math.sin(2 * g)
                         - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g);
  // Hour angle calculation
  final solarTimeCorrection = 0.0; // Simplified: ignoring equation of time and longitude correction for solar noon
  final hourAngleRad = ((ts.toUtc().hour + ts.toUtc().minute / 60.0 + ts.toUtc().second / 3600.0) - 12 + solarTimeCorrection) * 15 * math.pi / 180.0;

  // Calculate elevation
  final sinElevation = math.sin(latRad) * math.sin(declinationRad) +
                       math.cos(latRad) * math.cos(declinationRad) * math.cos(hourAngleRad);
  // Ensure elevation is within valid asin range [-1, 1] due to approximations
  final elevationRad = math.asin(math.max(-1.0, math.min(1.0, sinElevation)));

  return elevationRad * 180.0 / math.pi; // Convert to degrees
}


class SolarProductionEstimator {
  final WeatherManager weather;
  final SolarEdgeApiService solarEdgeApi; // Add SolarEdgeApiService dependency

  SolarProductionEstimator({required this.weather, required this.solarEdgeApi}); // Update constructor

  /// Fallback function to estimate irradiance based on cloud cover and solar elevation.
  double _irradianceFallback(WeatherData h, double elevDeg) {
    // Calculate clear sky irradiance based on elevation (max 1000 W/m² at zenith)
    // Ensure sin argument is non-negative as elevation can be slightly negative due to calculation/refraction
    final clearSkyIrradiance = 1000 * math.max(0.0, math.sin(elevDeg * math.pi / 180.0));
    // Get cloud cover percentage (0 to 1)
    final cloudCoverFactor = (h.cloudCover ?? 0.0) / 100.0;
    // Reduce clear sky irradiance by cloud cover
    return clearSkyIrradiance * (1.0 - cloudCoverFactor);
  }


  /// Retourne l'énergie totale qu'on peut raisonnablement attendre aujourd'hui (kWh)
  Future<double> estimateTotalDailyEnergy(UserPreferences prefs) async {
    // 1. Récupération de la puissance crête
    final double? pPeakKw = prefs.peakPowerKw;
    if (pPeakKw == null) return 0;

    // 2. Heures de soleil “utiles” prévues par la météo (cloudCover de 0–1)
    // Call getWeatherForecast using cache if possible
    final weatherForecast = await weather.getWeatherForecast(forceRefresh: false); // Use cache
    if (weatherForecast == null) {
      // Handle case where forecast is not available
      return 0;
    }

    // Get location details (handle potential nulls, though WeatherManager provides defaults)
    final latDeg = weather.latitude;
    final lonDeg = weather.longitude;
    if (latDeg == null || lonDeg == null) {
       print("Error: Location not available in WeatherManager for solar estimation.");
       return 0; // Cannot estimate without location
    }
    final latRad = latDeg * math.pi / 180.0;
    final lonRad = lonDeg * math.pi / 180.0;


    // Filter forecast for today's hours only
    final now = DateTime.now();
    final todayForecast = weatherForecast.hourlyForecast
        .where((h) => h.timestamp.year  == now.year &&
                      h.timestamp.month == now.month &&
                      h.timestamp.day   == now.day)
        .toList();

    // 3. Somme de l’irradiance utile, considérant l'élévation solaire
    double kwh = 0;
    for (final hour in todayForecast) { // Use the filtered list
      // Calculate solar elevation for the middle of the hour for better accuracy
      final hourTimestamp = hour.timestamp.add(const Duration(minutes: 30));
      final elevation = _solarElevation(hourTimestamp, latRad, lonRad);

      // Skip calculation if the sun is below the horizon
      if (elevation <= 0) continue;

      // Get irradiance: use provided value or fallback based on elevation
      final irr = hour.shortwaveRadiation ?? _irradianceFallback(hour, elevation); // W/m²

      final eff = 0.78;                  // rendement global (câbles, onduleur…)
      // Calculation based on the provided formula, using elevation-aware irradiance
      final kwhHour = pPeakKw * eff * (irr / 1000.0);  // kWh ≈ kWc × eff × kWh/m²
      kwh += kwhHour;
    }

    // Safety check: if the calculation is still abnormally low, use a heuristic
    if (kwh < 0.5) {
      // Heuristic: "5 full hours" equivalent
      kwh = pPeakKw * 0.78 * 5;
    }

    // 4. Bonus si l’utilisateur a renseigné l’inclinaison / orientation
    if (prefs.panelOrientation == 'Sud') kwh *= 1.05;
    if ((prefs.panelTilt ?? 30) > 35) kwh *= 0.97; // petite pénalité

    return double.parse(kwh.toStringAsFixed(1));   // 0.1 kWh près
  }

  /// Estime l'énergie restant à produire pour le reste de la journée (kWh)
  Future<double> estimateEnergyRestOfDay(UserPreferences prefs) async {
     // 1. Récupération de la puissance crête
    final double? pPeakKw = prefs.peakPowerKw;
    if (pPeakKw == null) return 0;

    // 2. Prévisions météo
    final weatherForecast = await weather.getWeatherForecast(forceRefresh: false); // Use cache if possible (already false, but confirm)
    if (weatherForecast == null) return 0;

    // Get location details
    final latDeg = weather.latitude;
    final lonDeg = weather.longitude;
     if (latDeg == null || lonDeg == null) {
       print("Error: Location not available for rest-of-day estimation.");
       return 0;
    }
    final latRad = latDeg * math.pi / 180.0;
    final lonRad = lonDeg * math.pi / 180.0;

    // Filter forecast for REMAINING hours of today
    final now = DateTime.now();
    final remainingForecast = weatherForecast.hourlyForecast
        .where((h) => h.timestamp.isAfter(now) && // Only future hours
                      h.timestamp.year  == now.year &&
                      h.timestamp.month == now.month &&
                      h.timestamp.day   == now.day)
        .toList();

    // 3. Somme de l’irradiance utile pour les heures restantes
    double kwhRemaining = 0;
    for (final hour in remainingForecast) {
      final hourTimestamp = hour.timestamp.add(const Duration(minutes: 30));
      final elevation = _solarElevation(hourTimestamp, latRad, lonRad);

      if (elevation <= 0) continue;

      final irr = hour.shortwaveRadiation ?? _irradianceFallback(hour, elevation);
      final eff = 0.78;
      final kwhHour = pPeakKw * eff * (irr / 1000.0);
      kwhRemaining += kwhHour;
    }

     // Apply orientation/tilt bonus/penalty (optional, could be removed for simplicity)
    if (prefs.panelOrientation == 'Sud') kwhRemaining *= 1.05;
    if ((prefs.panelTilt ?? 30) > 35) kwhRemaining *= 0.97;

    // Return rounded value
    return double.parse(kwhRemaining.toStringAsFixed(1));
  }

  /// Estime la puissance attendue MAINTENANT en fonction de la météo actuelle et de l'élévation solaire (en W)
  Future<double> estimateExpectedPowerNow(UserPreferences prefs) async {
    // 1. Puissance crête
    final double? pPeakKw = prefs.peakPowerKw;
    if (pPeakKw == null) return 0;

    // 2. Météo actuelle
    final currentWeatherData = await weather.getCurrentWeather(forceRefresh: false); // Use cache
    if (currentWeatherData == null) {
      print("Error: Current weather not available for expected power estimation.");
      return 0; // Cannot estimate without current weather
    }

    // 3. Localisation et élévation solaire actuelle
    final latDeg = weather.latitude;
    final lonDeg = weather.longitude;
    if (latDeg == null || lonDeg == null) {
       print("Error: Location not available for expected power estimation.");
       return 0;
    }
    final latRad = latDeg * math.pi / 180.0;
    final lonRad = lonDeg * math.pi / 180.0;
    final now = DateTime.now();
    final elevation = _solarElevation(now, latRad, lonRad);

    // Si nuit / crépuscule, puissance attendue = 0
    if (elevation <= 0) return 0;

    // 4. Irradiance actuelle (donnée ou fallback basé sur élévation)
    final irr = currentWeatherData.shortwaveRadiation ?? _irradianceFallback(currentWeatherData, elevation); // W/m²

    // 5. Calcul de la puissance attendue (en W)
    final eff = 0.78; // Rendement global
    double expectedPowerW = pPeakKw * 1000 * eff * (irr / 1000.0); // kWc * 1000 * eff * (W/m² / 1000) = W

    // 6. Bonus/Malus orientation/inclinaison (identique à l'estimation journalière)
    if (prefs.panelOrientation == 'Sud') expectedPowerW *= 1.05;
    if ((prefs.panelTilt ?? 30) > 35) expectedPowerW *= 0.97;

    return expectedPowerW; // Retourner la puissance en Watts
  }

  /// Renvoie la puissance PV attendue (W) pour chaque pas horaire restant aujourd’hui.
  Future<List<(DateTime ts, double powerW)>> expectedPowerCurveToday(
      UserPreferences prefs,
      {Duration step = const Duration(minutes: 30)}) async {

    final pPeak = prefs.peakPowerKw;
    if (pPeak == null) {
      debugPrint("SolarProductionEstimator: Peak power not set in preferences. Cannot calculate power curve.");
      return [];
    }

    final fc = await weather.getWeatherForecast(forceRefresh: false);
    if (fc == null) {
      debugPrint("SolarProductionEstimator: Weather forecast not available. Cannot calculate power curve.");
      return [];
    }

    final lat = weather.latitude, lon = weather.longitude;
    if (lat == null || lon == null) {
      debugPrint("SolarProductionEstimator: Location (lat/lon) not available. Cannot calculate power curve.");
      return [];
    }

    final latRad = lat * math.pi / 180, lonRad = lon * math.pi / 180;
    final now = DateTime.now();
    debugPrint("SolarProductionEstimator.expectedPowerCurveToday: Starting curve calculation for ${DateFormat('yyyy-MM-dd').format(now)} with peakPower: $pPeak kW, Lat: $lat, Lon: $lon, Step: ${step.inMinutes} min");

    // On part du prochain “step” entier pour aligner sur 00 / 30 min
    var t = DateTime(now.year, now.month, now.day, now.hour,
        (now.minute ~/ step.inMinutes + 1) * step.inMinutes);

    final List<(DateTime, double)> out = [];

    while (t.day == now.day) {
      // Cherche la météo de l’heure correspondante (≈ centre du pas)
      final h = fc.hourlyForecast.firstWhere(
        (w) => w.timestamp.hour == t.hour && w.timestamp.day == t.day && w.timestamp.month == t.month && w.timestamp.year == t.year, // Ensure it's for the correct day too
        orElse: () {
          // Try to find the closest hour if exact match fails for the current day
          return fc.hourlyForecast.firstWhere(
            (w) => w.timestamp.day == t.day && w.timestamp.month == t.month && w.timestamp.year == t.year,
            orElse: () => WeatherData( 
              timestamp: t, temperature: 0, humidity: 0, windSpeed: 0, condition: 'N/A', iconCode: '', cloudCover: 100, shortwaveRadiation: null
            )
          );
        }
      );

      final elev = _solarElevation(
          t.add(step ~/ 2), // milieu du pas
          latRad,
          lonRad);
      
      double irr = 0;
      double pw = 0;

      if (elev <= 0) {
        // pw remains 0 (nuit)
        debugPrint("SolarProductionEstimator.expectedPowerCurveToday: Time: ${t.toIso8601String()}, Elevation: ${elev.toStringAsFixed(2)} <= 0. Power: 0 W");
      } else {
        irr = h.shortwaveRadiation ?? _irradianceFallback(h, elev);
        pw = pPeak * 1000 * 0.78 * (irr / 1000); // pPeak is in kW, so pPeak * 1000 is W
        if (prefs.panelOrientation == 'Sud') pw *= 1.05;
        if ((prefs.panelTilt ?? 30) > 35) pw *= 0.97;
        debugPrint("SolarProductionEstimator.expectedPowerCurveToday: Time: ${t.toIso8601String()}, WeatherHour: ${h.timestamp.toIso8601String()}, Cloud: ${h.cloudCover}%, Rad: ${h.shortwaveRadiation?.toStringAsFixed(2)}, Elev: ${elev.toStringAsFixed(2)}, CalcIrr: ${irr.toStringAsFixed(2)}, EstPower: ${pw.toStringAsFixed(2)} W");
      }
      out.add((t, pw));
      t = t.add(step);
    }
    debugPrint("SolarProductionEstimator.expectedPowerCurveToday: Curve calculation completed. Points: ${out.length}");
    return out;
  }

  /// Retourne la liste des créneaux (start, end) où la puissance attendue
  /// dépasse `thresholdPct` % de la puissance max prévue de la journée.
  Future<List<(DateTime start, DateTime end)>> highProductionSlots(
      UserPreferences prefs,
      {double thresholdPct = 0.7}) async {

    final curve = await expectedPowerCurveToday(prefs);
    if (curve.isEmpty) return [];

    // Find the maximum power in the curve, handle potential empty list after filtering
    final maxP = curve.isNotEmpty ? curve.map((e) => e.$2).reduce(math.max) : 0.0;
    if (maxP <= 0) return []; // No production expected

    final thr = maxP * thresholdPct;

    List<(DateTime, DateTime)> slots = [];
    DateTime? slotStart;

    // Iterate through the power curve points
    for (int i = 0; i < curve.length; i++) {
      final (ts, pw) = curve[i];
      final isLastPoint = i == curve.length - 1;

      if (pw >= thr) {
        slotStart ??= ts; // Start a new slot if not already in one
      }

      // End the slot if power drops below threshold OR it's the last point and we are in a slot
      if ((pw < thr || isLastPoint) && slotStart != null) {
        // The end time is the timestamp of the *current* point if power dropped,
        // or the timestamp of the *next* interval start if it's the last point.
        // Since 'ts' is the start of the interval, the end is 'ts' + step duration.
        // We need the step duration used in expectedPowerCurveToday. Default is 30 mins.
        // Let's assume the default step for now. A better approach might be to return the step from the curve function.
        final step = const Duration(minutes: 30); // Assuming default step
        final slotEnd = ts.add(step); // End time is the start of the *next* interval

        slots.add((slotStart, slotEnd));
        slotStart = null; // Reset slot start
      }
    }

    // The original logic for the last slot might be slightly off.
    // The loop above handles the last point correctly.
    // The check `if (slotStart != null) slots.add((slotStart, curve.last.$1));`
    // might set the end time incorrectly to the *start* of the last interval.
    // The revised loop logic should be more accurate.

    return slots;
  }

  /// Trouve le meilleur créneau horaire pour lancer un appareil
  /// entre `start` et `end` pour une charge `loadKw` et une durée `durationMin`.
  /// Utilise `highProductionSlots` et filtre les chevauchements.
  Future<List<DateTime>> bestSlotBetween(DateTime start, DateTime end, double loadKw, int durationMin, UserPreferences prefs) async {
    debugPrint("SolarProductionEstimator.bestSlotBetween: Request for load ${loadKw}kW, duration ${durationMin}min, between ${start.toIso8601String()} and ${end.toIso8601String()}");
    final powerCurve = await expectedPowerCurveToday(prefs); // Get the detailed power curve for today
    if (powerCurve.isEmpty) {
      debugPrint("SolarProductionEstimator.bestSlotBetween: Power curve is empty. No slots can be suggested.");
      return []; // No power curve, no slots
    }

    final List<DateTime> suitableStartTimes = [];
    final Duration applianceDuration = Duration(minutes: durationMin);
    final double loadWatts = loadKw * 1000; // Convert load to Watts for comparison with power curve

    // Iterate through all possible start times in the power curve
    for (int i = 0; i < powerCurve.length; i++) {
      final potentialStartTime = powerCurve[i].$1;

      // Check if this potential start time is within the user's requested range [start, end]
      if (potentialStartTime.isBefore(start) || potentialStartTime.isAfter(end.subtract(applianceDuration))) {
        continue; // This start time is outside the user's desired window or too late to complete the cycle
      }

      // Determine the end time of the appliance cycle
      final applianceEndTime = potentialStartTime.add(applianceDuration);

      // Collect all power readings from the curve that fall within this appliance cycle
      List<double> powerReadingsInCycle = [];
      for (final point in powerCurve) {
        // Check if the curve point's timestamp is within the appliance cycle [potentialStartTime, applianceEndTime)
        // The end of the interval for point.$1 is point.$1.add(step_duration_from_curve)
        // For simplicity, we consider the power at point.$1 to be constant for its interval.
        // A more accurate way would be to average over the exact duration.
        if ((point.$1.isAtSameMomentAs(potentialStartTime) || point.$1.isAfter(potentialStartTime)) &&
            point.$1.isBefore(applianceEndTime)) {
          powerReadingsInCycle.add(point.$2);
        }
      }

      // Ensure we have enough data points for the duration
      // The number of points depends on the step used in expectedPowerCurveToday (default 30 min)
      // For a 90 min duration and 30 min step, we'd expect 3 points.
      if (powerReadingsInCycle.isEmpty) { // Or check if count matches expected based on duration/step
        debugPrint("SolarProductionEstimator.bestSlotBetween: Not enough power readings for cycle starting at ${potentialStartTime.toIso8601String()}");
        continue; 
      }

      // Check if ALL power readings during the cycle are >= loadWatts
      // This is a strict check: continuous coverage.
      // An alternative is to check if average power is sufficient.
      bool sufficientPowerThroughout = powerReadingsInCycle.every((power) => power >= loadWatts);
      
      // Calculate average power if needed for a less strict check
      // double averagePowerInCycle = powerReadingsInCycle.reduce((a, b) => a + b) / powerReadingsInCycle.length;
      // bool sufficientAveragePower = averagePowerInCycle >= loadWatts;

      if (sufficientPowerThroughout) {
        debugPrint("SolarProductionEstimator.bestSlotBetween: Found SUITABLE slot starting at ${potentialStartTime.toIso8601String()}. Power readings: $powerReadingsInCycle. Load: $loadWatts W.");
        suitableStartTimes.add(potentialStartTime);
      } else {
        debugPrint("SolarProductionEstimator.bestSlotBetween: Slot starting at ${potentialStartTime.toIso8601String()} NOT suitable. Power readings: $powerReadingsInCycle. Load: $loadWatts W.");
      }
    }
    
    if (suitableStartTimes.isEmpty) {
        debugPrint("SolarProductionEstimator.bestSlotBetween: No suitable slots found after checking power requirements.");
    } else {
        debugPrint("SolarProductionEstimator.bestSlotBetween: Found ${suitableStartTimes.length} suitable slots: ${suitableStartTimes.map((s) => s.toIso8601String()).join(', ')}");
    }
    // TODO: Implement logic to pick the *best* among suitableStartTimes if multiple are found.
    // For now, returning all suitable start times. The AI can pick the first or ask the user.
    return suitableStartTimes;
  }
}
