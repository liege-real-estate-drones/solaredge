// solaredge_monitor/lib/data/services/notification_service.dart
// lib/data/services/notification_service.dart
// Version corrigée (onDidReceiveLocalNotification retiré)

import 'dart:async';
import 'dart:convert'; // Pour jsonEncode/Decode si utilisé dans payload
import 'dart:developer'; // Pour log

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'; // Pour kIsWeb
import 'package:flutter/material.dart'; // Pour BuildContext, WidgetsFlutterBinding etc.
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../utils/file_logger.dart';
import '../models/notification_model.dart'; // Modèle pour Hive
// Pas besoin de ServiceManager ici si on obtient les instances autrement

// --- Constantes ---
const String tag = "NotificationService";
// Récupérer les définitions des canaux depuis background_worker_service ou les redéfinir ici
const AndroidNotificationChannel userAlertChannel = AndroidNotificationChannel(
    'solaredge_channel_id', 'Alertes SolarEdge',
    description:
        'Notifications importantes concernant votre production solaire.',
    importance: Importance.max);
const AndroidNotificationChannel backgroundServiceChannel =
    AndroidNotificationChannel(
        'solaredge_background_service_channel', 'Service Arrière-Plan',
        description:
            'Notification indiquant que l\'application surveille en arrière-plan.',
        importance: Importance.low,
        showBadge: false);

// --- Handler de messages FCM en arrière-plan (niveau supérieur) ---
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // IMPORTANT: Isolate séparé. Initialisation minimale.
  final fileLogger = FileLogger();
  // Il faut appeler initialize() avant d'utiliser le logger
  await fileLogger.initialize();
  fileLogger.log(
      'INFO $tag: Handling a background message ${message.messageId}',
      stackTrace: StackTrace.current);
  log('$tag: Handling a background message ${message.messageId}');
  // Logic pour afficher notif locale si data-only message...
}

// --- Classe NotificationService ---
class NotificationService {
  // Singleton
  static NotificationService? _instance;
  factory NotificationService() {
    _instance ??= NotificationService._internal();
    return _instance!;
  }
  NotificationService._internal();

  /// Génère un ID sûr (0 … 2 147 483 647)
  int generateNotifId() => DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  // late final FirebaseMessaging _firebaseMessaging; // Remove late final
  final FileLogger _fileLogger = FileLogger();

  // Getter pour accéder à FirebaseMessaging.instance à la demande
  FirebaseMessaging get _firebaseMessagingInstance {
    return FirebaseMessaging.instance;
  }

  Box<NotificationModel>? _notificationBox;

  // --- Initialisation ---
  Future<void> initialize(BuildContext? context) async {
    // debugPrint('$tag: Initializing NotificationService...'); // Added log
    await _fileLogger.initialize(); // Assurer init logger
    _fileLogger.log('INFO $tag: Initializing NotificationService...',
        stackTrace: StackTrace.current);
    // log('$tag: Initializing...');

    // 1. Initialiser Hive Box
    try {
      if (!Hive.isBoxOpen('notifications')) {
        _notificationBox =
            await Hive.openBox<NotificationModel>('notifications');
        _fileLogger.log(
            'INFO $tag: Hive box "notifications" opened by NotificationService.',
            stackTrace: StackTrace.current);
      } else {
        _notificationBox = Hive.box<NotificationModel>('notifications');
        _fileLogger.log(
            'INFO $tag: Accessed already open Hive box "notifications".',
            stackTrace: StackTrace.current);
      }
    } catch (e, s) {
      _fileLogger.log('ERROR $tag: Failed to open Hive box "notifications": $e',
          stackTrace: s);
    }

    // 2. Initialiser FlutterLocalNotifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // *** CORRECTION ICI : Retrait de onDidReceiveLocalNotification ***
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      // onDidReceiveLocalNotification: _onDidReceiveLocalNotification, // <= PARAMÈTRE SUPPRIMÉ
    );
    // *** FIN CORRECTION ***

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
    // _fileLogger.log('INFO $tag: FlutterLocalNotifications initialized.',
    //     stackTrace: StackTrace.current);

    // _firebaseMessaging = FirebaseMessaging.instance; // Remove initialization here

