import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
// import 'package:get_it/get_it.dart'; // Import pour GetIt (peut être retiré si plus utilisé du tout) - Retiré car non utilisé
// import 'package:hive/hive.dart'; // Remplacé par UserPreferencesService
import '../models/user_preferences.dart'; // Import du modèle UserPreferences
import 'user_preferences_service.dart'; // Import du nouveau service

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final UserPreferencesService _userPreferencesService; // Rendre final et injecter

  // Constructeur pour injecter UserPreferencesService
  AuthService({required UserPreferencesService userPreferencesService})
      : _userPreferencesService = userPreferencesService;

  // Stream pour suivre l'état de l'authentification
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  // Obtenir l'utilisateur actuel
  User? get currentUser => _auth.currentUser;
  
  // Connexion avec Google
  Future<UserCredential> signInWithGoogle() async {
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      // Abort if the user cancelled the sign-in
      if (googleUser == null) {
        throw Exception('Google sign-in cancelled by the user');
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      // Create a new credential
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final UserCredential userCredential = await _auth.signInWithCredential(credential);

      return userCredential;
    } catch (e) {
      debugPrint('Error during Google sign-in: $e');
      rethrow;
    }
  }
  
  // Connexion avec email et mot de passe
  Future<UserCredential> signInWithEmailAndPassword(String email, String password) async {
    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Sauvegarder/charger les préférences utilisateur après connexion - Plus nécessaire avec Firestore unique
      // await _handleUserPreferences(userCredential.user!);

      return userCredential;
    } catch (e) {
      debugPrint('Erreur lors de la connexion par email: $e');
      rethrow;
    }
  }

  // Connexion anonyme
  Future<UserCredential> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();
      debugPrint('INFO: Connexion anonyme réussie pour ${userCredential.user?.uid}.');
      // Pas besoin de gérer les préférences ici, car c'est souvent pour un accès temporaire
      // ou avant une mise à niveau vers un compte permanent.
      return userCredential;
    } catch (e) {
      debugPrint('Erreur lors de la connexion anonyme: $e');
      rethrow;
    }
  }
  
  // Inscription avec email et mot de passe
  Future<UserCredential> registerWithEmailAndPassword(String email, String password) async {
    try {
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Sauvegarder/charger les préférences utilisateur après inscription - Plus nécessaire avec Firestore unique
      // await _handleUserPreferences(userCredential.user!);

      return userCredential;
    } catch (e) {
      debugPrint('Erreur lors de l\'inscription: $e');
      rethrow;
    }
  }
  
  // Gérer la sauvegarde/le chargement des préférences utilisateur après connexion/inscription - Supprimé car Hive n'est plus utilisé pour UserPreferences
  // Future<void> _handleUserPreferences(User user) async {
  //   try {
  //     // Charger les préférences depuis Firestore
  //     final firestorePrefs = await _userPreferencesService.loadUserPreferences(user);

  //     // Charger les préférences locales (Hive)
  //     final Box<UserPreferences> preferencesBox = await Hive.openBox<UserPreferences>('userPreferences');
  //     final localPrefs = preferencesBox.get('preferences'); // Supposons que la clé est 'preferences'

  //     if (firestorePrefs != null) {
  //       // Si des préférences existent dans Firestore, les utiliser et potentiellement mettre à jour Hive
  //       if (localPrefs == null || localPrefs.solarEdgeApiKey != firestorePrefs.solarEdgeApiKey || localPrefs.siteId != firestorePrefs.siteId) {
  //          // Mettre à jour Hive si les préférences Firestore sont différentes ou si Hive est vide
  //          await preferencesBox.put('preferences', firestorePrefs);
  //       }
  //     } else if (localPrefs != null && (localPrefs.solarEdgeApiKey != null || localPrefs.siteId != null)) {
  //       // Si aucune préférence dans Firestore mais des préférences locales existent (avec API/Site ID), les sauvegarder dans Firestore
  //       await _userPreferencesService.saveUserPreferences(user, localPrefs);
  //     }

  //     await preferencesBox.close(); // Fermer la box Hive
  //   } catch (e) {
  //     debugPrint('Erreur lors de la gestion des préférences utilisateur: $e');
  //     // Continuer même en cas d'erreur pour ne pas bloquer la connexion
  //   }
  // }

  // Sauvegarder les préférences API et Site ID pour l'utilisateur actuellement connecté
  Future<void> saveApiPreferencesForCurrentUser(UserPreferences preferences) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        await _userPreferencesService.saveUserPreferences(user, preferences);
        debugPrint('INFO: Préférences API sauvegardées dans Firestore pour ${user.uid}.');
      } else {
        debugPrint('WARNING: Impossible de sauvegarder les préférences API dans Firestore, aucun utilisateur connecté.');
        // Optionnel: Gérer ce cas, par exemple en demandant à l'utilisateur de se connecter
      }
    } catch (e) {
      debugPrint('Erreur lors de la sauvegarde des préférences API dans Firestore: $e');
      rethrow;
    }
  }


  // Déconnexion
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut(); // Déconnexion de Google (si connecté via Google)
      await _auth.signOut(); // Déconnexion de Firebase
    } catch (e) {
      debugPrint('Erreur lors de la déconnexion: $e');
      rethrow;
    }
  }
  
  // Réinitialiser le mot de passe
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      debugPrint('Erreur lors de la réinitialisation du mot de passe: $e');
      rethrow;
    }
  }
  
  // Mettre à jour le profil utilisateur
  Future<void> updateUserProfile({String? displayName, String? photoURL}) async {
    try {
      if (_auth.currentUser != null) {
        await _auth.currentUser!.updateProfile(
          displayName: displayName,
          photoURL: photoURL,
        );
      }
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour du profil: $e');
      rethrow;
    }
  }
  
  // Vérifier l'email
  Future<void> sendEmailVerification() async {
    try {
      if (_auth.currentUser != null && !_auth.currentUser!.emailVerified) {
        await _auth.currentUser!.sendEmailVerification();
      }
    } catch (e) {
      debugPrint('Erreur lors de l\'envoi de la vérification d\'email: $e');
      rethrow;
    }
  }
  
  // Mettre à jour l'email
  Future<void> updateEmail(String newEmail) async {
    try {
      if (_auth.currentUser != null) {
        await _auth.currentUser!.updateEmail(newEmail);
      }
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour de l\'email: $e');
      rethrow;
    }
  }
  
  // Mettre à jour le mot de passe
  Future<void> updatePassword(String newPassword) async {
    try {
      if (_auth.currentUser != null) {
        await _auth.currentUser!.updatePassword(newPassword);
      }
    } catch (e) {
      debugPrint('Erreur lors de la mise à jour du mot de passe: $e');
      rethrow;
    }
  }
  
  // Obtenir le token FCM pour les notifications
  Future<String?> getFCMToken() async {
    try {
      User? user = _auth.currentUser;
      if (user != null) {
        // Cette méthode est fictive, il faudrait utiliser FirebaseMessaging pour obtenir un vrai token
        // return await FirebaseMessaging.instance.getToken();
        return 'fcm_token_example';
      }
      return null;
    } catch (e) {
      debugPrint('Erreur lors de la récupération du token FCM: $e');
      return null;
    }
  }
}
