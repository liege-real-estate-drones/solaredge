
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart';
import 'package:solaredge_monitor/data/services/auth_service.dart';
import 'package:solaredge_monitor/presentation/pages/setup/steps/electricity_price_setup_step.dart';
import 'package:solaredge_monitor/presentation/pages/location_configuration_screen.dart';
import 'package:solaredge_monitor/presentation/pages/setup/steps/api_setup_step.dart';
import 'package:solaredge_monitor/presentation/pages/setup/steps/gemini_setup_step.dart';
import 'package:solaredge_monitor/presentation/pages/setup/steps/welcome_step.dart';

import 'package:shared_preferences/shared_preferences.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  void _nextPage() {
    if (_currentPage < 4) { // Changed from 3 to 4
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    } else {
      // Final step
      _completeSetup();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.ease,
      );
    }
  }

  Future<void> _completeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('setup_complete', true);

    if (!mounted) return;

    final serviceManager = Provider.of<ServiceManager>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);

    // Assurez-vous qu'un utilisateur est connecté (même anonymement) avant de sauvegarder les préférences
    if (authService.currentUser == null) {
      try {
        await authService.signInAnonymously();
        debugPrint("SetupScreen: Connexion anonyme réussie pour la sauvegarde des préférences.");
      } catch (e) {
        debugPrint("SetupScreen: Échec de la connexion anonyme: $e");
        // Gérer l'erreur, peut-être afficher un message à l'utilisateur
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erreur: Impossible de sauvegarder les préférences sans connexion. $e'), backgroundColor: Colors.red),
          );
        }
        return; // Ne pas continuer si la connexion anonyme échoue
      }
    }

    // Re-initialize services with the new settings (cela inclura la sauvegarde des préférences)
    await serviceManager.initializeCoreServices();

    if (!mounted) return;

    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final serviceManager = Provider.of<ServiceManager>(context, listen: false);

    final List<Widget> _steps = [
      WelcomeStep(onNext: _nextPage),
      ApiSetupStep(onNext: _nextPage, onPrevious: _previousPage),
      GeminiSetupStep(onNext: _nextPage, onPrevious: _previousPage),
      ElectricityPriceSetupStep(onNext: _nextPage, onPrevious: _previousPage), // New step
      LocationConfigurationScreen(onNext: _completeSetup, onPrevious: _previousPage),
    ];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (page) {
          setState(() {
            _currentPage = page;
          });
        },
        children: _steps,
      ),
    );
  }
}