    // 3. Configurer les canaux
    await _createNotificationChannels();

    // 4. Configurer FCM en utilisant le getter
    await _setupFCM(context);

    // 5. Demander la permission (si contexte dispo)
    if (context != null && !kIsWeb) {
      await requestNotificationPermission(context);
    }

    _fileLogger.log('INFO $tag: Initialization complete.',
        stackTrace: StackTrace.current);
    // log('$tag: Initialization complete.');
  }

  // --- Méthode pour afficher une notification depuis le background ---
  // Appelée par BackgroundWorkerService après vérification des règles
  Future<void> showBackgroundNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
    AndroidNotificationChannel channel = userAlertChannel, // Canal par défaut
  }) async {
    // Log ajouté au tout début de la fonction
    _fileLogger.log(
        'INFO $tag: >>> ENTERING showBackgroundNotification (ID: $id, Title: "$title")',
        stackTrace: StackTrace.current);

    _fileLogger.log('INFO $tag: showBackgroundNotification CALLED ...',
        stackTrace: StackTrace.current); // Log added
    // Assurer l'initialisation du logger et du plugin (peut être redondant si déjà fait)
    if (!_fileLogger.isInitialized) await _fileLogger.initialize();
    _fileLogger.log(
        'INFO $tag: showBackgroundNotification START (ID: $id, Title: "$title", Payload: "$payload")', // Log start with content
        stackTrace: StackTrace.current);

    // Préparer les détails Android/iOS
    final androidDetails = AndroidNotificationDetails(
      channel.id,
      channel.name,
      channelDescription: channel.description,
      importance: channel.importance,
      priority: channel.importance == Importance.max
          ? Priority.high
          : Priority.defaultPriority,
      // Ajoute d'autres options si nécessaire (style, icône, etc.)
      // Assurer que l'icône est correctement référencée
      icon: '@mipmap/ic_launcher', // Explicitly set default icon
    );
    const iosDetails = DarwinNotificationDetails(
        presentSound: true, presentBadge: true, presentAlert: true);
    final platformDetails =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    try {
      _fileLogger.log(
          'INFO $tag: Attempting _flutterLocalNotificationsPlugin.show() ...',
          stackTrace: StackTrace.current); // Log added
      _fileLogger.log(
          'INFO $tag: Before calling _flutterLocalNotificationsPlugin.show (ID: $id)',
          stackTrace: StackTrace.current);

      // Log juste avant l'appel show
      _fileLogger.log(
          'INFO $tag: Calling _flutterLocalNotificationsPlugin.show with ID: $id',
          stackTrace: StackTrace.current); // Utilise l'ID passé en paramètre

      // Afficher la notification via le plugin
      await _flutterLocalNotificationsPlugin.show(
        id, // Utilise l'ID passé en paramètre
        title, // Utilise le titre passé en paramètre
        body, // Utilise le corps passé en paramètre
        platformDetails, // Utilise les détails de plateforme préparés
        payload: payload, // Utilise le payload passé en paramètre
      );

      // Log juste après l'appel show
      _fileLogger.log(
          'INFO $tag: _flutterLocalNotificationsPlugin.show() call finished.',
          stackTrace: StackTrace.current);

      _fileLogger.log(
          'INFO $tag: _flutterLocalNotificationsPlugin.show() COMPLETED ...',
          stackTrace: StackTrace.current); // Log added
      _fileLogger.log(
          'INFO $tag: After calling _flutterLocalNotificationsPlugin.show (ID: $id)',
          stackTrace: StackTrace.current);

      // Sauvegarder dans Hive
      // Vérifie et (ré)ouvre la box si nécessaire
      if (!Hive.isBoxOpen('notifications')) {
        await Hive.openBox<NotificationModel>('notifications');
        _fileLogger.log(
            'INFO $tag: Hive box "notifications" reopened for saving.',
            stackTrace: StackTrace.current);
      }
      _notificationBox ??= Hive.box<NotificationModel>(
          'notifications'); // Assure que _notificationBox est assigné

      if (_notificationBox != null && _notificationBox!.isOpen) {
        _fileLogger.log('INFO $tag: Attempting to save notification to Hive...',
            stackTrace: StackTrace.current); // Log added
        _fileLogger.log('INFO $tag: Before saving notification $id to Hive.',
            stackTrace: StackTrace.current);
        final notificationModel = NotificationModel(
          id: id
              .toString(), // Utiliser l'ID int converti en String pour la clé Hive
          title: title,
          body: body,
          timestamp: DateTime.now(),
          type: payload.startsWith('criteria_')
              ? 'criteria'
              : (payload.startsWith('daily_summary') ? 'recap' : 'system'),
          isRead: false,
          data: {'payload': payload}, // Stocker le payload original
        );
        // Utilise put() avec l'ID de la notification comme clé pour permettre une suppression facile
        await _notificationBox!.put(notificationModel.id, notificationModel);
        _fileLogger.log('INFO $tag: Notification ... saved/updated in Hive.', // Log mis à jour
            stackTrace: StackTrace.current);
        _fileLogger.log(
            'INFO $tag: Notification ${notificationModel.id} saved/updated in Hive using put().', // Log mis à jour
            stackTrace: StackTrace.current);
      } else {
        _fileLogger.log(
            'ERROR $tag: Cannot save notification $id to Hive, box is not open after attempting to reopen.', // Message d'erreur mis à jour
            stackTrace: StackTrace.current);
      }
    } catch (e, s) {
      _fileLogger.log(
          'ERROR $tag: Exception caught in showBackgroundNotification (ID: $id): $e',
          stackTrace: s);
      _fileLogger.log(
          'ERROR $tag: Stack trace for exception in showBackgroundNotification (ID: $id): $s',
          stackTrace: StackTrace.current); // Log stack trace explicitly
      debugPrint(
          '🔴 showBackgroundNotification EXCEPTION → $e'); // Added debug print
    }
    _fileLogger.log('INFO $tag: showBackgroundNotification END (ID: $id)',
        stackTrace: StackTrace.current);
  }

  Future<void> _createNotificationChannels() async {
    try {
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(userAlertChannel);
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(backgroundServiceChannel);
      // _fileLogger.log(
      //     'INFO $tag: Notification channels checked/created by NotificationService.',
      //     stackTrace: StackTrace.current);
    } catch (e, s) {
      _fileLogger.log('ERROR $tag: Notification channel creation failed: $e',
          stackTrace: s);
    }
  }

  // --- Configuration FCM ---
  Future<void> _setupFCM(BuildContext? context) async {
    // _fileLogger.log('INFO $tag: Setting up FCM handlers...',
    //     stackTrace: StackTrace.current);
    try {
      // Utiliser le getter pour accéder à FirebaseMessaging.instance
      NotificationSettings settings =
          await _firebaseMessagingInstance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      _fileLogger.log(
          'INFO $tag: FCM Permission status: ${settings.authorizationStatus}',
          stackTrace: StackTrace.current);

      // Log et récupération du token
      String? token = await _firebaseMessagingInstance.getToken(); // Use getter
      if (token != null) {
        _fileLogger.log('INFO $tag: FCM Token obtained.',
            stackTrace: StackTrace.current);
      } else {
        _fileLogger.log('WARNING $tag: FCM Token is null.',
            stackTrace: StackTrace.current);
      }

      _firebaseMessagingInstance.onTokenRefresh.listen((newToken) {
        // Use getter
        _fileLogger.log('INFO $tag: FCM Token refreshed.',
            stackTrace: StackTrace.current);
        // Logique pour mettre à jour le token sur le serveur si nécessaire
      });
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // Use class directly
        _fileLogger.log('INFO $tag: FCM Message received in foreground.',
            stackTrace: StackTrace.current);
        if (message.notification != null) {
          _showForegroundFCMNotification(message);
        }
      });
      RemoteMessage? initialMessage =
          await _firebaseMessagingInstance.getInitialMessage(); // Use getter
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage, true);
      }
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        // Use class directly
        _handleMessageOpenedApp(message, false);
      });
      // _fileLogger.log('INFO $tag: FCM Handlers configured.',
      //     stackTrace: StackTrace.current);
    } catch (e, s) {
      _fileLogger.log('ERROR $tag: FCM Setup failed: $e', stackTrace: s);
    }
  }

  Future<void> _showForegroundFCMNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;
    if (notification != null && android != null && !kIsWeb) {
      const AndroidNotificationChannel fcmChannel = AndroidNotificationChannel(
          'fcm_fallback_channel', 'Messages FCM',
          description: 'Notifications reçues via Firebase Cloud Messaging.',
          importance: Importance.max);
      // S'assurer que le canal existe (bonne pratique)
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(fcmChannel);

      await _flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
            android: AndroidNotificationDetails(
              fcmChannel.id, fcmChannel.name,
              channelDescription: fcmChannel.description,
              icon: android.smallIcon ?? '@mipmap/ic_launcher', // Default icon
            ),
            iOS: const DarwinNotificationDetails()),
        payload: jsonEncode(message.data),
      );
      _fileLogger.log(
          'INFO $tag: Shown local notification for foreground FCM message.',
          stackTrace: StackTrace.current);
    }
  }

  void _handleMessageOpenedApp(RemoteMessage message, bool fromTerminated) {
    _fileLogger.log(
        'INFO $tag: FCM Notification tapped (fromTerminated: $fromTerminated).',
        stackTrace: StackTrace.current);
    log('$tag: FCM tapped (fromTerminated: $fromTerminated): ${message.data}');
    // Navigation logic here...
  }

  // --- Callbacks pour Notifications Locales ---
  // Callback principal pour les taps sur les notifications locales (app ouverte ou en background)
  Future<void> _onDidReceiveNotificationResponse(
      NotificationResponse notificationResponse) async {
    final String? payload = notificationResponse.payload;
    final int? id = notificationResponse.id;
    _fileLogger.log('INFO $tag: Local notification tapped (ID: $id).',
        stackTrace: StackTrace.current);
    log('$tag: Local notification tapped (ID: $id, Payload: $payload)');

    if (payload != null) {
      try {
        Map<String, dynamic> payloadData = jsonDecode(payload);
        if (payloadData.containsKey('hiveId')) {
          String hiveId = payloadData['hiveId'];
          await markNotificationAsRead(hiveId);
          _fileLogger.log(
              'INFO $tag: Marked notification $hiveId as read via payload.',
              stackTrace: StackTrace.current);
        }
      } catch (e) {
        _fileLogger.log(
            'WARNING $tag: Could not parse payload or find hiveId for notification $id: $e',
            stackTrace: StackTrace.current);
      }
    }
    // Navigation logic based on payload...
  }

  // Callback pour les taps quand l'app est terminée
  @pragma('vm:entry-point')
  static void notificationTapBackground(
      NotificationResponse notificationResponse) {
    // Isolate séparé
    final fileLogger = FileLogger();
    fileLogger.initialize().then((_) {
      fileLogger.log(
          // Utiliser l'instance locale
          'INFO $tag: Background tap handler invoked for notification ${notificationResponse.id}',
          stackTrace: StackTrace.current);
      log('$tag: notificationTapBackground received: ${notificationResponse.payload}');
      // Traitement du payload, ex: sauvegarder ID pour marquer lu au prochain démarrage
    });
  }

  // --- Gestion des Permissions ---
  Future<bool> requestNotificationPermission(BuildContext context) async {
    // _fileLogger.log('INFO $tag: Requesting notification permission...',
    //     stackTrace: StackTrace.current);
    try {
      PermissionStatus status = await Permission.notification.request();
      _fileLogger.log(
          'INFO $tag: Notification permission status: ${status.name}',
          stackTrace: StackTrace.current);
      if (status.isGranted) return true;
      if (status.isPermanentlyDenied) {
        _fileLogger.log(
            'WARNING $tag: Notification permission permanently denied.',
            stackTrace: StackTrace.current);
        // _showPermissionDeniedDialog(context); // Optionnel
      } else {
        _fileLogger.log('WARNING $tag: Notification permission denied.',
            stackTrace: StackTrace.current);
      }
    } catch (e, s) {
      _fileLogger.log(
          'ERROR $tag: Error requesting notification permission: $e',
          stackTrace: s);
    }
    return false;
  }

  // --- Gestion des Notifications dans Hive ---
  Future<void> markNotificationAsRead(String notificationId) async {
    if (_notificationBox == null || !_notificationBox!.isOpen) {
      _fileLogger.log(
          'ERROR $tag: Cannot mark notification $notificationId as read, box is not open.',
          stackTrace: StackTrace.current);
      return;
    }
    try {
      final notification = _notificationBox!.get(notificationId);
      if (notification != null && !notification.isRead) {
        final updatedNotification = notification.copyWith(isRead: true);
        await _notificationBox!.put(notificationId, updatedNotification);
        _fileLogger.log(
            'INFO $tag: Notification $notificationId marked as read.',
            stackTrace: StackTrace.current);
      }
    } catch (e, s) {
      _fileLogger.log(
          'ERROR $tag: Failed to mark notification $notificationId as read: $e',
          stackTrace: s);
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    if (_notificationBox == null || !_notificationBox!.isOpen) {
      _fileLogger.log(
          'ERROR $tag: Cannot delete notification $notificationId as read, box is not open.',
          stackTrace: StackTrace.current);
      return;
    }
    try {
      await _notificationBox!.delete(notificationId);
      _fileLogger.log(
          'INFO $tag: Notification $notificationId deleted from Hive.',
          stackTrace: StackTrace.current);
    } catch (e, s) {
      _fileLogger.log(
          'ERROR $tag: Failed to delete notification $notificationId from Hive: $e',
          stackTrace: s);
    }
  }

  Future<void> deleteAllReadNotifications() async {
    if (_notificationBox == null || !_notificationBox!.isOpen) return;
    try {
      // Récupère les clés des notifications lues sans caster en String
      final keysToDelete = _notificationBox!.keys.where((key) {
        final notification = _notificationBox!.get(key); // Pas besoin de cast explicite ici
        return notification?.isRead ?? false;
      }).toList(); // Garde le type original de la clé (dynamic, mais Hive le gère)

      if (keysToDelete.isNotEmpty) {
        await _notificationBox!.deleteAll(keysToDelete);
        _fileLogger.log(
            'INFO $tag: Deleted ${keysToDelete.length} read notifications.',
            stackTrace: StackTrace.current);
      }
    } catch (e, s) {
      _fileLogger.log('ERROR $tag: Failed to delete read notifications: $e',
          stackTrace: s);
    }
  }

  Future<void> deleteAllNotifications() async {
    if (_notificationBox == null || !_notificationBox!.isOpen) return;
    try {
      int count = await _notificationBox!.clear();
      _fileLogger.log('INFO $tag: Deleted all $count notifications from Hive.',
          stackTrace: StackTrace.current);
    } catch (e, s) {
      _fileLogger.log('ERROR $tag: Failed to clear notifications box: $e',
          stackTrace: s);
    }
  }

  List<NotificationModel> getAllNotifications() {
    if (_notificationBox == null || !_notificationBox!.isOpen) {
      _fileLogger.log(
          'WARNING $tag: Cannot get notifications, box is not open. Returning empty list.',
          stackTrace: StackTrace.current);
      return [];
    }
    try {
      var notifications = _notificationBox!.values.toList();
      notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return notifications;
    } catch (e, s) {
      _fileLogger.log('ERROR $tag: Failed to get notifications from Hive: $e',
          stackTrace: s);
      return [];
    }
  }

  ValueListenable<Box<NotificationModel>>? getNotificationsListenable() {
    if (_notificationBox == null || !_notificationBox!.isOpen) {
      _fileLogger.log(
          'WARNING $tag: Cannot get notifications listenable, box is not open.',
          stackTrace: StackTrace.current);
      return null;
    }
    try {
      if (Hive.isBoxOpen('notifications')) {
        _notificationBox = Hive.box<NotificationModel>('notifications');
        return _notificationBox!.listenable();
      } else {
        _fileLogger.log(
            'ERROR $tag: Notifications box became closed unexpectedly before returning listenable.',
            stackTrace: StackTrace.current);
        return null;
      }
    } catch (e, s) {
      _fileLogger.log('ERROR $tag: Error getting notifications listenable: $e',
          stackTrace: s);
      return null;
    }
  }

  // --- Nettoyage ---
  Future<void> dispose() async {
    // _fileLogger.log('INFO $tag: Disposing NotificationService...',
    //     stackTrace: StackTrace.current);
    // La box Hive est gérée globalement
  }
}
