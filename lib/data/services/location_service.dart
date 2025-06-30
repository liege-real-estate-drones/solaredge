import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service permettant de gérer la localisation de l'installation solaire
/// Prend en charge plusieurs sources de coordonnées et formats d'adresse
class LocationService {
  // Clés pour les SharedPreferences
  static const String _latitudeKey = 'site_latitude';
  static const String _longitudeKey = 'site_longitude';
  static const String _locationSourceKey = 'location_source';
  static const String _addressKey = 'site_address';

    // Clés pour les coordonnées spécifiques de l'adresse du site (sauvegardées une fois)
  static const String _siteAddressLatitudeKey = 'site_address_latitude';
  static const String _siteAddressLongitudeKey = 'site_address_longitude';
  static const String _siteAddressSourceKey = 'site_address_source'; // Source d'origine de ces coordonnées

  
  // Sources possibles des coordonnées
  static const String sourceGeocoding = 'geocoding';
  static const String sourceDeviceLocation = 'device_location';
  static const String sourceManual = 'manual';
  static const String sourceSolarEdgeAPI = 'solaredge_api';
  static const String sourceDefault = 'default';
  static const String sourceSiteAddress = 'site_address_saved'; // Nouvelle source
  
  // Clés pour les composants de l'adresse
  static const String _siteStreetKey = 'site_address';
  static const String _siteCityKey = 'site_city';
  static const String _siteZipKey = 'site_zip';
  static const String _siteCountryKey = 'site_country';
  static const String _siteCountryCodeKey = 'site_countryCode';
  
  // Obtenir les coordonnées stockées avec logs améliorés
  Future<(double?, double?, String?)> getSavedCoordinates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final latitude = prefs.getDouble(_latitudeKey);
      final longitude = prefs.getDouble(_longitudeKey);
      final source = prefs.getString(_locationSourceKey);
      
      // Log amélioré pour le débogage
      if (latitude != null && longitude != null) {
        debugPrint('✅ Coordonnées trouvées en SharedPreferences: $latitude, $longitude (source: $source)');
      } else {
        debugPrint('❌ Aucune coordonnée trouvée en SharedPreferences');
      }
      
