import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart';

class ApiSetupStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const ApiSetupStep({super.key, required this.onNext, required this.onPrevious});

  @override
  State<ApiSetupStep> createState() => _ApiSetupStepState();
}

class _ApiSetupStepState extends State<ApiSetupStep> {
  final _formKey = GlobalKey<FormState>();
  final _apiKeyController = TextEditingController();
  final _siteIdController = TextEditingController();

  Future<void> _saveApiSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('solaredge_api_key', _apiKeyController.text);
    await prefs.setString('solaredge_site_id', _siteIdController.text);

    // Déclencher la réinitialisation du service API dans le ServiceManager
    if (mounted) {
      final serviceManager = Provider.of<ServiceManager>(context, listen: false);
      await serviceManager.initializeApiServiceFromPreferences();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onPrevious,
        ),
        title: const Text('Configuration SolarEdge'),
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
                decoration: const InputDecoration(labelText: 'Clé API SolarEdge'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre clé API';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _siteIdController,
                decoration: const InputDecoration(labelText: 'ID du site SolarEdge'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer l\'ID de votre site';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    _saveApiSettings().then((_) => widget.onNext());
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

