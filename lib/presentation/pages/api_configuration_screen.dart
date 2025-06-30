import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import pour FilteringTextInputFormatter
import 'package:provider/provider.dart'; // Import Provider
import 'package:solaredge_monitor/data/models/user_preferences.dart'; // Import UserPreferences
import 'package:solaredge_monitor/data/services/auth_service.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Import ServiceManager
import 'package:solaredge_monitor/data/services/user_preferences_service.dart'; // Import UserPreferencesService
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';

class ApiConfigurationScreen extends StatefulWidget {
  final String errorMessage;
  final VoidCallback onRetry;
  final bool isApiKeyMissing;

  const ApiConfigurationScreen({
    super.key,
    required this.errorMessage,
    required this.onRetry,
    this.isApiKeyMissing = true,
  });

  @override
  State<ApiConfigurationScreen> createState() => _ApiConfigurationScreenState();
}

class _ApiConfigurationScreenState extends State<ApiConfigurationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _siteIdController = TextEditingController();
  final TextEditingController _peakPowerController = TextEditingController(); // Contrôleur pour la puissance crête

  bool _isLoading = false;
  String? _currentErrorMessage; // Utiliser un état local pour le message d'erreur

  @override
  void initState() {
    super.initState();
    _currentErrorMessage = widget.errorMessage; // Initialiser avec le message passé
    // Optionnel: Charger les préférences existantes pour pré-remplir les champs
    _loadExistingPreferences();
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _siteIdController.dispose();
    _peakPowerController.dispose();
    super.dispose();
  }

  // Charger les préférences existantes pour pré-remplir les champs
  Future<void> _loadExistingPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userPreferencesService = Provider.of<UserPreferencesService>(context, listen: false);
        final existingPrefs = await userPreferencesService.loadUserPreferences(user);
        if (existingPrefs != null) {
          _apiKeyController.text = existingPrefs.solarEdgeApiKey ?? '';
          _siteIdController.text = existingPrefs.siteId ?? '';
          _peakPowerController.text = existingPrefs.peakPowerKw?.toString() ?? ''; // Pré-remplir la puissance crête
        }
      } catch (e) {
        debugPrint('Error loading existing preferences: $e');
        // Gérer l'erreur de chargement si nécessaire
      }
    }
  }


  // Gérer la sauvegarde des préférences API et Site ID
  Future<void> _handleSaveConfiguration() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _currentErrorMessage = null; // Effacer le message d'erreur précédent
      });

      try {
        final userPreferencesService = Provider.of<UserPreferencesService>(context, listen: false);
        final authService = Provider.of<AuthService>(context, listen: false); // Nécessaire pour obtenir l'utilisateur

        User? user = authService.currentUser;

        // Si l'utilisateur n'est pas connecté, tenter une connexion anonyme
        if (user == null) {
           debugPrint('INFO ApiConfigurationScreen: Utilisateur non connecté. Tentative de connexion anonyme...');
           try {
             final newUserCredential = await authService.signInAnonymously();
             user = newUserCredential.user;
             debugPrint('INFO ApiConfigurationScreen: Connexion anonyme réussie (${user?.uid}).');
           } catch (anonError) {
             debugPrint('ERROR ApiConfigurationScreen: Échec de la connexion anonyme: $anonError');
             setState(() {
               _currentErrorMessage = 'Impossible de se connecter anonymement pour sauvegarder les préférences: $anonError';
               _isLoading = false;
             });
             return; // Arrêter le processus si la connexion anonyme échoue
           }
        }

        if (user != null) {
           // Charger les préférences existantes pour fusionner
           final existingPrefs = await userPreferencesService.loadUserPreferences(user);

           // Créer un objet UserPreferences avec les nouvelles données API et la puissance crête
           final updatedPreferences = (existingPrefs ?? UserPreferences()).copyWith(
             solarEdgeApiKey: _apiKeyController.text.trim(),
             siteId: _siteIdController.text.trim(),
             peakPowerKw: double.tryParse(_peakPowerController.text.trim()), // Sauvegarder la puissance crête
             // Les autres préférences sont conservées par copyWith si elles existent déjà
           );

           debugPrint('DEBUG ApiConfigurationScreen: Sauvegarde des préférences API et puissance crête...');
           await userPreferencesService.saveUserPreferences(user, updatedPreferences);
           debugPrint('INFO ApiConfigurationScreen: Préférences API et puissance crête sauvegardées avec succès pour ${user.uid}.');

           // Mettre à jour l'instance de SolarEdgeApiService dans le ServiceManager
           final serviceManager = Provider.of<ServiceManager>(context, listen: false);
           await serviceManager.initializeApiServiceFromPreferences(); // Re-initialiser le service API

           // Ajouter un court délai pour permettre au Provider de se mettre à jour
           await Future.delayed(const Duration(milliseconds: 500));

           // Naviguer vers l'écran principal
           if (mounted) {
             Navigator.of(context).pushReplacementNamed('/home');
           }
        } else {
           // Ce cas ne devrait pas arriver si la connexion anonyme réussit
           setState(() {
             _currentErrorMessage = 'Erreur interne: Utilisateur non disponible après connexion anonyme.';
             _isLoading = false;
           });
        }

      } catch (e) {
        // Gérer les erreurs de sauvegarde ou d'initialisation API
        debugPrint('ERROR ApiConfigurationScreen: Erreur lors de la sauvegarde ou de l\'initialisation API: $e');
        setState(() {
          _currentErrorMessage = 'Erreur de configuration: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold( // Utiliser Scaffold pour avoir une structure de page standard
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: const Text('Configuration API'),
        backgroundColor: AppTheme.backgroundColor,
        foregroundColor: AppTheme.textPrimaryColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Form( // Utiliser un Form pour la validation
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Icône
                  Icon(
                    widget.isApiKeyMissing ? Icons.vpn_key_outlined : Icons.error_outline,
                    size: 80,
                    color: widget.isApiKeyMissing ? AppTheme.primaryColor : Colors.red,
                  ),
                  const SizedBox(height: 24),

                  // Titre
                  Text(
                    widget.isApiKeyMissing
                      ? 'Configuration API SolarEdge nécessaire'
                      : 'Problème avec l\'API SolarEdge',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),

                  // Description du problème ou message d'erreur local
                  Text(
                    _currentErrorMessage ?? widget.errorMessage, // Afficher le message local s'il existe
                    style: TextStyle(
                      fontSize: 16,
                      color: _currentErrorMessage != null ? Colors.redAccent : AppTheme.textSecondaryColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Champs de saisie
                  TextFormField(
                    controller: _apiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Clé API SolarEdge',
                      prefixIcon: Icon(Icons.key),
                      hintText: 'Votre clé API',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer votre clé API';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _siteIdController,
                    decoration: const InputDecoration(
                      labelText: 'ID du site',
                      prefixIcon: Icon(Icons.house),
                      hintText: 'L\'ID de votre installation',
                    ),
                     keyboardType: TextInputType.number, // Clavier numérique
                     inputFormatters: [FilteringTextInputFormatter.digitsOnly], // N'accepter que les chiffres
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer l\'ID de votre site';
                      }
                       if (int.tryParse(value) == null) {
                         return 'Veuillez entrer un nombre valide';
                       }
                      return null;
                    },
                  ),
                   const SizedBox(height: 16),
                   TextFormField( // Champ pour la puissance crête
                     controller: _peakPowerController,
                     decoration: const InputDecoration(
                       labelText: 'Puissance crête (kWc)',
                       prefixIcon: Icon(Icons.flash_on),
                       hintText: 'Ex: 5.0',
                     ),
                     keyboardType: TextInputType.numberWithOptions(decimal: true), // Clavier numérique avec décimales
                     inputFormatters: [
                       FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')), // N'accepter que les nombres décimaux
                     ],
                     validator: (value) {
                       if (value == null || value.isEmpty) {
                         return 'Veuillez entrer la puissance crête';
                       }
                       if (double.tryParse(value) == null || double.parse(value) <= 0) {
                         return 'Veuillez entrer un nombre positif valide';
                       }
                       return null;
                     },
                   ),


                  const SizedBox(height: 32),

                  // Bouton de sauvegarde
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleSaveConfiguration,
                    icon: _isLoading ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ) : const Icon(Icons.save),
                    label: Text(_isLoading ? 'Sauvegarde...' : 'Sauvegarder la configuration'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Bouton Réessayer (si l'erreur n'est pas due à une clé manquante)
                  if (!widget.isApiKeyMissing)
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : widget.onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer le chargement'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                    ),

                  // Étapes à suivre (uniquement pour l'absence de clé API) - Déplacé après les champs de saisie
                  if (widget.isApiKeyMissing) ...[
                    const SizedBox(height: 32),
                     const Text(
                      'Comment obtenir votre clé API et ID de site :',
                       style: TextStyle(
                         fontSize: 18,
                         fontWeight: FontWeight.bold,
                         color: AppTheme.textPrimaryColor,
                       ),
                       textAlign: TextAlign.center,
                     ),
                     const SizedBox(height: 16),
                    _buildStepCard(
                      context,
                      step: 1,
                      title: 'Connectez-vous à votre compte SolarEdge',
                      description: 'Rendez-vous sur le site monitoring.solaredge.com et connectez-vous à votre compte.',
                      icon: Icons.login,
                    ),
                    _buildStepCard(
                      context,
                      step: 2,
                      title: 'Accédez à l\'API',
                      description: 'Dans le panneau Admin, sélectionnez "Site Access" puis l\'onglet "API".',
                      icon: Icons.settings,
                    ),
                    _buildStepCard(
                      context,
                      step: 3,
                      title: 'Copiez votre clé API et ID de site',
                      description: 'Vous y trouverez la clé API et l\'ID de votre site. Entrez ces informations ci-dessus.',
                      icon: Icons.content_copy,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Widgets d'étape personnalisés (inchangé)
  Widget _buildStepCard(
    BuildContext context, {
    required int step,
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.borderRadius),
          side: const BorderSide(color: AppTheme.cardBorderColor, width: 0.5),
        ),
        color: AppTheme.cardColor,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Numéro d'étape
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    step.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Contenu de l'étape
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 20, color: AppTheme.primaryColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimaryColor,
                            ),
                            softWrap: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

