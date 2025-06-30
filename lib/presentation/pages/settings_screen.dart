import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:solaredge_monitor/data/services/solaredge_api_service.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _siteIdController = TextEditingController();
  final TextEditingController _maxPowerController = TextEditingController();
  
  bool _isLoading = false;
  bool _isTesting = false;
  bool _isSaved = false;
  bool _hasConsent = false;
  String? _errorMessage;
  String? _testConnectionResult;
  bool _testConnectionSuccess = false;
  
  // Stockage temporaire des coordonnées du site
  double? _siteLatitude;
  double? _siteLongitude;
  String? _siteName;
  double? _sitePeakPower;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadSiteCoordinates();
  }
  
  // Charger les coordonnées du site stockées
  Future<void> _loadSiteCoordinates() async {
    try {
      final prefs = Provider.of<SharedPreferences>(context, listen: false);
      
      // Récupérer les coordonnées stockées
      final latitude = prefs.getDouble('site_latitude');
      final longitude = prefs.getDouble('site_longitude');
      final name = prefs.getString('site_name') ?? 'Mon Installation';
      final peakPower = prefs.getDouble('site_peak_power');
      
      if (latitude != null && longitude != null) {
        setState(() {
          _siteLatitude = latitude;
          _siteLongitude = longitude;
          _siteName = name;
          _sitePeakPower = peakPower;
          
          // Initialiser le contrôleur de puissance maximale
          if (peakPower != null) {
            _maxPowerController.text = peakPower.toString();
          }
        });
        debugPrint('Coordonnées du site chargées depuis les préférences: $_siteLatitude, $_siteLongitude');
        debugPrint('Puissance crête de l\'installation: $_sitePeakPower kW');
      }
    } catch (e) {
      debugPrint('Erreur lors du chargement des coordonnées: $e');
    }
  }
  
  @override
  void dispose() {
    _apiKeyController.dispose();
    _siteIdController.dispose();
    _maxPowerController.dispose();
    super.dispose();
  }
  
  // Charger les paramètres depuis SharedPreferences
  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final prefs = Provider.of<SharedPreferences>(context, listen: false);
      
      // Récupérer les valeurs sauvegardées
      final apiKey = prefs.getString('solaredge_api_key') ?? '';
      final siteId = prefs.getString('solaredge_site_id') ?? '';
      final maxPower = prefs.getDouble('max_power');
      
      // Mettre à jour les contrôleurs
      _apiKeyController.text = apiKey;
      _siteIdController.text = siteId;
      if (maxPower != null) {
        _maxPowerController.text = maxPower.toString();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors du chargement des paramètres: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Tester la connexion à l'API SolarEdge
  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    setState(() {
      _isTesting = true;
      _testConnectionResult = null;
      _testConnectionSuccess = false;
    });
    
    try {
      // Créer une instance temporaire du service API avec les valeurs actuelles
      final apiService = SolarEdgeApiService(
        apiKey: _apiKeyController.text.trim(),
        siteId: _siteIdController.text.trim(),
      );
      
      // Tenter de récupérer les détails du site pour vérifier que la connexion fonctionne
      final siteDetails = await apiService.getSiteDetails();
      
      // Extraire le nom du site
      String? siteName;
      double? peakPower;
      
      // Extraire les informations importantes
      if (siteDetails['site'] != null) {
        final site = siteDetails['site'] as Map<String, dynamic>;
        siteName = site['name'] as String?;
        
        // Extraire la puissance crête de l'installation
        if (site['peakPower'] != null) {
          if (site['peakPower'] is double) {
            peakPower = site['peakPower'] as double;
          } else if (site['peakPower'] is int) {
            peakPower = (site['peakPower'] as int).toDouble();
          } else if (site['peakPower'] is String) {
            peakPower = double.tryParse(site['peakPower'] as String);
          }
          
          // Mettre à jour le contrôleur de puissance maximale
          if (peakPower != null && _maxPowerController.text.isEmpty) {
            _maxPowerController.text = peakPower.toString();
          }
        }
      } else {
        siteName = siteDetails['name'] as String?;
        
        // Essayer de récupérer la puissance crête au format plat
        if (siteDetails['peakPower'] != null) {
          if (siteDetails['peakPower'] is double) {
            peakPower = siteDetails['peakPower'] as double;
          } else if (siteDetails['peakPower'] is int) {
            peakPower = (siteDetails['peakPower'] as int).toDouble();
          } else if (siteDetails['peakPower'] is String) {
            peakPower = double.tryParse(siteDetails['peakPower'] as String);
          }
          
          // Mettre à jour le contrôleur de puissance maximale
          if (peakPower != null && _maxPowerController.text.isEmpty) {
            _maxPowerController.text = peakPower.toString();
          }
        }
      }
      
      // Extraire les coordonnées géographiques du site si disponibles
      final location = siteDetails['location'];
      double? latitude, longitude;
      
      if (location != null) {
        // Conversion explicite des coordonnées (qui peuvent être retournées sous différents formats)
        try {
          // Gérer différents formats possibles: double, int, string
          if (location['latitude'] != null) {
            if (location['latitude'] is double) {
              latitude = location['latitude'] as double;
            } else if (location['latitude'] is int) {
              latitude = (location['latitude'] as int).toDouble();
            } else if (location['latitude'] is String) {
              latitude = double.tryParse(location['latitude'] as String);
            }
          }
          
          if (location['longitude'] != null) {
            if (location['longitude'] is double) {
              longitude = location['longitude'] as double;
            } else if (location['longitude'] is int) {
              longitude = (location['longitude'] as int).toDouble();
            }
          } else if (location['longitude'] is String) {
            longitude = double.tryParse(location['longitude'] as String);
          }
          
          // Afficher le type réel des données pour le débogage
          debugPrint('Type latitude: ${location['latitude']?.runtimeType}, valeur: ${location['latitude']}');
          debugPrint('Type longitude: ${location['longitude']?.runtimeType}, valeur: ${location['longitude']}');
          debugPrint('Coordonnées converties: $latitude, $longitude');
        } catch (e) {
          debugPrint('Erreur lors de la conversion des coordonnées: $e');
          // Ne pas propager l'erreur, on continuera avec des coordonnées null
        }
      }
      
      // Si on arrive ici, c'est que la connexion a réussi
      String connectionMessage = 'Connexion réussie! Nom du site: ${siteName ?? "Non défini"}\n';

      // Ajouter la puissance crête si disponible
      if (peakPower != null) {
        connectionMessage += 'Puissance crête: ${peakPower.toStringAsFixed(2)} kW\n';
      }

      // Ajouter les coordonnées si disponibles
      if (latitude != null && longitude != null) {
        connectionMessage += 'Latitude: ${latitude.toStringAsFixed(4)}, Longitude: ${longitude.toStringAsFixed(4)}\n';
      }

      setState(() {
        _siteName = siteName;
        _sitePeakPower = peakPower;
        _testConnectionSuccess = true;
        _testConnectionResult = connectionMessage;
        
        // Sauvegarder les coordonnées du site pour une utilisation future
        _saveSiteCoordinates(latitude, longitude, siteName, peakPower);
      });
    } catch (e) {
      setState(() {
        _testConnectionSuccess = false;
        _testConnectionResult = 'Échec de la connexion: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }
  
  // Sauvegarder les coordonnées du site
  Future<void> _saveSiteCoordinates(double? latitude, double? longitude, String? name, double? peakPower) async {
    final prefs = Provider.of<SharedPreferences>(context, listen: false);
    if (latitude != null) {
      await prefs.setDouble('site_latitude', latitude);
    }
    if (longitude != null) {
      await prefs.setDouble('site_longitude', longitude);
    }
    if (name != null) {
      await prefs.setString('site_name', name);
    }
    if (peakPower != null) {
      await prefs.setDouble('site_peak_power', peakPower);
    }
  }

  // Sauvegarder les paramètres dans SharedPreferences
  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _isSaved = false;
      _errorMessage = null;
    });

    try {
      final prefs = Provider.of<SharedPreferences>(context, listen: false);

      await prefs.setString('solaredge_api_key', _apiKeyController.text.trim());
      await prefs.setString('solaredge_site_id', _siteIdController.text.trim());
      
      // Sauvegarder la puissance maximale si elle est valide
      final maxPowerText = _maxPowerController.text.trim();
      if (maxPowerText.isNotEmpty) {
        final maxPower = double.tryParse(maxPowerText);
        if (maxPower != null) {
          await prefs.setDouble('max_power', maxPower);
        }
      } else {
        await prefs.remove('max_power'); // Supprimer si le champ est vide
      }

      setState(() {
        _isSaved = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paramètres sauvegardés avec succès')),
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors de la sauvegarde: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Ouvrir la documentation SolarEdge
  void _openDocumentation() async {
    final url = Uri.parse('https://www.solaredge.com/sites/default/files/se_monitoring_api.pdf');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir la documentation')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextFormField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Clé API',
                        hintText: 'Saisissez votre clé API SolarEdge',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'La clé API est obligatoire';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _siteIdController,
                      decoration: const InputDecoration(
                        labelText: 'ID du site',
                        hintText: 'Saisissez l\'ID de votre site SolarEdge',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'L\'ID du site est obligatoire';
                        }
                        if (int.tryParse(value) == null) {
                          return 'L\'ID du site doit être numérique';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _maxPowerController,
                      decoration: const InputDecoration(
                        labelText: 'Puissance maximale (kW)',
                        hintText: 'Ex: 5.0',
                        helperText: 'Puissance maximale de votre installation solaire',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'La puissance maximale est obligatoire';
                        }
                        if (double.tryParse(value) == null) {
                          return 'Veuillez saisir un nombre valide';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isTesting ? null : _testConnection,
                            child: _isTesting
                                ? const CircularProgressIndicator()
                                : const Text('Tester la connexion'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _saveSettings,
                            child: _isLoading
                                ? const CircularProgressIndicator()
                                : const Text('Sauvegarder'),
                          ),
                        ),
                      ],
                    ),
                    if (_testConnectionResult != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(
                          _testConnectionResult!,
                          style: TextStyle(
                            color: _testConnectionSuccess ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _openDocumentation,
                      child: const Text('Documentation API SolarEdge'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}