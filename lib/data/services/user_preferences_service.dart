import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'; // Import pour debugPrint
import '../models/user_preferences.dart';

class UserPreferencesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Sauvegarder les préférences utilisateur dans Firestore
  Future<void> saveUserPreferences(User user, UserPreferences preferences) async {
    debugPrint('DEBUG UserPreferencesService: Tentative de sauvegarde des préférences pour l\'utilisateur ${user.uid}. Authentifié: ${user.isAnonymous ? 'Anonyme' : 'Oui'}.');
    try {
      await _firestore
          .collection('userpreferences')
          .doc(user.uid)
          .set(preferences.toJson());
      debugPrint('INFO UserPreferencesService: Préférences utilisateur sauvegardées avec succès pour ${user.uid}.');
    } catch (e) {
      debugPrint('ERROR UserPreferencesService: Erreur lors de la sauvegarde des préférences utilisateur pour ${user.uid}: $e');
      print('Erreur lors de la sauvegarde des préférences utilisateur: $e'); // Garder le print pour les logs
      rethrow;
    }
  }

  // Charger les préférences utilisateur depuis Firestore
  Future<UserPreferences?> loadUserPreferences(User user) async {
    try {
      final doc = await _firestore
          .collection('userpreferences')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        return UserPreferences.fromJson(doc.data()!);
      } else {
        return null; // Aucune préférence trouvée pour cet utilisateur
      }
    } catch (e) {
      print('Erreur lors du chargement des préférences utilisateur: $e');
      return null;
    }
  }
}
