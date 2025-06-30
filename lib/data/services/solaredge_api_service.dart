import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math'; // Pour min() dans _handleResponse et max() pour le fallback

import 'package:flutter/foundation.dart'; // Pour debugPrint
import 'package:http/http.dart' as http;
import 'package:solaredge_monitor/data/models/solar_data.dart';
import 'package:solaredge_monitor/data/services/location_service.dart'; // Assurez-vous d'avoir ce service si utilisé
import 'package:shared_preferences/shared_preferences.dart'; // Assurez-vous d'avoir ce package si utilisé pour site_name etc.
import 'package:solaredge_monitor/utils/power_utils.dart'; // Assurez-vous d'avoir cet utilitaire
import 'package:solaredge_monitor/utils/file_logger.dart'; // Pour le logging

// Définir un alias pour SolarEdgeApiException pour éviter les conflits si importé ailleurs
import 'package:solaredge_monitor/data/models/api_exceptions.dart'
    as api_exceptions;

class SolarEdgeApiService {
  final String baseUrl = 'https://monitoringapi.solaredge.com/site/';
  final String apiKey;
  final String siteId;

  SolarEdgeApiService({required this.apiKey, required this.siteId});

  // Cache
  final Map<String, dynamic> _cache = {};
  final Map<String, DateTime> _cacheExpiry = {};
  static const Duration _powerdataCacheDuration = Duration(minutes: 5);
  static const Duration _dailyCacheDuration = Duration(hours: 1);
  static const Duration _monthlyCacheDuration = Duration(hours: 12);
  static const Duration _yearlyCacheDuration = Duration(days: 1);

  // Rate Limiting
  static const Duration _apiCallDelay = Duration(milliseconds: 500);
  static DateTime _lastApiCall = DateTime(2000);

  // Helper pour construire les URLs
  Uri _buildUri(String endpoint, Map<String, String> queryParams) {
    final params = {
      'api_key': apiKey,
      ...queryParams,
    };
    if (siteId.isEmpty) {
      throw ArgumentError('Site ID cannot be empty');
    }
    return Uri.parse('$baseUrl$siteId/$endpoint')
        .replace(queryParameters: params);
  }

  // Helper pour gérer les réponses HTTP et les erreurs
  dynamic _handleResponse(http.Response response, String errorContext) {
    final logger = FileLogger(); // Obtenir instance du logger
    logger.log(
        'INFO: API Response Status: ${response.statusCode} for $errorContext',
        stackTrace: StackTrace.current); // Ajout INFO: et stackTrace
    dynamic decodedBody;
    String rawBody = response.body;
    String detailedErrorMessage = errorContext;

    try {
      if (rawBody.isNotEmpty) {
        decodedBody = json.decode(rawBody);
        // Tenter d'extraire le message d'erreur standard SolarEdge
        if (decodedBody is Map<String, dynamic> &&
            decodedBody.containsKey('String') &&
            decodedBody['String'] is Map) {
          final errorDetails = decodedBody['String'];
          if (errorDetails.containsKey('code') &&
              errorDetails.containsKey('message')) {
            detailedErrorMessage =
                'API Error ${errorDetails['code']}: ${errorDetails['message']}';
          }
        } else if (decodedBody is Map<String, dynamic> &&
            decodedBody.containsKey('error') &&
            decodedBody['error'] is Map &&
            decodedBody['error'].containsKey('message')) {
          detailedErrorMessage =
              'API Error: ${decodedBody['error']['message']}';
        } else {
          // Pas de structure d'erreur reconnue
        }
      } else {
        detailedErrorMessage =
            'lors de $errorContext: Code ${response.statusCode}, Body: (empty)';
        if (response.statusCode == 200) {
          throw api_exceptions.SolarEdgeApiException(
            // Utiliser l'alias
            'Réponse invalide reçue du serveur (corps vide)',
            errorType: api_exceptions
                .SolarEdgeErrorType.INVALID_RESPONSE, // Utiliser l'alias
            statusCode: response.statusCode,
          );
        }
      }
    } catch (e, s) {
      // Capture stacktrace here
      logger.log(
          'ERROR: Could not decode response body for $errorContext: $e. Raw body: ${rawBody.substring(0, min(rawBody.length, 200))}...',
          stackTrace: s); // Ajout ERROR: et utilisation du stacktrace 's'
      detailedErrorMessage =
          'lors de $errorContext: Code ${response.statusCode}, Body (non-JSON): ${rawBody.length > 200 ? '${rawBody.substring(0, 200)}...' : rawBody}';
      if (response.statusCode == 200) {
        throw api_exceptions.SolarEdgeApiException(
          // Utiliser l'alias
          'Réponse invalide reçue du serveur (corps non-JSON valide)',
          errorType: api_exceptions
              .SolarEdgeErrorType.INVALID_RESPONSE, // Utiliser l'alias
          statusCode: response.statusCode,
          originalError: e,
        );
      }
    }

    if (response.statusCode == 200) {
      if (decodedBody == null &&
          rawBody.isNotEmpty &&
          rawBody.toLowerCase() == 'null') {
        logger.log(
            'WARNING: API $errorContext returned 200 OK with literal "null" body.',
            stackTrace: StackTrace.current); // Ajout WARNING: et stackTrace
        throw api_exceptions.SolarEdgeApiException(
          // Utiliser l'alias
          'Réponse invalide reçue du serveur (contenu décodé est null)',
          errorType: api_exceptions
              .SolarEdgeErrorType.INVALID_RESPONSE, // Utiliser l'alias
          statusCode: response.statusCode,
        );
      }
      logger.log(
          'INFO: API Response Decoded Body for $errorContext: $decodedBody',
          stackTrace: StackTrace.current); // Ajout INFO: et stackTrace
      return decodedBody;
    } else if (response.statusCode == 401) {
      throw api_exceptions.SolarEdgeApiException(
        // Utiliser l'alias
        detailedErrorMessage.contains('API Error')
            ? detailedErrorMessage
            : 'Authentification échouée (401). Vérifiez clé API/Site ID.',
        errorType: api_exceptions
            .SolarEdgeErrorType.INVALID_API_KEY, // Utiliser l'alias
        statusCode: response.statusCode,
      );
    } else if (response.statusCode == 403) {
      throw api_exceptions.SolarEdgeApiException(
        // Utiliser l'alias
        detailedErrorMessage.contains('API Error')
            ? detailedErrorMessage
            : 'Accès refusé (403). Vérifiez permissions clé API.',
        errorType: api_exceptions
            .SolarEdgeErrorType.INVALID_API_KEY, // Utiliser l'alias
        statusCode: response.statusCode,
      );
    } else if (response.statusCode == 404) {
      throw api_exceptions.SolarEdgeApiException(
        // Utiliser l'alias
        detailedErrorMessage.contains('API Error')
            ? detailedErrorMessage
            : 'Site non trouvé (404). Vérifiez ID Site.',
        errorType: api_exceptions
            .SolarEdgeErrorType.INVALID_SITE_ID, // Utiliser l'alias
        statusCode: response.statusCode,
      );
    } else if (response.statusCode == 429) {
      throw api_exceptions.SolarEdgeApiException(
        // Utiliser l'alias
        detailedErrorMessage.contains('API Error')
            ? detailedErrorMessage
            : 'Trop de requêtes (429). Veuillez patienter.',
        errorType: api_exceptions
            .SolarEdgeErrorType.RATE_LIMIT_EXCEEDED, // Utiliser l'alias
        statusCode: response.statusCode,
      );
    } else if (response.statusCode >= 500) {
      throw api_exceptions.SolarEdgeApiException(
        // Utiliser l'alias
        detailedErrorMessage.contains('API Error')
            ? detailedErrorMessage
            : 'Erreur serveur SolarEdge (${response.statusCode}).',
        errorType:
            api_exceptions.SolarEdgeErrorType.SERVER_ERROR, // Utiliser l'alias
        statusCode: response.statusCode,
      );
    } else {
      throw api_exceptions.SolarEdgeApiException(
        // Utiliser l'alias
        detailedErrorMessage.contains('API Error')
            ? detailedErrorMessage
            : 'Erreur API inattendue (${response.statusCode}) lors de $errorContext',
        errorType:
            api_exceptions.SolarEdgeErrorType.UNKNOWN_ERROR, // Utiliser l'alias
        statusCode: response.statusCode,
      );
    }
  }

