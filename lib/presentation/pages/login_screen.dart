import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solaredge_monitor/data/services/auth_service.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
// import 'package:hive/hive.dart'; // Remplacé par UserPreferencesService
import 'package:solaredge_monitor/data/models/user_preferences.dart'; // Import pour UserPreferences
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Import ServiceManager
import 'package:solaredge_monitor/data/services/user_preferences_service.dart'; // Import du service Firestore
import 'package:firebase_auth/firebase_auth.dart'; // Nécessaire pour obtenir l'utilisateur

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _siteIdController = TextEditingController();

  bool _isLoading = false;
  bool _showApiKeyInput = false;
  bool _isLogin = true; // Nouvelle variable d'état pour basculer entre connexion et inscription
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo et titre
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(50),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor.withOpacity(0.3),
                                blurRadius: 15,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.solar_power,
                            size: 50,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _isLogin ? 'SolarEdge Monitor' : 'Créer un compte', // Titre dynamique
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isLogin ? 'Connectez-vous pour accéder à vos données' : 'Inscrivez-vous pour commencer', // Slogan dynamique
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppTheme.textSecondaryColor,
                          ),
                        ),
                      ],
                    ).animate().fadeIn(duration: 500.ms),
                  ),

                  const SizedBox(height: 40),

                  // Afficher un message d'erreur si nécessaire
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
                        border: Border.all(color: Colors.red.withOpacity(0.5)),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ).animate().shake(),

                  if (_errorMessage != null) const SizedBox(height: 20),

                  // Formulaire de connexion ou d'inscription
                  if (!_showApiKeyInput) ...[
                    // Email
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer votre email';
                        }
                        if (!value.contains('@')) {
                          return 'Veuillez entrer un email valide';
                        }
                        return null;
                      },
                    ).animate().fadeIn(duration: 500.ms, delay: 200.ms),

                    const SizedBox(height: 20),

                    // Mot de passe
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: _isLogin ? 'Mot de passe' : 'Mot de passe (6+ caractères)', // Label dynamique
                        prefixIcon: const Icon(Icons.lock),
                      ),
                      obscureText: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return _isLogin ? 'Veuillez entrer votre mot de passe' : 'Veuillez choisir un mot de passe';
                        }
                        if (value.length < 6) {
                          return 'Le mot de passe doit contenir au moins 6 caractères';
                        }
                        return null;
                      },
                    ).animate().fadeIn(duration: 500.ms, delay: 400.ms),

                    const SizedBox(height: 30),

                    // Bouton de connexion ou d'inscription
                    ElevatedButton(
                      onPressed: _isLoading ? null : (_isLogin ? _handleEmailPasswordLogin : _handleEmailPasswordSignup), // Action dynamique
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: AppTheme.primaryColor,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 2,
                            )
                          : Text( // Retrait de const ici
                              _isLogin ? 'Se connecter' : 'S\'inscrire', // Texte dynamique
                              style: const TextStyle(fontSize: 16),
                            ),
                    ).animate().fadeIn(duration: 500.ms, delay: 600.ms),

                    const SizedBox(height: 20),

                    // Lien pour basculer entre connexion et inscription
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isLogin = !_isLogin; // Basculer l'état
                          _errorMessage = null; // Effacer les messages d'erreur
                          _formKey.currentState?.reset(); // Réinitialiser le formulaire
                        });
                      },
                      child: Text(
                        _isLogin ? 'Pas encore de compte ? S\'inscrire' : 'Déjà un compte ? Se connecter', // Texte dynamique
                        style: const TextStyle(color: AppTheme.accentColor),
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 800.ms),

                    const SizedBox(height: 20),

                    // Séparateur (uniquement en mode connexion)
                    if (_isLogin) ...[
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'OU',
                              style: TextStyle(
                                color: AppTheme.textSecondaryColor.withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ).animate().fadeIn(duration: 500.ms, delay: 1000.ms),

                      const SizedBox(height: 20),

                      // Bouton de connexion Google (uniquement en mode connexion)
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _handleGoogleLogin,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Colors.grey),
                        ),
                        icon: const Icon(Icons.login),
                        label: const Text('Continuer avec Google'),
                      ).animate().fadeIn(duration: 500.ms, delay: 1200.ms),

                      const SizedBox(height: 20),

                      // Lien pour configurer directement l'API (uniquement en mode connexion)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _showApiKeyInput = true;
                          });
                        },
                        child: const Text(
                          'Configurer directement l\'API SolarEdge',
                          style: TextStyle(color: AppTheme.accentColor),
                        ),
                      ).animate().fadeIn(duration: 500.ms, delay: 1400.ms),
                    ],
                  ] else ...[
                    // Configuration de l'API SolarEdge (inchangé)
                    const Text(
                      'Configuration de l\'API SolarEdge',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(duration: 500.ms),

                    const SizedBox(height: 20),

                    // Clé API
                    TextFormField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Clé API SolarEdge',
                        prefixIcon: Icon(Icons.key),
                        hintText: 'Votre clé API du portail SolarEdge',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer votre clé API';
                        }
                        return null;
                      },
                    ).animate().fadeIn(duration: 500.ms, delay: 200.ms),

                    const SizedBox(height: 20),

                    // ID du site
                    TextFormField(
                      controller: _siteIdController,
                      decoration: const InputDecoration(
                        labelText: 'ID du site',
                        prefixIcon: Icon(Icons.house),
                        hintText: 'L\'ID de votre installation solaire',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer l\'ID de votre site';
                        }
                        return null;
                      },
                    ).animate().fadeIn(duration: 500.ms, delay: 400.ms),

                    const SizedBox(height: 30),

                    // Bouton de validation
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleDirectApiConfig,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        backgroundColor: AppTheme.primaryColor,
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 2,
                            )
                          : const Text(
                              'Valider la configuration',
                              style: TextStyle(fontSize: 16),
                            ),
                    ).animate().fadeIn(duration: 500.ms, delay: 600.ms),

                    const SizedBox(height: 20),

                    // Retour à la connexion classique
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showApiKeyInput = false;
                        });
                      },
                      child: const Text(
                        'Retour à la connexion classique',
                        style: TextStyle(color: AppTheme.accentColor),
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 800.ms),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Méthode pour gérer la connexion avec email et mot de passe
  Future<void> _handleEmailPasswordLogin() async {
    // Valider le formulaire
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        final authService = Provider.of<AuthService>(context, listen: false);

        // Tenter de se connecter
        await authService.signInWithEmailAndPassword(
          _emailController.text.trim(),
          _passwordController.text,
        );

        // Si la connexion réussit, naviguer vers l'écran principal ou le setup
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          final bool setupComplete = prefs.getBool('setup_complete') ?? false;
          if (setupComplete) {
            Navigator.of(context).pushReplacementNamed('/home');
          } else {
            Navigator.of(context).pushReplacementNamed('/setup');
          }
        }
      } catch (e) {
        // Gérer les erreurs
        setState(() {
          _errorMessage = 'Erreur de connexion: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  // Méthode pour gérer l'inscription avec email et mot de passe (NOUVEAU)
  Future<void> _handleEmailPasswordSignup() async {
    // Valider le formulaire
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        final authService = Provider.of<AuthService>(context, listen: false);

        // Tenter de s'inscrire
        await authService.registerWithEmailAndPassword(
          _emailController.text.trim(),
          _passwordController.text,
        );

        // Si l'inscription réussit, naviguer vers l'écran principal (ou un écran de confirmation)
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          final bool setupComplete = prefs.getBool('setup_complete') ?? false;
          if (setupComplete) {
            Navigator.of(context).pushReplacementNamed('/home');
          } else {
            Navigator.of(context).pushReplacementNamed('/setup');
          }
        }
      } catch (e) {
        // Gérer les erreurs
        setState(() {
          _errorMessage = 'Erreur d\'inscription: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }


  // Méthode pour gérer la connexion avec Google
  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);

      // Tenter de se connecter avec Google
      await authService.signInWithGoogle();

      // Si la connexion réussit, naviguer vers l'écran principal
      if (mounted) {
        final prefs = await SharedPreferences.getInstance();
        final bool setupComplete = prefs.getBool('setup_complete') ?? false;
        if (setupComplete) {
          Navigator.of(context).pushReplacementNamed('/home');
        } else {
          Navigator.of(context).pushReplacementNamed('/setup');
        }
      }
    } catch (e) {
      // Gérer les erreurs
      setState(() {
        _errorMessage = 'Erreur de connexion Google: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  // Méthode pour configurer directement l'API
  Future<void> _handleDirectApiConfig() async {
    // Valider le formulaire
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        // Récupérer les instances nécessaires
        final authService = Provider.of<AuthService>(context, listen: false);
        final userPreferencesService = UserPreferencesService(); // Instancier le service

        // Créer un objet UserPreferences avec les données API
        // Charger les préférences existantes depuis Firestore si l'utilisateur est connecté
        UserPreferences? existingPreferences;
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          existingPreferences = await userPreferencesService.loadUserPreferences(user);
        }

        // Fusionner les nouvelles données API avec les préférences existantes ou utiliser les valeurs par défaut
        final userPreferences = (existingPreferences ?? UserPreferences()).copyWith(
          solarEdgeApiKey: _apiKeyController.text.trim(),
          siteId: _siteIdController.text.trim(),
          // Les autres préférences sont conservées par copyWith si elles existent déjà
        );


        print('DEBUG LoginScreen: Sauvegarde des préférences API...');

        // Déclencher la logique de sauvegarde dans Firebase via UserPreferencesService
        // Cela suppose que l'utilisateur est déjà connecté (même anonymement)
        // Si l'utilisateur n'est pas connecté, il faudrait peut-être le connecter anonymement ici.
        if (user != null) {
           print('DEBUG LoginScreen: Utilisateur connecté (${user.uid}), appel à userPreferencesService.saveUserPreferences...');
           await userPreferencesService.saveUserPreferences(user, userPreferences);
            print('DEBUG LoginScreen: userPreferencesService.saveUserPreferences terminé.');
         } else {
           print('INFO LoginScreen: Utilisateur non connecté. Tentative de connexion anonyme...');
           try {
             // Tenter une connexion anonyme
             final newUserCredential = await authService.signInAnonymously();
             final anonymousUser = newUserCredential.user;
             if (anonymousUser != null) {
                print('INFO LoginScreen: Connexion anonyme réussie (${anonymousUser.uid}). Nouvelle tentative de sauvegarde des préférences API...');
                // Réessayer de sauvegarder les préférences avec l'utilisateur anonyme
                await userPreferencesService.saveUserPreferences(anonymousUser, userPreferences);
                print('DEBUG LoginScreen: userPreferencesService.saveUserPreferences terminé après connexion anonyme.');
             } else {
                print('ERROR LoginScreen: Connexion anonyme réussie mais utilisateur est null.');
                // Gérer ce cas si nécessaire
             }

           } catch (anonError) {
             print('ERROR LoginScreen: Échec de la connexion anonyme ou de la sauvegarde post-anonyme: $anonError');
             // Si la connexion anonyme échoue, on ne peut pas sauvegarder dans Firestore.
             // On pourrait afficher une erreur plus spécifique ici si nécessaire.
             // throw Exception('Impossible de sauvegarder les préférences API sans connexion.'); // Optionnel: Lancer une erreur pour informer l'utilisateur
           }
         }

         // Mettre à jour l'instance de SolarEdgeApiService dans le ServiceManager
        final serviceManager = ServiceManager(); // Obtenir l'instance du ServiceManager
        // Le ServiceManager doit maintenant charger les préférences depuis Firestore
        await serviceManager.initializeApiServiceFromPreferences(); // Appeler la méthode

        // Ajouter un court délai pour permettre au Provider de se mettre à jour
        await Future.delayed(const Duration(milliseconds: 500)); // Délai ajouté

        // Naviguer vers l'écran principal
        if (mounted) {
          final prefs = await SharedPreferences.getInstance();
          final bool setupComplete = prefs.getBool('setup_complete') ?? false;
          if (setupComplete) {
            Navigator.of(context).pushReplacementNamed('/home');
          } else {
            Navigator.of(context).pushReplacementNamed('/setup');
          }
        }
      } catch (e) {
        // Gérer les erreurs
        setState(() {
          _errorMessage = 'Erreur de configuration: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _apiKeyController.dispose();
    _siteIdController.dispose();
    super.dispose();
  }
}
