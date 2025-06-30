// lib/presentation/pages/notifications_screen.dart
// Version corrigée (retrait visualDensity + rappel pour getter)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import pour TextInputFormatter
import 'package:hive_flutter/hive_flutter.dart'; // Réimporter Hive pour NotificationModel
// import 'package:provider/provider.dart'; // Non utilisé
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart'; // Pour formatter TimeOfDay
import 'package:firebase_auth/firebase_auth.dart'; // Nécessaire pour UserPreferencesService

// Imports locaux
import '../../data/models/user_preferences.dart'; // Assurez-vous que le getter y est ajouté!
import '../../data/models/notification_model.dart';
import '../../data/services/background_worker_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/user_preferences_service.dart'; // Import du service Firestore
import '../../utils/file_logger.dart';
import '../theme/app_theme.dart'; // Import du thème existant

// --- Constantes ---
const String tag = "NotificationsScreen";

// Définition locale des paddings (car absents de AppTheme)
const double _paddingSmall = 8.0;
const double _paddingMedium = 16.0;
const double _paddingLarge = 24.0;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FileLogger _fileLogger = FileLogger();
  // late Box<UserPreferences> _userPrefsBox; // Remplacé par UserPreferencesService
  UserPreferences? _userPreferences;
  late SharedPreferences _prefs;
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService(); // Instancier le service

  bool _isLoading = true;
  bool _notificationsGloballyEnabled = true;
  int _powerCheckFrequency = 30;
  TimeOfDay _selectedSummaryTime = const TimeOfDay(hour: 18, minute: 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPreferences();
    });
  }

  @override
  void dispose() {
    // Fermer la boîte Hive lorsque le widget est supprimé - Plus nécessaire
    // if (_userPrefsBox.isOpen) {
    //   _userPrefsBox.close();
    //   _fileLogger.log('INFO $tag: Hive box "user_preferences" closed in dispose.', stackTrace: StackTrace.current);
    // }
    super.dispose();
  }

  // --- Logique de chargement/sauvegarde (modifiée pour utiliser Firestore) ---
  Future<void> _loadPreferences() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Charger les préférences depuis Firestore via le service
      final user =
          FirebaseAuth.instance.currentUser; // Obtenir l'utilisateur connecté
      if (user != null) {
        _userPreferences =
            await _userPreferencesService.loadUserPreferences(user);
        _fileLogger.log(
            'INFO $tag: Preferences loaded from Firestore for user ${user.uid}.',
            stackTrace: StackTrace.current);
      } else {
        _fileLogger.log(
            'WARNING $tag: No authenticated user found to load preferences.',
            stackTrace: StackTrace.current);
      }

      _userPreferences ??=
          UserPreferences(); // Utiliser les préférences par défaut si non trouvées

      _prefs = await SharedPreferences.getInstance();
      _notificationsGloballyEnabled =
          _prefs.getBool('notifications_enabled') ?? true;
      _powerCheckFrequency = _prefs.getInt('power_check_frequency') ?? 30;
      final timeStr = _userPreferences!.notificationSettings.dailySummaryTime;
      final parts = timeStr.split(':');
      _selectedSummaryTime = TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 18,
        minute: int.tryParse(parts[1]) ?? 0,
      );
      _fileLogger.log('INFO $tag: Preferences loaded successfully.',
          stackTrace: StackTrace.current);
    } catch (e, s) {
      _fileLogger.log('ERROR $tag: Failed to load preferences: $e',
          stackTrace: s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur chargement préférences: $e')),
        );
      }
      _userPreferences ??= UserPreferences();
      _selectedSummaryTime = const TimeOfDay(hour: 18, minute: 0);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _savePreferences() async {
    if (_userPreferences == null || !mounted) return;
    await _prefs.setInt('power_check_frequency', _powerCheckFrequency);
    await _prefs.setBool(
        'notifications_enabled', _notificationsGloballyEnabled);
    // 🔥 Ajout : Enregistrer l'heure du récapitulatif quotidien
    await _prefs.setString(
        'daily_summary_time',
        _userPreferences!.notificationSettings.dailySummaryTime);

    try {
      // Sauvegarder les préférences dans Firestore via le service
      final user =
          FirebaseAuth.instance.currentUser; // Obtenir l'utilisateur connecté
      if (user != null) {
        await _userPreferencesService.saveUserPreferences(
            user, _userPreferences!);
        _fileLogger.log(
            'INFO $tag: Preferences saved to Firestore for user ${user.uid}.',
            stackTrace: StackTrace.current);
      } else {
        _fileLogger.log(
            'WARNING $tag: No authenticated user found to save preferences.',
            stackTrace: StackTrace.current);
      }

      _fileLogger.log('INFO $tag: Preferences saved successfully.',
          stackTrace: StackTrace.current);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Préférences sauvegardées'),
              duration: Duration(seconds: 2)),
        );
      }
      // ---------- Mise à jour du worker ----------
      // Mettre à jour les préférences dans le service worker et reprogrammer les tâches
      final workerService = BackgroundWorkerService(); // Obtient l'instance
      // Assigner les préférences mises à jour au service avant de reprogrammer
      workerService.userPreferences = _userPreferences!;
      await workerService.schedulePowerCheckTask();
      await workerService.scheduleDailyProductionCheckTask();
      _fileLogger.log(
          'INFO $tag: Background tasks rescheduled after saving preferences.',
          stackTrace: StackTrace.current);
    } catch (e, s) {
      _fileLogger.log('ERROR $tag: Failed to save preferences: $e',
          stackTrace: s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur sauvegarde préférences: $e')),
        );
      }
    }
  }

  // --- Fonctions de mise à jour de l'état (inchangées pour la logique) ---
  void _updateGlobalEnable(bool value) {
    if (mounted) {
      setState(() {
        _notificationsGloballyEnabled = value;
      });
      _savePreferences();
    }
  }

  void _updatePowerCheckFrequency(double value) {
    if (mounted) {
      setState(() {
        _powerCheckFrequency = value.toInt();
      });
      // Sauvegarde déclenchée par onChangeEnd
    }
  }

  void _updatePowerNotificationEnable(bool value) {
    if (_userPreferences != null && mounted) {
      setState(() {
        _userPreferences = _userPreferences!.copyWith(
          notificationSettings: _userPreferences!.notificationSettings.copyWith(
            enablePowerNotifications: value,
          ),
        );
      });
      _savePreferences();
    }
  }

  void _updateDailySummaryEnable(bool value) {
    if (_userPreferences != null && mounted) {
      setState(() {
        _userPreferences = _userPreferences!.copyWith(
          notificationSettings: _userPreferences!.notificationSettings.copyWith(
            enableDailySummary: value,
          ),
        );
      });
      _savePreferences();
    }
  }

  Future<void> _selectSummaryTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedSummaryTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            // Utilisation de Theme.of(context).copyWith
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppTheme.primaryColor,
                  onPrimary: Colors.white,
                  surface: AppTheme.cardColor,
                  onSurface: AppTheme.textPrimaryColor,
                ),
            textButtonTheme: TextButtonThemeData(
              style:
                  TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
            ),
            dialogBackgroundColor: AppTheme.backgroundColor,
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedSummaryTime && mounted) {
      final newTimeStr =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        _selectedSummaryTime = picked;
        _userPreferences = _userPreferences!.copyWith(
          notificationSettings: _userPreferences!.notificationSettings.copyWith(
            dailySummaryTime: newTimeStr,
          ),
        );
      });
      _savePreferences();
    }
  }

  void _addOrEditCriteria(NotificationCriteria? criteria) {
    showDialog(
      context: context,
      builder: (context) => _CriteriaDialog(
        criteria: criteria,
        onSave: (newCriteria) {
          if (mounted && _userPreferences != null) {
            List<NotificationCriteria> currentCriteria =
                List.from(_userPreferences!.notificationSettings.powerCriteria);
            if (criteria == null) {
              currentCriteria.add(newCriteria);
            } else {
              final index =
                  currentCriteria.indexWhere((c) => c.id == newCriteria.id);
              if (index != -1) {
                currentCriteria[index] = newCriteria;
              } else {
                currentCriteria.add(newCriteria);
              }
            }
            setState(() {
              _userPreferences = _userPreferences!.copyWith(
                notificationSettings:
                    _userPreferences!.notificationSettings.copyWith(
                  powerCriteria: currentCriteria,
                ),
              );
            });
            _savePreferences();
          }
        },
      ),
    );
  }

  void _deleteCriteria(NotificationCriteria criteria) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: AppTheme.cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppTheme.borderRadiusLarge)),
              title: const Text('Confirmer la suppression'),
              content:
                  const Text('Voulez-vous vraiment supprimer ce critère ?'),
              actions: [
                TextButton(
                  child: const Text('Annuler'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                TextButton(
                  child: const Text('Supprimer',
                      style: TextStyle(color: Colors.redAccent)),
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (_userPreferences != null && mounted) {
                      List<NotificationCriteria> currentCriteria = List.from(
                          _userPreferences!.notificationSettings.powerCriteria);
                      currentCriteria.removeWhere((c) => c.id == criteria.id);
                      setState(() {
                        _userPreferences = _userPreferences!.copyWith(
                          notificationSettings:
                              _userPreferences!.notificationSettings.copyWith(
                            powerCriteria: currentCriteria,
                          ),
                        );
                      });
                      _savePreferences();
                    }
                  },
                ),
              ],
            ));
  }

  void _updateCriteriaEnable(NotificationCriteria criteria, bool isEnabled) {
    if (_userPreferences != null && mounted) {
      List<NotificationCriteria> currentCriteria =
          List.from(_userPreferences!.notificationSettings.powerCriteria);
      final index = currentCriteria.indexWhere((c) => c.id == criteria.id);
      if (index != -1) {
        currentCriteria[index] =
            currentCriteria[index].copyWith(isEnabled: isEnabled);
        setState(() {
          _userPreferences = _userPreferences!.copyWith(
            notificationSettings:
                _userPreferences!.notificationSettings.copyWith(
              powerCriteria: currentCriteria,
            ),
          );
        });
        _savePreferences();
      }
    }
  }

  // --- Fonctions de gestion de l'historique (inchangées) ---
  Future<void> _clearAllNotifications() async {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: AppTheme.cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppTheme.borderRadiusLarge)),
              title: const Text('Confirmer la suppression'),
              content: const Text(
                  'Voulez-vous vraiment effacer tout l\'historique ?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler')),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final notifService = NotificationService();
                    await notifService.deleteAllNotifications();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Historique des notifications effacé')),
                      );
                    }
                  },
                  child: const Text('Tout effacer',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ));
  }

  Future<void> _clearReadNotifications() async {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
              backgroundColor: AppTheme.cardColor,
              shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppTheme.borderRadiusLarge)),
              title: const Text('Confirmer la suppression'),
              content: const Text(
                  'Voulez-vous vraiment effacer les notifications lues ?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annuler')),
                TextButton(
                  onPressed: () async {
                    Navigator.of(context).pop();
                    final notifService = NotificationService();
                    await notifService.deleteAllReadNotifications();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Notifications lues effacées')),
                      );
                    }
                  },
                  child: const Text('Effacer lues',
                      style: TextStyle(color: Colors.orange)),
                ),
              ],
            ));
  }

  // --- Build Method (UI Reconstruite et Corrigée) ---
  @override
  Widget build(BuildContext context) {
    final notificationService = NotificationService();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications & Alertes'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryColor))
          : _userPreferences == null
              ? Center(
                  child: Padding(
                  padding: const EdgeInsets.all(_paddingMedium),
                  child: Text(
                    'Erreur lors du chargement des préférences de notification. Veuillez réessayer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ))
              : ListView(
                  padding: const EdgeInsets.all(_paddingMedium),
                  children: [
                    // --- Section Générale dans une Card ---
                    _buildSectionCard(
                      title: 'Paramètres Généraux',
                      icon: Icons.settings_outlined,
                      children: [
                        SwitchListTile(
                          title: const Text('Activer les notifications'),
                          secondary: const Icon(Icons.notifications_active,
                              color: AppTheme.textSecondaryColor),
                          value: _notificationsGloballyEnabled,
                          onChanged: _updateGlobalEnable,
                          activeColor: AppTheme.accentColor,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: _paddingSmall),
                          inactiveThumbColor: Colors.grey,
                          // visualDensity: VisualDensity.compact, // Retiré
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: _paddingSmall),
                          child: Row(
                            children: [
                              const Icon(Icons.timer_outlined,
                                  color: AppTheme.textSecondaryColor),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                        'Fréquence vérification puissance',
                                        style: TextStyle(fontSize: 14)),
                                    Slider(
                                      value: _powerCheckFrequency.toDouble(),
                                      min: 15,
                                      max: 180,
                                      divisions: (180 - 15) ~/ 5,
                                      label: '$_powerCheckFrequency min',
                                      activeColor: AppTheme.primaryColor,
                                      inactiveColor: AppTheme.primaryColor
                                          .withOpacity(0.3),
                                      thumbColor: AppTheme.primaryColor,
                                      onChanged: _notificationsGloballyEnabled
                                          ? _updatePowerCheckFrequency
                                          : null,
                                      onChangeEnd: (value) {
                                        if (_notificationsGloballyEnabled) {
                                          _savePreferences();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 16.0),
                                child: Text(
                                  '$_powerCheckFrequency min',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: _paddingLarge),

                    // --- Section Alertes de Puissance dans une Card ---
                    _buildSectionCard(
                      title: 'Alertes de Puissance',
                      icon: Icons.power_outlined,
                      children: [
                        SwitchListTile(
                          title: const Text('Activer les alertes de puissance'),
                          value: _userPreferences!
                              .notificationSettings.enablePowerNotifications,
                          onChanged: _notificationsGloballyEnabled
                              ? _updatePowerNotificationEnable
                              : null,
                          activeColor: AppTheme.accentColor,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: _paddingSmall),
                          inactiveThumbColor: Colors.grey,
                          // visualDensity: VisualDensity.compact, // Retiré
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        if (_userPreferences!
                            .notificationSettings.enablePowerNotifications)
                          ..._buildPowerCriteriaList(),
                        if (!_userPreferences!
                            .notificationSettings.enablePowerNotifications)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                vertical: 16.0, horizontal: _paddingSmall),
                            child: Center(
                                child: Text(
                                    'Les alertes de puissance sont désactivées.',
                                    style: TextStyle(
                                        color: AppTheme.textSecondaryColor))),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(
                              top: 8.0,
                              left: _paddingSmall,
                              right: _paddingSmall,
                              bottom: 8.0),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add_alert_outlined,
                                  size: 18),
                              label: const Text('Ajouter Critère'),
                              onPressed: _notificationsGloballyEnabled &&
                                      _userPreferences!.notificationSettings
                                          .enablePowerNotifications
                                  ? () => _addOrEditCriteria(null)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                backgroundColor: AppTheme.accentColor,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: _paddingLarge),

                    // --- Section Récapitulatif Quotidien dans une Card ---
                    _buildSectionCard(
                      title: 'Récapitulatif Quotidien',
                      icon: Icons.summarize_outlined,
                      children: [
                        SwitchListTile(
                          title:
                              const Text('Activer le récapitulatif quotidien'),
                          value: _userPreferences!
                              .notificationSettings.enableDailySummary,
                          onChanged: _notificationsGloballyEnabled
                              ? _updateDailySummaryEnable
                              : null,
                          activeColor: AppTheme.accentColor,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: _paddingSmall),
                          inactiveThumbColor: Colors.grey,
                          // visualDensity: VisualDensity.compact, // Retiré
                        ),
                        ListTile(
                          leading: const Icon(Icons.access_time_outlined,
                              color: AppTheme.textSecondaryColor),
                          title: const Text('Heure d\'envoi du récapitulatif'),
                          subtitle: Text(
                              'Programmé vers ${_selectedSummaryTime.format(context)}'),
                          trailing: const Icon(Icons.arrow_drop_down,
                              color: AppTheme.textSecondaryColor),
                          onTap: _notificationsGloballyEnabled &&
                                  _userPreferences!
                                      .notificationSettings.enableDailySummary
                              ? () => _selectSummaryTime(context)
                              : null,
                          enabled: _notificationsGloballyEnabled &&
                              _userPreferences!
                                  .notificationSettings.enableDailySummary,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: _paddingSmall),
                          // visualDensity: VisualDensity.compact, // Retiré de ListTile aussi (parfois cause erreurs)
                        ),
                      ],
                    ),
                    const SizedBox(height: _paddingLarge),

                    // --- Section Historique dans une Card ---
                    _buildSectionCard(
                      title: 'Historique des Notifications',
                      icon: Icons.history_outlined,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8.0, horizontal: _paddingSmall),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.delete_sweep_outlined,
                                    size: 18),
                                label: const Text('Effacer lues'),
                                onPressed: _clearReadNotifications,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.orange,
                                  side: const BorderSide(color: Colors.orange),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                              ),
                              OutlinedButton.icon(
                                icon: const Icon(Icons.delete_forever_outlined,
                                    size: 18),
                                label: const Text('Tout effacer'),
                                onPressed: _clearAllNotifications,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side:
                                      const BorderSide(color: Colors.redAccent),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(
                            height: 20,
                            indent: 16,
                            endIndent: 16,
                            thickness: 0.5),
                        _buildNotificationHistory(notificationService),
                      ],
                    ),
                  ],
                ),
    );
  }

  // Widget Helper pour construire une section dans une Card
  Widget _buildSectionCard(
      {required String title,
      required IconData icon,
      required List<Widget> children}) {
    final theme = Theme.of(context);
    final cardTheme = theme.cardTheme;

    return Card(
      elevation: cardTheme.elevation ?? 2.0,
      shape: cardTheme.shape ??
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.borderRadius),
            side: const BorderSide(color: AppTheme.cardBorderColor, width: 0.5),
          ),
      color: cardTheme.color ?? AppTheme.cardColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: _paddingMedium, horizontal: _paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.primaryColor, size: 20),
                const SizedBox(width: _paddingSmall),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: AppTheme.textPrimaryColor,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: _paddingMedium),
            if (children.isNotEmpty)
              const Divider(
                  height: 1, thickness: 0.5, color: AppTheme.cardBorderColor),
            const SizedBox(height: _paddingSmall),
            ...children,
          ],
        ),
      ),
    );
  }

  // Helper pour construire la liste des critères de puissance
  List<Widget> _buildPowerCriteriaList() {
    if (_userPreferences == null ||
        _userPreferences!.notificationSettings.powerCriteria.isEmpty) {
      return [
        const Padding(
          padding:
              EdgeInsets.symmetric(vertical: 16.0, horizontal: _paddingSmall),
          child: Center(
              child: Text('Aucun critère de puissance défini.',
                  style: TextStyle(color: AppTheme.textSecondaryColor))),
        )
      ];
    }

    return _userPreferences!.notificationSettings.powerCriteria.map((criteria) {
      final bool isCriteriaGloballyEnabled = _notificationsGloballyEnabled &&
          _userPreferences!.notificationSettings.enablePowerNotifications;
      final bool isCriteriaIndividuallyEnabled = criteria.isEnabled;
      final bool isFullyActive =
          isCriteriaGloballyEnabled && isCriteriaIndividuallyEnabled;

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isCriteriaGloballyEnabled
              ? () => _addOrEditCriteria(criteria)
              : null,
          borderRadius: BorderRadius.circular(AppTheme.borderRadiusSmall),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: _paddingSmall, vertical: 4.0),
            child: Row(
              children: [
                Switch(
                  value: isCriteriaIndividuallyEnabled,
                  onChanged: isCriteriaGloballyEnabled
                      ? (value) => _updateCriteriaEnable(criteria, value)
                      : null,
                  activeColor: AppTheme.accentColor,
                  inactiveThumbColor: Colors.grey[600],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  // visualDensity: VisualDensity.compact, // Retiré
                ),
                const SizedBox(width: _paddingSmall),
                Expanded(
                  child: Opacity(
                    opacity: isFullyActive ? 1.0 : 0.6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${criteria.type == 'above' ? 'Supérieur à' : 'Inférieur à'} ${criteria.threshold.toStringAsFixed(0)} ${criteria.unit}',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          // Suppression de l'affichage du cooldown
                          'Max: ${criteria.maxNotificationsPerDay}/j, ${criteria.startTime}-${criteria.endTime}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.textSecondaryColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // Utilisation du getter (vérifie qu'il est bien présent dans NotificationCriteria)
                        if (criteria.activeDays.isNotEmpty)
                          Text(
                            'Jours: ${criteria.formattedActiveDaysShort}', // Assurez-vous que ce getter existe!
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondaryColor),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Supprimer',
                  color: Colors.redAccent
                      .withOpacity(isCriteriaGloballyEnabled ? 1.0 : 0.5),
                  onPressed: isCriteriaGloballyEnabled
                      ? () => _deleteCriteria(criteria)
                      : null,
                  splashRadius: 20,
                  constraints: const BoxConstraints(),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Modifier',
                  color: AppTheme.textSecondaryColor
                      .withOpacity(isCriteriaGloballyEnabled ? 1.0 : 0.5),
                  onPressed: isCriteriaGloballyEnabled
                      ? () => _addOrEditCriteria(criteria)
                      : null,
                  splashRadius: 20,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  // Construire la liste de l'historique
  Widget _buildNotificationHistory(NotificationService notificationService) {
    final theme = Theme.of(context);
    final listenable = notificationService.getNotificationsListenable();
    if (listenable == null) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(
            child: Text(
                "Impossible d'accéder à l'historique des notifications (service non initialisé ou erreur).",
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondaryColor))),
      );
    }

    return ValueListenableBuilder<Box<NotificationModel>>(
      valueListenable: listenable,
      builder: (context, box, _) {
        // Vérifier si la boîte est ouverte et non nulle avant d'accéder aux valeurs
        final notifications = (box?.values.toList() ?? [])
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        if (notifications.isEmpty) {
          return const Padding(
            padding:
                EdgeInsets.symmetric(vertical: 16.0, horizontal: _paddingSmall),
            child: Center(
                child: Text('Aucune notification dans l\'historique.',
                    style: TextStyle(color: AppTheme.textSecondaryColor))),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: notifications.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            thickness: theme.dividerTheme.thickness ?? 0.5,
            indent: 56,
            endIndent: 16,
            color: theme.dividerTheme.color ?? AppTheme.cardBorderColor,
          ),
          itemBuilder: (context, index) {
            final notification = notifications[index];
            return ListTile(
              contentPadding: const EdgeInsets.only(
                  left: _paddingSmall, right: 0, top: 4, bottom: 4),
              leading: Icon(
                notification.isRead
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined,
                color: notification.isRead
                    ? AppTheme.textSecondaryColor.withOpacity(0.7)
                    : AppTheme.primaryColor,
              ),
              title: Text(notification.title,
                  style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: notification.isRead
                          ? AppTheme.textSecondaryColor
                          : AppTheme.textPrimaryColor)),
              subtitle: Text(
                  '${notification.body}\n${notification.formattedTimestamp}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: notification.isRead
                          ? AppTheme.textSecondaryColor.withOpacity(0.7)
                          : AppTheme.textSecondaryColor,
                      fontSize: 12)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Supprimer cette notification',
                color: AppTheme.textSecondaryColor.withOpacity(0.7),
                onPressed: () =>
                    notificationService.deleteNotification(notification.id),
                splashRadius: 20,
              ),
              onTap: () {
                if (!notification.isRead) {
                  notificationService.markNotificationAsRead(notification.id);
                }
              },
              // visualDensity: VisualDensity.compact, // Retiré
            );
          },
        );
      },
    );
  }
} // Fin _NotificationsScreenState