  // Méthode pour respecter le délai API
  Future<void> _respectApiRateLimit() async {
    final now = DateTime.now();
    final timeSinceLastCall = now.difference(_lastApiCall);
    if (timeSinceLastCall < _apiCallDelay) {
      final waitTime = _apiCallDelay - timeSinceLastCall;
      debugPrint(// debugPrint is fine, no need to log excessively here
          '⏱️ Attente de ${waitTime.inMilliseconds}ms pour respecter la limite d\'API');
      await Future.delayed(waitTime);
    }
    _lastApiCall = DateTime.now();
  }

  // Méthode générique pour faire un appel API
  Future<dynamic> _makeApiCall(String endpoint, Map<String, String> queryParams,
      String errorContext) async {
    // Utiliser le logger global fileLogger
    await fileLogger.initialize(); // Assurer l'initialisation

    if (apiKey.isEmpty) {
      throw api_exceptions.SolarEdgeApiException(
          'Clé API non fournie au service.', // Utiliser l'alias
          errorType: api_exceptions
              .SolarEdgeErrorType.CONFIG_ERROR); // Utiliser l'alias
    }
    if (siteId.isEmpty) {
      throw api_exceptions.SolarEdgeApiException(
          'ID de Site non fourni au service.', // Utiliser l'alias
          errorType: api_exceptions
              .SolarEdgeErrorType.CONFIG_ERROR); // Utiliser l'alias
    }

    await _respectApiRateLimit();
    final uri = _buildUri(endpoint, queryParams);
    fileLogger.log('INFO: 🌍 Appel API vers: $uri',
        stackTrace: StackTrace.current);

    try {
      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 20));

