
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

class GeminiSetupStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const GeminiSetupStep({super.key, required this.onNext, required this.onPrevious});

  @override
  State<GeminiSetupStep> createState() => _GeminiSetupStepState();
}

class _GeminiSetupStepState extends State<GeminiSetupStep> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();

  Future<void> _saveGeminiApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', _apiKeyController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onPrevious,
        ),
        title: const Text('Configuration Assistant AI'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextFormField(
                controller: _apiKeyController,
                decoration: const InputDecoration(labelText: 'Clé API Gemini'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre clé API Gemini';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _saveGeminiApiKey().then((_) => widget.onNext());
                  }
                },
                child: const Text('Suivant'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