      return (latitude, longitude, source);
    } catch (e) {
      debugPrint('❌ Erreur lors de la récupération des coordonnées: $e');
      return (null, null, null);
    }
  }
  
  // Sauvegarder les coordonnées avec confirmation de succès
  Future<bool> saveCoordinates(double latitude, double longitude, String source, {bool isSiteAddressCoordinates = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Valider les coordonnées
      if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        debugPrint('❌ Coordonnées invalides: $latitude, $longitude');
        return false;
      }

      // Sauvegarder les coordonnées actives
      await prefs.setDouble(_latitudeKey, latitude);
      await prefs.setDouble(_longitudeKey, longitude);
      await prefs.setString(_locationSourceKey, source);
      debugPrint('✅ Coordonnées actives sauvegardées: $latitude, $longitude (source: $source)');

      // Si ce sont les coordonnées spécifiques de l'adresse du site, les sauvegarder aussi séparément
      if (isSiteAddressCoordinates) {
        await prefs.setDouble(_siteAddressLatitudeKey, latitude);
        await prefs.setDouble(_siteAddressLongitudeKey, longitude);
        await prefs.setString(_siteAddressSourceKey, source); // Sauvegarder aussi leur source d'origine
        debugPrint('✅ Coordonnées spécifiques de l\'adresse du site sauvegardées: $latitude, $longitude (source: $source)');
      }
      
      // Mettre à jour le flag pour informer l'application du changement (si nécessaire par d'autres parties de l'app)
      await prefs.setBool('coordinates_updated', true);
      return true;
    } catch (e) {
      debugPrint('❌ Erreur lors de la sauvegarde des coordonnées: $e');
      return false;
    }
  }

  Future<(double?, double?, String?)> getSavedSiteAddressCoordinates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final latitude = prefs.getDouble(_siteAddressLatitudeKey);
      final longitude = prefs.getDouble(_siteAddressLongitudeKey);
      final source = prefs.getString(_siteAddressSourceKey); // Récupérer aussi la source d'origine

      if (latitude != null && longitude != null) {
        debugPrint('✅ Coordonnées spécifiques de l\'adresse du site récupérées: $latitude, $longitude (source: $source)');
      } else {
        debugPrint('❌ Aucune coordonnée spécifique de l\'adresse du site trouvée.');
      }
      return (latitude, longitude, source);
    } catch (e) {
      debugPrint('❌ Erreur lors de la récupération des coordonnées spécifiques de l\'adresse du site: $e');
      return (null, null, null);
    }
  }
  
  // Sauvegarder l'adresse du site
  Future<bool> saveSiteAddress(Map<String, dynamic> addressData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String fullAddress = _formatAddress(addressData);
      await prefs.setString(_addressKey, fullAddress);
      
      debugPrint('✅ Adresse du site sauvegardée: $fullAddress');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur lors de la sauvegarde de l\'adresse: $e');
      return false;
    }
  }
  
  // Récupérer l'adresse stockée au format texte complet
  Future<String?> getSavedAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final address = prefs.getString(_addressKey);
      
      if (address != null && address.isNotEmpty) {
        debugPrint('✅ Adresse récupérée depuis les préférences: $address');
      } else {
        debugPrint('❌ Aucune adresse complète trouvée dans les préférences');
        
        // Tenter de reconstruire l'adresse à partir des composants individuels
        final addressMap = await getSavedAddressComponents();
        if (addressMap.isNotEmpty) {
          final reconstructedAddress = _formatAddress(addressMap);
          debugPrint('🔄 Adresse reconstruite à partir des composants: $reconstructedAddress');
          return reconstructedAddress;
        }
      }
      
      return address;
    } catch (e) {
      debugPrint('❌ Erreur lors de la récupération de l\'adresse: $e');
      return null;
    }
  }
  
  // Récupérer les composants individuels de l'adresse stockée
  Future<Map<String, dynamic>> getSavedAddressComponents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> addressComponents = {};
      
      // Tenter de récupérer chaque composant
      final street = prefs.getString(_siteStreetKey);
      final city = prefs.getString(_siteCityKey);
      final zip = prefs.getString(_siteZipKey);
      final country = prefs.getString(_siteCountryKey);
      final countryCode = prefs.getString(_siteCountryCodeKey);
      
      // Ajouter les composants non-null à la map
      if (street != null && street.isNotEmpty) addressComponents['address'] = street;
      if (city != null && city.isNotEmpty) addressComponents['city'] = city;
      if (zip != null && zip.isNotEmpty) addressComponents['zip'] = zip;
      if (country != null && country.isNotEmpty) addressComponents['country'] = country;
      if (countryCode != null && countryCode.isNotEmpty) addressComponents['countryCode'] = countryCode;
      
      debugPrint('📋 Composants d\'adresse récupérés: ${addressComponents.length} champs');
      
      return addressComponents;
    } catch (e) {
      debugPrint('❌ Erreur lors de la récupération des composants d\'adresse: $e');
      return {};
    }
  }
  
  // Sauvegarder les composants individuels de l'adresse
  Future<bool> saveAddressComponents(Map<String, String> components) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      int savedCount = 0;
      
      // Sauvegarder chaque composant individuellement
      for (var entry in components.entries) {
        final key = 'site_${entry.key}';
        await prefs.setString(key, entry.value);
        savedCount++;
      }
      
      // Reconstruire et sauvegarder l'adresse complète
      final completeAddress = _formatAddressFromComponents(components);
      await prefs.setString(_addressKey, completeAddress);
      
      debugPrint('✅ $savedCount composants d\'adresse sauvegardés');
      debugPrint('✅ Adresse complète reconstruite et sauvegardée: $completeAddress');
      
      return true;
    } catch (e) {
      debugPrint('❌ Erreur lors de la sauvegarde des composants d\'adresse: $e');
      return false;
    }
  }
  
  // Formater une adresse à partir des composants individuels
  String _formatAddressFromComponents(Map<String, String> components) {
    final List<String> addressParts = [];
    
    if (components.containsKey('address')) addressParts.add(components['address']!);
    if (components.containsKey('zip')) addressParts.add(components['zip']!);
    if (components.containsKey('city')) addressParts.add(components['city']!);
    if (components.containsKey('country')) addressParts.add(components['country']!);
    
    return addressParts.join(', ');
  }
  
  // Géocoder une adresse pour obtenir des coordonnées
  Future<(double?, double?)> geocodeAddress(Map<String, dynamic> addressData) async {
    try {
      // Vérifier si l'adresse contient des données
      if (addressData.isEmpty) {
        debugPrint('❌ Données d\'adresse vides, impossible de géocoder');
        return (null, null);
      }
      
      final String fullAddress = _formatAddress(addressData);
      debugPrint('🔍 Tentative de géocodage de l\'adresse: $fullAddress');
      
      // Essayer plusieurs formats d'adresse si le premier échoue
      List<String> addressFormats = [
        fullAddress,
        // Format simplifié: ville, code postal, pays
        '${addressData['city'] ?? ''}, ${addressData['zip'] ?? ''}, ${addressData['country'] ?? ''}',
        // Uniquement ville et pays
        '${addressData['city'] ?? ''}, ${addressData['country'] ?? ''}',
      ];
      
      for (var address in addressFormats) {
        if (address.trim().isEmpty) continue;
        
        try {
          debugPrint('🔍 Essai avec format: $address');
          final locations = await locationFromAddress(address);
          
          if (locations.isNotEmpty) {
            final latitude = locations.first.latitude;
            final longitude = locations.first.longitude;
            
            // Sauvegarder ces coordonnées
            final saved = await saveCoordinates(latitude, longitude, sourceGeocoding);
            
            if (saved) {
              debugPrint('✅ Géocodage réussi: $latitude, $longitude pour $address');
              return (latitude, longitude);
            }
          }
        } catch (e) {
          debugPrint('⚠️ Échec avec ce format d\'adresse: $e');
          // Continuer avec le format suivant
          continue;
        }
      }
      
      debugPrint('❌ Géocodage échoué pour toutes les variantes d\'adresse');
      return (null, null);
    } catch (e) {
      debugPrint('❌ Erreur lors du géocodage: $e');
      return (null, null);
    }
  }
  
  // Obtenir la position actuelle de l'appareil
  Future<(double?, double?)> getCurrentLocation() async {
    try {
      debugPrint('🔍 Tentative d\'obtention de la position actuelle...');
      
      // Vérifier les permissions
      LocationPermission permission = await Geolocator.checkPermission();
      
      if (permission == LocationPermission.denied) {
        debugPrint('⚠️ Permission de localisation refusée, demande en cours...');
        permission = await Geolocator.requestPermission();
        
        if (permission == LocationPermission.denied) {
          debugPrint('❌ Autorisation de localisation refusée par l\'utilisateur');
          return (null, null);
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        debugPrint('❌ Autorisation de localisation refusée de façon permanente');
        return (null, null);
      }
      
      debugPrint('✅ Permissions de localisation accordées, récupération de la position...');
      
      // Obtenir la position actuelle
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      
      // Sauvegarder ces coordonnées
      final saved = await saveCoordinates(position.latitude, position.longitude, sourceDeviceLocation);
      
      if (saved) {
        debugPrint('✅ Position actuelle obtenue et sauvegardée: ${position.latitude}, ${position.longitude}');
        return (position.latitude, position.longitude);
      } else {
        debugPrint('❌ Échec de sauvegarde de la position actuelle');
        return (position.latitude, position.longitude); // Retourner quand même les coordonnées obtenues
      }
    } catch (e) {
      debugPrint('❌ Erreur lors de la récupération de la localisation actuelle: $e');
      return (null, null);
    }
  }
  
  // Enregistrer des coordonnées manuelles avec validation
  Future<bool> saveManualCoordinates(double latitude, double longitude) async {
    try {
      // Vérifier que les valeurs sont valides
      if (latitude < -90 || latitude > 90) {
        debugPrint('❌ Latitude invalide: $latitude (doit être entre -90 et 90)');
        return false;
      }
      
      if (longitude < -180 || longitude > 180) {
        debugPrint('❌ Longitude invalide: $longitude (doit être entre -180 et 180)');
        return false;
      }
      
      debugPrint('🔍 Sauvegarde des coordonnées manuelles: $latitude, $longitude');
      return await saveCoordinates(latitude, longitude, sourceManual);
    } catch (e) {
      debugPrint('❌ Erreur lors de la sauvegarde des coordonnées manuelles: $e');
      return false;
    }
  }
  
  // Formater l'adresse pour le géocodage
  String _formatAddress(Map<String, dynamic> addressData) {
    final List<String> addressParts = [];
    
    if (addressData.containsKey('address') && addressData['address'] != null) {
      addressParts.add(addressData['address']);
    }
    
    if (addressData.containsKey('zip') && addressData['zip'] != null) {
      addressParts.add(addressData['zip']);
    }
    
    if (addressData.containsKey('city') && addressData['city'] != null) {
      addressParts.add(addressData['city']);
    }
    
    if (addressData.containsKey('country') && addressData['country'] != null) {
      addressParts.add(addressData['country']);
    }
    
    return addressParts.join(', ');
  }
  
  // Effacer toutes les données de localisation
  Future<bool> clearLocationData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_latitudeKey);
      await prefs.remove(_longitudeKey);
      await prefs.remove(_locationSourceKey);
      await prefs.remove(_addressKey);
      
      debugPrint('✅ Données de localisation effacées avec succès');
      return true;
    } catch (e) {
      debugPrint('❌ Erreur lors de l\'effacement des données de localisation: $e');
      return false;
    }
  }
}