      return _handleResponse(response, errorContext);
    } on TimeoutException catch (e, s) {
      fileLogger.log('ERROR: ❌ Timeout lors de $errorContext: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException(
          // Utiliser l'alias
          'Le serveur SolarEdge n\'a pas répondu à temps.',
          errorType: api_exceptions
              .SolarEdgeErrorType.NETWORK_ERROR, // Utiliser l'alias
          originalError: e);
    } on SocketException catch (e, s) {
      fileLogger.log(
          'ERROR: ❌ Erreur réseau (Socket) lors de $errorContext: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException(
          // Utiliser l'alias
          'Impossible de joindre le serveur SolarEdge. Vérifiez la connexion.',
          errorType: api_exceptions
              .SolarEdgeErrorType.NETWORK_ERROR, // Utiliser l'alias
          originalError: e);
    } on http.ClientException catch (e, s) {
      fileLogger.log(
          'ERROR: ❌ Erreur réseau (Client) lors de $errorContext: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException(
          'Erreur de connexion réseau: ${e.message}', // Utiliser l'alias
          errorType: api_exceptions
              .SolarEdgeErrorType.NETWORK_ERROR, // Utiliser l'alias
          originalError: e);
    } on api_exceptions.SolarEdgeApiException {
      // Utiliser l'alias
      rethrow;
    } catch (e, s) {
      fileLogger.log(
          'ERROR: ❌ Erreur inattendue générique lors de $errorContext: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException(
        // Utiliser l'alias
        'Erreur inattendue lors de $errorContext: ${e.toString()}',
        errorType: api_exceptions
              .SolarEdgeErrorType.UNKNOWN_ERROR, // Utiliser l'alias
        originalError: e,
      );
    }
  }

  Future<bool> checkConnection() async {
    final logger = FileLogger();
    logger.log(
        'INFO: 🚦 Test de connexion demandé (vérification type réponse incluse)...',
        stackTrace: StackTrace.current);
    try {
      final dynamic responseData =
          await _makeApiCall('details', {}, 'test de connexion (details)');

      if (responseData is Map<String, dynamic>) {
        if (responseData.containsKey('details')) {
          logger.log(
              'INFO: ✅ Test de connexion réussi (Réponse de /details est une Map contenant "details").',
              stackTrace: StackTrace.current);
          return true;
        } else {
          logger.log(
              'WARNING: ❌ Test de connexion échoué: La réponse de /details est une Map, mais il manque la clé "details". Réponse: $responseData',
              stackTrace: StackTrace.current);
          return false;
        }
      } else {
        logger.log(
            'WARNING: ❌ Test de connexion échoué: La réponse de /details (status 200 OK) n\'est pas une Map valide. Type reçu: ${responseData?.runtimeType}, Données reçues: $responseData',
            stackTrace: StackTrace.current);
        return false;
      }
    } on api_exceptions.SolarEdgeApiException catch (e, s) {
      // Utiliser l'alias
      logger.log(
          'ERROR: ❌ Test de connexion échoué (SolarEdgeApiException): ${e.message} (Type: ${e.errorType})',
          stackTrace: s);
      return false;
    } catch (e, s) {
      logger.log(
          'ERROR: ❌ Test de connexion échoué (Erreur inattendue globale): $e',
          stackTrace: s);
      return false;
    }
  }

  Future<SolarData> getCurrentPowerData() async {
    final String errorContext =
        'la récupération des données en temps réel (overview)';
    final logger = FileLogger();
    final cacheKey = 'current_power';

    if (_isCacheValid(cacheKey, _powerdataCacheDuration)) {
      logger.log('INFO: 📋 Utilisation cache pour puissance actuelle', stackTrace: StackTrace.current);
      final cachedData = _cache[cacheKey];
      if (cachedData is SolarData) {
        return cachedData;
      } else {
        logger.log('WARNING: Cache pour $cacheKey invalide (type ${cachedData?.runtimeType}), rechargement...', stackTrace: StackTrace.current);
      }
    }

    try {
      final dynamic data = await _makeApiCall('overview', {}, errorContext);

      if (data is! Map<String, dynamic>) {
        throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
          'Format de réponse inattendu pour $errorContext (attendu: Map). Reçu: ${data?.runtimeType}',
          errorType: api_exceptions.SolarEdgeErrorType.INVALID_RESPONSE, // Utiliser l'alias
        );
      }

      if (data.containsKey('overview') &&
          data['overview'] is Map<String, dynamic>) {
        final overviewData = data['overview'] as Map<String, dynamic>;
        if (overviewData.containsKey('currentPower') &&
            overviewData['currentPower'] is Map<String, dynamic>) {
          final powerData =
              overviewData['currentPower'] as Map<String, dynamic>;
          if (powerData.containsKey('power')) {
            var powerValue = powerData['power'];
            double currentPowerW = 0.0;
            if (powerValue is num) {
              currentPowerW = powerValue.toDouble();
            } else if (powerValue is String) {
              currentPowerW = double.tryParse(powerValue.trim()) ?? 0.0;
            }
            logger.log(
                'INFO: 🔌 Puissance actuelle (overview): ${PowerUtils.formatWatts(currentPowerW)}',
                stackTrace: StackTrace.current);
            final result = SolarData(timestamp: DateTime.now(), power: currentPowerW, energy: 0,);
            _saveToCache(cacheKey, result, _powerdataCacheDuration);
            return result;
          }
        }
      }
      logger.log('WARNING: ⚠️ Structure currentPower non trouvée dans /overview',
          stackTrace: StackTrace.current);
      throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
        'Impossible d\'extraire currentPower depuis /overview.',
        errorType: api_exceptions.SolarEdgeErrorType.INVALID_RESPONSE, // Utiliser l'alias
      );
    } on api_exceptions.SolarEdgeApiException { // Utiliser l'alias
      rethrow;
    } catch (e, s) {
      logger.log('ERROR: ❌ Erreur inattendue dans getCurrentPowerData: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
        'Erreur inattendue GetPower: ${e.toString()}',
        errorType: api_exceptions.SolarEdgeErrorType.UNKNOWN_ERROR, // Utiliser l'alias
        originalError: e,
      );
    }
  }

  /// Récupère l'énergie totale produite aujourd'hui.
  Future<double> getEnergyProducedToday() async {
    final String errorContext = 'la récupération de l\'énergie produite aujourd\'hui';
    final logger = FileLogger();
    final cacheKey = 'energy_today';

    if (_isCacheValid(cacheKey, _powerdataCacheDuration)) {
      logger.log('INFO: 📋 Utilisation cache pour énergie aujourd\'hui', stackTrace: StackTrace.current);
      final cachedData = _cache[cacheKey];
      if (cachedData is double) {
        return cachedData;
      } else {
        logger.log('WARNING: Cache pour $cacheKey invalide (type ${cachedData?.runtimeType}), rechargement...', stackTrace: StackTrace.current);
      }
    }

    try {
      final dynamic data = await _makeApiCall('overview', {}, errorContext);

      if (data is! Map<String, dynamic>) {
        throw api_exceptions.SolarEdgeApiException(
          'Format de réponse inattendu pour $errorContext (attendu: Map). Reçu: ${data?.runtimeType}',
          errorType: api_exceptions.SolarEdgeErrorType.INVALID_RESPONSE,
        );
      }

      if (data.containsKey('overview') &&
          data['overview'] is Map<String, dynamic>) {
        final overviewData = data['overview'] as Map<String, dynamic>;
        if (overviewData.containsKey('lastDayData') &&
            overviewData['lastDayData'] is Map<String, dynamic>) {
          final lastDayData = overviewData['lastDayData'] as Map<String, dynamic>;
          if (lastDayData.containsKey('energy')) {
            var energyValue = lastDayData['energy'];
            double energyTodayWh = 0.0;
            if (energyValue is num) {
              energyTodayWh = energyValue.toDouble();
            } else if (energyValue is String) {
              energyTodayWh = double.tryParse(energyValue.trim()) ?? 0.0;
            }
            // L'API retourne l'énergie en Wh, l'estimateur attend des kWh
            final energyTodayKwh = energyTodayWh / 1000.0;
            logger.log(
                'INFO: ⚡ Énergie produite aujourd\'hui (overview): ${energyTodayKwh.toStringAsFixed(3)} kWh',
                stackTrace: StackTrace.current);
            _saveToCache(cacheKey, energyTodayKwh, _powerdataCacheDuration);
            return energyTodayKwh;
          }
        }
      }
      logger.log('WARNING: ⚠️ Structure lastDayData ou energy non trouvée dans /overview',
          stackTrace: StackTrace.current);
      // Retourner 0 si les données ne sont pas trouvées, ne pas lever d'exception bloquante
      return 0.0;
    } on api_exceptions.SolarEdgeApiException {
      rethrow; // Rethrow known API exceptions
    } catch (e, s) {
      logger.log('ERROR: ❌ Erreur inattendue dans getEnergyProducedToday: $e',
          stackTrace: s);
      // Retourner 0 en cas d'erreur inattendue pour ne pas bloquer l'estimation
      return 0.0;
    }
  }

  // --- Cache Helpers ---
  bool _isCacheValid(String cacheKey, Duration validityDuration) {
    if (!_cache.containsKey(cacheKey)) return false;
    final expiry = _cacheExpiry[cacheKey];
    if (expiry == null) return false;
    return DateTime.now().isBefore(expiry);
  }

  void _saveToCache(String cacheKey, dynamic data, Duration validityDuration) {
    final logger = FileLogger();
    _cache[cacheKey] = data;
    _cacheExpiry[cacheKey] = DateTime.now().add(validityDuration);
    logger.log(
        'INFO: 💾 Données sauvegardées en cache: $cacheKey (expire le ${_cacheExpiry[cacheKey]})',
        stackTrace: StackTrace.current);
  }

  Future<DailySolarData> getDailyEnergy(DateTime date) async {
    final logger = FileLogger();
    final String dateStr = _formatDate(date);
    final cacheKey = 'daily_$dateStr';

    if (_isCacheValid(cacheKey, _dailyCacheDuration)) {
      logger.log('INFO: 📋 Utilisation cache pour jour $dateStr',
          stackTrace: StackTrace.current);
      final cachedData = _cache[cacheKey];
      if (cachedData is DailySolarData) {
        return cachedData;
      } else {
        logger.log(
            'WARNING: Cache pour $cacheKey invalide (type ${cachedData?.runtimeType}), rechargement...',
            stackTrace: StackTrace.current);
      }
    }

    try {
      // 1. Récupérer l'énergie totale et les données horaires
      final dynamic hourlyEnergyData = await _makeApiCall(
          'energy',
          {
            'startDate': dateStr,
            'endDate': dateStr,
            'timeUnit': 'HOUR', // Utiliser HOUR pour les données horaires
          },
          'récupération énergie horaire pour jour');

      if (hourlyEnergyData is! Map<String, dynamic> ||
          !hourlyEnergyData.containsKey('energy') ||
          hourlyEnergyData['energy'] is! Map ||
          !(hourlyEnergyData['energy'] as Map).containsKey('values') ||
          hourlyEnergyData['energy']['values'] is! List) {
        throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
            'Format réponse énergie horaire invalide',
            errorType: api_exceptions.SolarEdgeErrorType.INVALID_RESPONSE); // Utiliser l'alias
      }
      final hourlyEnergyValues = hourlyEnergyData['energy']['values'] as List;

      final List<SolarData> hourlyDataResult = [];
      double totalEnergyResult = 0;

      for (var entry in hourlyEnergyValues) {
        if (entry is Map<String, dynamic>) {
          final DateTime? timestamp =
              DateTime.tryParse(entry['date'] as String? ?? '');
          final double energy = (entry['value'] as num?)?.toDouble() ?? 0.0;
          if (timestamp != null) {
            totalEnergyResult += energy;
            // Pour les données horaires, la puissance instantanée n'est pas directement donnée ici,
            // mais l'énergie est l'accumulation sur l'heure. On peut laisser power à 0 ou estimer.
            // Laissons power à 0 ici, car powerDetails donne la puissance instantanée.
            hourlyDataResult
                .add(SolarData(timestamp: timestamp, power: 0, energy: energy));
          }
        }
      }

      // 2. Récupérer le pic de puissance
      double peakPowerResult = 0; // Initialisation à 0
      logger.log('DEBUG: Appel API pour powerDetails journalier...', stackTrace: StackTrace.current);
      try {
        final String startTime = '$dateStr 00:00:00';
        final String endTime = '$dateStr 23:59:59';

        final dynamic powerDetailsData = await _makeApiCall(
            'powerDetails',
            {
              'startTime': startTime,
              'endTime': endTime,
            },
            'récupération détails puissance journalière');

        logger.log('DEBUG: Réponse reçue pour powerDetails journalier. Traitement des données...', stackTrace: StackTrace.current);

        if (powerDetailsData is Map<String, dynamic> &&
            powerDetailsData.containsKey('powerDetails') &&
            powerDetailsData['powerDetails'] is Map) {
          final powerDetails =
              powerDetailsData['powerDetails'] as Map<String, dynamic>;
          if (powerDetails.containsKey('meters') &&
              powerDetails['meters'] is List) {
            final meterTelemetries = powerDetails['meters'] as List;
            for (var meter in meterTelemetries) {
              if (meter is Map<String, dynamic> &&
                  meter['type'] == 'Production' &&
                  meter.containsKey('values') &&
                  meter['values'] is List) {
                final values = meter['values'] as List;
                for (var valueEntry in values) {
                  if (valueEntry is Map<String, dynamic>) {
                    final double power =
                        (valueEntry['value'] as num?)?.toDouble() ?? 0.0;
                    if (power > peakPowerResult) peakPowerResult = power; // Utiliser peakPowerResult
                  }
                }
              }
            }
          }
          logger.log('DEBUG: Traitement powerDetails journalier terminé. Pic de puissance: $peakPowerResult W', stackTrace: StackTrace.current);
        } else {
           logger.log('WARNING: Structure powerDetails journalier inattendue ou vide.', stackTrace: StackTrace.current);
           // NE PAS lever d'exception ici, on va tenter le fallback
        }

      } catch (e, s) { // Attraper toutes les erreurs (API, parsing, etc.) liées à powerDetails
        logger.log('WARNING: ⚠️ Impossible de récupérer pic puissance jour via powerDetails: ${e.toString()}', stackTrace: s);

        // --- FALLBACK LOGIC ---
        // Estimer le pic à partir des données horaires si powerDetails a échoué
        if (hourlyEnergyValues.isNotEmpty) { // Assurer qu'on a des données horaires
            double maxHourlyEnergyDiff = 0;
            // Trier par date pour être sûr (normalement déjà fait par l'API mais sécurité)
            hourlyEnergyValues.sort((a,b) {
               final dateA = DateTime.tryParse(a?['date'] as String? ?? '');
               final dateB = DateTime.tryParse(b?['date'] as String? ?? '');
               if (dateA == null || dateB == null) return 0;
               return dateA.compareTo(dateB);
            });

            // Calculer la différence max (qui approxime la puissance horaire max en W)
            for (int i = 0; i < hourlyEnergyValues.length; i++) {
                final currentEnergy = (hourlyEnergyValues[i]?['value'] as num?)?.toDouble() ?? 0.0;
                 // La différence simple n'est pas le pic, c'est l'énergie de l'heure.
                 // Une meilleure approx. est de prendre la plus grande valeur d'énergie horaire
                 // car 1000 Wh sur 1h = 1000W de puissance moyenne.
                if (currentEnergy > maxHourlyEnergyDiff) {
                   maxHourlyEnergyDiff = currentEnergy;
                }
            }

             // S'assurer que le pic calculé est au moins aussi grand que l'énergie max sur une heure
             peakPowerResult = max(peakPowerResult, maxHourlyEnergyDiff);
             logger.log('INFO: Pic puissance estimé depuis données horaires: ${peakPowerResult.toStringAsFixed(0)} W (utilisé comme fallback)', stackTrace: StackTrace.current);
        } else {
             logger.log('WARNING: Aucune donnée horaire disponible pour estimer le pic de puissance.', stackTrace: StackTrace.current);
        }
        // --- END FALLBACK LOGIC ---
      }

      // 3. Combiner les informations et créer l'objet DailySolarData final
      final dailyDataResult = DailySolarData(
        date: date,
        totalEnergy: totalEnergyResult,
        peakPower: peakPowerResult, // Utiliser le pic trouvé OU estimé
        hourlyData: hourlyDataResult,
      );

      _saveToCache(cacheKey, dailyDataResult, _dailyCacheDuration);
      return dailyDataResult;

    } on api_exceptions.SolarEdgeApiException { // Utiliser l'alias
      rethrow;
    } catch (e, s) {
      logger.log('ERROR: ❌ Erreur inattendue getDailyEnergy: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
        'Erreur inattendue GetDaily: ${e.toString()}',
        errorType: api_exceptions.SolarEdgeErrorType.UNKNOWN_ERROR, // Utiliser l'alias
        originalError: e,
      );
    }
  }

  // Nouvelle méthode pour obtenir les détails de puissance par intervalle pour une date donnée
  Future<List<SolarData>> getPowerDetailsForDate(DateTime date) async {
    final logger = FileLogger();
    final String dateStr = _formatDate(date);
    final String startTime = '$dateStr 00:00:00';
    final String endTime = '$dateStr 23:59:59';
    final cacheKey = 'power_details_$dateStr'; // Clé de cache spécifique pour les détails de puissance

    // Vérifier le cache
    if (_isCacheValid(cacheKey, _dailyCacheDuration)) { // Utiliser la durée de cache journalière
      logger.log('INFO: 📋 Utilisation cache pour détails puissance jour $dateStr', stackTrace: StackTrace.current);
      final cachedData = _cache[cacheKey];
      if (cachedData is List<SolarData>) {
        return cachedData;
      } else {
        logger.log('WARNING: Cache pour $cacheKey invalide (type ${cachedData?.runtimeType}), rechargement...', stackTrace: StackTrace.current);
      }
    }

    try {
      final dynamic powerDetailsData = await _makeApiCall(
          'powerDetails',
          {
            'startTime': startTime,
            'endTime': endTime,
          },
          'récupération détails puissance journalière');

      if (powerDetailsData is! Map<String, dynamic> ||
          !powerDetailsData.containsKey('powerDetails') ||
          powerDetailsData['powerDetails'] is! Map ||
          !(powerDetailsData['powerDetails'] as Map).containsKey('meters') ||
          powerDetailsData['powerDetails']['meters'] is! List) {
        throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
            'Format réponse détails puissance journalière invalide',
            errorType: api_exceptions.SolarEdgeErrorType.INVALID_RESPONSE); // Utiliser l'alias
      }

      final meterTelemetries = powerDetailsData['powerDetails']['meters'] as List;
      final List<SolarData> powerDataList = [];

      // Trouver les données de production
      for (var meter in meterTelemetries) {
        if (meter is Map<String, dynamic> &&
            meter['type'] == 'Production' &&
            meter.containsKey('values') &&
            meter['values'] is List) {
          final values = meter['values'] as List;
          for (var valueEntry in values) {
            if (valueEntry is Map<String, dynamic>) {
              final DateTime? timestamp = DateTime.tryParse(valueEntry['date'] as String? ?? '');
              final double power = (valueEntry['value'] as num?)?.toDouble() ?? 0.0;
              if (timestamp != null) {
                powerDataList.add(SolarData(timestamp: timestamp, power: power, energy: 0)); // Energy is 0 for power data points
              }
            }
          }
          break; // On a trouvé les données de production, on peut sortir de cette boucle
        }
      }

      // Trier les données par timestamp
      powerDataList.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      _saveToCache(cacheKey, powerDataList, _dailyCacheDuration); // Sauvegarder en cache
      return powerDataList;

    } on api_exceptions.SolarEdgeApiException { // Utiliser l'alias
      rethrow;
    } catch (e, s) {
      logger.log('ERROR: ❌ Erreur inattendue getPowerDetailsForDate: $e', stackTrace: s);
      throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
        'Erreur inattendue GetPowerDetailsForDate: ${e.toString()}',
        errorType: api_exceptions.SolarEdgeErrorType.UNKNOWN_ERROR, // Utiliser l'alias
        originalError: e,
      );
    }
  }

  Future<MonthlySolarData> getMonthlyEnergy(DateTime month) async {
    final logger = FileLogger();
    final DateTime firstDay = DateTime(month.year, month.month, 1);
    final DateTime lastDay = DateTime(month.year, month.month + 1, 0);
    final String startDate = _formatDate(firstDay);
    final String endDate = _formatDate(lastDay);
    final String cacheKey = 'monthly_${month.year}_${month.month}';

    if (_isCacheValid(cacheKey, _monthlyCacheDuration)) {
      logger.log(
          'INFO: 📋 Utilisation cache pour mois ${month.year}-${month.month}',
          stackTrace: StackTrace.current);
      final cachedData = _cache[cacheKey];
      if (cachedData is MonthlySolarData) return cachedData;
      logger.log('WARNING: Cache pour $cacheKey invalide, rechargement...',
          stackTrace: StackTrace.current);
    }

    try {
      // 1. Récupérer l'énergie totale par jour (comme avant)
      final dynamic energyData = await _makeApiCall(
          'energy',
          {
            'startDate': startDate,
            'endDate': endDate,
            'timeUnit': 'DAY',
          },
          'récupération énergie mensuelle');

      if (energyData is! Map<String, dynamic> ||
          !energyData.containsKey('energy') ||
          energyData['energy'] is! Map ||
          !(energyData['energy'] as Map).containsKey('values') ||
          energyData['energy']['values'] is! List) {
        throw api_exceptions.SolarEdgeApiException('Format réponse énergie mensuelle invalide', // Utiliser l'alias
            errorType: api_exceptions.SolarEdgeErrorType.INVALID_RESPONSE); // Utiliser l'alias
      }
      final energyValues = energyData['energy']['values'] as List;

      final List<DailySolarData> dailyData = [];
      double totalEnergy = 0;

      for (var entry in energyValues) {
        if (entry is Map<String, dynamic>) {
          final DateTime? date =
              DateTime.tryParse(entry['date'] as String? ?? '');
          final double energy = (entry['value'] as num?)?.toDouble() ?? 0.0;
          if (date != null) {
            totalEnergy += energy;
            dailyData.add(DailySolarData(
                date: date, totalEnergy: energy, peakPower: 0, hourlyData: []));
          }
        }
      }

      // 2. *** NOUVEAU: Essayer de récupérer le pic de puissance pour le mois ***
      double peakPowerMonth = 0; // Initialiser à 0
      try {
         logger.log('DEBUG: Appel API pour powerDetails mensuel ($startDate - $endDate)...', stackTrace: StackTrace.current);
         final String startTimeMonth = '$startDate 00:00:00';
         // Pour endTime, il faut prendre le *lendemain* du dernier jour à 00:00:00 ou le dernier jour à 23:59:59
         final String endTimeMonth = '${_formatDate(lastDay.add(const Duration(days: 1)))} 00:00:00';
         // Ou alternative: final String endTimeMonth = '$endDate 23:59:59';

         final dynamic powerDetailsDataMonth = await _makeApiCall(
             'powerDetails',
             {
               'startTime': startTimeMonth,
               'endTime': endTimeMonth,
             },
             'récupération détails puissance mensuelle');

         // Parser la réponse pour trouver le pic
         if (powerDetailsDataMonth is Map<String, dynamic> &&
            powerDetailsDataMonth.containsKey('powerDetails') &&
            powerDetailsDataMonth['powerDetails'] is Map) {
           final powerDetails = powerDetailsDataMonth['powerDetails'] as Map<String, dynamic>;
           if (powerDetails.containsKey('meters') && powerDetails['meters'] is List) {
             final meterTelemetries = powerDetails['meters'] as List;
             for (var meter in meterTelemetries) {
               if (meter is Map<String, dynamic> &&
                   meter['type'] == 'Production' &&
                   meter.containsKey('values') &&
                   meter['values'] is List) {
                 final values = meter['values'] as List;
                 for (var valueEntry in values) {
                   if (valueEntry is Map<String, dynamic>) {
                     final double power = (valueEntry['value'] as num?)?.toDouble() ?? 0.0;
                     if (power > peakPowerMonth) peakPowerMonth = power; // Mettre à jour le pic du mois
                   }
                 }
               }
             }
           }
            logger.log('DEBUG: Pic de puissance mensuel trouvé via API: $peakPowerMonth W', stackTrace: StackTrace.current);
         } else {
            logger.log('WARNING: Structure powerDetails mensuel inattendue ou vide.', stackTrace: StackTrace.current);
         }
      } catch (e, s) {
         logger.log('WARNING: ⚠️ Impossible de récupérer pic puissance mois via powerDetails: ${e.toString()}', stackTrace: s);
         // Ne pas faire échouer la fonction, on continue avec peakPowerMonth = 0
      }
      // --- FIN NOUVELLE PARTIE ---


      // 3. Créer l'objet final
      final monthlyData = MonthlySolarData(
        month: firstDay,
        totalEnergy: totalEnergy,
        peakPower: peakPowerMonth, // Utiliser la valeur trouvée (ou 0 si échec)
        dailyData: dailyData,
      );
      _saveToCache(cacheKey, monthlyData, _monthlyCacheDuration);
      return monthlyData;

    } on api_exceptions.SolarEdgeApiException { // Utiliser l'alias
      rethrow;
    } catch (e, s) {
      logger.log('ERROR: ❌ Erreur inattendue getMonthlyEnergy: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
        'Erreur inattendue GetMonthly: ${e.toString()}',
        errorType: api_exceptions.SolarEdgeErrorType.UNKNOWN_ERROR, // Utiliser l'alias
        originalError: e,
      );
    }
  }

  Future<YearlySolarData> getYearlyEnergy(int year) async {
    final logger = FileLogger();
    final DateTime firstDay = DateTime(year, 1, 1);
    final DateTime lastDay = DateTime(year, 12, 31);
    final String startDate = _formatDate(firstDay);
    final String endDate = _formatDate(lastDay);
    final String cacheKey = 'yearly_$year';

    if (_isCacheValid(cacheKey, _yearlyCacheDuration)) {
      logger.log('INFO: 📋 Utilisation cache pour année $year',
          stackTrace: StackTrace.current);
      final cachedData = _cache[cacheKey];
      if (cachedData is YearlySolarData) return cachedData;
      logger.log('WARNING: Cache pour $cacheKey invalide, rechargement...',
          stackTrace: StackTrace.current);
    }

    try {
      final dynamic energyData = await _makeApiCall(
          'energy',
          {
            'startDate': startDate,
            'endDate': endDate,
            'timeUnit': 'MONTH',
          },
          'récupération énergie annuelle');

      if (energyData is! Map<String, dynamic> ||
          !energyData.containsKey('energy') ||
          energyData['energy'] is! Map ||
          !(energyData['energy'] as Map).containsKey('values') ||
          energyData['energy']['values'] is! List) {
        throw api_exceptions.SolarEdgeApiException('Format réponse énergie annuelle invalide', // Utiliser l'alias
            errorType: api_exceptions.SolarEdgeErrorType.INVALID_RESPONSE); // Utiliser l'alias
      }
      final energyValues = energyData['energy']['values'] as List;

      final List<MonthlySolarData> monthlyData = [];
      double totalEnergy = 0;
      double peakPower = 0; // Pic de l'année (approximé par overview)

      try {
        final dynamic overviewData = await _makeApiCall(
            'overview', {}, 'récupération overview pour pic annuel');
        if (overviewData is Map<String, dynamic> &&
            overviewData.containsKey('overview') &&
            overviewData['overview'] is Map) {
          final overview = overviewData['overview'] as Map<String, dynamic>;
          peakPower = (overview['peakPower'] as num?)?.toDouble() ?? 0.0;
        }
      } catch (e, s) {
        logger.log(
            'WARNING: ⚠️ Impossible de récupérer l\'overview pour le pic annuel: $e',
            stackTrace: s);
      }

      for (var entry in energyValues) {
        if (entry is Map<String, dynamic>) {
          final DateTime? date =
              DateTime.tryParse(entry['date'] as String? ?? '');
          final double energy = (entry['value'] as num?)?.toDouble() ?? 0.0;
          if (date != null) {
            totalEnergy += energy;
            monthlyData.add(MonthlySolarData(
                month: date, totalEnergy: energy, peakPower: 0, dailyData: []));
          }
        }
      }

      final yearlyData = YearlySolarData(
        year: year,
        totalEnergy: totalEnergy,
        peakPower: peakPower,
        monthlyData: monthlyData,
      );
      _saveToCache(cacheKey, yearlyData, _yearlyCacheDuration);
      return yearlyData;
    } on api_exceptions.SolarEdgeApiException { // Utiliser l'alias
      rethrow;
    } catch (e, s) {
      logger.log('ERROR: ❌ Erreur inattendue getYearlyEnergy: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
        'Erreur inattendue GetYearly: ${e.toString()}',
        errorType: api_exceptions.SolarEdgeErrorType.UNKNOWN_ERROR, // Utiliser l'alias
        originalError: e,
      );
    }
  }

  Future<Map<String, dynamic>> getSiteDetails() async {
    await fileLogger.initialize();

    final String errorContext = 'la récupération des détails du site';
    fileLogger.log('INFO SolarEdgeService: Attempting to get site details...',
        stackTrace: StackTrace.current);

    try {
      final dynamic data = await _makeApiCall('details', {}, errorContext);

      if (data is! Map<String, dynamic>) {
        fileLogger.log(
            'ERROR SolarEdgeService: Response for details is not a Map. Type: ${data?.runtimeType}',
            stackTrace: StackTrace.current);
        throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
          'Format de réponse inattendu (non-Map) pour $errorContext. Reçu: ${data?.runtimeType}',
          errorType: api_exceptions.SolarEdgeErrorType.INVALID_RESPONSE, // Utiliser l'alias
        );
      }

      Map<String, dynamic> siteDetailsMap;
      if (data.containsKey('details') &&
          data['details'] is Map<String, dynamic>) {
        fileLogger.log(
            'INFO SolarEdgeService: Found details under "details" key.',
            stackTrace: StackTrace.current);
        siteDetailsMap = data['details'] as Map<String, dynamic>;
      } else if (data.containsKey('id') || data.containsKey('name')) {
        fileLogger.log(
            'INFO SolarEdgeService: Assuming details are at the root level.',
            stackTrace: StackTrace.current);
        siteDetailsMap = data;
      } else {
        fileLogger.log(
            'ERROR SolarEdgeService: Response is a Map but structure is unknown. Keys: ${data.keys}',
            stackTrace: StackTrace.current);
        throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
          'Structure JSON inattendue pour les détails du site. Clés reçues: ${data.keys}',
          errorType: api_exceptions.SolarEdgeErrorType.INVALID_RESPONSE, // Utiliser l'alias
        );
      }

      fileLogger.log(
          'INFO SolarEdgeService: Proceeding to extract and save location data.',
          stackTrace: StackTrace.current);
      await _extractAndSaveSiteLocation(siteDetailsMap);

      return siteDetailsMap;
    } on api_exceptions.SolarEdgeApiException catch (e, s) { // Utiliser l'alias
      fileLogger.log(
          'ERROR SolarEdgeService: SolarEdgeApiException in getSiteDetails: ${e.message}',
          stackTrace: s);
      rethrow;
    } catch (e, s) {
      fileLogger.log(
          'ERROR SolarEdgeService: Unexpected error in getSiteDetails: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException( // Utiliser l'alias
        'Erreur inattendue GetDetails: ${e.toString()}',
        errorType: api_exceptions.SolarEdgeErrorType.UNKNOWN_ERROR, // Utiliser l'alias
        originalError: e,
      );
    }
  }

  Future<void> _extractAndSaveSiteLocation(
      Map<String, dynamic> siteDetails) async {
    final logger = FileLogger();
    try {
      logger.log('INFO: 🔍 Extraction localisation...',
          stackTrace: StackTrace.current);
      Map<String, dynamic>? locationData;
      String? siteName;
      double? peakPower;

      if (siteDetails.containsKey('name')) {
        siteName = siteDetails['name'] as String?;
      }
      if (siteDetails.containsKey('peakPower')) {
        peakPower = (siteDetails['peakPower'] as num?)?.toDouble();
      }
      if (siteDetails.containsKey('location') &&
          siteDetails['location'] is Map<String, dynamic>) {
        locationData = siteDetails['location'] as Map<String, dynamic>;
      } else {
        logger.log('WARNING: Aucune clé "location" trouvée.',
            stackTrace: StackTrace.current);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      if (siteName != null) {
        logger.log('INFO: ✅ Nom site: $siteName',
            stackTrace: StackTrace.current);
        await prefs.setString('site_name', siteName);
      }
      if (peakPower != null && peakPower > 0) {
        await prefs.setDouble('site_peak_power', peakPower);
        logger.log('INFO: ✅ Puissance crête site: $peakPower W',
            stackTrace: StackTrace.current);
      }

      final locationService = LocationService();
      final addressSaved = await locationService.saveSiteAddress(locationData);

      if (addressSaved) {
        logger.log('INFO: ✅ Adresse site sauvegardée.',
            stackTrace: StackTrace.current);
        for (var entry in locationData.entries) {
          if (entry.value != null && entry.value is String) {
            await prefs.setString('site_${entry.key}', entry.value as String);
          }
        }
        final (latitude, longitude, source) =
            await locationService.getSavedCoordinates();
        if (latitude != null && longitude != null) {
          logger.log(
              'INFO: ℹ️ Coords déjà présentes ($source): $latitude, $longitude.',
              stackTrace: StackTrace.current);
        } else {
          final (lat, long) = await geocodeSiteAddress(locationData);
        if (lat != null && long != null) {
          // Enregistre ces coordonnées comme étant celles de l'adresse du site
          await locationService.saveCoordinates(lat, long, LocationService.sourceGeocoding, isSiteAddressCoordinates: true);
          logger.log('INFO: ✅ Coords géocodées et sauvegardées comme adresse du site: $lat, $long',
              stackTrace: StackTrace.current);
        } else {
          logger.log('WARNING: ⚠️ Géocodage échoué pour l\'adresse API.',
              stackTrace: StackTrace.current);
        }
        }
      } else {
        logger.log('ERROR: ❌ Échec sauvegarde adresse site.',
            stackTrace: StackTrace.current);
      }
    } catch (e, s) {
      logger.log('ERROR: ❌ Erreur extraction/sauvegarde localisation: $e',
          stackTrace: s);
    }
  }

  // Nouvelle méthode pour obtenir l'énergie totale et le pic de puissance pour une semaine donnée
  Future<WeeklySolarData> getWeeklyEnergy(DateTime dateInWeek) async {
    final logger = FileLogger();
    // Trouver le début de la semaine (Lundi)
    final DateTime startOfWeek =
        dateInWeek.subtract(Duration(days: dateInWeek.weekday - 1));
    final DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));
    final String startDateStr = _formatDate(startOfWeek);
    final String endDateStr = _formatDate(endOfWeek);
    final String cacheKey = 'weekly_${startDateStr}_${endDateStr}';

    if (_isCacheValid(cacheKey, _dailyCacheDuration)) {
      // Utiliser une durée de cache similaire au quotidien
      logger.log(
          'INFO: 📋 Utilisation cache pour semaine $startDateStr - $endDateStr',
          stackTrace: StackTrace.current);
      final cachedData = _cache[cacheKey];
      if (cachedData is WeeklySolarData) {
        return cachedData;
      } else {
        logger.log(
            'WARNING: Cache pour $cacheKey invalide (type ${cachedData?.runtimeType}), rechargement...',
            stackTrace: StackTrace.current);
      }
    }

    try {
      double totalEnergyWeek = 0;
      double peakPowerWeek = 0;
      List<DailySolarData> dailyDataList = [];

      // Récupérer les données quotidiennes pour chaque jour de la semaine
      for (int i = 0; i < 7; i++) {
        final currentDate = startOfWeek.add(Duration(days: i));
        try {
          final dailyData = await getDailyEnergy(
              currentDate); // Réutilise la méthode existante
          totalEnergyWeek += dailyData.totalEnergy;
          if (dailyData.peakPower > peakPowerWeek) {
            peakPowerWeek = dailyData.peakPower;
          }
          dailyDataList.add(dailyData);
        } catch (e, s) {
          logger.log(
              'WARNING: Impossible de récupérer données jour ${_formatDate(currentDate)} pour bilan semaine: $e',
              stackTrace: s);
          // Continuer même si un jour échoue, pour avoir un bilan partiel
        }
      }

      final weeklyData = WeeklySolarData(
        startDate: startOfWeek,
        endDate: endOfWeek,
        totalEnergy: totalEnergyWeek,
        peakPower: peakPowerWeek,
        dailyData: dailyDataList,
      );

      _saveToCache(
          cacheKey, weeklyData, _dailyCacheDuration); // Sauvegarder en cache
      return weeklyData;
    } on api_exceptions.SolarEdgeApiException {
      // Utiliser l'alias
      rethrow;
    } catch (e, s) {
      logger.log('ERROR: ❌ Erreur inattendue getWeeklyEnergy: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException(
        // Utiliser l'alias
        'Erreur inattendue GetWeekly: ${e.toString()}',
        errorType:
            api_exceptions.SolarEdgeErrorType.UNKNOWN_ERROR, // Utiliser l'alias
        originalError: e,
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Future<(double?, double?)> geocodeSiteAddress(
      Map<String, dynamic> locationData) async {
    final logger = FileLogger();
    try {
      final locationService = LocationService();
      final (lat, long) = await locationService.geocodeAddress(locationData);
      if (lat != null && long != null) {
        logger.log('INFO: Géocodage réussi: $lat, $long',
            stackTrace: StackTrace.current);
        return (lat, long);
      } else {
        logger.log('WARNING: Géocodage échoué.',
            stackTrace: StackTrace.current);
        return (null, null);
      }
    } catch (e, s) {
      logger.log('ERROR: ❌ Erreur géocodage: $e', stackTrace: s);
      return (null, null);
    }
  }

  /// Récupère l'énergie totale et les données par unité de temps pour une plage de dates donnée.
  /// timeUnit peut être 'DAY', 'HOUR', 'QUARTER_OF_AN_HOUR', etc.
  Future<SolarDataRange> getEnergyRange(DateTime startDate, DateTime endDate,
      {required String timeUnit}) async {
    final logger = FileLogger();
    final String startDateStr = _formatDate(startDate);
    final String endDateStr = _formatDate(endDate);
    final String cacheKey =
        'energy_range_${startDateStr}_${endDateStr}_$timeUnit';

    // Le cache pour les plages arbitraires est plus complexe, on peut l'omettre pour l'instant
    // ou implémenter une logique plus sophistiquée si nécessaire.
    // Pour l'instant, pas de cache pour cette méthode générique.

    try {
      final dynamic energyData = await _makeApiCall(
          'energy',
          {
            'startDate': startDateStr,
            'endDate': endDateStr,
            'timeUnit': timeUnit,
          },
          'récupération énergie pour plage de dates ($timeUnit)');

      if (energyData is! Map<String, dynamic> ||
          !energyData.containsKey('energy') ||
          energyData['energy'] is! Map ||
          !(energyData['energy'] as Map).containsKey('values') ||
          energyData['energy']['values'] is! List) {
        throw api_exceptions.SolarEdgeApiException(
            'Format réponse énergie pour plage de dates invalide',
            errorType: api_exceptions.SolarEdgeErrorType.INVALID_RESPONSE);
      }
      final energyValues = energyData['energy']['values'] as List;

      final List<SolarData> dataPoints = [];
      double totalEnergy = 0;
      // L'endpoint /energy ne fournit pas le pic de puissance pour la plage entière.
      // On peut calculer le pic à partir des valeurs retournées si timeUnit est assez fin (ex: HOUR, QUARTER_OF_AN_HOUR)
      // ou l'omettre si timeUnit est DAY ou MONTH.
      double peakPower = 0; // Initialiser à 0

      for (var entry in energyValues) {
        if (entry is Map<String, dynamic>) {
          final DateTime? timestamp =
              DateTime.tryParse(entry['date'] as String? ?? '');
          final double energy = (entry['value'] as num?)?.toDouble() ?? 0.0;
          if (timestamp != null) {
            totalEnergy += energy;
            // Si l'unité de temps est fine, on peut considérer l'énergie de l'intervalle comme une approximation de la puissance moyenne sur cet intervalle.
            // Pour un pic, il faudrait idéalement utiliser powerDetails, mais cette méthode est pour /energy.
            // On peut prendre la valeur d'énergie la plus élevée comme une très grossière approximation du pic si timeUnit est petit.
            // Pour l'instant, on laisse peakPower à 0 pour cette méthode générique, car elle ne le fournit pas directement.
            dataPoints
                .add(SolarData(timestamp: timestamp, power: 0, energy: energy));
          }
        }
      }

      // Définir une nouvelle classe SolarDataRange pour encapsuler les résultats
      return SolarDataRange(
        startDate: startDate,
        endDate: endDate,
        timeUnit: timeUnit,
        totalEnergy: totalEnergy,
        peakPower: peakPower, // Sera 0 pour l'instant
        dataPoints: dataPoints,
      );
    } on api_exceptions.SolarEdgeApiException {
      rethrow;
    } catch (e, s) {
      logger.log('ERROR: ❌ Erreur inattendue getEnergyRange: $e',
          stackTrace: s);
      throw api_exceptions.SolarEdgeApiException(
        'Erreur inattendue GetEnergyRange: ${e.toString()}',
        errorType: api_exceptions.SolarEdgeErrorType.UNKNOWN_ERROR,
        originalError: e,
      );
    }
  }
}

// Définir une classe pour les données hebdomadaires (si elle n'existe pas déjà)
// Assurez-vous que cette classe est définie dans solar_data.dart ou un fichier similaire
class WeeklySolarData {
  final DateTime startDate;
  final DateTime endDate;
  final double totalEnergy; // en Wh
  final double peakPower; // en W
  final List<DailySolarData> dailyData;

  WeeklySolarData({
    required this.startDate,
    required this.endDate,
    required this.totalEnergy,
    required this.peakPower,
    required this.dailyData,
  });
}

// Définir une nouvelle classe pour les données de plage d'énergie (si elle n'existe pas déjà)
// Assurez-vous que cette classe est définie dans solar_data.dart ou un fichier similaire
class SolarDataRange {
  final DateTime startDate;
  final DateTime endDate;
  final String timeUnit;
  final double totalEnergy; // en Wh
  final double
      peakPower; // en W (sera 0 pour l'instant avec l'endpoint /energy)
  final List<SolarData> dataPoints;

  SolarDataRange({
    required this.startDate,
    required this.endDate,
    required this.timeUnit,
    required this.totalEnergy,
    required this.peakPower,
    required this.dataPoints,
  });
}
