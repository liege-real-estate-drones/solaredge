// lib/presentation/pages/ai_assistant_screen.dart (Exemple simplifié)
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solaredge_monitor/data/models/ai_assistant_model.dart';
import 'package:solaredge_monitor/data/services/ai_service.dart';
import 'package:solaredge_monitor/data/services/assistant_service.dart'; // Importer AssistantService
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  AiConversation? _currentConversation;
  StreamSubscription? _conversationSubscription;
  bool _isLoading = false;
  late AssistantService _assistantService; // Add AssistantService variable

  // Liste de questions prédéfinies générée dynamiquement
  List<String> _predefinedQuestions = [];
  String? _selectedQuestion;

  bool _isServiceReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final aiService = Provider.of<AiService>(context, listen: false);
        _assistantService = Provider.of<AssistantService>(context, listen: false);

        // Générer la liste des questions prédéfinies à partir des intents rapides
        _predefinedQuestions = _assistantService.quickIntents.map((intent) {
          String description = intent.id;
          switch (intent.id) {
            case 'daily_energy':
              description = 'Quelle est ma production aujourd\'hui ?';
              break;
            case 'weekly_summary':
              description = 'Quel est le bilan énergétique de la semaine ?';
              break;
            case 'monthly_summary':
              description = 'Quel est le bilan énergétique du mois ?';
              break;
            case 'last_week_summary':
              description = 'Résumé de la semaine dernière ?';
              break;
            case 'yearly_summary':
              description = 'Résumé de l\'année ?';
              break;
            case 'best_time_washing_machine':
              description = 'Quand lancer ma machine à laver ?';
              break;
            case 'tomorrow_production':
              description = 'Production prévue demain ?';
              break;
            case 'fallback_to_ai':
              description = 'Poser une autre question...';
              break;
          }
          return description;
        }).toList();

        // S\'abonner au stream de conversation
        _conversationSubscription = aiService.conversationStream.listen((conversation) {
           if (mounted) {
              setState(() {
                _currentConversation = conversation;
                _isLoading = false;
              });
              _scrollToBottom();
           }
        });
        aiService.setActiveConversation("default_conversation");
        setState(() {
          _isServiceReady = true;
        });
      } catch (e) {
        // Gérer l\'erreur si le Provider n\'est pas trouvé
        debugPrint("Error in AiAssistantScreen initState: $e");
        setState(() {
          _isServiceReady = false;
          // Vous pouvez définir un message d\'erreur ici si vous voulez l\'afficher à l\'utilisateur
        });
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _conversationSubscription?.cancel();
    super.dispose();
  }

  void _sendMessage() {
    final message = _textController.text.trim();
    if (message.isNotEmpty) {
      setState(() {
         _isLoading = true;
      });
      _assistantService.processUserText(message); // Call AssistantService
      _textController.clear();
      FocusScope.of(context).unfocus();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
     WidgetsBinding.instance.addPostFrameCallback((_) {
       if (_scrollController.hasClients) {
         _scrollController.animateTo(
           _scrollController.position.maxScrollExtent,
           duration: const Duration(milliseconds: 300),
           curve: Curves.easeOut,
         );
       }
     });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isServiceReady) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Assistant IA'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('Initialisation de l\'assistant...'),
            ],
          ),
        ),
      );
    }

    final aiService = context.watch<AiService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentConversation?.title ?? 'Assistant IA'),
      ),
      body: Column(
        children: [
          // Liste déroulante des questions prédéfinies
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: DropdownButton<String>(
              hint: const Text('Choisir une question rapide...'),
              value: _selectedQuestion,
              items: _predefinedQuestions.map((String question) {
                return DropdownMenuItem<String>(
                  value: question,
                  child: Text(question),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  setState(() {
                    _selectedQuestion = newValue;
                  });
                  _sendPredefinedMessage(newValue);
                }
              },
               isExpanded: true,
            ),
          ),
          Expanded(
            child: _currentConversation == null
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _currentConversation!.messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                       if (_isLoading && index == _currentConversation!.messages.length) {
                         return const _TypingIndicator();
                       }
                       final message = _currentConversation!.messages[index];
                       return _buildMessageBubble(message);
                    },
                  ),
          ),
          _buildChatInput(aiService),
        ],
      ),
       bottomNavigationBar: NavigationBar(
        selectedIndex: 4,
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              Navigator.of(context).pushReplacementNamed('/');
              break;
            case 1:
              Navigator.of(context).pushReplacementNamed('/daily', arguments: {'selectedDate': DateTime.now()});
              break;
            case 2:
              Navigator.of(context).pushReplacementNamed('/monthly');
              break;
            case 3:
              Navigator.of(context).pushReplacementNamed('/yearly');
              break;
            case 4:
              break;
          }
        },
         destinations: const [
           NavigationDestination(
             icon: Icon(Icons.home_outlined),
             selectedIcon: Icon(Icons.home),
             label: 'Accueil',
           ),
           NavigationDestination(
             icon: Icon(Icons.calendar_today_outlined),
             selectedIcon: Icon(Icons.calendar_today),
             label: 'Jour',
           ),
           NavigationDestination(
             icon: Icon(Icons.calendar_month_outlined),
             selectedIcon: Icon(Icons.calendar_month),
             label: 'Mois',
           ),
           NavigationDestination(
             icon: Icon(Icons.event_available_outlined),
             selectedIcon: Icon(Icons.event_available),
             label: 'Année',
           ),
           NavigationDestination(
             icon: Icon(Icons.assistant_outlined),
             selectedIcon: Icon(Icons.assistant),
             label: 'Assistant',
           ),
         ],
      ),
    );
  }

  void _sendPredefinedMessage(String message) {
     setState(() {
        _isLoading = true;
        _selectedQuestion = null;
     });
     _assistantService.processUserText(message); // Call AssistantService
     FocusScope.of(context).unfocus();
     _scrollToBottom();
  }


  Widget _buildMessageBubble(AiMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        decoration: BoxDecoration(
          color: message.isUser
              ? AppTheme.primaryColor.withOpacity(0.8)
              : AppTheme.cardColor,
          borderRadius: BorderRadius.circular(16.0),
           border: message.isUser ? null : Border.all(color: AppTheme.cardBorderColor.withOpacity(0.5))
        ),
        child: Column(
           crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
           mainAxisSize: MainAxisSize.min,
           children: [
              SelectableText(
                message.content.isNotEmpty ? message.content : 'Désolé, je n\'ai pas pu générer de réponse pour le moment.', // Display default message if content is empty
                style: TextStyle(
                  color: message.isUser ? Colors.white : AppTheme.textPrimaryColor,
                ),
              ),
           ],
        )

      ),
    );
  }

  Widget _buildChatInput(AiService? aiService) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -1),
            blurRadius: 4.0,
            color: Colors.black.withOpacity(0.1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Posez une question sur vos stats...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 16.0),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
               enabled: true, // Always enabled
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendMessage, // Always enabled
            color: AppTheme.primaryColor,
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        decoration: BoxDecoration(
          color: AppTheme.cardColor,
          borderRadius: BorderRadius.circular(16.0),
          border: Border.all(color: AppTheme.cardBorderColor.withOpacity(0.5))
        ),
        child: const SizedBox(
           width: 50,
           height: 20,
           child: Center(
              child: _AnimatedDots(),
           )
        ),
      ),
    );
  }
}

class _AnimatedDots extends StatefulWidget {
  const _AnimatedDots();

  @override
  _AnimatedDotsState createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return ScaleTransition(
          scale: Tween(begin: 0.4, end: 1.0).animate(
            CurvedAnimation(
              parent: _controller,
              curve: Interval(0.1 * index, 0.3 + 0.1 * index, curve: Curves.easeInOut),
            ),
          ),
          child: FadeTransition(
             opacity: Tween(begin: 0.5, end: 1.0).animate(
                CurvedAnimation(
                   parent: _controller,
                   curve: Interval(0.1 * index, 0.3 + 0.1 * index, curve: Curves.easeInOut),
                 ),
               ),
            child: Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: const BoxDecoration(
                color: AppTheme.textSecondaryColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}
