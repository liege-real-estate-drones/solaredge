import 'package:hive/hive.dart';
import 'package:intl/intl.dart'; // Import pour DateFormat

part 'notification_model.g.dart';

@HiveType(typeId: 5)
class NotificationModel extends HiveObject {
  // Extension HiveObject ajoutée
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String body;

  @HiveField(3)
  final DateTime timestamp;

  @HiveField(4)
  final String type; // 'power', 'energy', 'weather', 'prediction', 'system'

  @HiveField(5)
  final Map<String, dynamic>? data; // Données supplémentaires

  @HiveField(6)
  final bool isRead;

  @HiveField(7)
  final String? imageUrl;

  NotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.type,
    this.data,
    this.isRead = false,
    this.imageUrl,
  });

  NotificationModel copyWith({
    String? id,
    String? title,
    String? body,
    DateTime? timestamp,
    String? type,
    Map<String, dynamic>? data,
    bool? isRead,
    String? imageUrl,
    // Gérer la nullabilité pour data et imageUrl
    bool keepData = true, // Garder data par défaut
    bool keepImageUrl = true, // Garder imageUrl par défaut
  }) {
    return NotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      data: keepData ? (data ?? this.data) : data,
      isRead: isRead ?? this.isRead,
      imageUrl: keepImageUrl ? (imageUrl ?? this.imageUrl) : imageUrl,
    );
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      type: json['type'] as String,
      data: json['data'] != null
          ? Map<String, dynamic>.from(json['data'])
          : null, // Assurer la copie
      isRead: json['isRead'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'timestamp': timestamp.toIso8601String(),
      'type': type,
      'data': data,
      'isRead': isRead,
      'imageUrl': imageUrl,
    };
  }

  // --- Ajout Getter pour timestamp formaté ---
  String get formattedTimestamp {
    // Formate la date et l'heure de manière lisible
    // Exemple : "22 avr. 2025 19:35" ou "Aujourd'hui 19:35" ou "Hier 10:15"

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final notificationDate =
        DateTime(timestamp.year, timestamp.month, timestamp.day);

    if (notificationDate == today) {
      return 'Aujourd\'hui ${DateFormat.Hm('fr_FR').format(timestamp)}';
    } else if (notificationDate == yesterday) {
      return 'Hier ${DateFormat.Hm('fr_FR').format(timestamp)}';
    } else {
      // Format standard pour les jours plus anciens
      return DateFormat('d MMM y HH:mm', 'fr_FR').format(timestamp);
    }
  }
// --- Fin ajout getter ---
}

@HiveType(typeId: 6)
class NotificationGroup extends HiveObject {
  // Extension HiveObject ajoutée
  @HiveField(0)
  final String type;

  @HiveField(1)
  final List<NotificationModel> notifications;

  NotificationGroup({
    required this.type,
    required this.notifications,
  });

  factory NotificationGroup.fromJson(Map<String, dynamic> json) {
    return NotificationGroup(
      type: json['type'] as String,
      notifications: (json['notifications'] as List)
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'notifications': notifications.map((e) => e.toJson()).toList(),
    };
  }
}
