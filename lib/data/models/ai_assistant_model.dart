class AiMessage {
  final String content;
  final DateTime timestamp;
  final bool isUser; // true si message de l'utilisateur, false si réponse de l'IA
  final List<String>? referencedData; // IDs des données référencées dans le message
  final Map<String, dynamic>? context; // Contexte additionnel pour l'IA

  AiMessage({
    required this.content,
    required this.timestamp,
    required this.isUser,
    this.referencedData,
    this.context,
  });

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    return AiMessage(
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isUser: json['isUser'] as bool,
      referencedData: json['referencedData'] != null
          ? List<String>.from(json['referencedData'] as List)
          : null,
      context: json['context'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      'isUser': isUser,
      'referencedData': referencedData,
      'context': context,
    };
  }
}

class AiConversation {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime lastUpdated;
  final List<AiMessage> messages;
  
  AiConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.lastUpdated,
    required this.messages,
  });

  factory AiConversation.fromJson(Map<String, dynamic> json) {
    return AiConversation(
      id: json['id'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      messages: (json['messages'] as List)
          .map((e) => AiMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'messages': messages.map((e) => e.toJson()).toList(),
    };
  }
  
  // Créer une nouvelle conversation
  factory AiConversation.create({required String title, String? firstMessage}) {
    final now = DateTime.now();
    final id = 'conv_${now.millisecondsSinceEpoch}';
    
    List<AiMessage> initialMessages = [];
    if (firstMessage != null) {
      initialMessages.add(
        AiMessage(
          content: firstMessage,
          timestamp: now,
          isUser: true,
        ),
      );
    }
    
    return AiConversation(
      id: id,
      title: title,
      createdAt: now,
      lastUpdated: now,
      messages: initialMessages,
    );
  }
  
  // Ajouter un message à la conversation
  AiConversation addMessage(AiMessage message) {
    List<AiMessage> updatedMessages = List.from(messages)..add(message);
    
    return AiConversation(
      id: id,
      title: title,
      createdAt: createdAt,
      lastUpdated: DateTime.now(),
      messages: updatedMessages,
    );
  }
}

class AiRecommendation {
  final String id;
  final String title;
  final String description;
  final DateTime createdAt;
  final String category; // 'energy_optimization', 'machine_usage', 'weather_alert', etc.
  final double priority; // 0-1, importance de la recommandation
  final Map<String, dynamic>? supportingData; // Données justifiant la recommandation
  final bool isDismissed;
  
  AiRecommendation({
    required this.id,
    required this.title,
    required this.description,
    required this.createdAt,
    required this.category,
    required this.priority,
    this.supportingData,
    this.isDismissed = false,
  });

  factory AiRecommendation.fromJson(Map<String, dynamic> json) {
    return AiRecommendation(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      category: json['category'] as String,
      priority: json['priority'] as double,
      supportingData: json['supportingData'] as Map<String, dynamic>?,
      isDismissed: json['isDismissed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'category': category,
      'priority': priority,
      'supportingData': supportingData,
      'isDismissed': isDismissed,
    };
  }
  
  AiRecommendation copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    String? category,
    double? priority,
    Map<String, dynamic>? supportingData,
    bool? isDismissed,
  }) {
    return AiRecommendation(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      category: category ?? this.category,
      priority: priority ?? this.priority,
      supportingData: supportingData ?? this.supportingData,
      isDismissed: isDismissed ?? this.isDismissed,
    );
  }
}
