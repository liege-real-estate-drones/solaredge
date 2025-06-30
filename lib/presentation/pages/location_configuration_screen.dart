import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get_it/get_it.dart';
import 'package:solaredge_monitor/data/models/user_preferences.dart';
import 'package:solaredge_monitor/data/services/auth_service.dart';
import 'package:solaredge_monitor/data/services/location_service.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart';
import 'package:solaredge_monitor/data/services/user_preferences_service.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/data/services/weather_manager.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationConfigurationScreen extends StatefulWidget {
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;

  const LocationConfigurationScreen({super.key, this.onNext, this.onPrevious});

  @override
  State<LocationConfigurationScreen> createState() =>
      _LocationConfigurationScreenState();
}

class _LocationConfigurationScreenState
    extends State<LocationConfigurationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _locationService = LocationService();

  final TextEditingController _streetController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _zipController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();

  double? _latitude;
  double? _longitude;
  String? _locationSource;
  String? _siteAddress;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _addressEdited = false;
  bool _showSolarEdgeOption = false;

  VoidCallback? _userPreferencesSubscription;

  @override
  void initState() {
    super.initState();
    // Le chargement des données est maintenant déclenché par didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final serviceManager = Provider.of<ServiceManager>(context, listen: false);

    // Si le listener n'est pas encore configuré ou si le serviceManager a changé
    if (_userPreferencesSubscription == null) {
      final listenerCallback = () {
        debugPrint(
            "DEBUG LocationConfigurationScreen: userPreferencesNotifier changed. Reloading location data.");
        _loadLocationData();
      };
      serviceManager.userPreferencesNotifier.addListener(listenerCallback);
      _userPreferencesSubscription = listenerCallback;

      // Déclencher un chargement initial si les préférences sont déjà là
      if (serviceManager.userPreferencesNotifier.value != null) {
        _loadLocationData();
      }
    }
  }

  @override
  void dispose() {
    final serviceManager = Provider.of<ServiceManager>(context, listen: false);
    if (_userPreferencesSubscription != null) {
      serviceManager.userPreferencesNotifier.removeListener(_userPreferencesSubscription!);
    }
    _streetController.dispose();
    _cityController.dispose();
    _zipController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _updateAndSaveLocationPreferences(
      double newLat, double newLon, String newActiveSource) async {
    if (!mounted) return;

    final serviceManager = Provider.of<ServiceManager>(context, listen: false);
    final userPreferencesService = GetIt.I<UserPreferencesService>();
    final authService = GetIt.I<AuthService>();
    final weatherManager = Provider.of<WeatherManager>(context, listen: false);

    final currentUser = authService.currentUser;
    if (currentUser == null) {
      debugPrint(
          "LocationConfigScreen: User not logged in. Cannot save preferences.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Utilisateur non connecté. Impossible de sauvegarder les préférences de localisation.'),
              backgroundColor: Colors.orange),
        );
      }
      return;
    }

    UserPreferences currentPrefs =
        serviceManager.userPreferencesNotifier.value ?? UserPreferences();

    String weatherLocationSourceValue;
    switch (newActiveSource) {
      case LocationService.sourceSiteAddress:
      case LocationService
            .sourceGeocoding: // Assuming geocoding is for the site
      case LocationService
            .sourceSolarEdgeAPI: // Assuming SolarEdge API provides site coordinates
        weatherLocationSourceValue =
            'site_primary'; // Align with UserPreferences expected values
        break;
      case LocationService.sourceDeviceLocation:
        weatherLocationSourceValue =
            'device_location'; // Align with UserPreferences expected values
        break;
      case LocationService.sourceManual:
        weatherLocationSourceValue =
            'manual_coordinates'; // Align with UserPreferences expected values
        break;
      default:
        debugPrint(
            "LocationConfigScreen: Unknown newActiveSource '$newActiveSource', defaulting weatherLocationSource to 'site_primary'.");
        weatherLocationSourceValue = 'site_primary';
    }

    UserPreferences updatedPrefs = currentPrefs.copyWith(
      latitude: newLat,
      longitude: newLon,
      weatherLocationSource: weatherLocationSourceValue,
    );

    try {
      await userPreferencesService.saveUserPreferences(
          currentUser, updatedPrefs);
      serviceManager.userPreferencesNotifier.value = updatedPrefs;

      await weatherManager.updateLocationAndWeather();

      debugPrint(
          "LocationConfigScreen: UserPreferences updated with location: Lat=$newLat, Lon=$newLon, ActiveSource=$newActiveSource, WeatherSourceForPrefs=$weatherLocationSourceValue");
      // No generic SnackBar here to avoid duplicate messages from calling methods.
    } catch (e) {
      debugPrint("LocationConfigScreen: Error saving UserPreferences: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Erreur lors de la sauvegarde des préférences de localisation: ${e.toString()}'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

// Dans _LocationConfigurationScreenState
// Anciennement _useSavedSiteAddressCoordinates, maintenant avec logique améliorée
  Future<void> _handleUseSiteAddressOption() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      // 1. Tenter de récupérer des coordonnées spécifiques du site déjà sauvegardées
      final (savedLat, savedLon, savedSource) =
          await _locationService.getSavedSiteAddressCoordinates();

      if (savedLat != null && savedLon != null && savedSource != null) {
        debugPrint(
            "LocationConfig: Utilisation des coordonnées spécifiques du site sauvegardées.");
        // Si trouvées, les activer
        final success = await _locationService.saveCoordinates(
            savedLat, savedLon, LocationService.sourceSiteAddress);
        if (success) {
          setState(() {
            _latitude = savedLat;
            _longitude = savedLon;
            _locationSource = LocationService.sourceSiteAddress;
            // Mettre à jour les champs de texte de l'adresse si des composants sont sauvegardés
            _updateAddressFieldsFromSavedComponents(); // Nouvelle fonction helper (voir ci-dessous)
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Coordonnées de l\'adresse du site (enregistrées) activées.'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw Exception(
              'Échec de la sauvegarde des coordonnées actives du site.');
        }
      } else {
        // 2. Si non trouvées, vérifier si les champs d'adresse du formulaire sont remplis
        debugPrint(
            "LocationConfig: Aucune coordonnée spécifique du site trouvée. Vérification des champs du formulaire.");
        if (_streetController.text
                .trim()
                .isNotEmpty || // Ou plus permissif: si au moins un champ est rempli
            _cityController.text.trim().isNotEmpty ||
            _zipController.text.trim().isNotEmpty ||
            _countryController.text.trim().isNotEmpty) {
          debugPrint(
              "LocationConfig: Champs d'adresse remplis, tentative de géocodage...");
          final addressComponents = {
            'address': _streetController.text.trim(),
            'city': _cityController.text.trim(),
            'zip': _zipController.text.trim(),
            'country': _countryController.text.trim(),
          };

          // Sauvegarder les composants de l'adresse actuelle (au cas où ils auraient été modifiés)
          await _locationService.saveAddressComponents(addressComponents);
          // Mettre à jour l'affichage de _siteAddress (basé sur les composants fraîchement sauvegardés)
          final currentFormattedAddress =
              await _locationService.getSavedAddress();
          setState(() {
            _siteAddress = currentFormattedAddress;
          });

          final (geocodedLat, geocodedLon) =
              await _locationService.geocodeAddress(addressComponents
                  .map((key, value) => MapEntry(key, value as dynamic)));

          if (geocodedLat != null && geocodedLon != null) {
            debugPrint(
                "LocationConfig: Géocodage des champs du formulaire réussi: $geocodedLat, $geocodedLon");
            // Sauvegarder comme coordonnées spécifiques ET comme coordonnées actives
            final savedSpecific = await _locationService.saveCoordinates(
                geocodedLat, geocodedLon, LocationService.sourceGeocoding,
                isSiteAddressCoordinates: true);
            final savedActive = await _locationService.saveCoordinates(
                geocodedLat,
                geocodedLon,
                LocationService
                    .sourceSiteAddress); // La source active est maintenant 'site_address'

            if (savedSpecific && savedActive) {
              setState(() {
                _latitude = geocodedLat;
                _longitude = geocodedLon;
                _locationSource = LocationService.sourceSiteAddress;
                _addressEdited = false; // L'adresse a été traitée et géocodée
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Adresse du formulaire géocodée et activée comme adresse du site.'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } else {
              throw Exception(
                  'Échec de la sauvegarde des coordonnées géocodées pour l\'adresse du site.');
            }
          } else {
            // Le géocodage de l'adresse du formulaire a échoué
            debugPrint(
                "LocationConfig: Géocodage des champs du formulaire échoué.");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text(
                      'Impossible de géocoder l\'adresse affichée. Veuillez la vérifier ou entrer des coordonnées manuelles.'),
                  backgroundColor: Colors.orange,
                  action: SnackBarAction(
                    label: 'COORDS. MANUELLES',
                    onPressed: _enterManualCoordinates,
                    textColor: Colors.white,
                  ),
                ),
              );
            }
          }
        } else {
          // Les champs d'adresse sont vides, et pas de coordonnées spécifiques trouvées
          debugPrint(
              "LocationConfig: Champs d'adresse vides, impossible de géocoder.");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Aucune adresse de site configurée à utiliser. Veuillez remplir les champs d\'adresse et géocoder, ou utiliser une autre option.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("LocationConfig: Erreur dans _handleUseSiteAddressOption: $e");
      setState(() {
        _hasError = true;
        _errorMessage = e.toString().replaceFirst("Exception: ", "");
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur: $_errorMessage'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
    // Après toute tentative (réussie ou non) de mise à jour des coordonnées via cette option,
    // WeatherManager is notified by _updateAndSaveLocationPreferences
  }

// Nouvelle fonction helper pour mettre à jour les champs de texte de l'adresse
  Future<void> _updateAddressFieldsFromSavedComponents() async {
    final addressComponents =
        await _locationService.getSavedAddressComponents();
    if (mounted) {
      setState(() {
        _streetController.text = addressComponents['address'] as String? ?? '';
        _cityController.text = addressComponents['city'] as String? ?? '';
        _zipController.text = addressComponents['zip'] as String? ?? '';
        _countryController.text = addressComponents['country'] as String? ?? '';
        _addressEdited =
            false; // L'adresse vient d'être chargée, pas encore éditée
      });
    }
    // Mettre aussi à jour la variable _siteAddress pour l'affichage immédiat
    final currentFormattedAddress = await _locationService.getSavedAddress();
    if (mounted) {
      setState(() {
        _siteAddress = currentFormattedAddress;
      });
    }
  }

  // Charger les données de localisation existantes
  Future<void> _loadLocationData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _addressEdited = false;
    });

    try {
      // Charger les coordonnées et l'adresse
      final (latitude, longitude, source) =
          await _locationService.getSavedCoordinates();
      final address = await _locationService.getSavedAddress();

      // Charger les composants de l'adresse
      final addressComponents =
          await _locationService.getSavedAddressComponents();

      // Remplir les contrôleurs de texte avec les valeurs sauvegardées
      _streetController.text = addressComponents['address'] as String? ?? '';
      _cityController.text = addressComponents['city'] as String? ?? '';
      _zipController.text = addressComponents['zip'] as String? ?? '';
      _countryController.text = addressComponents['country'] as String? ?? '';

      // Vérifier si des données SolarEdge sont disponibles
      final prefs = await SharedPreferences.getInstance();
      final hasSolarEdgeAPI = prefs.getString('solaredge_api_key') != null &&
          prefs.getString('solaredge_site_id') != null;

      if (hasSolarEdgeAPI) {
        _showSolarEdgeOption = true;
      }

      setState(() {
        _latitude = latitude;
        _longitude = longitude;
        _locationSource = source;
        _siteAddress = address;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _geocodeManualAddress() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    // Construire un objet adresse à partir des champs
    final addressComponents = {
      'address': _streetController.text.trim(),
      'city': _cityController.text.trim(),
      'zip': _zipController.text.trim(),
      'country': _countryController.text.trim(),
    };

    try {
      // Sauvegarder les composants d'adresse individuels
      final success = await _locationService.saveAddressComponents(
        addressComponents.map((key, value) => MapEntry(key, value)),
      );

      if (!success) {
        throw Exception('Échec de sauvegarde des composants d\'adresse');
      }

      // Tenter le géocodage
      final (lat, long) = await _locationService.geocodeAddress(
        addressComponents.map((key, value) => MapEntry(key, value as dynamic)),
      );

      if (lat != null && long != null) {
        // Sauvegarde les coordonnées actives ET comme coordonnées spécifiques du site
        final saved = await _locationService.saveCoordinates(
            lat, long, LocationService.sourceGeocoding,
            isSiteAddressCoordinates: true);

        if (saved) {
          setState(() {
            _latitude = lat;
            _longitude = long;
            _locationSource = LocationService
                .sourceGeocoding; // La source active reste geocoding
            _isLoading = false;
            _addressEdited = false;
          });

          // Message de succès
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Adresse géocodée avec succès!'),
              backgroundColor: Colors.green,
            ),
          );

          // Call the new centralized method
          await _updateAndSaveLocationPreferences(
              lat, long, LocationService.sourceGeocoding);
        } else {
          throw Exception('Échec de la sauvegarde des coordonnées géocodées.');
        }
      } else {
        // Géocodage échoué
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Impossible de trouver les coordonnées pour cette adresse. Essayez une autre méthode.',
            ),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'COORDS. MANUELLES',
              onPressed: _enterManualCoordinates,
              textColor: Colors.white,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $_errorMessage'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Entrer des coordonnées manuellement
  Future<void> _enterManualCoordinates() async {
    final TextEditingController latController =
        TextEditingController(text: _latitude?.toString() ?? '');
    final TextEditingController longController =
        TextEditingController(text: _longitude?.toString() ?? '');

    final result = await showDialog<(double?, double?)>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Coordonnées manuelles'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: latController,
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  hintText: 'Ex: 50.8503',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: longController,
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  hintText: 'Ex: 4.3517',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                // Parse les coordonnées
                double? lat;
                double? long;

                try {
                  lat = double.parse(latController.text);
                  long = double.parse(longController.text);

                  if (lat < -90 || lat > 90 || long < -180 || long > 180) {
                    throw Exception('Coordonnées hors limites');
                  }

                  Navigator.of(context).pop((lat, long));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Coordonnées invalides. Vérifiez le format.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      final (latitude, longitude) = result;

      if (latitude != null && longitude != null) {
        // Sauvegarder les nouvelles coordonnées
        await _locationService.saveManualCoordinates(latitude, longitude);

        setState(() {
          _latitude = latitude;
          _longitude = longitude;
          _locationSource = LocationService.sourceManual;
        });
        // Call the new centralized method
        await _updateAndSaveLocationPreferences(
            latitude, longitude, LocationService.sourceManual);

        // Afficher un message de succès
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Coordonnées manuelles enregistrées et préférences mises à jour!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  // Utiliser la localisation actuelle de l'appareil
  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final (latitude, longitude) = await _locationService.getCurrentLocation();

      if (latitude != null && longitude != null) {
        setState(() {
          _latitude = latitude;
          _longitude = longitude;
          _locationSource = LocationService.sourceDeviceLocation;
          _isLoading = false;
        });
        // Call the new centralized method
        await _updateAndSaveLocationPreferences(
            latitude, longitude, LocationService.sourceDeviceLocation);

        // Afficher un message de succès
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Localisation mise à jour et préférences sauvegardées!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage =
              'Impossible d\'obtenir la position actuelle. Vérifiez vos autorisations de localisation.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  // Utiliser les coordonnées depuis l'API SolarEdge
  Future<void> _useSolarEdgeLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final apiKey = prefs.getString('solaredge_api_key');
      final siteId = prefs.getString('solaredge_site_id');

      if (apiKey == null || siteId == null) {
        throw Exception('Clé API ou ID de site manquant');
      }

      // Créer un service API SolarEdge
      final apiService = SolarEdgeApiService(apiKey: apiKey, siteId: siteId);

      // Récupérer les détails du site
      await apiService.getSiteDetails();

      // Vérifier si des coordonnées ont été sauvegardées
      final (lat, long, source) = await _locationService.getSavedCoordinates();

      if (lat != null && long != null) {
        setState(() {
          _latitude = lat;
          _longitude = long;
          _locationSource = source;
          _isLoading = false;
        });

        // Rafraîchir également l'adresse
        final address = await _locationService.getSavedAddress();
        final components = await _locationService.getSavedAddressComponents();

        if (address != null) {
          setState(() {
            _siteAddress = address;
          });
        }

        // Mettre à jour les contrôleurs avec les nouvelles valeurs
        _streetController.text = components['address'] as String? ?? '';
        _cityController.text = components['city'] as String? ?? '';
        _zipController.text = components['zip'] as String? ?? '';
        _countryController.text = components['country'] as String? ?? '';

        // Message de succès
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Informations de localisation récupérées depuis SolarEdge'),
            backgroundColor: Colors.green,
          ),
        );

        // Call the new centralized method
        // 'source' here is the one from _locationService.getSavedCoordinates() after apiService.getSiteDetails()
        // which should be LocationService.sourceSolarEdgeAPI if saveCoordinates was called correctly in LocationService
        await _updateAndSaveLocationPreferences(
            lat, long, source ?? LocationService.sourceSolarEdgeAPI);
      } else {
        throw Exception('Aucune coordonnée trouvée via l\'API SolarEdge');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: $_errorMessage'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Affiche un dialogue avec les coordonnées copiables
  void _showCopyableCoordinates() {
    if (_latitude == null || _longitude == null) return;

    final String coords = '$_latitude,$_longitude';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Coordonnées GPS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Copiez ces coordonnées pour les utiliser dans une application de cartographie:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      coords,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Coordonnées copiées dans le presse-papier'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    tooltip: 'Copier dans le presse-papier',
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('FERMER'),
          ),
        ],
      ),
    );
  }

  // Obtenir une description de la source de localisation
  String _getSourceDescription() {
    if (_locationSource == null) return 'Non définie';

    switch (_locationSource) {
      case LocationService.sourceGeocoding:
        return 'Géocodage de l\'adresse du site';
      case LocationService.sourceDeviceLocation:
        return 'Position actuelle de l\'appareil';
      case LocationService.sourceManual:
        return 'Coordonnées entrées manuellement';
      case LocationService.sourceSolarEdgeAPI:
        return 'Données SolarEdge API';
      case LocationService.sourceSiteAddress:
        return 'Adresse du site (configurée)';
      default:
        return 'Source inconnue';
    }
  }

  // Obtenir une couleur pour la source de localisation
  Color _getSourceColor() {
    if (_locationSource == null) return Colors.red;

    switch (_locationSource) {
      case LocationService.sourceGeocoding:
        return Colors.green;
      case LocationService.sourceDeviceLocation:
        return Colors.orange;
      case LocationService.sourceManual:
        return Colors.blue;
      case LocationService.sourceSolarEdgeAPI:
        return Colors.purple;
      case LocationService.sourceSiteAddress: // Nouvelle source
        return Colors.teal; // Ou une autre couleur distinctive
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _hasError
            ? _buildErrorView()
            : _buildContentView();

    if (widget.onNext != null) {
      // If part of a setup flow, don't use Scaffold/AppBar here
      return content;
    } else {
      // If standalone screen, use Scaffold/AppBar
      return Scaffold(
        appBar: AppBar(
          title: const Text('Configuration de la localisation'),
        ),
        body: content,
      );
    }
  }

  // Construire la vue d'erreur
  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Erreur lors du chargement des données de localisation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              style: const TextStyle(
                color: AppTheme.textSecondaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadLocationData,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Construire la vue principale
  Widget _buildContentView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        onChanged: () {
          setState(() {
            _addressEdited = true;
          });
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Explication
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                side: const BorderSide(
                    color: AppTheme.cardBorderColor, width: 0.5),
              ),
              color: AppTheme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppTheme.primaryColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Pourquoi les coordonnées sont-elles importantes?',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: AppTheme.textPrimaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Les coordonnées GPS de votre installation sont utilisées pour obtenir des données météo précises, essentielles pour analyser les performances de vos panneaux solaires.',
                      style: TextStyle(
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Section Adresse du site avec formulaire éditable
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Adresse du site',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimaryColor,
                  ),
                ),
                if (_addressEdited)
                  ElevatedButton(
                    onPressed: _geocodeManualAddress,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      minimumSize: const Size(0, 36),
                    ),
                    child: const Text('Géocoder'),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Formulaire d'adresse
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                side: const BorderSide(
                    color: AppTheme.cardBorderColor, width: 0.5),
              ),
              color: AppTheme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Rue / Numéro
                    TextFormField(
                      controller: _streetController,
                      decoration: const InputDecoration(
                        labelText: 'Rue et numéro',
                        hintText: 'Ex: Vieille Ruelle 31',
                        prefixIcon: Icon(Icons.home),
                      ),
                      validator: (value) {
                        if (_addressEdited &&
                            (value == null || value.isEmpty)) {
                          return 'Veuillez entrer une rue';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Ville et Code postal sur la même ligne
                    Row(
                      children: [
                        // Code postal
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            controller: _zipController,
                            decoration: const InputDecoration(
                              labelText: 'Code postal',
                              hintText: 'Ex: 4347',
                            ),
                            validator: (value) {
                              if (_addressEdited &&
                                  (value == null || value.isEmpty)) {
                                return 'Obligatoire';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Ville
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _cityController,
                            decoration: const InputDecoration(
                              labelText: 'Ville',
                              hintText: 'Ex: Fexhe-le-Haut-Clocher',
                            ),
                            validator: (value) {
                              if (_addressEdited &&
                                  (value == null || value.isEmpty)) {
                                return 'Veuillez entrer une ville';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Pays
                    TextFormField(
                      controller: _countryController,
                      decoration: const InputDecoration(
                        labelText: 'Pays',
                        hintText: 'Ex: Belgium',
                        prefixIcon: Icon(Icons.public),
                      ),
                      validator: (value) {
                        if (_addressEdited &&
                            (value == null || value.isEmpty)) {
                          return 'Veuillez entrer un pays';
                        }
                        return null;
                      },
                    ),

                    // Adresse complète actuelle
                    if (_siteAddress != null && !_addressEdited) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Adresse complète enregistrée:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondaryColor,
                                  ),
                                ),
                                Text(
                                  _siteAddress!,
                                  style: const TextStyle(
                                    color: AppTheme.textPrimaryColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Coordonnées actuelles
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Coordonnées actuelles',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimaryColor,
                  ),
                ),
                // Groupe de boutons à droite
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_locationSource ==
                        LocationService
                            .sourceDeviceLocation) // Afficher seulement si GPS est la source
                      IconButton(
                        icon: const Icon(Icons.refresh,
                            color: AppTheme.primaryColor),
                        tooltip: 'Actualiser la position GPS',
                        onPressed: _isLoading
                            ? null
                            : _useCurrentLocation, // Réutilise la fonction existante
                      ),
                    if (_latitude != null && _longitude != null)
                      IconButton(
                        onPressed: () {
                          // CORRECTION: Utiliser une URL valide pour Google Maps et les coordonnées
                          final Uri googleMapsUrl = Uri.parse(
                              'https://www.google.com/maps/search/?api=1&query=$_latitude,$_longitude');
                          // final googleMapsUrl = 'https://www.google.com/maps/search/?api=1&query=$_latitude,$_longitude'; // Ancienne URL incorrecte
                          launchUrl(googleMapsUrl,
                              mode: LaunchMode.externalApplication);
                        },
                        icon:
                            const Icon(Icons.map, color: AppTheme.primaryColor),
                        tooltip: 'Voir sur la carte',
                      ),
                  ],
                )
              ],
            ),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                side: const BorderSide(
                    color: AppTheme.cardBorderColor, width: 0.5),
              ),
              color: AppTheme.cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Afficher les coordonnées
                    if (_latitude != null && _longitude != null) ...[
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: AppTheme.textSecondaryColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Latitude: ${_latitude!.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimaryColor,
                                  ),
                                ),
                                Text(
                                  'Longitude: ${_longitude!.toStringAsFixed(6)}',
                                  style: const TextStyle(
                                    color: AppTheme.textPrimaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(),
                      const SizedBox(height: 8),
                      // Source des coordonnées
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: _getSourceColor()),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Source: ${_getSourceDescription()}',
                              style: TextStyle(
                                color: _getSourceColor(),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text(
                            'Aucune coordonnée définie',
                            style: TextStyle(
                              color: AppTheme.textSecondaryColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Options de localisation
            const Text(
              'Options de localisation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),

            // Boutons d'action - Version simplifiée
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.borderRadius),
                side: const BorderSide(
                    color: AppTheme.cardBorderColor, width: 0.5),
              ),
              color: AppTheme.cardColor,
              child: Column(
                children: [
                  // Message d'avertissement si on utilise la position actuelle
                  if (_locationSource ==
                      LocationService.sourceDeviceLocation) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.orange),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Vous utilisez actuellement la position de votre appareil. Pour une analyse précise des performances, utilisez plutôt les coordonnées exactes du site d\'installation.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Option SolarEdge API (recommandée)
                  if (_showSolarEdgeOption)
                    ListTile(
                      leading: const Icon(Icons.api, color: Colors.purple),
                      title: const Text('Utiliser les données SolarEdge'),
                      subtitle: const Text(
                          'Adresse et coordonnées exactes du site de production'),
                      tileColor: Colors.cyan.shade50,
                      trailing: _locationSource ==
                              LocationService.sourceSolarEdgeAPI
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: _useSolarEdgeLocation,
                    ),

                  // Séparateur
                  const Divider(height: 1),

                  // Option position actuelle de l'appareil
                  ListTile(
                    leading:
                        const Icon(Icons.my_location, color: Colors.orange),
                    title: const Text('Utiliser la position actuelle'),
                    subtitle: const Text(
                        'Coordonnées de votre appareil (moins précis)'),
                    trailing: _locationSource ==
                            LocationService.sourceDeviceLocation
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: _useCurrentLocation,
                  ),

                  // Séparateur
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.home_work_outlined,
                        color: Colors.teal), // Icône suggérée
                    title:
                        const Text('Utiliser l\'adresse du site (configurée)'),
                    subtitle: const Text(
                        'Active les coordonnées du site définies via SolarEdge ou manuellement'),
                    // La condition pour `trailing` vérifie si la source active est celle de l'adresse du site.
                    // Ou si c'est du geocoding ET qu'on a des coordonnées (ce qui est le cas après _useSolarEdgeLocation ou _geocodeManualAddress)
                    trailing: _locationSource ==
                                LocationService.sourceSiteAddress ||
                            (_locationSource ==
                                    LocationService.sourceGeocoding &&
                                _latitude != null &&
                                _longitude !=
                                    null) // Garder cette logique pour le checkmark
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: _isLoading
                        ? null
                        : _handleUseSiteAddressOption, // APPELLE LA NOUVELLE FONCTION
                  ),
                  const Divider(height: 1), // Séparateur

                  // Option SolarEdge API (recommandée)
                  if (_showSolarEdgeOption)
                    ListTile(
                      leading: const Icon(Icons.api, color: Colors.purple),
                      title: const Text(
                          'Utiliser les données SolarEdge (API)'), // Titre clarifié
                      subtitle: const Text(
                          'Récupère et définit l\'adresse et les coordonnées du site'), // Description clarifiée
                      tileColor: Colors.cyan.shade50,
                      trailing: _locationSource ==
                              LocationService
                                  .sourceSolarEdgeAPI // Adaptez si sourceSolarEdgeAPI est effectivement utilisé
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                      onTap: _useSolarEdgeLocation,
                    ),
                  if (_showSolarEdgeOption) const Divider(height: 1),

                  // Option pour entrer manuellement les coordonnées
                  ListTile(
                    leading:
                        const Icon(Icons.edit_location_alt, color: Colors.blue),
                    title: const Text('Entrer les coordonnées manuellement'),
                    subtitle:
                        const Text('Spécifiez latitude et longitude exactes'),
                    trailing: _locationSource == LocationService.sourceManual
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : null,
                    onTap: _enterManualCoordinates,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Bouton pour terminer
            Center(
              child: ElevatedButton.icon(
                onPressed: () async {
                  // WeatherManager should have been updated by _updateAndSaveLocationPreferences if location changed.
                  // This final call can be a safeguard or removed if confident.
                  // For now, let's keep it to ensure WeatherManager is up-to-date before popping.
                  final weatherManager =
                      Provider.of<WeatherManager>(context, listen: false);
                  await weatherManager.updateLocationAndWeather();

                  if (widget.onNext != null) {
                    widget.onNext!();
                  } else {
                    // Retourner à l'écran précédent
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Terminer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
