
import 'package:flutter/material.dart';

class LocationSetupStep extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const LocationSetupStep({super.key, required this.onNext, required this.onPrevious});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onPrevious,
        ),
        title: const Text('Configuration de la Localisation'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Configurez votre localisation pour des prévisions météo précises.',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: onNext,
                child: const Text('Terminer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
