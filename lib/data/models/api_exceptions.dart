// Fichier: solaredge_monitor/lib/data/models/api_exceptions.dart

/// Enumération des types d'erreurs possibles avec l'API SolarEdge.
enum SolarEdgeErrorType {
  /// Erreur inconnue ou non classifiée.
  UNKNOWN_ERROR,

  /// Erreur liée au réseau (pas de connexion, timeout, etc.).
  NETWORK_ERROR,

  /// Erreur liée à une clé API invalide ou expirée (401, 403).
  INVALID_API_KEY,

  /// Erreur liée à un ID de site invalide ou non trouvé (404).
  INVALID_SITE_ID,

  /// Erreur provenant directement du serveur SolarEdge (5xx).
  SERVER_ERROR,

  /// La réponse reçue du serveur est invalide ou inattendue (ex: JSON mal formé, corps vide).
  INVALID_RESPONSE, // Ajouté

  /// Trop de requêtes envoyées à l'API (429).
  RATE_LIMIT_EXCEEDED, // Ajouté

  /// Erreur de configuration interne (ex: clé API ou ID site manquant dans le service).
  CONFIG_ERROR, // Ajouté
}

/// Exception personnalisée pour les erreurs liées à l'API SolarEdge.
class SolarEdgeApiException implements Exception {
  /// Message décrivant l'erreur.
  final String message;

  /// Type d'erreur spécifique (si connu).
  final SolarEdgeErrorType errorType;

  /// Code de statut HTTP (si applicable).
  final int? statusCode;

  /// Exception originale ayant causé cette erreur (pour le débogage).
  final dynamic originalError;

  SolarEdgeApiException(
    this.message, {
    this.errorType = SolarEdgeErrorType.UNKNOWN_ERROR,
    this.statusCode,
    this.originalError,
  });

  @override
  String toString() {
    String result = 'SolarEdgeApiException [$errorType]: $message';
    if (statusCode != null) {
      result += ' (Status Code: $statusCode)';
    }
    // Optionnel: Ajouter l'erreur originale pour plus de détails en debug
    // if (originalError != null) {
    //   result += '\nOriginal Error: $originalError';
    // }
    return result;
  }
}
