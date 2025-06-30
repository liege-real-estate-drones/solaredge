import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:solaredge_monitor/data/services/auth_service.dart';
import 'package:solaredge_monitor/presentation/theme/app_theme.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:solaredge_monitor/data/services/service_manager.dart'; // Import ServiceManager

import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkConfiguration();
  }

  Future<void> _checkConfiguration() async {
    final prefs = await SharedPreferences.getInstance();
    final bool setupComplete = prefs.getBool('setup_complete') ?? false;
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.authStateChanges.first; // S'assurer que l'état d'authentification est connu

    if (!mounted) return;

    if (authService.currentUser == null) {
      // Si non connecté, toujours aller à l'écran de connexion
      Navigator.of(context).pushReplacementNamed('/login');
    } else {
      // Si connecté, vérifier l'état de la configuration
      if (setupComplete) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        Navigator.of(context).pushReplacementNamed('/setup');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo stylisé
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(75),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.solar_power,
                size: 80,
                color: AppTheme.primaryColor,
              ),
            )
            .animate()
            .fadeIn(duration: 500.ms)
            .scale(begin: const Offset(0.5, 0.5), end: Offset(1.0, 1.0), duration: 600.ms, curve: Curves.easeOutBack),
            
            const SizedBox(height: 40),
            
            // Nom de l'application
            const Text(
              'SolarEdge Monitor',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimaryColor,
                letterSpacing: 1.2,
              ),
            )
            .animate()
            .fadeIn(duration: 500.ms, delay: 300.ms)
            .moveY(begin: 10, end: 0, duration: 600.ms, curve: Curves.easeOutQuad),
            
            const SizedBox(height: 10),
            
            // Slogan
            const Text(
              'Surveillez votre production solaire intelligemment',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.textSecondaryColor,
              ),
            )
            .animate()
            .fadeIn(duration: 500.ms, delay: 600.ms),
            
            const SizedBox(height: 60),
            
            // Indicateur de chargement
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
            )
            .animate()
            .fadeIn(duration: 500.ms, delay: 1000.ms),
          ],
        ),
      ),
    );
  }
}