// --- Dialogue pour Ajouter/Modifier un Critère ---
class _CriteriaDialog extends StatefulWidget {
  final NotificationCriteria? criteria;
  final ValueChanged<NotificationCriteria> onSave;

  const _CriteriaDialog({this.criteria, required this.onSave});

  @override
  State<_CriteriaDialog> createState() => _CriteriaDialogState();
}

class _CriteriaDialogState extends State<_CriteriaDialog> {
  late TextEditingController _thresholdController;
  late TextEditingController _messageController;
  // Suppression du contrôleur de fréquence
  // late TextEditingController _frequencyController;
  late TextEditingController _maxPerDayController;

  String _type = 'above';
  String _unit = 'W';
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  List<int> _activeDays = [];
  bool _isEnabled = true;
  late String _id;

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final c = widget.criteria;
    _id = c?.id ?? const Uuid().v4();
    _type = c?.type ?? 'above';
    _unit = c?.unit ?? 'W';
    _thresholdController =
        TextEditingController(text: c?.threshold.toStringAsFixed(0) ?? '');
    _messageController = TextEditingController(text: c?.message ?? '');
    // Suppression de l'initialisation du contrôleur de fréquence
    // _frequencyController =
    //     TextEditingController(text: c?.frequency.toString() ?? '60');
    _maxPerDayController = TextEditingController(
        text: c?.maxNotificationsPerDay.toString() ?? '5');
    _startTime = c?.startTimeOfDay;
    _endTime = c?.endTimeOfDay;
    _activeDays = List<int>.from(c?.activeDays ?? [1, 2, 3, 4, 5, 6, 7]);
    _isEnabled = c?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _thresholdController.dispose();
    _messageController.dispose();
    // Suppression du dispose du contrôleur de fréquence
    // _frequencyController.dispose();
    _maxPerDayController.dispose();
    super.dispose();
  }

  String _formatTimeOfDayOrPlaceholder(TimeOfDay? tod) {
    if (tod == null) return '--:--';
    final now = DateTime.now();
    final dt = DateTime(now.year, now.month, now.day, tod.hour, tod.minute);
    return DateFormat('HH:mm').format(dt);
  }

  Future<void> _selectTime(BuildContext context, bool isStart) async {
    final initialTime = isStart
        ? (_startTime ?? const TimeOfDay(hour: 0, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 23, minute: 59));
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: AppTheme.primaryColor,
                  surface: AppTheme.cardColor,
                  onSurface: AppTheme.textPrimaryColor,
                ),
            dialogBackgroundColor: AppTheme.backgroundColor,
            textButtonTheme: TextButtonThemeData(
              style:
                  TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_activeDays.contains(day)) {
        if (_activeDays.length > 1) {
          _activeDays.remove(day);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Au moins un jour doit être sélectionné."),
              duration: Duration(seconds: 2)));
        }
      } else {
        _activeDays.add(day);
        _activeDays.sort();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dialogTheme = Theme.of(context).dialogTheme;
    final inputTheme = Theme.of(context).inputDecorationTheme;

    return AlertDialog(
      backgroundColor: AppTheme.cardColor,
      shape: dialogTheme.shape ??
          RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.borderRadiusLarge)),
      title: Text(
          widget.criteria == null
              ? 'Ajouter un Critère'
              : 'Modifier le Critère',
          style: dialogTheme.titleTextStyle),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: _type,
                  decoration: InputDecoration(
                    labelText: 'Type de condition',
                    border: inputTheme.border,
                    contentPadding: inputTheme.contentPadding,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'above', child: Text('Puissance Supérieure à')),
                    DropdownMenuItem(
                        value: 'below', child: Text('Puissance Inférieure à')),
                  ],
                  onChanged: (value) => setState(() => _type = value!),
                  validator: (value) => value == null ? 'Type requis' : null,
                ),
                const SizedBox(height: _paddingMedium),
                TextFormField(
                  controller: _thresholdController,
                  decoration: InputDecoration(
                    labelText: 'Seuil de déclenchement ($_unit)',
                    hintText: 'Ex: 3000',
                    border: inputTheme.border,
                    contentPadding: inputTheme.contentPadding,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null ||
                        value.isEmpty ||
                        double.tryParse(value) == null) {
                      return 'Nombre valide requis';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: _paddingMedium),
                TextFormField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    labelText: 'Message personnalisé (optionnel)',
                    hintText: 'La production dépasse le seuil...',
                    border: inputTheme.border,
                    contentPadding: inputTheme.contentPadding,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: _paddingMedium),
                // Suppression du TextFormField pour le cooldown
                // Row(
                //   crossAxisAlignment: CrossAxisAlignment.start,
                //   children: [
                // Expanded(
                //   child: TextFormField(
                //     controller: _frequencyController,
                //     decoration: InputDecoration(
                //       labelText: 'Cooldown (min)',
                //       hintText: 'Ex: 60',
                //       border: inputTheme.border,
                //       contentPadding: inputTheme.contentPadding,
                //     ),
                //     keyboardType: TextInputType.number,
                //     inputFormatters: [
                //       FilteringTextInputFormatter.digitsOnly
                //     ],
                //     validator: (value) {
                //       if (value == null ||
                //           value.isEmpty ||
                //           int.tryParse(value) == null ||
                //           int.parse(value) < 0) {
                //         return 'Entier >= 0 requis';
                //       }
                //       if (int.parse(value) == 0)
                //         return '0 = pas de cooldown';
                //       return null;
                //     },
                //   ),
                // ),
                // const SizedBox(width: _paddingMedium),
                // Expanded(
                //   child: // Retrait de l'Expanded inutile <-- Suppression commentaire
                TextFormField(
                  // Le TextFormField Max notifs/jour prend toute la largeur maintenant
                  controller: _maxPerDayController,
                  decoration: InputDecoration(
                    labelText: 'Max notifs/jour',
                    hintText: 'Ex: 5',
                    border: inputTheme.border,
                    contentPadding: inputTheme.contentPadding,
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value == null ||
                        value.isEmpty ||
                        int.tryParse(value) == null ||
                        int.parse(value) <= 0) {
                      return 'Entier > 0 requis';
                    }
                    return null;
                  },
                ), // Ajout de la parenthèse fermante manquante
                //   ],
                // ),
                const SizedBox(height: _paddingLarge),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Début:',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondaryColor)),
                          Text(_formatTimeOfDayOrPlaceholder(_startTime),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      TextButton(
                        child: const Text('Modifier Début'),
                        onPressed: () => _selectTime(context, true),
                      ),
                    ]),
                const SizedBox(height: _paddingSmall),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Fin:',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textSecondaryColor)),
                          Text(_formatTimeOfDayOrPlaceholder(_endTime),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      TextButton(
                        child: const Text('Modifier Fin'),
                        onPressed: () => _selectTime(context, false),
                      ),
                    ]),
                const SizedBox(height: _paddingMedium),
                const Text('Jours Actifs:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: _paddingSmall),
                Wrap(
                  spacing: 6.0,
                  runSpacing: 0.0,
                  children: List.generate(7, (index) {
                    final day = index + 1;
                    final dayChar = ['L', 'M', 'M', 'J', 'V', 'S', 'D'][index];
                    final isSelected = _activeDays.contains(day);
                    return FilterChip(
                      label: Text(dayChar),
                      selected: isSelected,
                      onSelected: (_) => _toggleDay(day),
                      // visualDensity: VisualDensity.compact, // Retiré
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSelected
                              ? AppTheme.primaryColor
                              : AppTheme.textSecondaryColor),
                      selectedColor: AppTheme.primaryColor.withOpacity(0.2),
                      checkmarkColor: AppTheme.primaryColor,
                      side: BorderSide(
                          color: isSelected
                              ? Colors.transparent
                              : AppTheme.cardBorderColor),
                    );
                  }),
                ),
                const SizedBox(height: _paddingLarge),
                SwitchListTile(
                  title: const Text('Activer ce critère'),
                  value: _isEnabled,
                  onChanged: (value) => setState(() => _isEnabled = value),
                  activeColor: AppTheme.accentColor,
                  contentPadding: EdgeInsets.zero,
                  // visualDensity: VisualDensity.compact, // Retiré
                  dense: true,
                ),
              ],
            ),
          )),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      actions: [
        TextButton(
          child: const Text('Annuler'),
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
              foregroundColor: AppTheme.textSecondaryColor),
        ),
        ElevatedButton(
          child:
              Text(widget.criteria == null ? 'Ajouter Critère' : 'Sauvegarder'),
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              // Utilisation correcte des paramètres nommés
              final newCriteria = NotificationCriteria(
                id: _id,
                type: _type,
                threshold: double.parse(_thresholdController.text),
                unit: _unit,
                message: _messageController.text.trim().isNotEmpty
                    ? _messageController.text.trim()
                    : null,
                maxNotificationsPerDay:
                    int.tryParse(_maxPerDayController.text) ?? 5,
                startTime: _startTime != null
                    ? '${_startTime!.hour.toString().padLeft(2, '0')}:${_startTime!.minute.toString().padLeft(2, '0')}'
                    : '00:00',
                endTime: _endTime != null
                    ? '${_endTime!.hour.toString().padLeft(2, '0')}:${_endTime!.minute.toString().padLeft(2, '0')}'
                    : '23:59',
                activeDays:
                    _activeDays.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : _activeDays,
                isEnabled: _isEnabled,
              );
              widget.onSave(newCriteria);
              Navigator.of(context).pop();
            }
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white),
        ),
      ],
    );
  }
}
